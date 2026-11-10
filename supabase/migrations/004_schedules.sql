-- Staff work schedules (orari), imported from the monthly Excel or edited by an admin.
-- schedule_people: names as written in the schedule, optionally linked to an app account.
-- schedule_entries: one cell per person, day and section; "extra" rows hold extra shifts.

create table public.schedule_people (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 1 and 120),
  user_id uuid unique references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.schedule_entries (
  id uuid primary key default gen_random_uuid(),
  day date not null,
  dept text not null check (char_length(dept) between 1 and 60),
  person_id uuid references public.schedule_people(id) on delete cascade,
  person_label text check (char_length(person_label) <= 120),
  value text not null check (char_length(value) between 1 and 60),
  is_extra boolean not null default false,
  created_at timestamptz not null default now(),
  check (person_id is not null or (is_extra and person_label is not null))
);
create unique index schedule_entries_cell on public.schedule_entries(day, dept, person_id) where not is_extra;
create index schedule_entries_day on public.schedule_entries(day);

-- Sections the signed-in user appears in (through their linked schedule name).
create function public.my_schedule_depts() returns setof text
language sql stable security definer set search_path = public as $$
  select distinct e.dept from public.schedule_entries e
  join public.schedule_people p on p.id = e.person_id
  where p.user_id = auth.uid()
$$;
revoke execute on function public.my_schedule_depts() from public, anon;
grant execute on function public.my_schedule_depts() to authenticated;

alter table public.schedule_people enable row level security;
alter table public.schedule_entries enable row level security;

-- Approved staff can read names (colleagues) and the entries of their own sections; admins manage everything.
create policy "schedule people read" on public.schedule_people for select to authenticated
  using (public.is_approved());
create policy "schedule people admin" on public.schedule_people for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "schedule entries read own sections" on public.schedule_entries for select to authenticated
  using (public.is_admin() or (public.is_approved() and dept in (select public.my_schedule_depts())));
create policy "schedule entries admin" on public.schedule_entries for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
