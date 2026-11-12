-- Pastrim days off corrected (user, 2026-11-12): Flora (Florije Neziri) is off Wednesday and Thursday,
-- Sanie (Sanie Hajdini) is off Friday and Saturday. November and December 2026.
-- Flora works 15-23; Sanie works 07-15 and keeps 10-18 on Tuesdays as in her November schedule (10, 17, 24.11).
update public.schedule_entries e set value = case when extract(isodow from e.day) in (3,4) then 'Pushim' else '15-23' end
from public.schedule_people p
where p.id = e.person_id and p.name = 'Florije Neziri' and e.dept = 'Pastrim' and not e.is_extra
  and e.day between '2026-11-01' and '2026-12-31';
update public.schedule_entries e set value = case when extract(isodow from e.day) in (5,6) then 'Pushim'
    when extract(isodow from e.day) = 2 and e.day <> '2026-11-03' then '10-18' else '07-15' end
from public.schedule_people p
where p.id = e.person_id and p.name = 'Sanie Hajdini' and e.dept = 'Pastrim' and not e.is_extra
  and e.day between '2026-11-01' and '2026-12-31';
