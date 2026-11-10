-- December 2026 schedule from Orari_Dhjetor_2026.xlsx (user, 2026-11-10).
-- First names in that file become aliases. Besian's two shifts under Mirembajtje are extra work.
-- December was empty, so nothing was deleted.
-- Lulzim's 28.12 extra 07-15 is stored as 07-15* (user: Lulzim has no extra days in December).
update public.schedule_people set aliases = array_append(aliases, 'Musa') where name = 'Musli Fazliu' and not ('Musa' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Afrim') where name = 'Afrim Gerbeshi' and not ('Afrim' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Agim') where name = 'Agim Islami' and not ('Agim' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Arber') where name = 'Arber Shkodra' and not ('Arber' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Baki') where name = 'Baki Zeneli' and not ('Baki' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Besian') where name = 'Besian Osmani' and not ('Besian' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Clirim') where name = 'Clirim Sopi' and not ('Clirim' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Edon') where name = 'Edon Bislimi' and not ('Edon' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Egzon') where name = 'Egzon Bellagoshi' and not ('Egzon' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Lulzim') where name = 'Lulzim Gashi' and not ('Lulzim' = any(aliases));
update public.schedule_people set aliases = array_append(aliases, 'Valton') where name = 'Valton Mustafa' and not ('Valton' = any(aliases));
with g(dept, nm, vals) as (values
('Cashier','Musa','08-16|08-16|08-16|Pushim|Pushim|16-00|16-00|16-00|16-00|16-00|Pushim|Pushim|08-16|08-16|08-16|08-16|08-16|Pushim|Pushim|16-00|16-00|16-00|16-00|16-00|Pushim|Pushim|08-16|08-16|08-16|08-16|08-16'),
('Cashier','Edon','16-00|16-00|16-00|16-00|16-00|Pushim|Pushim|08-16|08-16|08-16|08-16|08-16|Pushim|Pushim|16-00|16-00|16-00|16-00|16-00|Pushim|Pushim|08-16|08-16|08-16|08-16|08-16|Pushim|Pushim|16-00|16-00|16-00'),
('Cashier','Clirim','17-01|Pushim|Pushim|08-16|08-16|08-16|08-16|17-01|Pushim|Pushim|16-00|16-00|16-00|16-00|Pushim|Pushim|Pushim|08-16|08-16|08-16|08-16|17-01|Pushim|Pushim|16-00|16-00|16-00|16-00|17-01|Pushim|Pushim'),
('Mirembajtje','Valton','09-17|07-15|07-15|15-23|15-23|Pushim|Pushim|09-17|09-17|07-15|07-15|15-23|Pushim|Pushim|07-15|09-17|09-17|07-15|07-15|Pushim|Pushim|09-17|09-17|09-17|09-17|07-15|Pushim|Pushim|15-23|15-23|15-23'),
('Mirembajtje','Egzon','23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|15-23|07-15|15-23|15-23'),
('Mirembajtje','Arber','15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15'),
('Mirembajtje','Agim','07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim|07-15|07-15|15-23|15-23|23-07|23-07|Pushim|Pushim'),
('Park','Baki','07-15|07-15|07-15|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|15-23|07-15|07-15|07-15|07-15|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15'),
('Park','Afrim','15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|15-23|15-23|15-23|15-23|15-23|Pushim|Pushim|07-15|07-15|07-15|07-15|07-15|Pushim|Pushim|15-23|15-23|15-23'),
('Park','Lulzim','16-00|Pushim|Pushim|07-15|07-15|07-15|07-15|16-00|Pushim|Pushim|15-23|15-23|07-15|15-23|Pushim|Pushim|Pushim|07-15|07-15|07-15|07-15|Pushim|Pushim|Pushim|15-23|15-23|15-23|15-23|Pushim|Pushim|Pushim')
), p as (select id, name, aliases from public.schedule_people)
insert into public.schedule_entries (day, dept, person_id, value, is_extra)
select date '2026-12-01' + (o - 1)::int, g.dept, (select p.id from p where lower(g.nm) = any(select lower(x) from unnest(p.aliases || p.name) x)), v, false
from g, unnest(string_to_array(g.vals, '|')) with ordinality as t(v, o) where v <> '';
with x(day, dept, nm, val) as (values
('2026-12-20','Mirembajtje','Besian','15-23'),
('2026-12-27','Mirembajtje','Besian','07-15'),
('2026-12-06','Mirembajtje','Egzon','23-07'),
('2026-12-07','Mirembajtje','Egzon','23-07'),
('2026-12-13','Mirembajtje','Lulzim','15-23*'),
('2026-12-14','Mirembajtje','Clirim','00-07*'),
('2026-12-15','Mirembajtje','Egzon','23-07'),
('2026-12-21','Mirembajtje','Lulzim','15-23*'),
('2026-12-22','Mirembajtje','Egzon','23-07'),
('2026-12-23','Mirembajtje','Egzon','23-07'),
('2026-12-28','Mirembajtje','Lulzim','07-15*'),
('2026-12-30','Mirembajtje','Egzon','23-07'),
('2026-12-31','Mirembajtje','Egzon','23-07')
), p as (select id, name, aliases from public.schedule_people)
insert into public.schedule_entries (day, dept, person_id, person_label, value, is_extra)
select x.day::date, x.dept, (select p.id from p where lower(x.nm) = any(select lower(y) from unnest(p.aliases || p.name) y)), x.nm, x.val, true from x;
