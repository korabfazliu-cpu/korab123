-- "Xoni" in the schedule Excel is Egzon Bellagoshi (user, 2026-11-10).
update public.schedule_people set aliases = array_append(aliases, 'Xoni')
  where name = 'Egzon Bellagoshi' and not ('Xoni' = any(aliases));
update public.schedule_entries e set person_id = p.id
  from public.schedule_people p
  where p.name = 'Egzon Bellagoshi' and e.person_id is null and lower(trim(e.person_label)) = 'xoni';

-- Extra entries marked with * (e.g. 07-15*) are not extra days (user, 2026-11-10):
-- not paid and not counted as work days. Same function as 007 plus one filter.
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
      and not (s.is_extra and s.value like '%*%')
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
