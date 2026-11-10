-- Automatic link between staff names (schedule_people) and app accounts (profiles).
-- An approved account is linked to a staff name when its full name matches the name or one of the aliases,
-- ignoring case, extra spaces, ë/ç and the order of first and last name; only when exactly one unlinked
-- name matches and the account is not linked yet. Manual links made by the admin are never changed.

create or replace function public.norm_name(t text) returns text
language sql immutable set search_path = public as $$
  select trim(regexp_replace(translate(lower(coalesce(t,'')), 'ëçéèáàíóúü', 'eceeaaiouu'), '\s+', ' ', 'g'));
$$;

-- "Emri Mbiemri" and "Mbiemri Emri" give the same key.
create or replace function public.name_key(t text) returns text
language sql immutable set search_path = public as $$
  select coalesce(string_agg(w, ' ' order by w), '') from unnest(string_to_array(public.norm_name(t), ' ')) w where w <> '';
$$;

create or replace function public.auto_link_profile(p_user uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare k text; pid uuid; n int;
begin
  if exists (select 1 from schedule_people where user_id = p_user) then return null; end if;
  select name_key(full_name) into k from profiles where id = p_user and status = 'approved';
  if k is null or k = '' then return null; end if;
  select count(*), min(sp.id::text)::uuid into n, pid from schedule_people sp
  where sp.user_id is null
    and (name_key(sp.name) = k or exists (select 1 from unnest(sp.aliases) a where name_key(a) = k));
  if n <> 1 then return null; end if;
  update schedule_people set user_id = p_user where id = pid and user_id is null;
  return pid;
end $$;

create or replace function public.auto_link_all() returns int
language plpgsql security definer set search_path = public as $$
declare r record; c int := 0;
begin
  for r in select id from profiles where status = 'approved' order by created_at loop
    if public.auto_link_profile(r.id) is not null then c := c + 1; end if;
  end loop;
  return c;
end $$;
revoke all on function public.auto_link_profile(uuid) from public, anon, authenticated;
revoke all on function public.auto_link_all() from public, anon, authenticated;

-- When an account becomes approved or changes its name.
create or replace function public.trg_profile_auto_link() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' then perform public.auto_link_profile(new.id); end if;
  return null;
end $$;
drop trigger if exists profile_auto_link on public.profiles;
create trigger profile_auto_link after insert or update of status, full_name on public.profiles
  for each row execute function public.trg_profile_auto_link();

-- When a staff name is added or renamed (Excel imports, aliases).
create or replace function public.trg_people_auto_link() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is null then perform public.auto_link_all(); end if;
  return null;
end $$;
drop trigger if exists people_auto_link on public.schedule_people;
create trigger people_auto_link after insert or update of name, aliases on public.schedule_people
  for each row when (new.user_id is null) execute function public.trg_people_auto_link();

-- Link the accounts that already exist.
select public.auto_link_all();
