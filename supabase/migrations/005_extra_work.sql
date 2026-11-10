-- "Punë extra": staff report extra work days (with hours); like leave, an admin must approve.
-- Approved extra work is added to the schedule (orari) as an extra shift for that person.

alter table public.absences drop constraint absences_leave_type_check;
alter table public.absences add constraint absences_leave_type_check
  check (leave_type in ('vjetor','mjekesor','martese','vdekje','lindje','gjak','papagese','bartur','kompenzim','extra'));

alter table public.absences
  add column shift text check (char_length(shift) <= 20),
  add constraint absences_extra_shift check (leave_type <> 'extra' or shift is not null);

grant update (shift) on public.absences to authenticated;

-- Schedule cells created from an approved extra-work request.
alter table public.schedule_entries
  add column absence_id uuid references public.absences(id) on delete cascade;
create index schedule_entries_absence on public.schedule_entries(absence_id);

-- Keep the schedule in sync with the request: approved -> one extra cell per day; otherwise none.
create function public.sync_extra_schedule() returns trigger
language plpgsql security definer set search_path = public as $$
declare pid uuid; dp text;
begin
  delete from public.schedule_entries where absence_id = new.id;
  if new.leave_type = 'extra' and new.status = 'approved' then
    select id into pid from public.schedule_people where user_id = new.user_id;
    if pid is not null then
      select dept into dp from public.schedule_entries
        where person_id = pid and not is_extra order by day desc limit 1;
      insert into public.schedule_entries(day, dept, person_id, value, is_extra, absence_id)
      select d::date, coalesce(dp, 'Punë extra'), pid, new.shift, true, new.id
      from generate_series(new.from_date, new.to_date, interval '1 day') d;
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.sync_extra_schedule() from public, anon, authenticated;
create trigger absences_extra_schedule after insert or update of status, leave_type, from_date, to_date, shift
on public.absences for each row execute function public.sync_extra_schedule();
