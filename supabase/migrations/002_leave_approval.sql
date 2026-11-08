-- Leave requests need admin approval.
-- New requests start as 'pending'; only an admin can set 'approved' or 'rejected'.
-- Rows that existed before this migration are treated as approved.

alter table public.absences
  add column status text not null default 'approved'
    check (status in ('pending','approved','rejected')),
  add column reviewed_at timestamptz,
  add column reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.absences alter column status set default 'pending';

-- Staff can only create pending requests.
drop policy "absences insert own approved" on public.absences;
create policy "absences insert own approved" on public.absences for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_approved() and status = 'pending');

-- Admins can review requests; only the review columns are updatable.
create policy "absences admin update" on public.absences for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
revoke update on public.absences from anon, authenticated;
grant update (status, reviewed_at, reviewed_by) on public.absences to authenticated;

create function public.stamp_absence_review() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
  end if;
  return new;
end $$;
create trigger absences_review before update on public.absences
for each row execute function public.stamp_absence_review();
revoke execute on function public.stamp_absence_review() from public, anon, authenticated;

-- Yearly allowance: pending and approved requests count, rejected ones do not.
create or replace function public.check_absence_quota() returns trigger
language plpgsql security definer set search_path = public as $$
declare used int; allowed int;
begin
  allowed := case new.leave_type
    when 'vjetor' then 20 when 'mjekesor' then 20
    when 'martese' then 5 when 'vdekje' then 5
    when 'lindje' then 3 when 'gjak' then 2
    else 0 end;
  if allowed > 0 then
    select coalesce(sum(days),0) into used from public.absences
    where user_id = new.user_id and leave_type = new.leave_type and status <> 'rejected'
      and extract(year from from_date) = extract(year from new.from_date);
    if used + new.days > allowed then
      raise exception 'Kaluat ditët e lejuara për këtë lloj pushimi (%).', allowed;
    end if;
  end if;
  return new;
end $$;
