// Sends a notifications row to the user's phones with Web Push. Called by the notifications insert trigger.
// No JWT: the body holds only a notification id (or {init:true} to create the VAPID keys on first use); the row is read with the service role, must be fresh (10 min)
// and not pushed yet, so calling it again cannot send anything new.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
let ready = false;

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");
  const body = await req.json().catch(() => ({}));
  if (!ready) {
    let { data: k } = await sb.rpc("get_vapid_keys").single();
    if (!k?.private_key) {
      // first use: create the key pair here and keep it in Vault
      const g = webpush.generateVAPIDKeys();
      await sb.rpc("set_vapid_keys", { p_public: g.publicKey, p_private: g.privateKey });
      ({ data: k } = await sb.rpc("get_vapid_keys").single());
    }
    if (!k?.public_key || !k?.private_key) return new Response("no keys", { status: 500 });
    webpush.setVapidDetails("https://digitalhr.vercel.app", k.public_key, k.private_key);
    ready = true;
  }
  if (body.init === true) return Response.json({ ready: true });
  const id = body.id;
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/.test(id)) return new Response("bad id", { status: 400 });
  const { data: n } = await sb.from("notifications").select("*").eq("id", id).maybeSingle();
  if (!n || n.pushed_at || Date.now() - new Date(n.created_at).getTime() > 10 * 60 * 1000) return new Response("skip");
  const { data: claimed } = await sb.from("notifications").update({ pushed_at: new Date().toISOString() }).eq("id", id).is("pushed_at", null).select("id");
  if (!claimed?.length) return new Response("skip");
  const { data: subs } = await sb.from("push_subscriptions").select("*").eq("user_id", n.user_id);
  const payload = JSON.stringify({ id: n.id, title: n.title, body: String(n.body).slice(0, 300), url: "/" });
  let sent = 0, gone = 0;
  for (const s of subs ?? []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) { await sb.from("push_subscriptions").delete().eq("id", s.id); gone++; }
    }
  }
  return Response.json({ sent, gone });
});
