# Architecture

```
ESP32 cane (simulated by simulator/sos.mjs)
   │ HTTPS POST /sos {deviceId, secretToken, type, timestamp, lat, lng, battery}
   ▼
Cloud Functions backend (functions/index.js)
   │ verify secret hash → store alert → look up caregivers → FCM push
   ▼
Firestore (project truepath-sos-2611)            FCM
   users / devices / alerts                        │ high-priority push
                                                   ▼
        ┌────────────────────────────┐   TruePath Care app (Flutter, app/)
        │ Fleet website (web/)       │   caregivers + cane users
        │ admin: everything          │   alerts, claim, manage
        │ others: own canes          │
        └────────────────────────────┘
```

## Components

- **Cane / simulator** — `simulator/sos.mjs` mirrors the firmware steps 1–8
  from the spec (long press → debounce → local buzz → GPS → WiFi → HTTPS →
  JSON → POST). Per-cane credentials live in `simulator/<deviceId>.json`
  (written by provisioning), the demo cane in `simulator/device.json`.
- **Backend** — Cloud Functions v2 (Node 22), run in the local emulator
  against production Firestore/FCM. See [Backend API](Backend-API.md).
- **App** — Flutter (Android). See [Mobile app](Mobile-App.md).
- **Website** — static HTML+JS, Firebase CDN SDK. See [Website](Website.md).

## Trust model

- The **cane** authenticates with a per-device secret; only its sha256 hash is
  stored. Unknown/wrong secret → 401, nothing stored, no push (spec step 10).
- **People** authenticate with Firebase Auth (email/password). Backend
  endpoints verify the ID token from the `Authorization: Bearer` header.
- **Roles are per-cane**, held on the device doc:
  - `ownerUid` — set once at claim time, immutable, cannot be removed.
  - `primaryCaregiverUid` — manages the cane alongside the owner; transferable.
  - `caregiverUids[]` — all receive SOS pushes; may resolve alerts.
  - `caneUserUid` — the cane user's account; sees alerts/cane, no management,
    no pushes (by design — the cane already buzzes locally).
- **Claiming** consumes a one-time pairing code (hash deleted on success), so
  a cane can never be re-claimed; recovery would be a manual admin operation.
- **Admin** is a Firebase custom claim (`admin: true`) used by the website and
  by `provision` in production. Granted via `scripts/make-admin.mjs`.

## Lifecycle of a cane

provision (factory: secret + claim code, status `provisioned`)
→ claim (owner locked in, status `active`, code burned)
→ manage (caregivers added/removed, primary transferred, cane user linked)
→ sos (alerts + pushes) → resolve (caregiver, app) → history.
