# Backend API

Base URLs:
- **Production**: `https://us-central1-truepath-sos-2611.cloudfunctions.net`
  (used by release app builds and real canes)
- **Local emulator**: `http://127.0.0.1:15002/truepath-sos-2611/us-central1`
  (`http://10.0.2.2:15002/...` from the Android emulator; used by debug builds)

The switch lives in `app/lib/config.dart` (kReleaseMode). All endpoints are
JSON POST. Human endpoints require `Authorization: Bearer <Firebase ID token>`.

## POST /sos — device → backend (no user auth; device secret instead)

```json
{ "deviceId": "cane-001", "secretToken": "...", "type": "sos",
  "timestamp": "2026-11-10T12:00:00Z", "lat": 9.9816, "lng": 76.2999, "battery": 78 }
```
- 201 `{ok, alertId, pushSent}` — alert stored, FCM sent to every caregiver's
  tokens (dead tokens pruned from `users/{uid}.fcmTokens`).
- 400 bad shape · 401 unknown device / wrong secret · 409 cane not claimed yet.
- Side effects: creates `alerts` doc (denormalized `deviceName`,
  `caregiverUids`, `memberUids`), updates device `battery`/`lastSeenAt`.

## POST /claim — unboxing

```json
{ "code": "TP-<deviceId>-<10 hex chars>" }        // or {deviceId, pairCode}
```
- 200 `{ok, deviceId}` — caller becomes immutable `ownerUid`, sole caregiver,
  `primaryCaregiverUid`; status → `active`; `pairCodeHash` deleted (one-time).
- 400 bad format · 401 wrong code · 404 no such cane · 409 already claimed.
- Runs in a Firestore transaction.

## POST /manage — owner or primary caregiver only

```json
{ "deviceId": "cane-xxx", "action": "addCaregiver", "email": "x@y.z" }
```
Actions (target by `email` or `uid` where applicable):
- `addCaregiver` — idempotent; adds to `caregiverUids` + `members` map.
- `removeCaregiver` — owner cannot be removed (400); removing the primary
  falls primary back to the owner.
- `setPrimaryCaregiver` — target must already be a caregiver (else 400).
- `linkCaneUser` / `unlinkCaneUser` — sets/clears `caneUserUid`.
- `setName` — takes `name` instead of email/uid.

403 if caller is neither owner nor primary · 404 unknown cane or email.
The `members{uid:{name,email}}` map is recomputed to only hold current people.

## POST /registerToken — claim a phone's FCM token

Requires an ID token. Registers the token on the caller's `users` doc AND
removes it from any other account still holding it (same phone, previous
sign-in) — a phone's token belongs to exactly one account, so nobody receives
pushes for alerts they can't read. The app also removes its token on sign-out.
```json
{ "token": "<fcm registration token>" }
```

## POST /mockSos — admin demo trigger

Requires an ID token with the `admin` custom claim. Fires the exact same
alert + push pipeline as `/sos` but authenticates the admin instead of the
device secret. Alerts get `simulated: true` and the push title says "(test)".
```json
{ "deviceId": "cane-xxx", "lat": 9.98, "lng": 76.29, "battery": 42 }   // all but deviceId optional
```
- 201 `{ok, alertId, pushSent}` · 403 not admin · 404 unknown cane ·
  409 cane not claimed. Defaults: jittered Kochi coords, last known battery.
- Used by the website's "🧪 Test SOS" button (admin view).

## POST /provision — "the factory"

Emulator: open. Production: requires an admin ID token (custom claim).
```json
{ "name": "Srehari's cane" }     // optional
```
- 201 `{ok, deviceId, secretToken, claimCode}` — secretToken goes into the
  ESP32 (simulator writes `simulator/<deviceId>.json`), claimCode goes on the
  box QR. Device doc starts `status: "provisioned"`, no owner.

## POST /setAdmin · POST /seed — emulator-only

- `setAdmin {email, admin?}` — sets the `admin` custom claim +
  `users/{uid}.isAdmin` (re-login required to take effect).
- `seed` — creates demo caregiver (`demo@truepath.app`) owning `cane-001`
  (already claimed), deletes cane-001's old alerts, returns a fresh device
  secret. Both return 403 outside the emulator.

## Getting an ID token in scripts/tests

```bash
API_KEY=<current_key from app/android/app/google-services.json>
curl -s "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$API_KEY" \
  -H 'content-type: application/json' \
  -d '{"email":"demo@truepath.app","password":"...","returnSecureToken":true}' # → .idToken
```
