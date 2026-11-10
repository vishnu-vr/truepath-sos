# Dev environment (this Mac)

## Ports & processes

| Thing | Where |
| ----- | ----- |
| Functions emulator | `127.0.0.1:15002` (NOT 5001/5002 — Docker squats those) |
| Emulator hub | 4400/4500 |
| Fleet website | `127.0.0.1:8787` (python http.server) |
| Backend from Android emulator | `10.0.2.2:15002` |

## Paths & tools

- Android SDK: `/opt/homebrew/share/android-commandlinetools` — export as
  `ANDROID_HOME`; adb/emulator live under it.
- JDK: Android Studio's bundled JBR
  (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`) — set as
  `JAVA_HOME` for sdkmanager/avdmanager; Flutter is configured to use it.
- AVD: `truepath` (android-36, **google_apis** image — plain AOSP has no
  Google Play services and FCM silently fails).
- Flutter 3.47.x via Homebrew; Firebase CLI via npm; FlutterFire CLI in
  `~/.pub-cache/bin`.

## Machine quirks (important)

1. **The JVM cannot download from the network** on this machine (curl works
   fine). Consequences:
   - Gradle wrapper uses a LOCAL distribution:
     `distributionUrl=file:///Users/vishnu.ramesh/.gradle/dists/gradle-9.3.1-all.zip`
     in `app/android/gradle/wrapper/gradle-wrapper.properties`. If you bump
     Gradle, curl the new zip there first.
   - Build with `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` (Maven
     dependency downloads work with it).
2. **Docker occupies ports 5000-5002** — keep the functions emulator on 15002
   (configured in `firebase.json`; scripts/simulator/app all assume it).
3. The functions emulator uses the **Firebase CLI's login** as Admin SDK
   credentials against production Firestore/FCM — `firebase login` must be
   done (account: vishnuramesh52@gmail.com owns project truepath-sos-2611).
4. Deploying functions requires the Blaze plan → develop on the emulator.
   `firebase deploy --only firestore` (rules+indexes) works on the free plan.

## Library gotchas already handled

- firebase-admin v13: import `FieldValue/GeoPoint/Timestamp` from
  `firebase-admin/firestore`.
- flutter_local_notifications v23: needs compileSdk 37 + desugaring; its
  `initialize`/`show` use named parameters.
- firebase_messaging v17: `getToken()` is deprecated → `register()` +
  `onRegistered`, which REQUIRES the
  `firebase_messaging_installation_id_enabled` manifest meta-data.

## UI automation on the emulator (for agents)

`adb shell input` basics used in testing: `tap x y`, `text '...'` (no spaces
issues with quotes; `@`/`!` fine), `keyevent 61`=Tab, `66`=Enter,
`67`=Backspace, `111`=Esc (closes dialogs too!), `KEYCODE_HOME`. Screenshot:
`adb exec-out screencap -p > file.png`. Beware: the on-screen keyboard shifts
layout (take a fresh screenshot before tapping), and system sheets (e.g. the
"Try out your stylus" promo) can steal typed text.
