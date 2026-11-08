-- Admins can correct a leave request (type, dates, days) and leave a comment for the employee.

alter table public.absences
  add column admin_comment text check (char_length(admin_comment) <= 1000),
  add column edited_at timestamptz;

-- RLS ("absences admin update") already limits updates to admins; widen the updatable columns.
grant update (leave_type, from_date, to_date, days, admin_comment) on public.absences to authenticated;

create or replace function public.stamp_absence_review() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
  end if;
  if (new.leave_type, new.from_date, new.to_date, new.days)
     is distinct from (old.leave_type, old.from_date, old.to_date, old.days) then
    new.edited_at := now();
  end if;
  return new;
end $$;

-- Yearly allowance also checked when an admin edits a request. The row itself is excluded
-- from the sum, and rejected requests never count.
create or replace function public.check_absence_quota() returns trigger
language plpgsql security definer set search_path = public as $$
declare used int; allowed int;
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
    if used + new.days > allowed then
      raise exception 'Kaluat ditët e lejuara për këtë lloj pushimi (%).', allowed;
    end if;
  end if;
  return new;
end $$;

drop trigger absences_quota on public.absences;
create trigger absences_quota before insert or update of leave_type, from_date, to_date, days, status
on public.absences for each row execute function public.check_absence_quota();
