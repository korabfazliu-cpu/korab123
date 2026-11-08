-- Staff leave tracker: schema, security (RLS) and storage rules.
-- Replace YOUR_ADMIN_EMAIL below before running.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  position text not null,
  role text not null default 'staff' check (role in ('staff','admin')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create table public.absences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  leave_type text not null default 'mjekesor'
    check (leave_type in ('vjetor','mjekesor','martese','vdekje','lindje','gjak','papagese','bartur','kompenzim')),
  from_date date not null,
  to_date date not null,
  days int not null check (days between 1 and 20),
  note text,
  doc_path text,
  created_at timestamptz not null default now(),
  check (to_date >= from_date),
  check (days <= (to_date - from_date) + 1),
  constraint absences_doc_required check (leave_type <> 'mjekesor' or days <= 3 or doc_path is not null),
  check (doc_path is null or doc_path like user_id::text || '/%')
);
create index absences_user_idx on public.absences(user_id, from_date);

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin' and status = 'approved')
$$;

create function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and status = 'approved')
$$;

-- New signups are 'pending'; the super admin email is approved as admin automatically.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare is_super boolean := lower(new.email) = lower('YOUR_ADMIN_EMAIL');
begin
  insert into public.profiles(id, full_name, position, role, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.raw_user_meta_data->>'position',''),
    case when is_super then 'admin' else 'staff' end,
    case when is_super then 'approved' else 'pending' end
  );
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- Yearly allowance per leave type (0 = no fixed limit).
create function public.check_absence_quota() returns trigger
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
    where user_id = new.user_id and leave_type = new.leave_type
      and extract(year from from_date) = extract(year from new.from_date);
    if used + new.days > allowed then
      raise exception 'Kaluat ditët e lejuara për këtë lloj pushimi (%).', allowed;
    end if;
  end if;
  return new;
end $$;
create trigger absences_quota before insert on public.absences
for each row execute function public.check_absence_quota();

revoke execute on function public.is_admin(), public.is_approved() from public, anon;
grant execute on function public.is_admin(), public.is_approved() to authenticated;
revoke execute on function public.handle_new_user(), public.check_absence_quota() from public, anon, authenticated;

alter table public.profiles enable row level security;
alter table public.absences enable row level security;

create policy "profiles read own or admin" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());
create policy "profiles admin update" on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "absences read own or admin" on public.absences for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());
create policy "absences insert own approved" on public.absences for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_approved());
create policy "absences admin delete" on public.absences for delete to authenticated
  using (public.is_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documents','documents', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

create policy "documents upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_approved());
create policy "documents read own or admin" on storage.objects for select to authenticated
  using (bucket_id = 'documents' and ((storage.foldername(name))[1] = (select auth.uid())::text or public.is_admin()));
