# Privacy Policy — University Point Locator

**Effective date:** 4 October 2026

University Point Locator ("the app") is a university bus-tracking and
navigation application. This policy explains what the app collects, why, and
with whom it is shared. Replace `[CONTACT EMAIL]` below with a monitored
email address before publishing.

## Data the app collects

| Data | Why | Who can see it |
|---|---|---|
| Email address and account name | Sign-in and account creation (Supabase Auth) | You; app administrators |
| Role and approval status (student / driver / admin) | Decides which screens you can use | App administrators |
| **Precise location, while a driver runs a trip** | Live bus positions for students' maps, ETA calculation, stop-arrival counting | All app users (this is the app's core function) |
| **Precise location, when you send an SOS alert** | Lets administrators and responders find you | App administrators |
| Trip records (route, start/end time, distance, stop progress) | Trip history for the driver and administrators | The driver; app administrators |
| Notification preferences (per stop) | Sends the alerts you asked for | You only |
| Device model (on SOS alerts) | Helps administrators diagnose reports | App administrators |

The app does **not** collect: contacts, photos, calendar, payment
information, advertising identifiers, or precise location when you are *not*
actively tracking a trip or sending an SOS.

## Location sharing (important)

When a driver starts a trip, their position is written to a shared database
and shown in real time on every student's map inside the app. This is
intentional and only happens while a trip is active. Ending the trip stops
location updates immediately. Students' locations are never shared —
students only *send* their location inside an SOS alert, which is visible to
administrators.

## Where data is stored

- **Supabase** (hosted PostgreSQL + authentication) — accounts, trips,
  locations, preferences. Access is restricted by row-level security
  policies: users only see the rows they are allowed to see.
- **OpenStreetMap tiles** (tile.openstreetmap.org and mirrors) — map imagery.
  Rendering a tile reveals your current map viewport to the tile server.
- **OSRM / Valhalla public routers** (router.project-osrm.org,
  valhalla1.openstreetmap.de) — route geometry. A route request sends the
  start/end coordinates of the requested route; it does not include your
  account or email.

## Retention and deletion

Trip history and bus positions are kept while your account exists. You may
request deletion of your account and all associated data (trips, SOS alerts,
preferences) by emailing `[CONTACT EMAIL]`; deletion is performed in
Supabase and cannot be undone.

## Sharing

No data is sold or shared with advertisers. Data is shared only with the
infrastructure listed above and with app administrators, who need it to
operate the service (approving drivers, responding to SOS alerts).

## Permissions used

- **Location** — live bus tracking (drivers) and SOS alerts (all roles).
- **Notifications** — arrival and approach alerts you subscribe to, plus the
  "Trip in progress" foreground-service notification while a driver tracks.
- **Internet** — maps, routing, and the Supabase backend.

## Children

The app is intended for university students. No data is collected from
children knowingly.

## Changes

Material changes will be announced in-app. Continued use after a change
means acceptance of the updated policy.

## Contact

Questions or deletion requests: `[CONTACT EMAIL]`.
