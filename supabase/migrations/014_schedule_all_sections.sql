-- Staff see the schedule of all sections (user, 2026-11-10), so they can see which colleagues share their shift.
-- Before: only the sections they appear in (my_schedule_depts()). Editing stays admin-only.
drop policy if exists "schedule entries read own sections" on public.schedule_entries;
create policy "schedule entries read approved" on public.schedule_entries for select to authenticated
  using (public.is_admin() or public.is_approved());
