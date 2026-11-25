-- Notify the individual staff member about every admin change that concerns them.
-- Already covered elsewhere: schedule changes (024), request approved/rejected/changed and extra corrections (023, 025),
-- leave balance corrections (client), payroll confirmation (016), Kontrollat (client).
-- Added here:
--   * admin edits a request that is still pending (dates, type, shift or comment) or only the comment of a decided request
--   * admin deletes a request
--   * pay adjustment (bonus / deduction) added or removed
--   * base salary changed
--   * account linked to a name in the schedule

create or replace function public.notify_person(p_person uuid, p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, title, body)
  select user_id, p_title, left(p_body, 2000) from public.schedule_people where id = p_person and user_id is not null;
$$;
revoke all on function public.notify_person(uuid, text, text) from public, anon, authenticated;

create or replace function public.first_name(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(split_part(full_name, ' ', 1), '') from public.profiles where id = p_user;
$$;
revoke all on function public.first_name(uuid) from public, anon, authenticated;

create or replace function public.absence_label(t text)
returns text language sql immutable as $$
  select case t
    when 'vjetor' then 'Pushimi vjetor' when 'mjekesor' then 'Pushimi mjekësor'
    when 'mjekesor_pp' then 'Pushimi mjekësor pa pagesë' when 'martese' then 'Leja për martesë'
    when 'vdekje' then 'Leja për vdekje në familje' when 'lindje' then 'Leja për lindje fëmije'
    when 'gjak' then 'Leja për dhurim gjaku' when 'papagese' then 'Pushimi pa pagesë'
    when 'bartur' then 'Pushimi i bartur' when 'kompenzim' then 'Pushimi me kompenzim'
    when 'extra' then 'Puna extra' else 'Kërkesa' end;
$$;

create or replace function public.absence_period(a public.absences)
returns text language sql immutable as $$
  select case when a.from_date = a.to_date then to_char(a.from_date, 'DD.MM.YYYY')
              else to_char(a.from_date, 'DD.MM.YYYY') || ' – ' || to_char(a.to_date, 'DD.MM.YYYY') end
         || case when a.leave_type = 'extra' and a.shift is not null then ', ndërrimi ' || a.shift
                 when a.leave_type <> 'extra' then ' (' || a.days || ' ditë)' else '' end;
$$;

-- Request updates (replaces 025 version; adds pending edits and comment-only changes)
create or replace function public.trg_absence_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare lbl text := public.absence_label(new.leave_type); per text := public.absence_period(new);
        first text := public.first_name(new.user_id); t text; b text;
        changed boolean := (new.from_date, new.to_date, new.days, new.leave_type, coalesce(new.shift, ''))
                           is distinct from (old.from_date, old.to_date, old.days, old.leave_type, coalesce(old.shift, ''));
        cmt boolean := coalesce(btrim(new.admin_comment), '') is distinct from coalesce(btrim(old.admin_comment), '');
begin
  if old.req_at is not null and new.req_at is null and public.is_admin() then
    if (new.from_date, new.to_date, coalesce(new.shift, '')) = (old.req_from, old.req_to, coalesce(old.req_shift, '')) then
      t := 'Korrigjimi i orarit u miratua';
      b := 'Përshëndetje ' || first || ', korrigjimi juaj u miratua nga administratori. Puna extra tani është: ' || per || '. Orari u përditësua.';
    else
      t := 'Korrigjimi i orarit nuk u miratua';
      b := 'Përshëndetje ' || first || ', korrigjimi juaj (' ||
        case when old.req_from = old.req_to then to_char(old.req_from, 'DD.MM.YYYY') else to_char(old.req_from, 'DD.MM.YYYY') || ' – ' || to_char(old.req_to, 'DD.MM.YYYY') end ||
        ', ndërrimi ' || coalesce(old.req_shift, '') || ') nuk u miratua. Mbetet puna extra e miratuar: ' || per || '.';
    end if;
  elsif new.status = 'approved' and old.status is distinct from 'approved' then
    t := lbl || ' u miratua';
    b := 'Përshëndetje ' || first || ', ' || lower(left(lbl, 1)) || substr(lbl, 2) || ' për ' || per || ' u miratua nga administratori.'
      || case when new.leave_type = 'extra' then ' Dita u shtua në orarin tuaj.' else '' end;
  elsif new.status = 'rejected' and old.status is distinct from 'rejected' then
    t := lbl || ' nuk u miratua';
    b := 'Përshëndetje ' || first || ', kërkesa juaj (' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || ') nuk u miratua nga administratori.';
  elsif new.status = old.status and public.is_admin() and changed then
    t := lbl || ' u ndryshua';
    b := 'Përshëndetje ' || first || ', administratori ndryshoi kërkesën tuaj' ||
      case new.status when 'approved' then ' të miratuar' when 'pending' then ' (ende në pritje të miratimit)' else '' end ||
      ': ' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || '.';
  elsif new.status = old.status and public.is_admin() and cmt and coalesce(btrim(new.admin_comment), '') <> '' then
    t := 'Koment i ri për kërkesën tuaj';
    b := 'Përshëndetje ' || first || ', administratori shtoi një koment te kërkesa juaj (' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || ').';
  else
    return null;
  end if;
  if new.admin_comment is not null and btrim(new.admin_comment) <> '' then
    b := b || E'\nKomenti: ' || new.admin_comment;
  end if;
  insert into notifications (user_id, title, body) values (new.user_id, t, left(b, 2000));
  return null;
end $$;

-- Request deleted by the admin
create or replace function public.trg_absence_delete_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare lbl text := public.absence_label(old.leave_type);
begin
  if public.is_admin() and old.user_id is distinct from auth.uid() then
    insert into notifications (user_id, title, body) values (old.user_id, lbl || ' u fshi',
      'Përshëndetje ' || public.first_name(old.user_id) || ', administratori fshiu kërkesën tuaj: ' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || public.absence_period(old) || '.'
      || case when old.leave_type = 'extra' and old.status = 'approved' then ' Dita u hoq nga orari juaj.' else '' end);
  end if;
  return null;
end $$;
create or replace trigger absences_delete_notify after delete on public.absences for each row execute function public.trg_absence_delete_notify();

-- Pay adjustments (bonus / deduction)
create or replace function public.trg_adjust_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare r public.payroll_adjust := case when tg_op = 'DELETE' then old else new end;
        mn text[] := array['janar','shkurt','mars','prill','maj','qershor','korrik','gusht','shtator','tetor','nëntor','dhjetor'];
        amt text := replace(to_char(abs(r.amount), 'FM999990.00'), '.', ',') || ' €';
begin
  perform public.notify_person(r.person_id,
    case when tg_op = 'DELETE' then 'Ndryshimi në pagë u hoq' else 'Ndryshim në pagë' end,
    'Për pagën e ' || mn[r.month] || ' ' || r.year || ': ' ||
    case when tg_op = 'DELETE' then 'u hoq ' else 'u shtua ' end ||
    case when r.amount >= 0 then 'shtesa +' else 'zbritja −' end || amt ||
    coalesce(' (' || nullif(btrim(r.note), '') || ')', '') || '.' ||
    E'\nPaga përfundimtare ju dërgohet kur administratori konfirmon listën e pagave.');
  return null;
end $$;
create or replace trigger payroll_adjust_notify after insert or delete on public.payroll_adjust for each row execute function public.trg_adjust_notify();

-- Base salary changed
create or replace function public.trg_base_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare fm text;
begin
  if tg_op = 'UPDATE' and (new.monthly, new.daily) is not distinct from (old.monthly, old.daily) then return null; end if;
  if new.monthly is null and new.daily is null then return null; end if;
  fm := case when new.monthly is not null then 'paga mujore ' || replace(to_char(new.monthly, 'FM999990.00'), '.', ',') || ' €'
             else 'paga ditore (part time) ' || replace(to_char(new.daily, 'FM999990.00'), '.', ',') || ' €' end;
  perform public.notify_person(new.person_id, 'Paga bazë u përditësua', 'Administratori përditësoi pagën tuaj bazë: ' || fm || '.');
  return null;
end $$;
create or replace trigger payroll_base_notify after insert or update on public.payroll_base for each row execute function public.trg_base_notify();

-- Account linked to a name in the schedule
create or replace function public.trg_link_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is not null and new.user_id is distinct from old.user_id then
    insert into notifications (user_id, title, body) values (new.user_id, 'Orari juaj u lidh me llogarinë',
      'Përshëndetje ' || public.first_name(new.user_id) || ', llogaria juaj u lidh me emrin "' || new.name || '" në orar. Tani te "Orari im" shihni ndërrimet tuaja dhe merrni njoftim për çdo ndryshim.');
  end if;
  return null;
end $$;
create or replace trigger people_link_notify after update of user_id on public.schedule_people for each row execute function public.trg_link_notify();
