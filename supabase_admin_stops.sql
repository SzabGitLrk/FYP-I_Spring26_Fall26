-- ============================================================================
-- Admin stop editor: allow admin users to manage pickup_points from the app
-- ============================================================================
--
-- WHY: the new "Manage Route Stops" screen (admin dashboard) adds / edits /
-- deletes stops on a map. Reads already work for everyone; WRITES need an
-- RLS policy, otherwise every save/delete fails with a permissions error.
--
-- Run this in the Supabase SQL Editor. It assumes:
--   * roles live in `profiles.role` (values include 'admin'), as used
--     elsewhere in this project (see supabase_security_fix.sql);
--   * `pickup_points` exists with RLS enabled.
--
-- The policy below lets ONLY a signed-in user whose profiles.role = 'admin'
-- insert/update/delete pickup_points. Everyone else is unaffected (reads are
-- handled by the existing public-read policy, if any).
--
-- NOTE: if `pickup_points` currently has NO policies (table locked to the
-- service role only), the SELECT side would also be blocked for students --
-- in that case add a public-read policy too (included below, commented out).

-- 1) Admins can manage stops (insert / update / delete).
drop policy if exists "Admins can manage stops" on public.pickup_points;
create policy "Admins can manage stops"
  on public.pickup_points
  for all
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );

-- 2) (Only if students currently CANNOT read stops at all) public read.
--    Uncomment if the map shows no stops for regular users after step 1.
-- drop policy if exists "Stops are publicly readable" on public.pickup_points;
-- create policy "Stops are publicly readable"
--   on public.pickup_points
--   for select
--   to authenticated, anon
--   using (true);
