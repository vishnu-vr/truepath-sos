# Runbook

All commands from `truepath/` unless noted. VS Code tasks exist for every one
of these (Terminal → Run Task), and F5 launches the app.

## Start everything

```bash
firebase emulators:start --only functions        # backend  (task: "backend: functions emulator")
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
  $ANDROID_HOME/emulator/emulator -avd truepath  # phone    (task: "android: start emulator")
cd app && flutter run                            # app      (F5 in VS Code)
python3 -m http.server 8787 -d web               # website  (task: "web: serve fleet site")
```

## Demo script (the full story)

1. `node scripts/seed.mjs` — demo data (safe to re-run; resets cane-001's
   secret + deletes its old alerts).
2. `node scripts/provision.mjs "New cane"` — prints the claim code.
3. In the app: create an account → Add cane → enter the claim code → cane
   appears under My canes with you as Owner+Primary.
4. Cane screen → Add caregiver (e.g. demo@truepath.app) → badges update live.
5. Home-button the app → `node simulator/sos.mjs --cane <deviceId>` →
   notification arrives → tap → SOS screen → Open in Maps / Mark Resolved.
6. Website (localhost:8787): admin login shows the whole fleet; any other
   account sees only its canes.

## Common operations

| Task | Command |
| ---- | ------- |
| Seed demo data | `node scripts/seed.mjs` |
| Provision a cane | `node scripts/provision.mjs ["name"]` |
| Grant/revoke website admin | `node scripts/make-admin.mjs <email> [--revoke]` (re-login needed) |
| SOS from demo cane | `node simulator/sos.mjs` |
| SOS from any cane | `node simulator/sos.mjs --cane <deviceId> [--lat --lng --battery]` |
| Negative test (must 401) | `node simulator/sos.mjs --secret WRONG` |
| Deploy rules+indexes | `firebase deploy --only firestore --project truepath-sos-2611` |
| Rebuild app | `cd app && JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true flutter build apk --debug` |
| Install on emulator | `adb install -r app/build/app/outputs/flutter-apk/app-debug.apk` |
| Static analysis | `cd app && flutter analyze` · `cd functions && node -e "require('./index.js')"` |

## Troubleshooting

- **Push not arriving**: app must have been opened once while signed in (token
  save); check `users/{uid}.fcmTokens` exists; emulator image must be
  google_apis; backend log says `pushSent: 0` when no tokens.
- **`ECONNRESET` from seed/scripts**: functions emulator not running, or an
  endpoint threw — read the emulator terminal/log; it hot-reloads
  `functions/index.js` on save.
- **Port taken on emulator start**: Docker again — confirm `firebase.json`
  still says 15002 and nothing else grabbed it (`lsof -nP -iTCP:15002`).
- **Gradle "could not download"**: the local-zip wrapper config was lost —
  see [Dev environment](Dev-Environment.md) §quirks.
- **Website shows permission errors**: expected for non-admins on admin
  queries; for admins, sign out/in after `make-admin` (claims are in the
  token).

## Production (live since 2026-11-10)

- Functions deployed:
  `https://us-central1-truepath-sos-2611.cloudfunctions.net/{sos,claim,manage,provision}`
  — redeploy with `firebase deploy --only functions`.
- Website: https://truepath-sos-2611.web.app (`firebase deploy --only hosting`).
- App: debug builds → local emulator; release builds → production URL
  (`app/lib/config.dart`). Release APKs go to App Distribution via the
  "app: distribute to Firebase testers" task.
- SOS against production: `node simulator/sos.mjs --cane <id> --url
  https://us-central1-truepath-sos-2611.cloudfunctions.net/sos`
- `seed`/`setAdmin` refuse to run in production; `provision` requires an
  admin ID token there. Dev flows (seed/provision/make-admin scripts) still
  use the LOCAL emulator — keep it for development.
- Both local emulator and production share the same Firestore/Auth/FCM, so
  data and logins are identical in both.
