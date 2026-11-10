-- Payroll confirmation (user, 2026-11-10):
-- * payroll_adjust: admin's manual changes per person and month (+/- amount with a note), included in payroll_month.total.
-- * confirm_payroll(year, month): admin confirms the month's list; a snapshot is saved per person (payroll_slips)
--   and every staff member linked to an account gets a notification with the pay they will receive.
--   Confirming again replaces the snapshot and sends an "updated" notification.
-- * Staff read their own slips; admin reads all.

create table public.payroll_adjust (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.schedule_people(id) on delete cascade,
  year int not null check (year between 2000 and 2100),
  month int not null check (month between 1 and 12),
  amount numeric(10,2) not null check (amount between -100000 and 100000),
  note text not null check (char_length(note) between 1 and 200),
  created_at timestamptz not null default now()
);
create index payroll_adjust_idx on public.payroll_adjust (year, month, person_id);
alter table public.payroll_adjust enable row level security;
create policy "payroll adjust admin" on public.payroll_adjust for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.payroll_confirm (
  year int not null, month int not null,
  confirmed_at timestamptz not null default now(),
  confirmed_by uuid references public.profiles(id) on delete set null,
  times int not null default 1,
  primary key (year, month)
);
alter table public.payroll_confirm enable row level security;
create policy "payroll confirm admin" on public.payroll_confirm for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.payroll_slips (
  person_id uuid not null references public.schedule_people(id) on delete cascade,
  year int not null, month int not null,
  user_id uuid references public.profiles(id) on delete set null,
  data jsonb not null,
  total numeric(10,2) not null,
  confirmed_at timestamptz not null default now(),
  primary key (person_id, year, month)
);
alter table public.payroll_slips enable row level security;
create policy "payroll slips read own or admin" on public.payroll_slips for select to authenticated
  using (public.is_admin() or user_id = (select auth.uid()));
create policy "payroll slips admin" on public.payroll_slips for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop function public.payroll_month(int, int);
create function public.payroll_month(p_year int, p_month int)
returns table (person_id uuid, name text, "position" text, monthly numeric, daily_rate numeric,
  work_days int, extra_days int, holiday_days int, holiday_list text,
  base_pay numeric, extra_pay numeric, holiday_pay numeric, total numeric, missing_base boolean,
  unpaid_days int, unpaid_pay numeric, adj_amount numeric, adj_note text)
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
  adj as (
    select pa.person_id, sum(pa.amount) amount, string_agg(pa.note, '; ' order by pa.created_at) note
    from payroll_adjust pa where pa.year = p_year and pa.month = p_month group by pa.person_id
  ),
  r as (
    select p.id, p.name, p.position, pb.monthly, pb.daily,
      coalesce(a.reg_days,0) reg_days, coalesce(a.work_days,0) work_days,
      coalesce(a.extra_days,0) extra_days, coalesce(a.holiday_days,0) holiday_days, a.holiday_list,
      case when pb.monthly is not null then round(pb.monthly / 22, 2) else pb.daily end rate,
      coalesce(u.unpaid_days, 0) unpaid_days,
      coalesce(adj.amount, 0) adj_amount, adj.note adj_note
    from schedule_people p
    left join adj on adj.person_id = p.id
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
      - case when monthly is not null then coalesce(unpaid_days * rate, 0) else 0 end
      + adj_amount total,
    rate is null missing_base,
    unpaid_days,
    case when monthly is not null then coalesce(unpaid_days * rate, 0) else 0 end unpaid_pay,
    adj_amount, adj_note
  from r
  where auth.uid() is null or public.is_admin()
  order by name;
$$;
grant execute on function public.payroll_month(int, int) to authenticated;

create or replace function public.eur_txt(v numeric) returns text
language sql immutable as $$
  select replace(replace(replace(to_char(round(coalesce(v,0),2), 'FM999G999G990D00'), ',', '#'), '.', ','), '#', '.') || ' €';
$$;

create or replace function public.confirm_payroll(p_year int, p_month int) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; again boolean; mname text; body text;
begin
  if not public.is_admin() then raise exception 'Vetëm administratori mund ta konfirmojë listën e pagave.'; end if;
  again := exists (select 1 from payroll_confirm where year = p_year and month = p_month);
  mname := (array['janar','shkurt','mars','prill','maj','qershor','korrik','gusht','shtator','tetor','nëntor','dhjetor'])[p_month] || ' ' || p_year;
  delete from payroll_slips where year = p_year and month = p_month;
  for r in select pm.*, sp.user_id from payroll_month(p_year, p_month) pm join schedule_people sp on sp.id = pm.person_id
           where not pm.missing_base loop
    insert into payroll_slips (person_id, year, month, user_id, data, total)
      values (r.person_id, p_year, p_month, r.user_id, to_jsonb(r) - 'user_id', r.total);
    if r.user_id is not null then
      body := 'Përshëndetje ' || split_part(r.name, ' ', 1) || ', paga juaj për ' || mname || ' është ' || eur_txt(r.total) || '.' || E'\n'
        || case when r.monthly is not null then '• Paga bazë: ' || eur_txt(r.base_pay)
                else '• Part time: ' || round(r.base_pay / nullif(r.daily_rate, 0)) || ' ditë × ' || eur_txt(r.daily_rate) || ' = ' || eur_txt(r.base_pay) end
        || case when r.extra_days > 0 then E'\n• Ditë extra: ' || r.extra_days || ' × ' || eur_txt(r.daily_rate) || ' = +' || eur_txt(r.extra_pay) else '' end
        || case when r.holiday_days > 0 then E'\n• Festa zyrtare në punë: ' || r.holiday_days || ' (' || r.holiday_list || ') = +' || eur_txt(r.holiday_pay) else '' end
        || case when r.unpaid_pay > 0 then E'\n• Pushim mjekësor pa pagesë: ' || r.unpaid_days || ' ditë = −' || eur_txt(r.unpaid_pay) else '' end
        || case when r.adj_amount <> 0 then E'\n• Ndryshim nga administratori: ' || case when r.adj_amount > 0 then '+' else '−' end || eur_txt(abs(r.adj_amount)) || coalesce(' (' || r.adj_note || ')', '') else '' end
        || E'\nPër pyetje, na kontaktoni.';
      insert into notifications (user_id, title, body)
        values (r.user_id, case when again then 'Paga e ' || mname || ' u përditësua' else 'Paga e ' || mname end, body);
    end if;
    n := n + 1;
  end loop;
  insert into payroll_confirm (year, month, confirmed_by) values (p_year, p_month, auth.uid())
    on conflict (year, month) do update set confirmed_at = now(), confirmed_by = excluded.confirmed_by, times = payroll_confirm.times + 1;
  return n;
end $$;
revoke all on function public.confirm_payroll(int, int) from public, anon;
grant execute on function public.confirm_payroll(int, int) to authenticated;
