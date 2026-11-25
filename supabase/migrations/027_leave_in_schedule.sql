-- Approved leave shows in the schedule.
-- When a leave request (any type except "Punë extra") is approved, the person's regular shifts on those days are
-- replaced with the leave ("PUSHIM VJETOR", "PUSHIM MJEKËSOR", ...); the original shift is kept in orig_value.
-- If the request is rejected, changed or deleted, the original shifts come back (and the new dates are applied).
-- Extra work keeps working as before (rows inserted for approved "Punë extra").

alter table public.schedule_entries add column if not exists orig_value text;

create or replace function public.leave_schedule_label(t text)
returns text language sql immutable as $$
  select case t
    when 'vjetor' then 'PUSHIM VJETOR' when 'bartur' then 'PUSHIM VJETOR'
    when 'mjekesor' then 'PUSHIM MJEKËSOR' when 'mjekesor_pp' then 'PUSHIM MJEKËSOR'
    when 'papagese' then 'PUSHIM PA PAGESË' when 'martese' then 'PUSHIM (martesë)'
    when 'vdekje' then 'PUSHIM (vdekje në familje)' when 'lindje' then 'PUSHIM (lindje fëmije)'
    when 'gjak' then 'PUSHIM (dhurim gjaku)' when 'kompenzim' then 'PUSHIM (kompenzim)' else 'PUSHIM' end;
$$;

create or replace function public.apply_absence_schedule(a public.absences)
returns void language plpgsql security definer set search_path = public as $$
declare pid uuid; dp text;
begin
  -- undo what this request did before
  update public.schedule_entries set value = orig_value, orig_value = null, absence_id = null
    where absence_id = a.id and orig_value is not null;
  delete from public.schedule_entries where absence_id = a.id;
  if a.status is distinct from 'approved' then return; end if;
  select id into pid from public.schedule_people where user_id = a.user_id;
  if pid is null then return; end if;
  if a.leave_type = 'extra' then
    select dept into dp from public.schedule_entries where person_id = pid and not is_extra order by day desc limit 1;
    insert into public.schedule_entries(day, dept, person_id, value, is_extra, absence_id)
    select d::date, coalesce(dp, 'Punë extra'), pid, a.shift, true, a.id
    from generate_series(a.from_date, a.to_date, interval '1 day') d;
  else
    update public.schedule_entries
      set orig_value = value, value = public.leave_schedule_label(a.leave_type), absence_id = a.id
    where person_id = pid and not is_extra and absence_id is null
      and day between a.from_date and a.to_date
      and value ~ '^\s*\d{1,2}(:\d{2})?\s*[-–]\s*\d{1,2}';
  end if;
end $$;
revoke all on function public.apply_absence_schedule(public.absences) from public, anon, authenticated;

create or replace function public.sync_extra_schedule()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.apply_absence_schedule(new);
  return new;
end $$;

-- Before a request is deleted, give the shifts back (the FK would otherwise cascade-delete the replaced rows).
create or replace function public.trg_absence_restore()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.schedule_entries set value = orig_value, orig_value = null, absence_id = null
    where absence_id = old.id and orig_value is not null;
  return old;
end $$;
create or replace trigger absences_restore before delete on public.absences for each row execute function public.trg_absence_restore();

-- Re-apply approved requests to a period (after an Excel import replaces the schedule, or after an account is linked).
create or replace function public.resync_absences(p_from date, p_to date, p_user uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare a public.absences; n int := 0;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'not allowed'; end if;
  for a in select * from public.absences where status = 'approved' and from_date <= p_to and to_date >= p_from
           and (p_user is null or user_id = p_user) loop
    perform public.apply_absence_schedule(a); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.resync_absences(date, date, uuid) from public, anon;
grant execute on function public.resync_absences(date, date, uuid) to authenticated;

-- When an account gets linked to a schedule name, apply that person's approved requests.
create or replace function public.trg_people_resync()
returns trigger language plpgsql security definer set search_path = public as $$
declare a public.absences;
begin
  if new.user_id is not null and new.user_id is distinct from old.user_id then
    for a in select * from public.absences where status = 'approved' and user_id = new.user_id loop
      perform public.apply_absence_schedule(a);
    end loop;
  end if;
  return null;
end $$;
create or replace trigger people_resync after update of user_id on public.schedule_people for each row execute function public.trg_people_resync();

-- Schedule notifications: changes made by a request (set or restored) are already announced by the request notification.
create or replace function public.trg_sched_notify()
returns trigger language plpgsql security definer set search_path = public as $$
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
             where n.absence_id is null and o.absence_id is null and p.user_id is not null and o.value is distinct from n.value
             group by p.user_id, p.name loop
      perform sched_notify_person(r.user_id, r.name, r.ch);
    end loop;
  end if;
  return null;
end $$;

-- Apply the requests that are already approved (e.g. Egzon Bellagoshi 26.11).
select public.resync_absences('2026-01-01', '2027-12-31');
