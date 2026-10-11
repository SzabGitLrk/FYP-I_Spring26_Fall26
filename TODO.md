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
- [ ] **Run `supabase_bus_issues.sql`** (idempotent) — creates `bus_issues`
  with its RLS policies and realtime membership behind the driver's
  Fuel Empty / Bus Fault buttons and the admin dashboard's "Bus Issue
  Reports" section. Until it runs those features fail honestly ("Could
  not send the report"; empty section) and nothing else breaks.
- [ ] **Run `supabase_advisor_fixes.sql`** (idempotent) — answers the Supabase
  Advisor report of 11 Oct 2026: pins `search_path` on the two live trigger
  functions, drops the dead `check_bus_proximity*` drift functions, revokes
  REST EXECUTE on trigger/utility functions, drops the open
  `bus_notifications` insert policy, and hides PII tables from the anon
  role at the grant layer. No app behavior changes (the app makes zero
  rpc() calls; every revoked read already ran as an authenticated user).
- [ ] **Enable leaked-password protection** (Dashboard → Authentication →
  Sign In / Providers → Email/Password → "Check password against
  HaveIBeenPwned.org") — the only Advisor finding that is a dashboard
  toggle, not SQL.
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
  The leftovers are closed too: the GPS stream error and the password-reset
  snackbar got friendly copy (reset keeps a specific rate-limit variant).
  The remaining `Error: ` prefixes render already-friendly text.
- [x] Driver bus matching no longer falls back to **all active buses** and
  never silently picks `routeBuses.first` — a bus-picker dialog must be
  confirmed whenever more than one candidate exists (and when the driver's
  name matches none, with a "No bus is assigned to you" subtitle); a route
  with zero buses refuses Start Trip with a clear message. Matching on
  `driver_id` (a `buses.driver_id` column + migration) remains a separate,
  deliberately unmade decision.
- [ ] Bottom overlay layout is hard-coded (`bottom:` constants) — restructure
  with `LayoutBuilder` for tablets/small widths; the ETA card now clears the
  SOS FAB and is capped at 2 lines, but a full layout pass is still wanted.
- [x] Stop-detail / "All Stops" bottom sheets now track live ETAs — both
  sheets listen to a `_busRevision` ValueNotifier bumped wherever
  `_busLocations` changes (a modal sheet is its own route and never saw
  the map's rebuilds, so its ETA froze at open).
- [x] Route ordering + per-route framing ("same route in every routes"):
  supabase-dart's `.order()` defaults to **descending**, so stops arrived
  last-stop-first — inverting the map's green/red first-last markers, the
  waypoint order sent to OSRM/Valhalla (wrong direction on one-ways), and
  driver/student `next_stop_index` decoding (both ends consistently
  backwards vs the bus's physical visit order). Every intentional sort now
  passes `ascending: true`, and the map auto-fits the route's stop bounds
  on ready (was a fixed zoom-13 view, so routes opened cropped and looked
  alike at first glance). Verified live on emulator: routes 7/8/9 fetch
  distinct geometry (105/110/76 points); routes 7 and 8 still share the
  PTS corridor by data design.
- [x] Admin dashboard state overhaul — `_isLoading` gate (no more
  0/0/0/0 and "No active SOS alerts" rendered as facts while four
  sequential queries were still in flight), in-page error banner with
  Retry instead of vanishing snackbars, all four loads run in parallel
  (and pull-to-refresh now refreshes buses too), and a **live
  `sos_alerts` subscription** so a new emergency appears without an app
  restart. Requires re-running `supabase_security_fix.sql` for the new
  Section 12 (sos_alerts realtime publication).
- [x] Role resolution fail-closed WITH visibility (#22): a failed
  profiles lookup now renders a "Could not verify account" screen with
  Retry/Sign-out instead of silently resolving to `student` (which hid an
  admin's flaky login inside the student home screen). Sign-out and
  identity changes clear the failure latch.
- [x] Dead menu entries cleaned up (#23): driver "Profile" menu now
  actually navigates (route existed all along); profile's "Edit Profile",
  both "View All" buttons and the dead Settings gear removed (no fake
  affordances). Trip-history rows stay non-interactive on purpose - they
  show no tap affordance; add a detail expansion only if wanted.
- [x] Realtime fallback: the map re-ages stale rows on a 30 s timer, polls
  `bus_locations` over REST every 30 s (cold floor if the websocket dies),
  and the feed's restart budget now cools down 60 s and retries instead of
  giving up until an app restart.
- [ ] Dead code pending your decision (~543 lines): `utils/helpers.dart`,
  `utils/app_theme.dart`, `models/profile.dart`, `widgets/map_legend.dart`,
  `widgets/bus_count_indicator.dart`, `widgets/loading_error.dart`
  (`device_service`, `logout_dialog`, `sos_button` already deleted).
- [ ] Tests: `route_service` decoder/fallback coverage and `models_test`
  (`fromJson` for every live model + `estimatedTimeTo` boundaries) are in;
  still none for role resolution or any screen; `widget_test` covers two
  widgets the app never builds.
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

Navigation/routing audit pass (11 Oct 2026, full Severity 1–3 + dummy-data
sweep follow-through): bus-feed rows collapsed to newest-per-bus (no more
ghost-marker trails or row-count "active" pills); one `_staleAfter` 5-min
constant governs feed/poll/ETA/alerts, with a 30 s age-out timer and a 30 s
REST poll; ETA only from a bus that is fresh and has not passed the stop,
with a 1.3 road-circuity factor and a 20 km/h urban speed floor (distance
card degrades honestly instead of blanking); reroute dead zone closed
(120→50 m floor) and guidance switches the GPS stream to unfiltered fixes
with a 2 s throttle so a stationary student can still latch arrival; feed
restart budget cools down 60 s + retries; join-at-stop prefers the later
near-equal stop (no backwards first leg); turn re-announce ladder (80 m /
25 m) + speed-scaled lookahead (5 s of travel), depart step held for 25 m,
arrival second gate within 15 m of the final maneuver; intermediate OSRM
arrive-steps voiced/shown as "Passing <stop>"; `startTrip` returns the
inserted trip id (no re-query guess, stale active trips reaped, dispose
ends the trip, honest "not recorded" message); stationary-bus 20 s
heartbeat; skipped-stop advance (head-only freeze gone); bus picker
instead of silent `.first`/all-buses; heading written only above 1.5 m/s;
logout `popUntil(isFirst)` (no signed-out PII stacked over login) on all
three roles; profile notification toggle captures state before `await` +
nullable `routeId`; admin mutations `.select('id')` row-verification +
ordered driver list; trip history outer-joins deleted routes; fabricated
student stats removed; notification permission reverts the toggle honestly
when denied; location-denied explains itself and offers Settings; route
cache (15 min TTL, 32 entries) with 6 s/8 s timeouts and a repo contact
UA; Google handoff opens in `travelmode=driving` + `dir_action=navigate`;
"End of route" copy; arrival-alert map pruned; device-clock skew warning;
pluralization/raw-exception sweep; `utils/helpers.dart` delegates to the
ceil ETA model (no round-trap); `bus_locations` 7-day retention SQL
documented in `supabase_launch_cleanup.sql`.

Driver SOS (11 Oct 2026): the dashboard has an emergency button, parity
with the student map's SOS — confirm dialog, best-effort GPS fix (live
stream → OS-cached → one fresh reading, honest refusal when location is
off), a 30 s session cooldown against duplicate taps, and the alert lands
in `sos_alerts` as `Bus <number> - <name>` so the live admin feed shows
WHICH bus has the problem. Zero schema change: there is no message column,
so the bus context rides in `user_name`.

Bus issue reports + route-tracking accuracy (11 Oct 2026): the driver
dashboard gained always-visible Fuel Empty / Bus Fault buttons (confirm
dialog → `bus_issues` insert carrying bus, driver, CHECK-constrained
issue type, GPS fix and a SERVER-clock `created_at` → green success
snackbar, 30 s cooldown); the admin dashboard gained a live "Bus Issue
Reports" feed (realtime subscription + row-verified Resolve, same write
pattern as SOS). New `lib/utils/geo_snapping.dart` map-matches the
DRAWN bus marker onto the route line (≤ 50 m snap; genuine detours shown
honestly; ETAs/distances keep the raw fix) so a GPS wander no longer
reads as "the bus left the route". Requires `supabase_bus_issues.sql`
(§A) to be run.
