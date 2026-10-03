# University Point Locator — TODO

Status of this file: it used to be a closed list of five historical
map-screen bugs ("COMPLETED ✅"). It now tracks the **open** work left after
the full three-part audit (algorithms, security/launch, state/lifecycle).
Closed items are summarised at the bottom.

---

## A. You must do in Supabase (blocking)

- [ ] **Re-run `supabase_security_fix.sql`** (now Sections 1–11) in the SQL
  Editor, then verify with the anon key:
  - `GET /rest/v1/trips?select=*` → `[]` (Section 7, still pending)
  - `POST /rest/v1/bus_locations` → 401/403 for anon, 201 for an approved driver (Section 8 — the bootstrap scripts had **no** INSERT policy for it)
  - `bus_locations` listed under Database → Replication / `supabase_realtime` (Section 9 — otherwise `.stream()` never updates)
  - `POST /rest/v1/admin_settings` → 403 for non-admins (Section 10)
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
- [ ] Write and host a **privacy policy** (email, precise location, SOS
  location; processors: Supabase, OpenStreetMap, OSRM, Valhalla).
- [ ] Play Console: Data Safety declaration, content rating, store listing,
  screenshots.
- [ ] Regenerate the upload keystore (current passwords are the Flutter
  tutorial defaults `android`/`android`), store it outside the repo, enrol in
  Play App Signing. `*.jks` is now gitignored and untracked.
- [ ] Foreground service for driver GPS: without `FOREGROUND_SERVICE(_LOCATION)`
  the stream dies minutes after the driver locks the phone — students see
  frozen buses on every real trip.
- [ ] Decide the routing endgame: precompute the 3 static routes into
  Postgres (best), self-host OSRM/Valhalla, or take a keyed free tier — the
  public demo routers have no SLA and will rate-limit a class-change burst.
- [ ] iOS is dead scaffolding (no `Podfile`, no location usage strings) —
  declare the project Android-only or regenerate the target.
- [ ] At scale: move tiles to a caching provider and update the OSM
  User-Agent contact (tile.openstreetmap.org policy).

## C. Open code work (deferred from the audit)

- [ ] Map error views still render raw exception text in some screens
  (`university_list`, `routes_list`, `pickup_points`, map's `_error`, driver
  dashboard) — introduce friendly typed errors; detail behind `kDebugMode`.
- [ ] Admin dashboard: no loading/error state (shows zeros + "No active SOS
  alerts" while four sequential queries run); load in parallel; subscribe to
  `sos_alerts` instead of fetching once.
- [ ] Driver bus matching falls back to **all active buses** when
  `userMetadata['name']` mismatches — match on `driver_id` and show an
  explicit "no bus assigned" empty state instead.
- [ ] Bottom overlay layout is hard-coded (`bottom:` constants) — restructure
  with `LayoutBuilder` for tablets/small widths; the ETA card now clears the
  SOS FAB and is capped at 2 lines, but a full layout pass is still wanted.
- [ ] Stop-detail / "All Stops" bottom sheets freeze their ETAs while open
  (the sheet is its own route and never rebuilds).
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
