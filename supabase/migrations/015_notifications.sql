-- In-app notifications for staff (user, 2026-11-10): e.g. when the admin corrects leave balances.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
create policy "notifications read own or admin" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());
create policy "notifications admin insert" on public.notifications for insert to authenticated
  with check (public.is_admin());
create policy "notifications mark own read" on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
