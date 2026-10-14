-- ============================================================
--  Admin INSERT / UPDATE on public.buses
--  University Point Locator - run in the Supabase SQL editor.
--
--  WHY: the admin dashboard now has an "Add Bus" button, but the
--  buses table currently has ONLY a public SELECT policy and an
--  admin DELETE policy. With no INSERT policy, RLS rejects every
--  insert and the button just shows a red "Could not add the bus"
--  error. This adds the missing admin INSERT (and UPDATE, so a
--  bus's status / route can be changed later without raw SQL).
--
--  Uses the same admin-existence check as the existing
--  "Buses delete" policy so behaviour stays consistent.
-- ============================================================

DROP POLICY IF EXISTS "Buses insert" ON public.buses;
CREATE POLICY "Buses insert" ON public.buses
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Buses update" ON public.buses;
CREATE POLICY "Buses update" ON public.buses
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Verify: as a logged-in admin, this insert (then delete) should succeed.
-- INSERT INTO public.buses (route_id, bus_number, status)
--   VALUES (<a real route id>, 'TEST-ADMIN', 'inactive');
-- DELETE FROM public.buses WHERE bus_number = 'TEST-ADMIN';
