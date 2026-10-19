-- ============================================================
--  Admin powers: reject/remove accounts + route CRUD
--  University Point Locator - run in the Supabase SQL editor.
--
--  Run AFTER supabase_security_fix.sql (it defines public.is_admin()).
--
--  WHY: the admin dashboard can now reject a pending driver, remove a
--  driver or student account, and add / edit / delete routes - but RLS
--  only allowed the admin to UPDATE profiles and read routes. Without
--  the policies below:
--    * Reject / Remove on a profile silently deletes nothing (zero
--      rows) and the app shows an honest error instead.
--    * Add / Edit / Delete Route is rejected by RLS.
--
--  WHAT THIS GRANTS (admin only, via public.is_admin()):
--    * profiles  : DELETE        (reject/remove an account)
--                  UPDATE already exists - nothing to do)
--    * routes    : INSERT / UPDATE / DELETE
--
--  WHAT IT DOES NOT GRANT: bus writes still need
--  supabase_admin_buses.sql (Add Bus, Edit Bus, driver assignment).
-- ============================================================

-- ---------- profiles: admin DELETE (reject / remove account) ----------
-- Deleting the profile row removes the app account: RoleRouter can no
-- longer resolve a role for that user id, so they are locked out of the
-- app even though the raw auth email still exists in Supabase Auth
-- (delete it from Auth > Users if you also want the login removed).
DROP POLICY IF EXISTS "Profiles delete" ON public.profiles;
CREATE POLICY "Profiles delete" ON public.profiles
  FOR DELETE
  USING (public.is_admin());

-- ---------- routes: admin INSERT / UPDATE / DELETE ----------
DROP POLICY IF EXISTS "Routes insert" ON public.routes;
CREATE POLICY "Routes insert" ON public.routes
  FOR INSERT
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Routes update" ON public.routes;
CREATE POLICY "Routes update" ON public.routes
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Routes delete" ON public.routes;
CREATE POLICY "Routes delete" ON public.routes
  FOR DELETE
  USING (public.is_admin());

-- Verify (as a logged-in admin):
--   1. Insert a test route, then delete it from the dashboard.
--   2. Rejecting a pending driver should REMOVE the row (and lock that
--      email out of the app until it signs up again).
