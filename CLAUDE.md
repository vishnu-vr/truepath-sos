# TruePath — AI assistant guide

SOS system for blind/deafblind users: ESP32 smart cane (simulated) → Firebase
backend → Flutter caregiver app ("TruePath Care") + fleet website. Product
spec: `../srehari.docx` (20-step SOS flow).

**Read the wiki before changing anything:** [`wiki/Home.md`](wiki/Home.md) is
the index. Most relevant pages: [Architecture](wiki/Architecture.md),
[Backend API](wiki/Backend-API.md), [Data model](wiki/Data-Model.md),
[Dev environment](wiki/Dev-Environment.md) (ports + machine quirks — saves you
an hour), [Runbook](wiki/Runbook.md) (how to run/demo/test everything).

## Hard-won facts (do not rediscover)

- Functions emulator runs on **port 15002** (Docker squats 5001/5002) and
  talks to **real** Firestore/FCM using the Firebase CLI's credentials.
  Project: `truepath-sos-2611` (Blaze plan). Functions are ALSO deployed to
  production: `https://us-central1-truepath-sos-2611.cloudfunctions.net/<fn>`
  (`firebase deploy --only functions`). Debug app builds use the local
  emulator; release builds use production (`app/lib/config.dart`,
  kReleaseMode switch). seed/setAdmin only work in the emulator; dev
  workflows (seed, provision scripts) still need it running.
- This Mac's JVM cannot download through Gradle: `gradle-wrapper.properties`
  points at a local zip (`~/.gradle/dists/gradle-9.3.1-all.zip`). Keep it.
- Android SDK: `/opt/homebrew/share/android-commandlinetools` (`ANDROID_HOME`),
  JDK = Android Studio's bundled JBR, AVD `truepath` (google_apis image — FCM
  needs it). Build with `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true`.
- firebase-admin v13: `FieldValue`/`GeoPoint`/`Timestamp` import from
  `firebase-admin/firestore`, NOT `admin.firestore.*`.
- flutter_local_notifications needs compileSdk 37 + core library desugaring;
  firebase_messaging's `register()` API needs the
  `firebase_messaging_installation_id_enabled` manifest meta-data. All already
  configured in `app/android/`.
- All device/membership writes go through backend endpoints (`claim`,
  `manage`, `provision`) — Firestore rules block client writes on purpose.
  The only client write is resolving an alert.

## Conventions

- Backend secrets are stored hashed (sha256) and compared constant-time.
- `seed`/`setAdmin` endpoints are emulator-only; `provision` is emulator-only
  or admin. Never weaken those guards.
- Alert docs denormalize `caregiverUids`/`memberUids`/`deviceName`; device
  docs denormalize `members{uid:{name,email}}` — update them together in the
  backend, never from clients.

Test credentials: see [`TEST_ACCOUNTS.md`](TEST_ACCOUNTS.md).
VS Code: F5 runs the app; tasks (⇧⌘B menu) start emulators/seed/SOS.
