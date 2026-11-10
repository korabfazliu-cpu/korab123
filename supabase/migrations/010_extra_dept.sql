-- November 2026: the "Extra" row right under the "Park" title in Orari.xlsx belongs to Mirembajtje (user, 2026-11-10).
-- Only rows imported from the Excel (no absence_id) are moved.
update public.schedule_entries set dept = 'Mirembajtje'
  where is_extra and dept = 'Park' and absence_id is null
    and day >= '2026-11-01' and day < '2026-12-01';
