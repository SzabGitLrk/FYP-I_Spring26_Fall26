-- =============================================================================
--  ADMIN DRIVER-APPROVAL DIAGNOSTIC + REPAIR
--  University Point Locator - run in the Supabase SQL editor.
--
--  SYMPTOM: the admin dashboard shows 0 students / 0 drivers and no pending
--  driver approvals, so a registered driver can never be approved.
--
--  The app-side logic is sound; an admin (profiles.role = 'admin') reads all
--  profiles through the is_admin() helper. So if the lists are empty, it is
--  almost always one of:
--    (A) is_admin() is missing or NOT SECURITY DEFINER  -> the profiles
--        SELECT policy errors / recurses and returns nothing.
--    (B) the "admin" account's role is not actually 'admin'.
--    (C) the profiles SELECT policy is missing / too strict.
--  This script repairs A and C, and prints the data to confirm B.
--  Everything below is idempotent (safe to run more than once).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1. Make sure is_admin() exists and is SECURITY DEFINER (repairs A)
--
-- SECURITY DEFINER is REQUIRED: the function is called from a policy on
-- `profiles` itself. Without it, Postgres hits "infinite recursion detected
-- in policy for relation profiles" and the admin's SELECT returns nothing.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO service_role;

-- Confirm it is SECURITY DEFINER (expect 'definer' in the result):
SELECT p.proname, CASE p.prosecdef WHEN true THEN 'definer' ELSE 'invoker' END AS security
FROM pg_proc p WHERE p.proname = 'is_admin';

-- -----------------------------------------------------------------------------
-- STEP 2. Ensure RLS policies let an admin read every profile (repairs C)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Profiles select" ON public.profiles;
CREATE POLICY "Profiles select" ON public.profiles
  FOR SELECT
  USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "Profiles update" ON public.profiles;
CREATE POLICY "Profiles update" ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id OR public.is_admin())
  WITH CHECK (auth.uid() = id OR public.is_admin());

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE ON public.profiles TO authenticated;

-- -----------------------------------------------------------------------------
-- STEP 3. INSPECT the data (answers B: is the admin really an admin?)
--
-- Run these and READ the results:
-- -----------------------------------------------------------------------------
-- 3a. Every profile, with role and approval. Look for your admin email
--     (role must be 'admin') and the driver you registered (role 'driver',
--     is_approved false -> that is the row the dashboard must show as pending).
SELECT id, name, email, role, is_approved
FROM public.profiles
ORDER BY role, name;

-- 3b. How many drivers are PENDING (is_approved not true). This is the number
--     the admin dashboard's "Pending Driver Approvals" should display.
SELECT count(*) AS pending_drivers
FROM public.profiles
WHERE role = 'driver' AND is_approved IS NOT TRUE;

-- -----------------------------------------------------------------------------
-- STEP 4. (Only if 3a shows your account is NOT role='admin') GRANT ADMIN
--
-- Replace the email, then run. Run as postgres (this editor) auth.uid() is
-- NULL, so the privilege guard lets it through deliberately.
-- -----------------------------------------------------------------------------
-- UPDATE public.profiles
-- SET role = 'admin', is_approved = true
-- WHERE email = 'REPLACE_WITH_YOUR_ADMIN_EMAIL';

-- =============================================================================
--  AFTER RUNNING: close the app fully and sign in as the admin again. The
--  dashboard now also live-updates when a driver signs up, so a pending driver
--  appears the moment they register. If the lists are STILL empty, copy the
--  output of Step 3a - that tells us exactly what the database holds.
-- =============================================================================
