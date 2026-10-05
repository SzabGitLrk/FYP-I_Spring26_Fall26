# University Point Locator — TODO

Status of this file: it used to be a closed list of five historical
map-screen bugs ("COMPLETED ✅"). It now tracks the **open** work left after
the full three-part audit (algorithms, security/launch, state/lifecycle).
Closed items are summarised at the bottom.

---

## A. You must do in Supabase (blocking)

- [x] **Re-run `supabase_security_fix.sql`** (now Sections 1–11) — done and
  verified from the anon key on 4 Oct 2026: `trips` → `[]`, `profiles?select=email`
  → `[]`, `otp_verification` → `[]`, anon `POST bus_locations` → 401 RLS,
  anon `POST admin_settings` → 401 RLS, anon `POST sos_alerts` → 401.
  Two checks still need a dashboard/SQL-editor glance:
  - `select tablename from pg_publication_tables where pubname='supabase_realtime'
    and tablename in ('bus_locations','sos_alerts');` → must return two rows
    (Sections 9 and 12 — **re-run the script once more after its §12 was
    added**; it is idempotent).
  - `select policyname, cmd from pg_policies where schemaname='public' and
    tablename in ('trips','sos_alerts');` → must show the new `Trips insert`
    and the admin-or-owner SOS policies (Sections 7/11/5).
  - `select email, is_approved from public.profiles where role='driver';`
    → your driver must be `true` (Sections 8/11 deny unapproved drivers).
  - Known oddity: live `admin_settings` has no `key` column (table predates
    the bootstrap; `CREATE IF NOT EXISTS` skipped it). Harmless — the app
    never queries it and Section 10's policies protect the table itself.
- [ ] `buses.driver_phone` is world-readable to the anon key — move it behind
  an authenticated view / RPC used by the "Contact" button.
- [ ] Decide the SOS throttling rule (trigger: max 1 active alert per user
  per 5 min) and read the displayed name from `profiles`, not the payload.
- [ ] `bus_locations` grows forever (append-only, one row per GPS fix) — add
  retention (upsert latest-per-bus, or `pg_cron` deleting rows older than N
  days). The read path is already capped at 500 rows.
- [ ] Email confirmation: decide auto-confirm ON vs OFF, verify the
  confirmation + password-reset emails actually arrive, and add a resend path.
- [ ] After re-running the fix, test driver approval end-to-end (the patch
  script's owner-only `profiles` UPDATE silently no-ops admin approvals).

## B. Launch-to-students blockers (Play / policy)

- [ ] `applicationId` is `com.example.*` — Google Play rejects it; it also
  leaks into the map User-Agent, manifest scheme and README. Change
  `namespace` + `applicationId`, move `MainActivity.kts`, the deep-link
  scheme, and `userAgentPackageName` together.
- [x] **Privacy policy drafted** — `PRIVACY_POLICY.md` in the repo root.
  Still to do: replace `[CONTACT EMAIL]` with a monitored address, host it
  (GitHub Pages / Supabase static), and paste the URL into the Play Console.
- [ ] Play Console: Data Safety declaration, content rating, store listing,
  screenshots.
- [ ] Regenerate the upload keystore (current passwords are the Flutter
  tutorial defaults `android`/`android`), store it outside the repo, enrol in
  Play App Signing. `*.jks` is now gitignored and untracked.
- [x] **Foreground service for driver GPS** — `flutter_foreground_task`
  ^11.0.3 wired in (`driver_dashboard` start/stop around every trip,
  location-typed service, `stopWithTask`). Still needs an on-device test:
  start a trip, lock the phone for 5 min, confirm positions keep arriving
  on a student's map. (Battery-optimisation exemption deliberately NOT
  requested — Play-hostile; add only if Samsung still throttles.)
- [ ] Decide the routing endgame: precompute the 3 static routes into
  Postgres (best), self-host OSRM/Valhalla, or take a keyed free tier — the
  public demo routers have no SLA and will rate-limit a class-change burst.
