-- =============================================================================
--  SUPABASE SECURITY HARDENING
--  Project: wstuufgiapgkskkcrdjx
--
--  Apply in the SQL Editor:
--    https://supabase.com/dashboard/project/wstuufgiapgkskkcrdjx/sql/new
--
--  This script is idempotent - every statement is DROP ... IF EXISTS /
--  CREATE OR REPLACE, so it is safe to run more than once.
--
--  Fixes, in order of severity:
--
--   1. PRIVILEGE ESCALATION (critical)
--      `profiles` UPDATE policy was `auth.uid() = id OR admin`, and RLS does
--      not restrict *columns* - so any signed-in user could run
--          PATCH /rest/v1/profiles?id=eq.<own-id>  {"role":"admin"}
--      and instantly become an admin. The signup trigger made it worse by
--      copying client-controlled `raw_user_meta_data->>'role'` straight into
--      the table, with no CHECK constraint on the column.
--
--   2. Client-trusted routing
--      The app read `user.userMetadata['role']` before consulting the DB.
--      Handled in Dart (`lib/screens/role_router.dart`), not here.
--
--   3. `is_approved` never enforced
--      Handled in Dart. This script guarantees the *value* can only be set by
--      an admin.
--
--   4. OTP table world-readable (high)
--      `otp_verification` had INSERT/SELECT/UPDATE all `WITH CHECK (true)`,
--      letting anyone with the anon key read every OTP. Policies are dropped
--      (RLS stays enabled => deny-all). The OTP screen is dead code and has
--      been removed from the app.
--
--   5. SOS alerts world-writable (high)
--      `sos_alerts` UPDATE was `USING (true)`, so anyone could resolve or
--      tamper with emergency alerts. Now admin-or-owner.
--
--   6. Profile email exposure (medium)
--      `profiles` SELECT was `USING (true)`, exposing every user's email and
--      role to the anon key. Now owner-or-admin.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- SECTION 1. Helper: is the current caller an admin?
--
-- SECURITY DEFINER is ESSENTIAL, not cosmetic: this function is called from
-- within policies on `profiles` itself. A plain function querying `profiles`
-- from a `profiles` policy re-enters RLS and Postgres fails with
-- "infinite recursion detected in policy for relation profiles".
-- Running as the owner (postgres, the table owner) skips RLS and breaks the
-- cycle. It only ever returns a boolean for the *calling* user.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$$;

-- The policy expressions are evaluated as the requesting role, so both anon
-- and authenticated need EXECUTE or the query dies with
-- "permission denied for function is_admin".
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO service_role;


-- -----------------------------------------------------------------------------
-- SECTION 2. Signup trigger: stop trusting client metadata
--
-- `raw_user_meta_data` is supplied verbatim by whoever calls /auth/v1/signup.
-- It must never be able to produce role='admin' or is_approved=true.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_profile_for_user()
RETURNS TRIGGER AS $$
DECLARE
  requested_role text;
BEGIN
  BEGIN
    requested_role := lower(coalesce(NEW.raw_user_meta_data->>'role', 'student'));

    -- Self-service registration may only ever yield student or driver.
    -- 'admin' (or anything unexpected) degrades to 'student'.
    IF requested_role NOT IN ('student', 'driver') THEN
      requested_role := 'student';
    END IF;

    INSERT INTO public.profiles (id, name, email, role, is_approved)
    VALUES (
      NEW.id,
      coalesce(NEW.raw_user_meta_data->>'name', 'User'),
      NEW.email,
      requested_role,
      false            -- approval is granted later by an admin, never at signup
    );
  EXCEPTION WHEN OTHERS THEN
    -- Never block account creation on a profile failure; role_router creates
    -- the row on first login if it is missing.
    RAISE WARNING 'create_profile_for_user trigger failed for user %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_user_created ON auth.users;
CREATE TRIGGER on_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_for_user();


-- -----------------------------------------------------------------------------
-- SECTION 3. Row guard: no non-admin can write privilege columns
--
-- Closes the column-level hole that RLS cannot express. Non-admin writes have
-- role/is_approved normalised on INSERT and silently reverted on UPDATE, so a
-- legitimate profile edit (name, email, avatar) still succeeds.
--
-- When auth.uid() IS NULL the caller is the SQL editor (postgres) or
-- service_role: both bypass RLS entirely, so they are trusted. Anon also has
-- auth.uid() IS NULL but cannot reach this path with effect - its direct
-- writes are rejected by the RLS policies in Section 4, and the only
-- unauthenticated route into this table is the signup trigger from Section 2,
-- which already normalises its own values.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_profile_privileges()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.role IS DISTINCT FROM 'student'
         AND NEW.role IS DISTINCT FROM 'driver' THEN
        NEW.role := 'student';
      END IF;
      NEW.is_approved := false;
    ELSE
      -- Revert rather than raise, so routine self-edits keep working.
      NEW.role := OLD.role;
      NEW.is_approved := OLD.is_approved;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_profile_privileges ON public.profiles;
