# Pushimet e Stafit (Staff Leave Tracker)

Small web app where staff create their own account (admin approves it), report leave by type, and upload a doctor's note for medical leave over 3 days.

- Frontend: one static file, `index.html` (no build step)
- Backend: Supabase (Auth, Postgres with Row Level Security, private Storage bucket)
- Hosting: Vercel

## Rules
| Leave type | Days / year |
|---|---|
| Annual | 20 |
| Medical | 20 (doctor's note required if more than 3 days) |
| Marriage / Death in family | 5 each |
| Birth of a child | 3 |
| Voluntary blood donation | 2 |
| Unpaid / Carried over / Compensation | no fixed limit |

Limits are enforced in the database (`supabase/migrations/001_schema.sql`), not only in the page.

## Setup
1. Create a Supabase project. In the SQL editor run `supabase/migrations/001_schema.sql` after replacing `YOUR_ADMIN_EMAIL` with the super admin email.
2. Supabase, Authentication, Providers: enable Email and "Allow new users to sign up". "Confirm email" is optional.
3. In `index.html` set `SB_URL` and `SB_KEY` (the **publishable** key; it is safe in the page, security comes from RLS). Never use the service role key.
4. Deploy the folder to Vercel as a static site. Turn off Deployment Protection if staff must open it without a Vercel login.
5. Register with the admin email. That account becomes an approved admin; everyone else appears under "Kërkesat" for approval.
