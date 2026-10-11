-- =============================================================================
--  supabase_advisor_fixes.sql — clears the Supabase Advisor (Database
--  Linter) findings from 11 Oct 2026 and closes the real gaps they point to.
--
--  IDEMPOTENT: safe to re-run. Run AFTER supabase_security_fix.sql.
--  Verified before writing this file:
--    * create_profile_for_user() and enforce_profile_privileges() bodies are
--      fully schema-qualified -> pinning search_path = '' cannot break them.
--    * The Flutter app makes ZERO PostgREST rpc() calls -> revoking or
--      dropping REST-execute on functions cannot break the app.
--    * check_bus_proximity / check_bus_proximity_simple / handle_new_user /
--      rls_auto_enable / system_logs exist only on the live database (drift
--      from old experiments) - no repo script references them.
--    * Trigger functions keep firing when their EXECUTE grant is revoked:
--      PostgreSQL does not check EXECUTE at trigger-fire time.
--
--  WHAT IS DELIBERATELY LEFT ALONE (documented accepts, see bottom):
--    * public.is_admin() stays executable - every admin-or-owner RLS policy
--      evaluates it per querying role. It is read-only and returns only a
--      boolean for the CALLER, so its exposure leaks nothing.
--    * Public read on universities/routes/pickup_points/buses - that IS the
--      product (map content; universities is even read during signup).
--    * system_logs open INSERT for authenticated - append-only log design,
--      authenticated-only, accepted.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- SECTION 1. lint 0011 function_search_path_mutable: pin the two live
-- trigger/utility functions. Bodies are fully qualified (public.profiles,
-- public.is_admin(); everything else is a builtin or a record field), so an
-- empty search_path is both safe and the strictest choice.
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.create_profile_for_user() SET search_path = '';
ALTER FUNCTION public.enforce_profile_privileges() SET search_path = '';


-- -----------------------------------------------------------------------------
-- SECTION 2. lint 0028/0029 anon & authenticated SECURITY DEFINER execution:
-- remove the dead drift functions and cut REST exposure on the trigger
-- functions. is_admin() is deliberately kept (see header).
-- -----------------------------------------------------------------------------

-- 2a. Dead standalone functions: drop outright. DO-guarded so a stray
--     dependency degrades to a NOTICE instead of failing the whole script.
DO $$
BEGIN
  DROP FUNCTION IF EXISTS public.check_bus_proximity();
EXCEPTION WHEN dependent_objects_still_exist THEN
  RAISE NOTICE 'check_bus_proximity is still referenced; left in place';
END $$;

DO $$
BEGIN
  DROP FUNCTION IF EXISTS public.check_bus_proximity_simple();
EXCEPTION WHEN dependent_objects_still_exist THEN
  RAISE NOTICE 'check_bus_proximity_simple is still referenced; left in place';
END $$;

-- 2b. Trigger/utility functions the app never calls over REST: revoke from
--     PUBLIC and both API roles. Triggers keep working (no EXECUTE check at
--     fire time); SQL editor / postgres / service_role keep access.
REVOKE EXECUTE ON FUNCTION public.create_profile_for_user()
  FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'handle_new_user'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.handle_new_user()
      FROM PUBLIC, anon, authenticated;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'rls_auto_enable'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()
      FROM PUBLIC, anon, authenticated;
  END IF;
END $$;


-- -----------------------------------------------------------------------------
-- SECTION 3. lint 0024 always-true INSERT + grant-layer lockdown of tables
-- the app never queries. Every revoke below changes NO app behavior: RLS
-- already denies these roles at the row level; this removes the surface at
-- the grant level too (and clears the GraphQL-exposure flags).
-- -----------------------------------------------------------------------------

-- 3a. lint 0024: bus_notifications has an open INSERT for everyone and the
--     app has zero references to the table -> drop the policy (default deny).
DROP POLICY IF EXISTS "Bus notify insert" ON public.bus_notifications;

-- 3b. Tables unused by the app (verified by grep over lib/): hide from both
--     API roles entirely.
REVOKE SELECT ON public.otp_verification FROM anon, authenticated;
REVOKE SELECT ON public.user_devices FROM anon, authenticated;
REVOKE SELECT ON public.bus_notifications FROM anon, authenticated;

-- system_logs exists only on the live DB; guard the revoke.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'system_logs'
  ) THEN
    REVOKE SELECT ON public.system_logs FROM anon, authenticated;
  END IF;
END $$;

-- 3c. admin_settings: RLS is already admin-only (security_fix Section 10);
--     hide from anon. The authenticated grant stays for any future admin tool.
REVOKE SELECT ON public.admin_settings FROM anon;


-- -----------------------------------------------------------------------------
-- SECTION 4. lint 0026: hide PII / operational tables from the ANON role at
-- the grant layer. Everything the app does with these tables runs as an
-- AUTHENTICATED user (verified per call site: profile owner, admin dashboard,
-- approved driver, logged-in student map) - including Supabase Realtime
-- delivery, which authorizes subscribers with their own JWT. Public-read
-- RLS policies are left untouched; anon simply stops seeing the tables at
-- all, so they vanish from the anon GraphQL schema too.
-- -----------------------------------------------------------------------------
REVOKE SELECT ON public.profiles            FROM anon;  -- emails + names
REVOKE SELECT ON public.sos_alerts          FROM anon;  -- user locations
REVOKE SELECT ON public.trips               FROM anon;  -- driver activity
REVOKE SELECT ON public.stop_notifications  FROM anon;  -- user->stop links
REVOKE SELECT ON public.bus_locations       FROM anon;  -- live positions
REVOKE SELECT ON public.bus_issues          FROM anon;  -- driver reports


-- =============================================================================
--  VERIFICATION — run afterwards:
--
--    1. Re-run the Database Advisor: the remaining findings should be ONLY
--       the documented accepts — public-read exposure of
--       universities/routes/pickup_points/buses, is_admin() executability,
--       and system_logs' authenticated INSERT.
--    2. App smoke test (as a logged-in student): map loads buses, routes and
--       stops; live markers still arrive. As admin: SOS + Bus Issue feeds
--       load. As driver: Start Trip records positions. All unchanged.
--    3. SELECT proname, prosecdef FROM pg_proc p JOIN pg_namespace n
--         ON n.oid = p.pronamespace
--         WHERE n.nspname = 'public' AND proname IN
--         ('check_bus_proximity','check_bus_proximity_simple');
--       Expect: zero rows (both dropped).
--
--  SEPARATE DASHBOARD TOGGLE (cannot be done in SQL):
--    Authentication -> Sign In / Providers (or Password) -> enable
--    "Check password against HaveIBeenPwned.org" (leaked password
--    protection), clearing the last Advisor warning.
-- =============================================================================
