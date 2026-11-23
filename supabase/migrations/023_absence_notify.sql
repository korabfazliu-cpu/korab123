-- Notify staff about their requests (user, 2026-11-23): every time the admin approves (or refuses) a request of any
-- type — annual, sick, unpaid sick, special leave, unpaid leave, extra work — and when the admin changes an approved
-- request. The notification row also goes to their phone through the push trigger (022).
create or replace function public.trg_absence_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare lbl text; per text; first text; t text; b text;
begin
  lbl := case new.leave_type
    when 'vjetor' then 'Pushimi vjetor' when 'mjekesor' then 'Pushimi mjekësor'
    when 'mjekesor_pp' then 'Pushimi mjekësor pa pagesë' when 'martese' then 'Leja për martesë'
    when 'vdekje' then 'Leja për vdekje në familje' when 'lindje' then 'Leja për lindje fëmije'
    when 'gjak' then 'Leja për dhurim gjaku' when 'papagese' then 'Pushimi pa pagesë'
    when 'bartur' then 'Pushimi i bartur' when 'kompenzim' then 'Pushimi me kompenzim'
    when 'extra' then 'Puna extra' else 'Kërkesa' end;
  per := case when new.from_date = new.to_date then to_char(new.from_date, 'DD.MM.YYYY')
              else to_char(new.from_date, 'DD.MM.YYYY') || ' – ' || to_char(new.to_date, 'DD.MM.YYYY') end
         || case when new.leave_type = 'extra' and new.shift is not null then ', ndërrimi ' || new.shift
                 when new.leave_type <> 'extra' then ' (' || new.days || ' ditë)' else '' end;
  select split_part(full_name, ' ', 1) into first from profiles where id = new.user_id;

  if new.status = 'approved' and old.status is distinct from 'approved' then
    t := lbl || ' u miratua';
    b := 'Përshëndetje ' || coalesce(first, '') || ', ' || lower(left(lbl, 1)) || substr(lbl, 2) || ' për ' || per || ' u miratua nga administratori.'
      || case when new.leave_type = 'extra' then ' Dita u shtua në orarin tuaj.' else '' end;
  elsif new.status = 'rejected' and old.status is distinct from 'rejected' then
    t := lbl || ' nuk u miratua';
    b := 'Përshëndetje ' || coalesce(first, '') || ', kërkesa juaj (' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || ') nuk u miratua nga administratori.';
  elsif new.status = 'approved' and old.status = 'approved'
        and (new.from_date, new.to_date, new.days, new.leave_type, coalesce(new.shift, ''))
            is distinct from (old.from_date, old.to_date, old.days, old.leave_type, coalesce(old.shift, '')) then
    t := lbl || ' u ndryshua';
    b := 'Përshëndetje ' || coalesce(first, '') || ', administratori ndryshoi kërkesën tuaj të miratuar: ' || lower(left(lbl, 1)) || substr(lbl, 2) || ', ' || per || '.';
  else
    return null;
  end if;
  if new.admin_comment is not null and btrim(new.admin_comment) <> '' then
    b := b || E'\nKomenti: ' || new.admin_comment;
  end if;
  insert into notifications (user_id, title, body) values (new.user_id, t, left(b, 2000));
  return null;
end $$;
drop trigger if exists absences_notify on public.absences;
create trigger absences_notify after update on public.absences
  for each row execute function public.trg_absence_notify();
