-- Follow-up (user, 2026-11-12): items marked "Jo" or "Intervenim" go back to the inspector after the admin
-- reviews the check; the inspector re-checks each one (done / not yet + note) and sends the final result to the admin.
-- Statuses: draft → submitted → (returned) → followup → final → closed  (or reviewed when nothing needed intervention).
alter table public.check_reports drop constraint check_reports_status_check;
alter table public.check_reports add constraint check_reports_status_check
  check (status in ('draft','submitted','returned','reviewed','followup','final','closed'));
alter table public.check_reports
  add column followup jsonb,            -- [{"si":0,"ii":3,"text":"...","res":"done|notyet","note":"...","at":"2026-11-13"}]
  add column final_at timestamptz;

drop policy "check reports update" on public.check_reports;
create policy "check reports update" on public.check_reports for update to authenticated
  using (public.is_admin() or (user_id = (select auth.uid()) and public.has_check_access() and status in ('draft','returned','followup')))
  with check (public.is_admin() or (user_id = (select auth.uid()) and status in ('draft','submitted','followup','final')));

create or replace function public.check_report_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if not public.is_admin() then
    if tg_op = 'UPDATE' then
      new.admin_comment := old.admin_comment; new.reviewed_at := old.reviewed_at; new.user_id := old.user_id;
      if old.status = 'followup' then
        -- during the re-check only the follow-up results may change
        if new.status not in ('followup','final') then new.status := old.status; end if;
        new.sections := old.sections; new.problems := old.problems; new.title := old.title;
        new.check_date := old.check_date; new.check_time := old.check_time; new.template_id := old.template_id;
      else
        new.followup := old.followup;
        if new.status not in ('draft','submitted') then new.status := old.status; end if;
      end if;
    else
      new.admin_comment := null; new.reviewed_at := null; new.followup := null;
    end if;
  end if;
  new.updated_at := now();
  select full_name into who from profiles where id = new.user_id;
  if new.status = 'submitted' and (tg_op = 'INSERT' or old.status is distinct from 'submitted') then
    new.submitted_at := now();
    insert into notifications (user_id, title, body)
      select p.id, 'Kontroll i ri: ' || new.title,
        coalesce(who, 'Stafi') || ' dërgoi kontrollin e ' || to_char(new.check_date, 'DD.MM.YYYY') || coalesce(' ora ' || new.check_time, '') || '. Shihni skedën Kontrollat.'
      from profiles p where p.role = 'admin';
  end if;
  if tg_op = 'UPDATE' and new.status = 'final' and old.status is distinct from 'final' then
    new.final_at := now();
    insert into notifications (user_id, title, body)
      select p.id, 'Rikontrolli përfundoi: ' || new.title,
        coalesce(who, 'Stafi') || ' dërgoi rezultatin final të rikontrollit për kontrollin e ' || to_char(new.check_date, 'DD.MM.YYYY') || '. Shihni skedën Kontrollat.'
      from profiles p where p.role = 'admin';
  end if;
  return new;
end $$;
