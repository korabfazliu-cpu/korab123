-- 1) Staff get a notification when their own schedule changes (user, 2026-11-23): a cell edited, an extra day added
--    or removed. Small changes list each day; bulk changes (Excel import, > 5 rows for a person in one statement)
--    send one summary per person, at most once every 3 minutes. Extras created by an approved "Punë extra" request
--    (absence_id set) are skipped: that request already notifies.
-- 2) schedule_people.extra_depts: sections where a person also works as extra staff, so they show as a row there
--    (user: Besian Osmani is extra staff in Cashier and Mirembajtje).
alter table public.schedule_people add column extra_depts text[] not null default '{}';
update public.schedule_people set extra_depts = array['Cashier','Mirembajtje'] where name = 'Besian Osmani';

create or replace function public.sched_notify_person(p_user uuid, p_name text, p_changes jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare n int := jsonb_array_length(p_changes); c jsonb; lines text := ''; t text; b text;
  dn text[] := array['e hënë','e martë','e mërkurë','e enjte','e premte','e shtunë','e diel'];
  mn text[] := array['janar','shkurt','mars','prill','maj','qershor','korrik','gusht','shtator','tetor','nëntor','dhjetor'];
  d0 date; d1 date;
begin
  if p_user is null or n = 0 then return; end if;
  if n > 5 then
    select min((x->>'day')::date), max((x->>'day')::date) into d0, d1 from jsonb_array_elements(p_changes) x;
    t := 'Orari u përditësua';
    b := 'Përshëndetje ' || split_part(p_name, ' ', 1) || ', orari juaj për ' || mn[extract(month from d0)::int] || ' ' || extract(year from d0)
      || case when date_trunc('month', d1) <> date_trunc('month', d0) then ' – ' || mn[extract(month from d1)::int] || ' ' || extract(year from d1) else '' end
      || ' u përditësua. Shihni orarin në aplikacion.';
    if exists (select 1 from notifications where user_id = p_user and title = t and created_at > now() - interval '3 minutes') then return; end if;
  else
    for c in select x from jsonb_array_elements(p_changes) x order by x->>'day' loop
      lines := lines || E'\n• ' || to_char((c->>'day')::date, 'DD.MM.YYYY') || ' (' || dn[extract(isodow from (c->>'day')::date)::int] || '): '
        || case when c->>'old' is null then 'u shtua ' || (c->>'new') || case when (c->>'extra')::boolean then ' – ditë extra, ' || (c->>'dept') else '' end
                when c->>'new' is null then 'u hoq ' || (c->>'old') || case when (c->>'extra')::boolean then ' (ditë extra)' else '' end
                else 'nga ' || (c->>'old') || ' në ' || (c->>'new') end;
    end loop;
    t := 'Ndryshim në orar';
    b := 'Përshëndetje ' || split_part(p_name, ' ', 1) || ', administratori ndryshoi orarin tuaj:' || lines;
  end if;
  insert into notifications (user_id, title, body) values (p_user, t, left(b, 2000));
end $$;
revoke all on function public.sched_notify_person(uuid, text, jsonb) from public, anon, authenticated;

create or replace function public.trg_sched_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if tg_op = 'INSERT' then
    for r in select p.user_id, p.name, jsonb_agg(jsonb_build_object('day', e.day, 'dept', e.dept, 'old', null, 'new', e.value, 'extra', e.is_extra)) ch
             from new_rows e join schedule_people p on p.id = e.person_id
             where e.absence_id is null and p.user_id is not null group by p.user_id, p.name loop
      perform sched_notify_person(r.user_id, r.name, r.ch);
    end loop;
  elsif tg_op = 'DELETE' then
    for r in select p.user_id, p.name, jsonb_agg(jsonb_build_object('day', e.day, 'dept', e.dept, 'old', e.value, 'new', null, 'extra', e.is_extra)) ch
             from old_rows e join schedule_people p on p.id = e.person_id
             where e.absence_id is null and p.user_id is not null group by p.user_id, p.name loop
      perform sched_notify_person(r.user_id, r.name, r.ch);
    end loop;
  else
    for r in select p.user_id, p.name, jsonb_agg(jsonb_build_object('day', n.day, 'dept', n.dept, 'old', o.value, 'new', n.value, 'extra', n.is_extra)) ch
             from new_rows n join old_rows o on o.id = n.id join schedule_people p on p.id = n.person_id
             where n.absence_id is null and p.user_id is not null and o.value is distinct from n.value group by p.user_id, p.name loop
      perform sched_notify_person(r.user_id, r.name, r.ch);
    end loop;
  end if;
  return null;
end $$;
drop trigger if exists sched_notify_ins on public.schedule_entries;
drop trigger if exists sched_notify_del on public.schedule_entries;
drop trigger if exists sched_notify_upd on public.schedule_entries;
create trigger sched_notify_ins after insert on public.schedule_entries referencing new table as new_rows
  for each statement execute function public.trg_sched_notify();
create trigger sched_notify_del after delete on public.schedule_entries referencing old table as old_rows
  for each statement execute function public.trg_sched_notify();
create trigger sched_notify_upd after update on public.schedule_entries referencing old table as old_rows new table as new_rows
  for each statement execute function public.trg_sched_notify();
