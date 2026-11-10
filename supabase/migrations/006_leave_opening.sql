-- One staff list for schedule and leave: full name, position and short names (aliases) used in the schedule Excel.
-- leave_opening: days already used per person, year and leave type, imported from the leave Excel.
-- The app adds approved in-app requests on top, and the yearly limit counts both.

alter table public.schedule_people
  add column position text check (char_length(position) <= 80),
  add column aliases text[] not null default '{}';

create table public.leave_opening (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.schedule_people(id) on delete cascade,
  year int not null check (year between 2000 and 2100),
  leave_type text not null check (leave_type in ('vjetor','mjekesor','martese','vdekje','lindje','gjak','papagese','bartur','kompenzim','extra')),
  used_days int not null check (used_days between 0 and 366),
  updated_at timestamptz not null default now(),
  unique (person_id, year, leave_type)
);

alter table public.leave_opening enable row level security;
create policy "leave opening read own or admin" on public.leave_opening for select to authenticated
  using (public.is_admin() or person_id in (select id from public.schedule_people where user_id = (select auth.uid())));
create policy "leave opening admin" on public.leave_opening for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Yearly allowance: imported days + pending/approved requests (rejected never count).
create or replace function public.check_absence_quota() returns trigger
language plpgsql security definer set search_path = public as $$
declare used int; opening int; allowed int;
begin
  if new.status = 'rejected' then return new; end if;
  allowed := case new.leave_type
    when 'vjetor' then 20 when 'mjekesor' then 20
    when 'martese' then 5 when 'vdekje' then 5
    when 'lindje' then 3 when 'gjak' then 2
    else 0 end;
  if allowed > 0 then
    select coalesce(sum(days),0) into used from public.absences
    where user_id = new.user_id and leave_type = new.leave_type and status <> 'rejected'
      and id <> new.id
      and extract(year from from_date) = extract(year from new.from_date);
    select coalesce(sum(o.used_days),0) into opening from public.leave_opening o
      join public.schedule_people p on p.id = o.person_id
    where p.user_id = new.user_id and o.leave_type = new.leave_type
      and o.year = extract(year from new.from_date);
    if used + opening + new.days > allowed then
      raise exception 'Kaluat ditët e lejuara për këtë lloj pushimi (%).', allowed;
    end if;
  end if;
  return new;
end $$;
