-- Monthly payroll: base salary per person (admin only), official holidays, and a month calculation.
-- Daily rate = monthly base / 22. Extra days = schedule entries marked extra (from the Excel or approved
-- "Punë extra" requests). Holiday bonus = one daily rate for each official holiday the person has a shift.
-- Part-time staff have a daily amount instead of a monthly base and are paid per worked day.

create table public.payroll_base (
  person_id uuid primary key references public.schedule_people(id) on delete cascade,
  monthly numeric(10,2) check (monthly >= 0),
  daily numeric(10,2) check (daily >= 0),
  updated_at timestamptz not null default now()
);
alter table public.payroll_base enable row level security;
create policy "payroll base admin" on public.payroll_base for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.holidays (
  day date primary key,
  name text not null check (char_length(name) between 1 and 80)
);
alter table public.holidays enable row level security;
create policy "holidays read" on public.holidays for select to authenticated using (true);
create policy "holidays admin" on public.holidays for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

insert into public.holidays (day, name) values
  ('2026-01-01','Viti i Ri'),('2026-01-02','Viti i Ri (dita e dytë)'),('2026-01-07','Krishtlindjet ortodokse'),
  ('2026-02-17','Dita e Pavarësisë'),('2026-03-20','Fitër Bajrami'),('2026-04-05','Pashkët katolike'),
  ('2026-04-06','E hëna e Pashkëve katolike'),('2026-04-09','Dita e Kushtetutës'),('2026-04-12','Pashkët ortodokse'),
  ('2026-04-13','E hëna e Pashkëve ortodokse'),('2026-05-01','Dita e Punës'),('2026-05-09','Dita e Evropës'),
  ('2026-05-27','Kurban Bajrami'),('2026-12-25','Krishtlindjet katolike'),
  ('2027-01-01','Viti i Ri'),('2027-01-02','Viti i Ri (dita e dytë)'),('2027-01-07','Krishtlindjet ortodokse'),
  ('2027-02-17','Dita e Pavarësisë'),('2027-03-09','Fitër Bajrami'),('2027-03-28','Pashkët katolike'),
  ('2027-03-29','E hëna e Pashkëve katolike'),('2027-04-09','Dita e Kushtetutës'),('2027-05-01','Dita e Punës'),
  ('2027-05-02','Pashkët ortodokse'),('2027-05-03','E hëna e Pashkëve ortodokse'),('2027-05-09','Dita e Evropës'),
  ('2027-05-16','Kurban Bajrami'),('2027-12-25','Krishtlindjet katolike');

-- A shift is a value that starts with hours, e.g. 07-15, 23-07, 07-15*.
create or replace function public.payroll_month(p_year int, p_month int)
returns table (person_id uuid, name text, "position" text, monthly numeric, daily_rate numeric,
  work_days int, extra_days int, holiday_days int, holiday_list text,
  base_pay numeric, extra_pay numeric, holiday_pay numeric, total numeric, missing_base boolean)
language sql stable security invoker set search_path = public as $$
  with b as (select make_date(p_year, p_month, 1) d0, (make_date(p_year, p_month, 1) + interval '1 month')::date d1),
  e as (
    select s.person_id, s.day, bool_or(not s.is_extra) reg, bool_or(s.is_extra) ext
    from schedule_entries s, b
    where s.person_id is not null and s.day >= b.d0 and s.day < b.d1
      and s.value ~ '^\s*\d{1,2}(:\d{2})?\s*-\s*\d{1,2}'
    group by s.person_id, s.day
  ),
  agg as (
    select e.person_id,
      count(*) filter (where e.reg)::int reg_days,
      count(*)::int work_days,
      count(*) filter (where e.ext)::int extra_days,
      count(h.day)::int holiday_days,
      string_agg(to_char(h.day,'DD.MM') || ' ' || h.name, ', ' order by h.day) holiday_list
    from e left join holidays h on h.day = e.day
    group by e.person_id
  ),
  r as (
    select p.id, p.name, p.position, pb.monthly, pb.daily,
      coalesce(a.reg_days,0) reg_days, coalesce(a.work_days,0) work_days,
      coalesce(a.extra_days,0) extra_days, coalesce(a.holiday_days,0) holiday_days, a.holiday_list,
      case when pb.monthly is not null then round(pb.monthly / 22, 2) else pb.daily end rate
    from schedule_people p
    left join payroll_base pb on pb.person_id = p.id
    left join agg a on a.person_id = p.id
  )
  select id, name, position, monthly, rate, work_days, extra_days, holiday_days, holiday_list,
    coalesce(case when monthly is not null then monthly else reg_days * rate end, 0) base_pay,
    coalesce(extra_days * rate, 0) extra_pay,
    coalesce(holiday_days * rate, 0) holiday_pay,
    coalesce(case when monthly is not null then monthly else reg_days * rate end, 0)
      + coalesce(extra_days * rate, 0) + coalesce(holiday_days * rate, 0) total,
    rate is null missing_base
  from r
  where auth.uid() is null or public.is_admin()
  order by name;
$$;
grant execute on function public.payroll_month(int, int) to authenticated;
