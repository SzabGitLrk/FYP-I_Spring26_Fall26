-- ============================================
-- COMPLETE SETUP: Run this in Supabase SQL Editor
-- Safe to run on existing DB (CREATE IF NOT EXISTS)
-- ============================================

BEGIN;

-- ========== CREATE ALL TABLES ==========

CREATE TABLE IF NOT EXISTS public.universities (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    city TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.routes (
    id BIGSERIAL PRIMARY KEY,
    university_id BIGINT REFERENCES public.universities(id) ON DELETE CASCADE,
    route_name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pickup_points (
    id BIGSERIAL PRIMARY KEY,
    route_id BIGINT REFERENCES public.routes(id) ON DELETE CASCADE,
    point_name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    address TEXT,
    landmark TEXT,
    order_index INT NOT NULL DEFAULT 0,
    estimated_time_from_previous INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.buses (
    id BIGSERIAL PRIMARY KEY,
    route_id BIGINT REFERENCES public.routes(id) ON DELETE CASCADE,
    bus_number TEXT NOT NULL,
    driver_name TEXT,
    driver_phone TEXT,
    capacity INT DEFAULT 20,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bus_locations (
    id BIGSERIAL PRIMARY KEY,
    bus_id BIGINT REFERENCES public.buses(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed DOUBLE PRECISION DEFAULT 0,
    heading DOUBLE PRECISION DEFAULT 0,
    next_stop_index INT DEFAULT 0,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT '',
    email TEXT,
    role TEXT NOT NULL DEFAULT 'student',
    is_approved BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.trips (
    id BIGSERIAL PRIMARY KEY,
    driver_id UUID,
    bus_id BIGINT REFERENCES public.buses(id) ON DELETE SET NULL,
    route_id BIGINT REFERENCES public.routes(id) ON DELETE SET NULL,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    distance_km DOUBLE PRECISION DEFAULT 0,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sos_alerts (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID,
    user_name TEXT NOT NULL DEFAULT '',
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.stop_notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    stop_id BIGINT REFERENCES public.pickup_points(id) ON DELETE CASCADE,
    route_id BIGINT REFERENCES public.routes(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_devices (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT,
    onesignal_id TEXT,
    platform TEXT DEFAULT 'android',
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.otp_verification (
    id BIGSERIAL PRIMARY KEY,
    phone_number TEXT NOT NULL,
    otp_code TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bus_notifications (
    id BIGSERIAL PRIMARY KEY,
    stop_id BIGINT REFERENCES public.pickup_points(id) ON DELETE CASCADE,
    bus_id BIGINT REFERENCES public.buses(id) ON DELETE SET NULL,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_settings (
    id BIGSERIAL PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    value TEXT NOT NULL DEFAULT ''
);

-- ========== SCHEMA ALTERATIONS ==========

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE public.user_devices ADD COLUMN IF NOT EXISTS email TEXT;

-- Fix stop_notifications.user_id type (text instead of uuid)
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'stop_notifications'
        AND column_name = 'user_id' AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.stop_notifications ALTER COLUMN user_id TYPE TEXT;
    END IF;
END $$;

-- ========== ENABLE RLS ==========

ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pickup_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bus_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stop_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_verification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bus_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_settings ENABLE ROW LEVEL SECURITY;

-- OTP verification policies (allow anonymous OTP flow)
DROP POLICY IF EXISTS "OTP insert" ON public.otp_verification;
CREATE POLICY "OTP insert" ON public.otp_verification FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "OTP select" ON public.otp_verification;
CREATE POLICY "OTP select" ON public.otp_verification FOR SELECT USING (true);
DROP POLICY IF EXISTS "OTP update" ON public.otp_verification;
CREATE POLICY "OTP update" ON public.otp_verification FOR UPDATE USING (true);

-- Admin settings: allow all authenticated users to read
DROP POLICY IF EXISTS "Admin settings select" ON public.admin_settings;
CREATE POLICY "Admin settings select" ON public.admin_settings FOR SELECT USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Admin settings insert" ON public.admin_settings;
CREATE POLICY "Admin settings insert" ON public.admin_settings FOR INSERT WITH CHECK (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Admin settings update" ON public.admin_settings;
CREATE POLICY "Admin settings update" ON public.admin_settings FOR UPDATE USING (auth.role() = 'authenticated');

-- ========== RLS POLICIES ==========

DROP POLICY IF EXISTS "Public read" ON public.universities;
CREATE POLICY "Public read" ON public.universities FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read" ON public.routes;
CREATE POLICY "Public read" ON public.routes FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read" ON public.pickup_points;
CREATE POLICY "Public read" ON public.pickup_points FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read" ON public.buses;
CREATE POLICY "Public read" ON public.buses FOR SELECT USING (true);
DROP POLICY IF EXISTS "Buses delete" ON public.buses;
CREATE POLICY "Buses delete" ON public.buses FOR DELETE USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

DROP POLICY IF EXISTS "Public read" ON public.bus_locations;
CREATE POLICY "Public read" ON public.bus_locations FOR SELECT USING (true);

DROP POLICY IF EXISTS "Profiles select" ON public.profiles;
CREATE POLICY "Profiles select" ON public.profiles FOR SELECT USING (true);
DROP POLICY IF EXISTS "Profiles insert" ON public.profiles;
CREATE POLICY "Profiles insert" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "Profiles update" ON public.profiles;
CREATE POLICY "Profiles update" ON public.profiles FOR UPDATE USING (
  auth.uid() = id OR EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
  )
);

DROP POLICY IF EXISTS "SOS insert" ON public.sos_alerts;
CREATE POLICY "SOS insert" ON public.sos_alerts FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "SOS select" ON public.sos_alerts;
CREATE POLICY "SOS select" ON public.sos_alerts FOR SELECT USING (true);
DROP POLICY IF EXISTS "SOS update" ON public.sos_alerts;
CREATE POLICY "SOS update" ON public.sos_alerts FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Trips select" ON public.trips;
CREATE POLICY "Trips select" ON public.trips FOR SELECT USING (true);
DROP POLICY IF EXISTS "Trips insert" ON public.trips;
CREATE POLICY "Trips insert" ON public.trips FOR INSERT WITH CHECK (auth.uid() = driver_id);
DROP POLICY IF EXISTS "Trips update" ON public.trips;
CREATE POLICY "Trips update" ON public.trips FOR UPDATE USING (auth.uid() = driver_id);

DROP POLICY IF EXISTS "Notify select" ON public.stop_notifications;
CREATE POLICY "Notify select" ON public.stop_notifications FOR SELECT USING (user_id = auth.uid()::text);
DROP POLICY IF EXISTS "Notify insert" ON public.stop_notifications;
CREATE POLICY "Notify insert" ON public.stop_notifications FOR INSERT WITH CHECK (user_id = auth.uid()::text);
DROP POLICY IF EXISTS "Notify update" ON public.stop_notifications;
CREATE POLICY "Notify update" ON public.stop_notifications FOR UPDATE USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Devices select" ON public.user_devices;
CREATE POLICY "Devices select" ON public.user_devices FOR SELECT USING (user_id = auth.uid()::text);
DROP POLICY IF EXISTS "Devices insert" ON public.user_devices;
CREATE POLICY "Devices insert" ON public.user_devices FOR INSERT WITH CHECK (user_id = auth.uid()::text);
DROP POLICY IF EXISTS "Devices update" ON public.user_devices;
CREATE POLICY "Devices update" ON public.user_devices FOR UPDATE USING (user_id = auth.uid()::text);

-- ========== AUTO-CREATE PROFILE ON SIGNUP ==========

CREATE OR REPLACE FUNCTION public.create_profile_for_user()
RETURNS TRIGGER AS $$
BEGIN
  BEGIN
    INSERT INTO public.profiles (id, name, email, role, is_approved)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
      NEW.email,
      COALESCE(NEW.raw_user_meta_data->>'role', 'student'),
      CASE WHEN COALESCE(NEW.raw_user_meta_data->>'role', 'student') = 'admin' THEN true ELSE false END
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'create_profile_for_user trigger failed for user %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_user_created ON auth.users;
CREATE TRIGGER on_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_for_user();

-- ========== SEED DATA ==========

-- Reset existing seed data
DELETE FROM bus_notifications WHERE stop_id IN (SELECT id FROM pickup_points);
DELETE FROM stop_notifications WHERE stop_id IN (SELECT id FROM pickup_points);
DELETE FROM bus_locations WHERE bus_id IN (SELECT id FROM buses);
DELETE FROM trips WHERE bus_id IN (SELECT id FROM buses);
DELETE FROM buses;
DELETE FROM pickup_points;
DELETE FROM routes;
DELETE FROM sos_alerts;
DELETE FROM universities WHERE city != 'Larkana';

-- Ensure Larkana university exists
INSERT INTO universities (id, name, city)
VALUES (1, 'The University of Larkana', 'Larkana')
ON CONFLICT (id) DO NOTHING;

-- Routes
INSERT INTO routes (university_id, route_name, description) VALUES
(1, 'PTS Route', 'Main route via Postal Training School'),
(1, 'Nae Dare → PTS Route', 'Starts from Nae Dare, ends at PTS'),
(1, 'OPP Colony Route', 'Connecting Opposite Colony to Qamber Bus Stop');

-- Pickup points
INSERT INTO pickup_points (route_id, point_name, latitude, longitude, address, order_index) VALUES
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'PTS (Postal Training School)', 27.5880, 68.2220, 'Main Larkana Bypass Road', 1),
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'University Chowk', 27.5680, 68.2220, 'Near Main Gate', 2),
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'Student Hostel Stop', 27.5720, 68.2250, 'Boys Hostel Gate', 3);

INSERT INTO pickup_points (route_id, point_name, latitude, longitude, address, order_index) VALUES
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'Nae Dare Stop', 27.5550, 68.2280, 'Nae Dare Colony', 1),
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'Old Railway Crossing', 27.5620, 68.2250, 'Near Railway Line', 2),
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'PTS Terminal', 27.5880, 68.2220, 'PTS Main Gate', 3);

INSERT INTO pickup_points (route_id, point_name, latitude, longitude, address, order_index) VALUES
((SELECT id FROM routes WHERE route_name = 'OPP Colony Route' LIMIT 1), 'OPP Colony Gate', 27.5630, 68.2200, 'Opposite Colony Main Gate', 1),
((SELECT id FROM routes WHERE route_name = 'OPP Colony Route' LIMIT 1), 'Qamber Bus Stop', 27.6000, 68.2500, 'Qamber City Road', 2);

-- Buses
INSERT INTO buses (route_id, bus_number, driver_name, status) VALUES
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'LARK-101', 'Driver PTS', 'active'),
((SELECT id FROM routes WHERE route_name = 'PTS Route' LIMIT 1), 'LARK-102', 'Driver Route A', 'active'),
((SELECT id FROM routes WHERE route_name = 'Nae Dare → PTS Route' LIMIT 1), 'LARK-201', 'Driver Nae Dare', 'active'),
((SELECT id FROM routes WHERE route_name = 'OPP Colony Route' LIMIT 1), 'LARK-301', 'Driver OPP', 'active');

-- Bus locations
INSERT INTO bus_locations (bus_id, latitude, longitude, speed, heading, next_stop_index) VALUES
((SELECT id FROM buses WHERE bus_number = 'LARK-101'), 27.5880, 68.2220, 25.5, 45, 2),
((SELECT id FROM buses WHERE bus_number = 'LARK-102'), 27.5680, 68.2220, 0.0, 0, 1),
((SELECT id FROM buses WHERE bus_number = 'LARK-201'), 27.5550, 68.2280, 30.2, 90, 2),
((SELECT id FROM buses WHERE bus_number = 'LARK-301'), 27.5630, 68.2200, 15.0, 180, 2);

COMMIT;

-- ============================================
-- TO CREATE AN ADMIN USER:
-- 1. Go to Authentication > Users > Add User
-- 2. Enter email/password, click Create
-- 3. Run:
-- ============================================
-- UPDATE public.profiles
-- SET role = 'admin', is_approved = true
-- WHERE id = (SELECT id FROM auth.users WHERE email = 'admin@example.com' LIMIT 1);
--
-- UPDATE auth.users
-- SET raw_user_meta_data = raw_user_meta_data || '{"role": "admin"}'::jsonb
-- WHERE email = 'admin@example.com';
-- ============================================
