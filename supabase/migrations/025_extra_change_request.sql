-- Staff can correct their own "Punë extra" reports.
-- * Pending or rejected report: the staff member edits it directly; it goes (back) to the admin as "Në pritje".
-- * Approved report: the correction is stored as a request (req_*); the approved shift stays in the schedule
--   until the admin approves the correction (applied, schedule updated) or rejects it (cleared).
-- The staff member is notified of the admin's decision; admins are notified of each correction request.

alter table public.absences
  add column if not exists req_from date,
  add column if not exists req_to date,
  add column if not exists req_shift text,
  add column if not exists req_note text,
  add column if not exists req_at timestamptz;

create or replace function public.request_extra_change(p_id uuid, p_from date, p_to date, p_shift text, p_note text default null)
returns text language plpgsql security definer set search_path = public as $$
declare a public.absences; nm text; sh text := regexp_replace(coalesce(p_shift, ''), '\s', '', 'g'); per text;
begin
  select * into a from public.absences where id = p_id for update;
  if a.id is null or a.user_id is distinct from auth.uid() then raise exception 'Kërkesa nuk u gjet.'; end if;
  if not public.is_approved() then raise exception 'Llogaria nuk është aktive.'; end if;
  if a.leave_type <> 'extra' then raise exception 'Vetëm puna extra mund të korrigjohet.'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'Zgjidhni datat e sakta.'; end if;
  if p_to - p_from > 30 then raise exception 'Periudha është shumë e gjatë.'; end if;
  if sh !~ '^\d{1,2}(:\d{2})?-\d{1,2}(:\d{2})?$' then raise exception 'Shkruani orarin, p.sh. 08-16.'; end if;
  p_note := nullif(left(btrim(coalesce(p_note, '')), 500), '');

  if a.status = 'approved' then
    if (p_from, p_to, sh) = (a.from_date, a.to_date, a.shift) then raise exception 'Nuk keni ndryshuar asgjë.'; end if;
    update public.absences set req_from = p_from, req_to = p_to, req_shift = sh, req_note = p_note, req_at = now() where id = p_id;
    select full_name into nm from public.profiles where id = a.user_id;
    per := case when p_from = p_to then to_char(p_from, 'DD.MM.YYYY') else to_char(p_from, 'DD.MM.YYYY') || ' – ' || to_char(p_to, 'DD.MM.YYYY') end;
    insert into public.notifications (user_id, title, body)
    select id, 'Korrigjim i orarit për miratim',
      coalesce(nm, 'Një punëtor') || ' kërkon korrigjimin e punës extra: nga ' ||
      case when a.from_date = a.to_date then to_char(a.from_date, 'DD.MM.YYYY') else to_char(a.from_date, 'DD.MM.YYYY') || ' – ' || to_char(a.to_date, 'DD.MM.YYYY') end ||
      ' ' || coalesce(a.shift, '') || ' në ' || per || ' ' || sh || '.' || coalesce(E'\nShënimi: ' || p_note, '') || E'\nHapni Kërkesat për ta miratuar ose refuzuar.'
    from public.profiles where role = 'admin' and status = 'approved';
    return 'requested';
  end if;

  -- pending or rejected: edit directly, back to the admin for approval
  update public.absences set from_date = p_from, to_date = p_to, days = (p_to - p_from) + 1, shift = sh,
    note = coalesce(p_note, note), status = 'pending', admin_comment = null,
    req_from = null, req_to = null, req_shift = null, req_note = null, req_at = null
  where id = p_id;
  update public.absences set edited_at = null where id = p_id;
  return 'updated';
end $$;
revoke all on function public.request_extra_change(uuid, date, date, text, text) from public, anon;
grant execute on function public.request_extra_change(uuid, date, date, text, text) to authenticated;

