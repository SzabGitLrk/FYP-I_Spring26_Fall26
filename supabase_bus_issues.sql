-- =============================================================================
--  supabase_bus_issues.sql — driver-reported bus problems (Fuel Empty /
--  Bus Fault)
--
--  WHY: the driver dashboard now has two operational report buttons next to
--  the emergency SOS. A fuel-empty or breakdown report must reach the admin
--  DASHBOARD live (same expectation as an SOS), so it needs its own table:
--  `sos_alerts` has no message/type column, and overloading `user_name` with
--  issue types would break the SOS display contract.
--
--  COLUMNS THE ADMIN SEES (all required by the spec):
--    bus          -> bus_id (FK, SET NULL on delete) + bus_number snapshot
--    driver       -> user_id (FK-less UUID) + driver_name snapshot
--    issue type   -> issue_type, CHECK-constrained to the two buttons
--    location     -> latitude / longitude
--    report time  -> created_at, SERVER clock (DEFAULT NOW()) so a wrong
--                    device clock cannot skew what dispatch sees
--
--  IDEMPOTENT: safe to run more than once. Mirrors the policy style of
--  supabase_security_fix.sql (admin-or-owner SELECT, admin-only UPDATE,
--  owner-only INSERT) and its Section 12 realtime-publication block.
--
--  RUN THIS in the Supabase SQL editor as postgres. Until it has run, the
--  driver's reports fail honestly ("Could not send the report") and the
--  admin's "Bus Issue Reports" section stays empty — nothing else breaks.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.bus_issues (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    driver_name TEXT NOT NULL DEFAULT '',
    bus_id BIGINT REFERENCES public.buses(id) ON DELETE SET NULL,
    bus_number TEXT NOT NULL DEFAULT '',
    issue_type TEXT NOT NULL CHECK (issue_type IN ('fuel_empty', 'bus_fault')),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- Small but grows one row per report; the admin reads "active, newest
-- first", so index exactly that shape.
CREATE INDEX IF NOT EXISTS bus_issues_status_created_idx
    ON public.bus_issues (status, created_at DESC);

ALTER TABLE public.bus_issues ENABLE ROW LEVEL SECURITY;

-- INSERT: a driver may only file reports as themselves (same WITH CHECK
-- shape as the sos_alerts insert policy; `user_id` is NOT NULL here).
DROP POLICY IF EXISTS "Bus issues insert" ON public.bus_issues;
CREATE POLICY "Bus issues insert" ON public.bus_issues
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- SELECT: admin reads every report (the dashboard's live feed); the filing
-- driver can read their own back. Anon sees nothing.
DROP POLICY IF EXISTS "Bus issues select" ON public.bus_issues;
CREATE POLICY "Bus issues select" ON public.bus_issues
  FOR SELECT
  USING (public.is_admin() OR auth.uid() = user_id);

-- UPDATE: resolving a report (status + resolved_at) is an admin action,
-- mirroring the SOS resolve path in admin_dashboard.dart.
DROP POLICY IF EXISTS "Bus issues update" ON public.bus_issues;
CREATE POLICY "Bus issues update" ON public.bus_issues
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- -----------------------------------------------------------------------------
-- Realtime, mirroring Section 12 of supabase_security_fix.sql: the admin
-- dashboard SUBSCRIBES to bus_issues. Without publication membership the
-- subscription silently delivers nothing and the feed degrades to
-- pull-to-refresh. Idempotent: already a member? nothing happens.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'bus_issues'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bus_issues;
  END IF;
END $$;


-- =============================================================================
--  VERIFICATION — run these afterwards (SQL editor).
--
--    1. SELECT tablename FROM pg_publication_tables
--         WHERE pubname = 'supabase_realtime' AND tablename IN
--         ('bus_locations','sos_alerts','bus_issues');
--       Expect: THREE rows.
--
--    2. SELECT policyname, cmd FROM pg_policies
--         WHERE schemaname = 'public' AND tablename = 'bus_issues';
--       Expect: three rows — Bus issues insert (insert),
--               Bus issues select (select), Bus issues update (update).
--
--    3. From the app (or REST with the anon key):
--         GET /rest/v1/bus_issues  ->  401/403 or [] for anon (RLS).
--       As an approved driver, tap Fuel Empty on the dashboard ->
--       the admin dashboard (logged in as admin) must show the report
--       WITHOUT refreshing, with bus, driver, type, pin and time.
--
--  TO GRANT ADMIN (unchanged, from supabase_security_fix.sql):
--      UPDATE public.profiles SET role = 'admin', is_approved = true
--      WHERE email = 'REPLACE_WITH_YOUR_EMAIL';
-- =============================================================================