CREATE TRIGGER enforce_profile_privileges
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_profile_privileges();


-- -----------------------------------------------------------------------------
-- SECTION 4. Defence in depth: CHECK constraint on role
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_role_check'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_role_check
      CHECK (role IN ('student', 'driver', 'admin'));
  END IF;
END $$;


-- -----------------------------------------------------------------------------
-- SECTION 5. Tighten Row Level Security policies
-- -----------------------------------------------------------------------------

-- 5a. profiles: owner-or-admin read (was USING (true) => all emails public)
DROP POLICY IF EXISTS "Profiles select" ON public.profiles;
CREATE POLICY "Profiles select" ON public.profiles
  FOR SELECT
  USING (auth.uid() = id OR public.is_admin());

-- 5b. profiles: owner-or-admin update (now routed through is_admin(), which
--     is recursion-safe; the trigger in Section 3 strips privilege columns
--     from non-admin writes)
DROP POLICY IF EXISTS "Profiles update" ON public.profiles;
CREATE POLICY "Profiles update" ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id OR public.is_admin())
  WITH CHECK (auth.uid() = id OR public.is_admin());

-- 5c. buses: delete was an EXISTS subquery against profiles; use the helper.
DROP POLICY IF EXISTS "Buses delete" ON public.buses;
CREATE POLICY "Buses delete" ON public.buses
  FOR DELETE
  USING (public.is_admin());

-- 5d. sos_alerts: was SELECT/UPDATE USING (true). Emergency alerts carry user
--     locations and are only ever read/resolved by the admin dashboard
--     (`admin_dashboard.dart`); owners still see their own.
DROP POLICY IF EXISTS "SOS select" ON public.sos_alerts;
CREATE POLICY "SOS select" ON public.sos_alerts
  FOR SELECT
  USING (public.is_admin() OR auth.uid() = user_id);

DROP POLICY IF EXISTS "SOS update" ON public.sos_alerts;
CREATE POLICY "SOS update" ON public.sos_alerts
  FOR UPDATE
  USING (public.is_admin() OR auth.uid() = user_id)
  WITH CHECK (public.is_admin() OR auth.uid() = user_id);

-- 5e. otp_verification: drop every policy. RLS remains ENABLED and there are
--     now zero policies => deny-all for anon and authenticated.
--     (If phone-OTP login is ever revived it must be generated and verified
--      server-side, never in the client.)
DROP POLICY IF EXISTS "OTP insert" ON public.otp_verification;
DROP POLICY IF EXISTS "OTP select" ON public.otp_verification;
DROP POLICY IF EXISTS "OTP update" ON public.otp_verification;


-- -----------------------------------------------------------------------------
-- SECTION 6. Grant the helper everywhere it is referenced
-- -----------------------------------------------------------------------------
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE ON public.profiles TO authenticated;


-- =============================================================================
--  VERIFICATION - run these afterwards.
--
--  All four must FAIL (HTTP 403/401 or zero rows) when called with the anon
--  key, and the first must succeed only as an authenticated non-admin user:
--
--    1. Self-escalate:
--         PATCH /rest/v1/profiles?id=eq.<your-uid>  {"role":"admin"}
--       Expect: 200 with 0 rows affected, or 403. Verify the role is unchanged.
--    2. Read everyone's emails:
--         GET  /rest/v1/profiles?select=email
--       Expect: [] (empty) for anon.
--    3. Read OTP codes:
--         GET  /rest/v1/otp_verification?select=*
--       Expect: 401/403 or [].
--    4. Tamper with a SOS alert:
--         PATCH /rest/v1/sos_alerts?id=eq.1  {"status":"resolved"}
--       Expect: 403.
--
--  TO GRANT ADMIN (there is no in-app way to do this, by design):
--      UPDATE public.profiles
--      SET role = 'admin', is_approved = true
--      WHERE email = 'you@example.com';
--    Run as postgres/service_role (SQL Editor). auth.uid() is NULL on that
--    path, so the guard in Section 3 lets it through deliberately.
-- =============================================================================