-- Staff may withdraw their own open correction.
create or replace function public.cancel_extra_change(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.absences set req_from = null, req_to = null, req_shift = null, req_note = null, req_at = null
  where id = p_id and user_id = auth.uid() and req_at is not null;
end $$;
revoke all on function public.cancel_extra_change(uuid) from public, anon;
grant execute on function public.cancel_extra_change(uuid) to authenticated;

-- Notifications: add the admin's decision on a correction request.
create or replace function public.trg_absence_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare lbl text; per text; first text; t text; b text;
begin
  lbl := case new.leave_type
    when 'vjetor' then 'Pushimi vjetor' when 'mjekesor' then 'Pushimi mjekësor'
    when 'mjekesor_pp' then 'Pushimi mjekësor pa pagesë' when 'martese' then 'Leja për martesë'
    when 'vdekje' then 'Leja për vdekje në familje' when 'lindje' then 'Leja për lindje fëmije'
    when 'gjak' then 'Leja për dhurim gjaku' when 'papagese' then 'Pushimi pa pagesë'
    when 'bartur' then 'Pushimi i bartur' when 'kompenzim' then 'Pushimi me kompenzim'
    when 'extra' then 'Puna extra' else 'Kërkesa' end;
  per := case when new.from_date = new.to_date then to_char(new.from_date, 'DD.MM.YYYY')
              else to_char(new.from_date, 'DD.MM.YYYY') || ' – ' || to_char(new.to_date, 'DD.MM.YYYY') end
         || case when new.leave_type = 'extra' and new.shift is not null then ', ndërrimi ' || new.shift
                 when new.leave_type <> 'extra' then ' (' || new.days || ' ditë)' else '' end;
  select split_part(full_name, ' ', 1) into first from profiles where id = new.user_id;

  -- the admin decided on a staff correction request (req_* cleared by an admin, not withdrawn by the staff member)
  if old.req_at is not null and new.req_at is null and public.is_admin() then
    if (new.from_date, new.to_date, coalesce(new.shift, '')) = (old.req_from, old.req_to, coalesce(old.req_shift, '')) then
      t := 'Korrigjimi i orarit u miratua';
      b := 'Përshëndetje ' || coalesce(first, '') || ', korrigjimi juaj u miratua nga administratori. Puna extra tani është: ' || per || '. Orari u përditësua.';
    else
      t := 'Korrigjimi i orarit nuk u miratua';
      b := 'Përshëndetje ' || coalesce(first, '') || ', korrigjimi juaj (' ||
        case when old.req_from = old.req_to then to_char(old.req_from, 'DD.MM.YYYY') else to_char(old.req_from, 'DD.MM.YYYY') || ' – ' || to_char(old.req_to, 'DD.MM.YYYY') end ||
        ', ndërrimi ' || coalesce(old.req_shift, '') || ') nuk u miratua. Mbetet puna extra e miratuar: ' || per || '.';
    end if;
  elsif new.status = 'approved' and old.status is distinct from 'approved' then
    t := lbl || ' u miratua';
    b := 'Përshëndetje ' || coalesce(first, '') || ', ' || lower(left(lbl, 1)) || substr(lbl, 2) || ' për ' || per || ' u miratua nga administratori.'
      || case when new.leave_type = 'extra' then ' Dita u shtua në orarin tuaj.' else '' end;
  elsif new.status = 'rejected' and old.status is distinct from 'rejected' then
    t := lbl || ' nuk u miratua';
    b := 'Përshëndetje ' || coalesce(first, '') || ', kërkesa juaj (' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || ') nuk u miratua nga administratori.';
  elsif new.status = 'approved' and old.status = 'approved' and public.is_admin()
        and (new.from_date, new.to_date, new.days, new.leave_type, coalesce(new.shift, ''))
            is distinct from (old.from_date, old.to_date, old.days, old.leave_type, coalesce(old.shift, '')) then
    t := lbl || ' u ndryshua';
    b := 'Përshëndetje ' || coalesce(first, '') || ', administratori ndryshoi kërkesën tuaj të miratuar: ' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || '.';
  else
    return null;
  end if;
  if new.admin_comment is not null and btrim(new.admin_comment) <> '' then
    b := b || E'\nKomenti: ' || new.admin_comment;
  end if;
  insert into notifications (user_id, title, body) values (new.user_id, t, left(b, 2000));
  return null;
end $$;

-- admins (RLS "absences admin update") clear req_* when approving or rejecting a correction; UPDATE on absences is column-level
grant update (req_from, req_to, req_shift, req_note, req_at) on public.absences to authenticated;
