# TiTiSwitch app (Flutter)

The customer app for Android and iOS from one code base. It uses the hub's REST API like the web
app (`app/`) and the same translation files (`assets/i18n/` = `app/i18n/`, checked by
`tests/frontend/test_mobile.py`).

* **Screens:** logo splash, hub address (first start), sign-in, home (today, quick scenes,
  devices, notifications), device (outputs, settings, timers, readings), scenes and automations
  (list, on/off, editor), me (homes, members and access levels, energy, support tickets,
  language, theme, about TiTiSwitch), adding a device (QR camera or typed label).
* **Without internet** the last answers of the hub are shown, and on the home Wi-Fi commands go
  straight to the devices, signed with each device's local key (`lib/core/local.dart`,
  contract in `docs/platform.md` → *Local control*). Secrets live in the phone's keystore.

## Build

Flutter 3.47 (stable). On GitHub: **Actions → mobile** builds the APK (artifact
`titiswitch-flutter-apk`). Locally:

```
flutter pub get
flutter analyze
flutter test
flutter build apk --release        # Android (needs the Android SDK)
flutter build ipa                  # iOS (on a Mac with Xcode)
```

A browser preview (`flutter build web --no-web-resources-cdn`) shows the screens; local control
and the camera work only on a phone. The release APK is signed with the debug key until a
release keystore is set up (kept out of git).
