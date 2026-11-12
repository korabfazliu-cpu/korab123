-- Pastrim rule (user, 2026-11-12): Bedrije always mornings 07-15 (off Sun–Mon), Flora always afternoons 15-23
-- (off Wed–Thu). Sanie covers: mornings when Bedrije is off (Sun, Mon), afternoons when Flora is off (Wed, Thu),
-- the middle shift 10-18 on Tuesdays, and is off Fri–Sat. November and December 2026.
update public.schedule_entries e set value = case extract(isodow from e.day)
    when 7 then '07-15' when 1 then '07-15' when 2 then '10-18' when 3 then '15-23' when 4 then '15-23' else 'Pushim' end
from public.schedule_people p
where p.id = e.person_id and p.name = 'Sanie Hajdini' and e.dept = 'Pastrim' and not e.is_extra
  and e.day between '2026-11-01' and '2026-12-31';
update public.schedule_entries e set value = case when extract(isodow from e.day) in (7,1) then 'Pushim' else '07-15' end
from public.schedule_people p
where p.id = e.person_id and p.name = 'Bedrije Gashi' and e.dept = 'Pastrim' and not e.is_extra
  and e.day between '2026-11-01' and '2026-12-31';
