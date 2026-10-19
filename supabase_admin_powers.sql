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
--    * trips     : UPDATE        (close an orphaned active trip)
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

-- ---------- trips: admin UPDATE (close an orphaned active trip) ----------
-- A trip normally closes only when ITS OWN driver taps End Trip
-- ("Trips update" is USING (auth.uid() = driver_id)). An orphan - the app
-- was killed mid-drive, or End Trip failed offline forever - can then be
-- closed by nobody, and it sits in the admin Active Trips count (and the
-- Active Trips detail sheet) as a permanent false positive.
--
-- Admin UPDATE lets the sheet's per-trip "Close trip" action mark the row
-- completed. The driver-side policy is untouched, so a driver still
-- cannot edit anyone else's trip.
DROP POLICY IF EXISTS "Trips update" ON public.trips;
CREATE POLICY "Trips update" ON public.trips
  FOR UPDATE
  USING (public.is_admin() OR auth.uid() = driver_id)
  WITH CHECK (public.is_admin() OR auth.uid() = driver_id);

-- Verify (as a logged-in admin):
--   1. Insert a test route, then delete it from the dashboard.
--   2. Rejecting a pending driver should REMOVE the row (and lock that
--      email out of the app until it signs up again).
--   3. Tap the Active Trips card, then "Close trip" on a stale row - the
--      row disappears and the headline count drops.

-- ---------- harden is_admin() ----------
-- SECURITY DEFINER + a floating search_path: the `profiles` reference in
-- the body resolves via the SESSION's search_path, so a path hijack
-- (pg_temp first, or an attacker-created schema listed before public)
-- could point it at a fake table that matches everyone - defeating the
-- single function every RLS policy below relies on. Pinning
-- search_path = '' forces schema-qualified resolution only.
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
$$;

-- ---------- routes: keep the buses when a route is deleted ----------
-- buses.route_id is ON DELETE CASCADE in supabase_final.sql, so deleting
-- a route from the dashboard silently DELETED every bus on it. Switch to
-- SET NULL: the vehicles stay in the fleet as "Unassigned" and can be
-- re-pointed at another route. (pickup_points keep their CASCADE - a
-- route's stops genuinely belong to it.)
ALTER TABLE public.buses DROP CONSTRAINT IF EXISTS buses_route_id_fkey;
ALTER TABLE public.buses ADD CONSTRAINT buses_route_id_fkey
  FOREIGN KEY (route_id) REFERENCES public.routes(id) ON DELETE SET NULL;