- [ ] iOS is dead scaffolding (no `Podfile`, no location usage strings) —
  declare the project Android-only or regenerate the target.
- [ ] At scale: move tiles to a caching provider and update the OSM
  User-Agent contact (tile.openstreetmap.org policy).

## C. Open code work (deferred from the audit)

- [x] Friendly errors: the five list/map/dashboard screens now show a
  human message (`_error` is no longer `e.toString()`); raw exceptions go
  to `debugPrint` only — done for university, routes, stops, map and driver.
  Remaining surfaces that still show raw text: driver `Location error: $e`
  snackbar and trip history's inline error (smaller scope).
- [ ] Driver bus matching falls back to **all active buses** when
  `userMetadata['name']` mismatches — it now WARNS loudly (snackbar) instead
  of failing silently; the proper fix is matching on `driver_id` (needs a
  `buses.driver_id` column + migration).
- [ ] Bottom overlay layout is hard-coded (`bottom:` constants) — restructure
  with `LayoutBuilder` for tablets/small widths; the ETA card now clears the
  SOS FAB and is capped at 2 lines, but a full layout pass is still wanted.
- [ ] Stop-detail / "All Stops" bottom sheets freeze their ETAs while open
  (the sheet is its own route and never rebuilds).
- [x] Admin dashboard state overhaul — `_isLoading` gate (no more
  0/0/0/0 and "No active SOS alerts" rendered as facts while four
  sequential queries were still in flight), in-page error banner with
  Retry instead of vanishing snackbars, all four loads run in parallel
  (and pull-to-refresh now refreshes buses too), and a **live
  `sos_alerts` subscription** so a new emergency appears without an app
  restart. Requires re-running `supabase_security_fix.sql` for the new
  Section 12 (sos_alerts realtime publication).
- [ ] Role resolution: a transient network error resolves to `student` with
  no retry UI (fail-closed, but silent for admins on flaky wifi).
- [ ] Dead menu entries that do nothing: profile "Edit Profile"/"View All",
  trip row tap, driver "profile" menu item — remove or implement.
- [ ] If realtime is unavailable, add a 30–60 s polling fallback so the map
  can recover without an app restart.
- [ ] Dead code pending your decision (~543 lines): `utils/helpers.dart`,
  `utils/app_theme.dart`, `models/profile.dart`, `widgets/map_legend.dart`,
  `widgets/bus_count_indicator.dart`, `widgets/loading_error.dart`
  (`device_service`, `logout_dialog`, `sos_button` already deleted).
- [ ] Tests: none for `route_service` (polyline decoders), models' `fromJson`,
  role resolution, or any screen; `widget_test` covers two widgets the app
  never builds.
- [ ] R8/minify is off — document that, or enable with `-keep` rules for
  `flutter_local_notifications` / `supabase`.

## D. Closed in this pass (record)

Fixed: route-projection teleporting (continuity window), arrival deadlock,
empty-route guard, monotonic step marks, roundabout exit 0, formatDistance
rounding, ETA model (stop→0/null, ceil), stale-bus age gates on both location
queries, UTC timestamps everywhere, parallel stop-notification load, reroute
backoff + off-route hysteresis, TTS retry, follow-camera pin/throttle/pan
disable, map rotation off, per-bus notification ids + 10-min cooldown + no
more toggle-off lie, "Arriving now" copy, `_startTracking` re-entrancy and
superseded-session cleanup, head-only stop counting, write-failure visibility,
trip-recording failure warning, role-router latch reset + stale-user guards +
"Check approval status", logout/SOS dialogs immune to the Android back button,
profile favourites wired to `stop_notifications` (no more demo data),
server-side role on the profile, trip history filtered to the driver +
failure-vs-empty states + tryParse guards, admin tryParse/derived pending
count, init-failure screen, release-build e-mail logging removed, browsable
deep link removed, POST_NOTIFICATIONS declared, release signing fails loudly
instead of silently using the debug key, keystores/`main`/`sage` untracked,
README claims corrected, bootstrap SQL scripts marked DO-NOT-RE-RUN, security
SQL extended with Sections 8–11.
