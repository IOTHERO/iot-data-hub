# TiTiSwitch app (Flutter)

The customer app for Android and iOS from one code base. It uses the hub's REST API like the web
app (`app/`) and the same translation files (`assets/i18n/` = `app/i18n/`, checked by
`tests/frontend/test_mobile.py`).

* **Screens:** logo splash, hub address (first start), sign-in with the two-step code, sign-up,
  forgotten password and the links the hub e-mails (verify, reset, invitation); home (today,
  quick scenes, favourites, groups and their editor, devices, notifications, live updates);
  device (outputs as one key, two keys or a momentary push, renamed with a long press; AC card,
  multi-step commands, timers, readings, 24 h chart, command log; settings: product picture and
  maker, name, room, sharing, transfer, removal, signed SMS, rules on the device, equipment
  behind an edge hub, support ticket); scenes (run, editor) and automations (list, on/off,
  editor, test); me (homes and their settings: place, tariff, SMS / call contacts, SMS PIN,
  holidays, how this phone reaches the home; a new home, invitations waiting, members and access
  levels, energy, tickets, language, theme, accent colour, arrive / leave detection, deleting
  the account, about TiTiSwitch); adding a device (QR camera, typed label, or industrial
  equipment through an edge hub). A maker's link (`…/app/?brand=<maker>`) as the hub address
  shows that maker on the sign-in page.
* **Same API as the web app:** `tests/frontend/test_mobile_api.py` checks that every `/api/...`
  path in `lib/` is a route of the hub.
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

A browser preview (`flutter build web --no-web-resources-cdn`) shows the screens; local control,
presence and the camera work only on a phone.

### Release signing

Without a release key the APK is signed with the debug key: fine for testing, but an app signed
with another key cannot later be installed over it. Make the key once and keep it (and its
passwords) safe; it is never committed (`*.jks`, `android/key.properties` are gitignored):

```
keytool -genkey -v -keystore titiswitch-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias titiswitch
```

* **Locally:** copy it to `android/app/release.jks` and write `android/key.properties` with
  `storeFile=release.jks`, `storePassword=…`, `keyAlias=titiswitch`, `keyPassword=…`.
* **On GitHub:** repository Settings → Secrets → Actions: `ANDROID_KEYSTORE_BASE64` (the file,
  base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The `mobile`
  workflow writes them for the build and deletes them afterwards.

iOS: `flutter build ipa` on a Mac with Xcode and an Apple developer account (signing in Xcode).
