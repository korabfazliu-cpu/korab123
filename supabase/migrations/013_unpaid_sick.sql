-- Sick leave after the 20 days are used up (user, 2026-11-10): staff confirm a notice and the request is stored
-- as leave_type 'mjekesor_pp' ("Pushim mjekësor pa pagesë"). Approved days are deducted from pay:
-- unpaid_days × daily rate for monthly staff (part-time staff are paid per worked day anyway).
alter table public.absences drop constraint absences_leave_type_check;
alter table public.absences add constraint absences_leave_type_check check (leave_type = any (array[
  'vjetor','mjekesor','mjekesor_pp','martese','vdekje','lindje','gjak','papagese','bartur','kompenzim','extra']));

drop function public.payroll_month(int, int);
create function public.payroll_month(p_year int, p_month int)
returns table (person_id uuid, name text, "position" text, monthly numeric, daily_rate numeric,
  work_days int, extra_days int, holiday_days int, holiday_list text,
  base_pay numeric, extra_pay numeric, holiday_pay numeric, total numeric, missing_base boolean,
  unpaid_days int, unpaid_pay numeric)
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
  -- approved "Pushim mjekësor pa pagesë" days inside the month (sick days after the 20 are used up)
  u as (
    select sp.id person_id, sum(least(a.days, (least(a.to_date, b.d1 - 1) - greatest(a.from_date, b.d0) + 1)))::int unpaid_days
    from absences a join schedule_people sp on sp.user_id = a.user_id, b
    where a.leave_type = 'mjekesor_pp' and a.status = 'approved' and a.from_date < b.d1 and a.to_date >= b.d0
    group by sp.id
  ),
  r as (
    select p.id, p.name, p.position, pb.monthly, pb.daily,
      coalesce(a.reg_days,0) reg_days, coalesce(a.work_days,0) work_days,
      coalesce(a.extra_days,0) extra_days, coalesce(a.holiday_days,0) holiday_days, a.holiday_list,
      case when pb.monthly is not null then round(pb.monthly / 22, 2) else pb.daily end rate,
      coalesce(u.unpaid_days, 0) unpaid_days
    from schedule_people p
    left join u on u.person_id = p.id
    left join payroll_base pb on pb.person_id = p.id
    left join agg a on a.person_id = p.id
  )
  select id, name, position, monthly, rate, work_days, extra_days, holiday_days, holiday_list,
    coalesce(case when monthly is not null then monthly else reg_days * rate end, 0) base_pay,
    coalesce(extra_days * rate, 0) extra_pay,
    coalesce(holiday_days * rate, 0) holiday_pay,
    coalesce(case when monthly is not null then monthly else reg_days * rate end, 0)
      + coalesce(extra_days * rate, 0) + coalesce(holiday_days * rate, 0)
      - case when monthly is not null then coalesce(unpaid_days * rate, 0) else 0 end total,
    rate is null missing_base,
    unpaid_days,
    case when monthly is not null then coalesce(unpaid_days * rate, 0) else 0 end unpaid_pay
  from r
  where auth.uid() is null or public.is_admin()
  order by name;
$$;
grant execute on function public.payroll_month(int, int) to authenticated;
