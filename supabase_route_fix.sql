-- ============================================================================
-- supabase_route_fix.sql  —  Fix the PTS Route loop + Qamber Bus Stop
-- Evidence: OSRM (the app's own routing engine) + Google Maps + OpenStreetMap
-- Run in the Supabase SQL Editor. Safe / idempotent. No app rebuild needed.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- DIAGNOSTIC (read-only): confirm what you have before changing anything
-- ---------------------------------------------------------------------------
SELECT id, route_id, order_index, point_name, latitude, longitude
FROM pickup_points
WHERE route_id IN (7, 8, 9)
ORDER BY route_id, order_index;

-- Duplicate-route check (re-runnable seed scripts can leave duplicates)
SELECT route_id, COUNT(*) AS stop_count
FROM pickup_points
GROUP BY route_id
HAVING COUNT(*) > 0
ORDER BY route_id;


-- ---------------------------------------------------------------------------
-- FIX A — PTS Route (route_id = 7) stop-order backtrack  →  THE VISIBLE LOOP
-- ---------------------------------------------------------------------------
-- What OSRM proved (real road geometry, "overview=full"):
--   Current order  PTS(27.588) → Chowk(27.568) → Hostel(27.572):
--       4519 m, dips SOUTH to 27.5656 then BACKTRACKS NORTH to the Hostel.
--       That double-back is the giant loop in your screenshots.
--   Swapped order  PTS(27.588) → Hostel(27.572) → Chowk(27.568):
--       3645 m, monotonic SOUTH, no backtrack.  (Saves 874 m.)
-- The residual ~0.76 km eastward swing stays in BOTH — that is the real road
-- crossing the Rice Canal + Railway barrier via Naudero Rd / N-105. It is
-- correct road geometry, NOT a bug, and cannot be removed.
--
-- ACTION: swap order_index 2 <-> 3 so the bus serves the Hostel BEFORE the
-- Chowk (hostel is on the way down from PTS). Only run this if that matches
-- the real service order — see the note at the bottom if the Chowk is first.

BEGIN;
  UPDATE pickup_points
  SET order_index = 3
  WHERE route_id = 7 AND point_name = 'University Chowk' AND order_index = 2;

  UPDATE pickup_points
  SET order_index = 2
  WHERE route_id = 7 AND point_name = 'Student Hostel Stop' AND order_index = 3;
COMMIT;


-- ---------------------------------------------------------------------------
-- FIX B — Qamber Bus Stop (route_id = 9) is on the WRONG SIDE of the city
-- ---------------------------------------------------------------------------
-- Google Maps / OSM: the town of Qambar is at 27.5892, 67.9997 — about 20 km
-- WEST of Larkana. The road to it ("Qambar Road", primary) leaves the city at
-- ~27.5686, 68.1957.
-- Your "Qamber Bus Stop" sits at 27.6000, 68.2500 — that is 4 km EAST / toward
-- Naudero, i.e. the OPPOSITE direction. OSRM routes it 5.2 km east.
-- OSRM nearest-road also puts it 130 m off any road (every other stop is 2-28 m).
--
-- If "Qamber" really means the bus toward Qambar town, point it WEST onto the
-- real Qambar Road (OSRM snaps it onto the road there). VERIFY / replace this
-- anchor with your own Google Maps pin for the exact stop:
--
--   UPDATE pickup_points
--   SET latitude = 27.5686, longitude = 68.1957
--   WHERE point_name = 'Qamber Bus Stop';
--
-- Uncomment the UPDATE above only after you confirm the direction.


-- ---------------------------------------------------------------------------
-- NOTE 1 — PTS identity ("Postal" vs "Police")
-- ---------------------------------------------------------------------------
-- The app labels the stop "Postal Training School", but the ONLY training
-- school mapped in Larkana (Google Maps + OSM) is the "Police Training School"
-- at 27.5661, 68.1967 — about 3.5 km from your PTS coordinate (27.5880, 68.2220)
-- and on the opposite (south-west) side of the city. Your screenshots show the
-- route running along the north-east Naudero Rd corridor, which matches YOUR
-- coordinate, not the Police Training School. So your coordinate is on-road and
-- in the right corridor — only the NAME may be wrong. Confirm what PTS actually
-- is (a university gate / terminal?) before renaming. Do NOT move the point to
-- the Police Training School unless that is genuinely where the bus stops.

-- ---------------------------------------------------------------------------
-- NOTE 2 — What did NOT need fixing
-- ---------------------------------------------------------------------------
-- OSRM nearest-road snapping of all 8 stops (distance to nearest real road):
--   PTS 2.9 m · University Chowk 18.9 m · Student Hostel 17.5 m · Nae Dare 2.8 m
--   Old Railway Crossing 13.4 m · PTS Terminal 2.9 m · OPP Colony Gate 27.7 m
--   Qamber Bus Stop 130 m  <-- the only off-road point (see Fix B)
-- So the seed coordinates are already ON roads. They do NOT need a mass rewrite.
-- Routes 8 and 9 (except Qamber's direction) route cleanly with no backtrack.

-- After running the fixes, reopen the route on the phone. The OSRM geometry
-- cache is coordinate/order-keyed, so the line refetches — no rebuild required.
