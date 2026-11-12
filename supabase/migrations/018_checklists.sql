-- Workplace inspection checklists ("Kontrollat"), user 2026-11-12.
-- Only the admin and staff explicitly granted access (check_access) can see or fill them; everyone else gets nothing.
-- The admin keeps the checklist templates; the inspector fills a report (OK / Jo / Intervenim + note per item,
-- problems needing intervention) and submits it; the admin is notified, reviews it or returns it for correction.

create table public.check_access (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  granted_at timestamptz not null default now()
);
alter table public.check_access enable row level security;
create policy "check access read own or admin" on public.check_access for select to authenticated
  using (public.is_admin() or user_id = (select auth.uid()));
create policy "check access admin" on public.check_access for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create or replace function public.has_check_access() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or (public.is_approved() and exists (select 1 from check_access where user_id = auth.uid()));
$$;
grant execute on function public.has_check_access() to authenticated;

create table public.check_templates (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 160),
  sections jsonb not null,            -- [{"title": "...", "items": ["...", ...]}, ...]
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.check_templates enable row level security;
create policy "check templates read" on public.check_templates for select to authenticated using (public.has_check_access());
create policy "check templates admin" on public.check_templates for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.check_reports (
  id uuid primary key default gen_random_uuid(),
  template_id uuid references public.check_templates(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) <= 160),
  check_date date not null default current_date,
  check_time text check (char_length(check_time) <= 10),
  sections jsonb not null,            -- template sections with answers: items [{"text","ans":"ok|jo|int","note"}]
  problems text check (char_length(problems) <= 4000),
  status text not null default 'draft' check (status in ('draft','submitted','returned','reviewed')),
  admin_comment text check (char_length(admin_comment) <= 1000),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index check_reports_user_idx on public.check_reports (user_id, created_at desc);
alter table public.check_reports enable row level security;
create policy "check reports read" on public.check_reports for select to authenticated
  using (public.is_admin() or (user_id = (select auth.uid()) and public.has_check_access()));
create policy "check reports insert own" on public.check_reports for insert to authenticated
  with check (user_id = (select auth.uid()) and public.has_check_access() and status in ('draft','submitted'));
create policy "check reports update" on public.check_reports for update to authenticated
  using (public.is_admin() or (user_id = (select auth.uid()) and public.has_check_access() and status in ('draft','returned')))
  with check (public.is_admin() or (user_id = (select auth.uid()) and status in ('draft','submitted')));
create policy "check reports delete" on public.check_reports for delete to authenticated
  using (public.is_admin() or (user_id = (select auth.uid()) and status = 'draft'));

-- Staff cannot touch the admin's fields; submit time is stamped; admins are notified on submit.
create or replace function public.check_report_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if not public.is_admin() then
    if tg_op = 'UPDATE' then
      new.admin_comment := old.admin_comment; new.reviewed_at := old.reviewed_at; new.user_id := old.user_id;
    else
      new.admin_comment := null; new.reviewed_at := null;
    end if;
  end if;
  new.updated_at := now();
  if new.status = 'submitted' and (tg_op = 'INSERT' or old.status is distinct from 'submitted') then
    new.submitted_at := now();
    select full_name into who from profiles where id = new.user_id;
    insert into notifications (user_id, title, body)
      select p.id, 'Kontroll i ri: ' || new.title,
        coalesce(who, 'Stafi') || ' dërgoi kontrollin e ' || to_char(new.check_date, 'DD.MM.YYYY') || coalesce(' ora ' || new.check_time, '') || '. Shihni skedën Kontrollat.'
      from profiles p where p.role = 'admin';
  end if;
  return new;
end $$;
create trigger check_report_guard before insert or update on public.check_reports
  for each row execute function public.check_report_guard();

-- The template from Formular_Kontrolli_Parking_Center.docx
insert into public.check_templates (title, sections) values (
  'Formular për kontrollin e vendit të punës',
  '[{"title":"Kontrolli i pastrimit","items":["Tualetet – pastërtia dhe higjiena","Dyert","Lavamanët","Shportat e mbeturinave","Guacat e tualeteve","Ndriçimi","Pastërtia e përgjithshme","Shkallët","Xhamat","Lifti – pastërtia dhe gjendja","Hyrje/Daljet – Ndriçimi"]},
    {"title":"Kontrolli i parkingut","items":["Makinat / pajisjet e parkingut","Shampoja / materialet e pastrimit","Ndriçimi i parkingut","Larja e parkingut","Depoja – rendi dhe pastërtia","Shenjëzimi horizontal dhe vertikal","Hidrantët dhe pajisjet kundër zjarrit","Ventilimi","Sensorët e zjarrit","Muret – pastërtia dhe gjendja","Ngjyra / dëmtimet e sipërfaqeve","Ndihma e parë – pajisjet dhe kompletimi"]}]'::jsonb);

-- Access for Valton Mustafa (his linked account)
insert into public.check_access (user_id)
  select user_id from public.schedule_people where name = 'Valton Mustafa' and user_id is not null
  on conflict do nothing;
