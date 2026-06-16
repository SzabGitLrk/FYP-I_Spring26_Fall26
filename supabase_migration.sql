-- ===========================================
-- COMPLETE RESET FOR LARKANA-ONLY APP
-- Deletes in correct order to avoid foreign key errors
-- ===========================================

BEGIN; -- Start transaction for safety

-- Step 1: Delete dependent records first
-- Delete bus_notifications referencing old pickup_points
DELETE FROM bus_notifications 
WHERE stop_id IN (SELECT id FROM pickup_points);

-- Delete stop_notifications (user preferences)
DELETE FROM stop_notifications 
WHERE stop_id IN (SELECT id FROM pickup_points);

-- Step 2: Delete bus_locations referencing old buses
DELETE FROM bus_locations 
WHERE bus_id IN (SELECT id FROM buses);

-- Step 3: Delete trips referencing old buses
DELETE FROM trips 
WHERE bus_id IN (SELECT id FROM buses);

-- Step 4: Delete buses
DELETE FROM buses;

-- Step 5: Delete pickup_points
DELETE FROM pickup_points;

-- Step 6: Delete routes
DELETE FROM routes;

-- Step 7: Delete SOS alerts (if any)
DELETE FROM sos_alerts;

-- Step 8: Now delete universities NOT in Larkana
DELETE FROM universities WHERE city != 'Larkana';

-- Step 9: Verify Larkana university exists (should be ID 1)
SELECT * FROM universities;

-- Step 10: Add new routes for Larkana University
INSERT INTO routes (university_id, route_name, description) VALUES
(1, 'PTS Route', 'Main route via Postal Training School'),
(1, 'Nae Dare → PTS Route', 'Starts from Nae Dare, ends at PTS'),
(1, 'OPP Colony Route', 'Connecting Opposite Colony to Qamber Bus Stop');

-- Step 11: Add new pickup points
-- For Route 1: PTS Route
INSERT INTO pickup_points (route_id, point_name, latitude, longitude, address, order_index) VALUES
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'PTS (Postal Training School)', 27.5880, 68.2220, 'Main Larkana Bypass Road', 1),
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'University Chowk', 27.5680, 68.2220, 'Near Main Gate', 2),
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'Student Hostel Stop', 27.5720, 68.2250, 'Boys Hostel Gate', 3);

-- For Route 2: Nae Dare → PTS Route
INSERT INTO pickup_points (route_id, point_name, latitude, longitude, address, order_index) VALUES
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'Nae Dare Stop', 27.5550, 68.2280, 'Nae Dare Colony', 1),
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'Old Railway Crossing', 27.5620, 68.2250, 'Near Railway Line', 2),
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'PTS Terminal', 27.5880, 68.2220, 'PTS Main Gate', 3);

-- For Route 3: OPP Colony Route
INSERT INTO pickup_points (route_id, point_name, latitude, longitude, address, order_index) VALUES
((SELECT id FROM routes WHERE route_name = 'OPP Colony Route' LIMIT 1), 'OPP Colony Gate', 27.5630, 68.2200, 'Opposite Colony Main Gate', 1),
((SELECT id FROM routes WHERE route_name = 'OPP Colony Route' LIMIT 1), 'Qamber Bus Stop', 27.6000, 68.2500, 'Qamber City Road', 2);

-- Step 12: Add new buses
INSERT INTO buses (route_id, bus_number, driver_name, status) VALUES
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'LARK-101', 'Driver PTS', 'active'),
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'LARK-102', 'Driver Route A', 'active'),
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'LARK-201', 'Driver Nae Dare', 'active'),
((SELECT id FROM routes WHERE route_name = 'OPP Colony Route' LIMIT 1), 'LARK-301', 'Driver OPP', 'active');

-- Step 13: Add initial bus locations
INSERT INTO bus_locations (bus_id, latitude, longitude, speed, heading, next_stop_index) VALUES
((SELECT id FROM buses WHERE bus_number = 'LARK-101'), 27.5880, 68.2220, 25.5, 45, 2),
((SELECT id FROM buses WHERE bus_number = 'LARK-102'), 27.5680, 68.2220, 0.0, 0, 1),
((SELECT id FROM buses WHERE bus_number = 'LARK-201'), 27.5550, 68.2280, 30.2, 90, 2),
((SELECT id FROM buses WHERE bus_number = 'LARK-301'), 27.5630, 68.2200, 15.0, 180, 2);

-- Step 14: Verify everything
SELECT 'Verification Results:' as message;
SELECT u.name as university, r.route_name, COUNT(pp.id) as pickup_points
FROM universities u
JOIN routes r ON r.university_id = u.id
LEFT JOIN pickup_points pp ON pp.route_id = r.id
GROUP BY u.name, r.route_name
ORDER BY r.route_name;

-- Step 15: Add email column to profiles (needed by app)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email TEXT;

-- Step 16: Fix stop_notifications user_id type
-- Drop dependent policies first, alter column, then recreate
DROP POLICY IF EXISTS "Users can manage their own notifications" ON public.stop_notifications;
DROP POLICY IF EXISTS "Notifications select" ON public.stop_notifications;
DROP POLICY IF EXISTS "Notifications insert" ON public.stop_notifications;
DROP POLICY IF EXISTS "Notifications update" ON public.stop_notifications;
ALTER TABLE public.stop_notifications ALTER COLUMN user_id TYPE TEXT;
CREATE POLICY "Notifications select" ON public.stop_notifications FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "Notifications insert" ON public.stop_notifications FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "Notifications update" ON public.stop_notifications FOR UPDATE USING (user_id = auth.uid()::text);

COMMIT; -- Save all changes
