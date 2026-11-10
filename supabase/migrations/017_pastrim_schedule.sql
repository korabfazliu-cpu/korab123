-- Pastrim schedules (user, 2026-11-10): November from the user's picture, December continuing the same rhythm (user's choice).
update public.schedule_people set aliases = array_append(aliases, 'Flora') where name = 'Florije Neziri' and not ('Flora' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Bedrije') where name = 'Bedrije Gashi' and not ('Bedrije' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Sanie') where name = 'Sanie Hajdini' and not ('Sanie' = any(aliases));
with g(ym, nm, vals) as (values
('2026-11','Bedrije Gashi','Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim'),
('2026-11','Florije Neziri','15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23'),
('2026-11','Sanie Hajdini','07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim|07-15|07-15|07-15|07-15'),
('2026-12','Bedrije Gashi','07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|07-15|07-15|07-15'),
('2026-12','Florije Neziri','15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23'),
('2026-12','Sanie Hajdini','10-18|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim|07-15|07-15|07-15|07-15|10-18|Pushim|Pushim')
)
insert into public.schedule_entries (day, dept, person_id, value, is_extra)
select (g.ym || '-01')::date + (o - 1)::int, 'Pastrim', (select id from public.schedule_people where name = g.nm), v, false
from g, unnest(string_to_array(g.vals, '|')) with ordinality as t(v, o) where v <> '';
