/// Single source of truth for ALL remote-service configuration.
///
/// This file deliberately holds ONLY values that are safe to ship inside a
/// client app bundle:
///
///  * Supabase **anon** key  - a publishable JWT scoped to `role=anon`. It is
///    designed to be public; real security comes from Row Level Security
///    policies, never from hiding this string.
///  * Supabase URL           - public project endpoint.
///
/// NEVER put a `service_role` key, database password, or any server-side
/// secret in this file: everything under `lib/` is compiled into the APK and
/// can be extracted by anyone who downloads it.
///
/// Maps require no API key at all: Google Maps was replaced with
/// `flutter_map` + OpenStreetMap, so there is no billing account, no
/// credentials page, and no per-platform key injection anywhere in this repo.
/// The only per-platform configuration left is the keystore
/// (`android/key.properties`), which is signing, not a network credential.
///
/// If Google Maps is ever reintroduced, its key cannot be read from Dart at
/// runtime — each platform has to inject it from its own config (an Android
/// `manifestPlaceholders` value, an iOS `Info.plist`/Swift constant, and a
/// script tag in `web/index.html`).
class AppConfig {
  const AppConfig._();

  /// Supabase project REST endpoint.
  static const String supabaseUrl = 'https://wstuufgiapgkskkcrdjx.supabase.co';

  /// Supabase anon (publishable) key.
  ///
  /// Decoded payload:
  /// ```json
  /// {"iss":"supabase","ref":"wstuufgiapgkskkcrdjx","role":"anon",
  ///  "iat":1772622732,"exp":2088198732}
  /// ```
  /// Issued 2026-03-04, expires 2036-03-03.
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndzdHV1ZmdpYXBna3Nra2NyZGp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MjI3MzIsImV4cCI6MjA4ODE5ODczMn0.LLDQ1PPFJJRVowZ_PaOWMBNeNJVepVC6W8LTmpZX6pg';
}
