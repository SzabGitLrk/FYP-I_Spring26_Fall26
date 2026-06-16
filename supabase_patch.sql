-- ============================================
-- PATCH: Fix schema mismatches for Flutter app
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. Add email column to profiles (app references it)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email TEXT;

-- 2. Change user_id in stop_notifications from uuid to text
-- (app may pass guest IDs that aren't valid UUIDs)
ALTER TABLE public.stop_notifications ALTER COLUMN user_id TYPE TEXT;

-- 3. Add email column to user_devices if missing
ALTER TABLE public.user_devices ADD COLUMN IF NOT EXISTS email TEXT;

-- 4. Enable RLS on tables that need it
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

-- 5. Add RLS policies for public read access
DROP POLICY IF EXISTS "Public read access" ON public.universities;
CREATE POLICY "Public read access" ON public.universities FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read access" ON public.routes;
CREATE POLICY "Public read access" ON public.routes FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read access" ON public.pickup_points;
CREATE POLICY "Public read access" ON public.pickup_points FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read access" ON public.buses;
CREATE POLICY "Public read access" ON public.buses FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read access" ON public.bus_locations;
CREATE POLICY "Public read access" ON public.bus_locations FOR SELECT USING (true);

-- 6. Profile policies
DROP POLICY IF EXISTS "Profiles select" ON public.profiles;
CREATE POLICY "Profiles select" ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Profiles insert" ON public.profiles;
CREATE POLICY "Profiles insert" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Profiles update" ON public.profiles;
CREATE POLICY "Profiles update" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- 7. SOS policies
DROP POLICY IF EXISTS "SOS insert" ON public.sos_alerts;
CREATE POLICY "SOS insert" ON public.sos_alerts FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "SOS select" ON public.sos_alerts;
CREATE POLICY "SOS select" ON public.sos_alerts FOR SELECT USING (true);

DROP POLICY IF EXISTS "SOS update" ON public.sos_alerts;
CREATE POLICY "SOS update" ON public.sos_alerts FOR UPDATE USING (true);

-- 8. Trip policies
DROP POLICY IF EXISTS "Trips select" ON public.trips;
CREATE POLICY "Trips select" ON public.trips FOR SELECT USING (true);

DROP POLICY IF EXISTS "Trips insert" ON public.trips;
CREATE POLICY "Trips insert" ON public.trips FOR INSERT WITH CHECK (auth.uid() = driver_id);

DROP POLICY IF EXISTS "Trips update" ON public.trips;
CREATE POLICY "Trips update" ON public.trips FOR UPDATE USING (auth.uid() = driver_id);

-- 9. Stop notification policies
DROP POLICY IF EXISTS "Notifications select" ON public.stop_notifications;
CREATE POLICY "Notifications select" ON public.stop_notifications FOR SELECT USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Notifications insert" ON public.stop_notifications;
CREATE POLICY "Notifications insert" ON public.stop_notifications FOR INSERT WITH CHECK (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Notifications update" ON public.stop_notifications;
CREATE POLICY "Notifications update" ON public.stop_notifications FOR UPDATE USING (user_id = auth.uid()::text);

-- 10. Device policies
DROP POLICY IF EXISTS "Devices select" ON public.user_devices;
CREATE POLICY "Devices select" ON public.user_devices FOR SELECT USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Devices insert" ON public.user_devices;
CREATE POLICY "Devices insert" ON public.user_devices FOR INSERT WITH CHECK (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Devices update" ON public.user_devices;
CREATE POLICY "Devices update" ON public.user_devices FOR UPDATE USING (user_id = auth.uid()::text);

-- 11. Auto-create profile on signup trigger (with error handling)
-- Wrapped in exception block so trigger failure never blocks user creation
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
    -- Silently ignore trigger errors so auth user creation is never blocked
    RAISE WARNING 'create_profile_for_user trigger failed for user %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_user_created ON auth.users;
CREATE TRIGGER on_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_for_user();
