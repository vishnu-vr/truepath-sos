# TruePath — SOS system for blind/deafblind users

Implements the 20-step SOS flow from `../srehari.docx`, plus the full account /
device lifecycle: sign-up, factory provisioning, QR claiming, multi-caregiver
management, and a fleet website.

## Components

- **Cane (simulated)** — `simulator/sos.mjs` plays the ESP32: builds the SOS
  JSON and POSTs it over HTTPS. Comments map 1:1 to the firmware steps.
- **Backend** — Cloud Functions (`functions/index.js`):
  - `POST /sos` — verify device secret → store alert → push to all caregivers.
  - `POST /claim` — claim a new cane with its one-time code; the claimer
    becomes the **immutable owner** and first/primary caregiver; the code is
    burned so the cane can never be claimed again.
  - `POST /manage` — owner/primary caregiver only: add/remove caregivers,
    transfer primary, link/unlink the cane user's account, rename.
  - `POST /provision` — the "factory" (emulator, or admin in production):
    creates a cane, returns its device secret + claim code.
  - `POST /setAdmin`, `POST /seed` — emulator-only ops helpers.
- **TruePath Care app** (Flutter, `app/`) — sign-up/sign-in, Alerts tab
  (active + history, live), My canes tab, Add cane (QR scan or manual code),
  cane management screen, FCM push with tap-through to the SOS screen,
  Open in Maps, Mark Resolved (caregivers only).
- **Fleet website** (`web/`) — plain HTML+JS on the Firebase CDN SDK.
  Admins (custom claim) see ALL canes, alerts, and accounts; everyone else
  sees only their own canes and alerts. Live via Firestore snapshots.

## Data model (Firestore)

| Collection      | Doc                                                          |
| --------------- | ------------------------------------------------------------ |
| `users/{uid}`   | `name`, `email`, `fcmTokens[]`, `isAdmin?`                    |
| `devices/{id}`  | `name`, `status` (`provisioned`/`active`), `secretHash`, `pairCodeHash` (until claimed), `ownerUid`, `primaryCaregiverUid`, `caregiverUids[]`, `caneUserUid`, `members{uid:{name,email}}`, `battery`, `lastSeenAt` |
| `alerts/{id}`   | `deviceId`, `deviceName`, `caregiverUids[]`, `memberUids[]`, `status`, `location`, `battery`, `sentAt`, `resolvedAt/By` |

Rules: users read/write only their own profile; devices/alerts readable by
their members (admins see all); the only client write anywhere is resolving
an alert (caregivers). Everything else goes through the backend.

## Running it

```bash
firebase login                                  # once

cd truepath
firebase emulators:start --only functions       # backend (port 15002)

node scripts/seed.mjs                           # demo: demo@truepath.app / Truepath!demo1 owns cane-001
node scripts/provision.mjs "Srehari's cane"     # factory: prints claim code TP-...
node scripts/make-admin.mjs demo@truepath.app   # admin role for the website

cd app && flutter run                           # app (Android emulator)
open https://truepath-sos-2611.web.app          # website (Firebase Hosting)
python3 -m http.server 8787 -d web              # …or serve it locally

node simulator/sos.mjs                          # SOS from cane-001
node simulator/sos.mjs --cane cane-xxxxxx       # SOS from a provisioned cane
node simulator/sos.mjs --secret WRONG           # negative test → 401
```

Full unboxing demo: create an account in the app → Add cane → enter/scan the
claim code from `provision.mjs` → cane appears under My canes → add caregivers
by email → background the app → fire the simulator → push arrives → tap →
SOS screen → Mark Resolved.

## Deploying (later)

Local emulator uses your Firebase CLI credentials against the real project;
nothing needs deploying for development. For production: upgrade to the Blaze
plan, `firebase deploy --only functions,firestore`, point `app/lib/config.dart`
and the simulator `--url` at the Cloud Functions URL, and host `web/` anywhere
static (e.g. Firebase Hosting). `seed`/`setAdmin` refuse to run outside the
emulator; `provision` requires an admin account in production.
