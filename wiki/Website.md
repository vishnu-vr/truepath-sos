# Fleet website

Single static page in `web/index.html` — no build step, no framework.
Firebase CDN modular SDK (auth + firestore), live `onSnapshot` tables,
light/dark via `prefers-color-scheme`.

## Where it runs

- **Hosted (live):** https://truepath-sos-2611.web.app — Firebase Hosting,
  free plan. Deploy updates with `firebase deploy --only hosting`
  (config: the `hosting` block in `firebase.json`, serving `web/`).
- **Local dev:** `python3 -m http.server 8787 -d web` → http://localhost:8787
  (or the VS Code task "web: serve fleet site").

Both domains are on Firebase Auth's authorized list by default, so sign-in
works in either place.

## Views

Decided by the `admin` custom claim on the signed-in account
(`getIdTokenResult().claims.admin`):

- **Admin** (header shows "· admin"): ALL canes (status, battery, last seen,
  people with owner/primary/cane-user role pills from the `members` map),
  the 50 most recent alerts fleet-wide with Google Maps links, and every
  account (`users` collection, admin badge).
- **Customer** (header shows "· my canes"): only canes where the user is
  owner, caregiver, or cane user (three merged queries), and only alerts
  where they are in `memberUids`.

The scoping is enforced by Firestore security rules, not just the UI — a
non-admin running the admin queries gets permission errors.

## Live map and battery

Leaflet 1.9.4 (cdnjs) with OpenStreetMap tiles, no API key. The **Live map**
card shows one marker per visible cane at `lastLocation`, coloured by battery
(green ≥50%, amber ≥20%, red below), with a popup. Clicking a cane row (or
marker) draws its 24-hour trail from `devices/{id}/locations`, live. The canes
table shows live battery with its age and the live location.

## Admin test panel (🧪 Test… on each active cane)

- **Test SOS at a spot**: click the map (or type lat/lng), set battery, and
  fire `/mockSos` there. The full alert + push pipeline runs (alert tagged
  `test`, push titled "(test)").
- **Simulate a walk**: click waypoints in order, then Start. The page
  interpolates points about 15 m apart and calls `/mockLocation` every 2 s,
  dropping battery 1% every 10 steps. Stop ends it. The cane moves live on
  this page and in the app.

Implementation note: row buttons pass only the cane ID (`openTest(id)`); the
panel reads the rest from the live `caneDocs` map. Don't inline names into
`onclick` attributes, because HTML-decoding turns `&#39;` back into `'` and
breaks the JS.

## Caching

`firebase.json` serves HTML with `Cache-Control: no-cache`, so a hosting
deploy is visible on the next page load (Hosting's default lets browsers
cache pages for an hour).

## Notes

- The web Firebase config (apiKey etc.) is embedded in the page; it comes
  from the registered web app (`flutterfire configure --platforms=android,web`
  regenerates it in `app/lib/firebase_options.dart` → `web`). These values
  are public identifiers, not secrets.
- Grant/revoke admin: `node scripts/make-admin.mjs <email> [--revoke]`, then
  sign out/in (claims live in the ID token).
- The website is read-only by design; management actions happen in the app
  (or could later call the same `/manage` endpoint — it already has CORS).
