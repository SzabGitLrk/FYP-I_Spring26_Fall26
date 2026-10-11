-- ============================================================================
-- Launch cleanup - run ONCE in the Supabase SQL editor before going live.
--
-- Why this exists: anon/authenticated roles cannot remove the demo seed data
-- (RLS filters the rows; PostgREST answers 204 while affecting zero rows),
-- so the cleanup must run as the SQL editor (postgres) role.
-- ============================================================================

-- 1) Static demo "live bus" positions frozen on 2026-06-16. The app already
--    hides them behind its 2-minute freshness filter, but production data
--    must not contain frozen fake positions at all.
DELETE FROM bus_locations
WHERE timestamp < '2026-07-01T00:00:00Z';

-- 2) Placeholder driver names that were seeded with the demo buses. They are
--    rendered verbatim in the bus details sheet ("Driver: Driver PTS").
--    NULL renders as "Not assigned" until real drivers are linked.
UPDATE buses
SET driver_name = NULL
WHERE driver_name IN ('Driver PTS', 'Driver Route A', 'Driver Nae Dare', 'Driver OPP');

-- 3) Verify the result: expect driver_name = NULL for all buses, and
--    bus_locations to contain only rows written by real driver trips.
SELECT id, bus_number, driver_name, route_id, status FROM buses ORDER BY id;
SELECT count(*) AS remaining_bus_locations FROM bus_locations;

-- 4) No demo accounts may remain in auth (e.g. anything @example.com).
--    Empty result expected:
SELECT id, email, created_at FROM auth.users WHERE email LIKE '%example.com';

-- 5) Reminder (see TODO.md): if Supabase "Confirm email" is still ON, new
--    students cannot sign up without clicking a mail link. Decide the policy
--    (keep confirmation + a real SMTP sender, or disable it for the pilot).
