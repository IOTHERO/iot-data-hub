# TiTiSwitch for Android

The customer app (`app/`) in a native shell. Every screen, translation and update comes from the
hub, so Android and the web version (iPhone: Safari → Share → Add to Home Screen) always match.
The shell adds what a web page cannot do:

* **Local control over the home Wi-Fi** while the internet is down (`LocalBridge.java`,
  `app/js/local.js`, contract in `docs/platform.md` → *Local control*): the app signs each command
  with the device's local key and a one-time nonce from the device.
* **Camera** for scanning a device's QR label.
* Links to other sites, `tel:` and `sms:` open in the phone's own apps.

## Build

Google's Android repositories are not reachable from Iran, so the APK is built on GitHub:
**Actions → android → Run workflow** (optionally with the hub address), or any push that changes
`android/`. The APK is under the run's *Artifacts* (`titiswitch-android-debug`).

Elsewhere (JDK 17, Android SDK 34, Gradle 8.7):

```
gradle -p android assembleDebug -PserverUrl=https://your-hub.example/app/
```

Without `serverUrl` the app asks for the hub address on first start; a long press on the back key
changes it later. The address must be HTTPS (plain HTTP only for a hub on a private address).

## Install on a phone

Download `app-debug.apk` to the phone, open it and allow installing from this source. The debug
build is signed with a debug key: fine for testing; a release for users needs a release keystore
(kept out of git, as a GitHub secret).
