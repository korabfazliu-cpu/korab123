-- Admin can delete user accounts from the app.
-- Deleting the auth user cascades to profiles and that user's absences (leave requests).
-- Extra-work schedule rows created from their approved requests are kept (absence_id is cleared first),
-- so schedules and payroll for past months do not change. The staff list entry (schedule_people)
-- stays and is just unlinked (user_id -> null).

create or replace function public.admin_delete_user(p_user uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Vetëm administratori mund të fshijë llogari.'; end if;
  if p_user = auth.uid() then raise exception 'Nuk mund ta fshini llogarinë tuaj.'; end if;
  if exists (select 1 from public.profiles where id = p_user and role = 'admin') then
    raise exception 'Llogaritë e administratorëve nuk fshihen nga aplikacioni.';
  end if;
  update public.schedule_entries set absence_id = null
    where absence_id in (select id from public.absences where user_id = p_user);
  delete from auth.users where id = p_user;
  if not found then raise exception 'Llogaria nuk u gjet.'; end if;
end $$;
revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Emails of accounts, for the admin's account list.
create or replace function public.admin_user_emails() returns table (id uuid, email text, last_sign_in_at timestamptz)
language sql stable security definer set search_path = public, auth as $$
  select u.id, u.email::text, u.last_sign_in_at from auth.users u where public.is_admin();
$$;
revoke all on function public.admin_user_emails() from public, anon;
grant execute on function public.admin_user_emails() to authenticated;
