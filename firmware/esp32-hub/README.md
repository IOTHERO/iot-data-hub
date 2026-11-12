# TiTi Hub: central switch hub (ESP32-WROOM-32)

The hub is the manager of a building's network. Modules (for example the Relay-8 / DEVICE 8DO)
connect to it over the LAN or Wi-Fi; the hub lists them, runs the schedules and scenes, and talks
to the server (OPC platform) as one device. **When the internet or the server is lost nothing
stops**: modules keep talking to the hub, scenes keep running from the DS3231 clock, the phone
app keeps controlling everything through the hub's local API, and SMS commands still work.

## Hardware

| Part | Pins (config.h) | Notes |
|---|---|---|
| ESP32-WROOM-32 | | 4 MB flash |
| W5500 LAN | CS 5, SCK 18, MISO 19, MOSI 23, INT 4, RST 13 | VSPI. Used first; Wi-Fi is the backup |
| Wi-Fi | on the ESP32 | Station, plus an access point in config mode |
| GSM modem **SIM800L** | RX 16 (from modem TXD), TX 17 (through a 1 k / 2 k divider), RST 26, no power key | AT commands, 9600 baud, 2G only |
| DS3231 RTC | SDA 21, SCL 22, SQW 34 (reserved) | CR2032 keeps the time through a power cut |
| LED RUN / CONNECT / ALARM | 27 / 14 / 33 | active HIGH through 1 k |
| Config switch | 32 (to GND) | ON at power-up = config mode |
| RS-485 (MAX485 / ADM2682E) | TX 15 → DI, RX 35 ← RO, DE+RE 2 | UART1, 9600 8N1; Modbus RTU master for modules on a bus |
| Reserved | 36, 39 (inputs only), 0, 12 | nothing driven; do not use 12 for outputs (strapping pin) |

SIM800L notes: it needs **3.4 to 4.4 V** at up to 2 A bursts (a Li-ion cell, or a 4 V buck, with a
1000 µF capacitor next to the module; never the ESP32 3.3 V pin). Its serial logic is 2.8 V, so put a
divider on ESP32 TX. It switches on by itself (no power key); the firmware resets it through RST when
it does not answer. It is a 2G modem: check that your operator still has 2G, and keep the antenna out
of a metal box. The firmware reads the supply voltage (`AT+CBC`) and raises the alarm `gsm_power`
below 3.5 V. Also advised: a battery or supercap UPS for the whole hub (the part that must live
through a power cut).

## LEDs

| LED | Meaning |
|---|---|
| RUN | steady = config mode; 1 Hz blink = healthy; 5 Hz = fault (low memory, no network link for 60 s) |
| CONNECT | steady = connected to the server; 1 Hz blink = server configured but not reachable; short blink every 2 s = local network only (working); off = no link |
| ALARM | fast blink = new alarm; steady = alarm acknowledged but still active; off = none |

## Config switch

- **ON at power-up:** config mode. The hub opens Wi-Fi `TiTi-HUB-XXXX` (password `titi1234`) and the
  portal at `http://192.168.1.100/`. A blank hub does this by itself. Admin password: `admin`.
- **Running, ON for 3 s:** opens module enrollment for 2 minutes.
- **Running, toggled 5 times in 15 s:** admin and Wi-Fi passwords back to the defaults.

## Parts (like the Relay-8 module: few files, quick to build)

| File | What |
|---|---|
| `config.h` | pins, limits, timings (the only place to change them) |
| `core.h` | interfaces between the parts, the `Settings` structure |
| `hub.ino` | main loop, LEDs, switch gestures, alarms, log, shared command door |
| `settings.cpp` | settings and module registry in NVS, validation |
| `clock.cpp` | DS3231, NTP, time sources |
| `net.cpp` | W5500, Wi-Fi, backup network, mDNS (`_titihub._tcp`) |
| `broker.cpp` | MQTT server for modules, module list and state, link to the server |
| `scenes.cpp` | schedules and scenarios (run on the hub) |
| `local.cpp` | signed local API for the phone app (port 8080) |
| `gsm.cpp` | modem task, SMS in and out, signed SMS commands |
| `rs485.cpp` | Modbus RTU master: modules on the RS-485 bus (DEVICE 8DO in RS-485 mode) look like MQTT ones |
| `portal.cpp` | web portal API, OTA, static files |
| `data/` | web UI (LittleFS image, separate from the firmware) |
| `tools/web/`, `tools/build_web.sh` | sources of `data/index.html` (theme of the Relay-8 module) |

## Build

Arduino IDE 2: board **ESP32 Dev Module**, arduino-esp32 **3.x** (W5500 needs it), libraries
**ArduinoJson 7** and **PicoMQTT**. The sketch folder has its own `partitions.csv`
(64 KB NVS for settings, module list and scenes; two 1.7 MB app slots; 512 KB LittleFS for the web
UI), so a web UI update never touches settings. Or with PlatformIO: `platformio run` and
`platformio run -t buildfs` (on Windows run it from PowerShell, not Git Bash).

Web UI: `bash tools/build_web.sh` rebuilds `data/index.html`; upload `data/` as LittleFS, or send
the image on the portal's System page ("web UI image" switch).

## What it does

- **Modules:** they connect to the hub as their MQTT server (host = hub address, port 1883, username =
  device id, password = device secret, empty topic prefix). Registered modules connect; an unknown
  module is accepted only while enrollment is open. The hub keeps each module's online state,
  address, firmware and latest values, and raises an alarm when one is silent for
  `moduleOfflineS` (90 s).
- **Server link:** one MQTT connection as `h/<hubId>/...` (see the contract document). The
  hub forwards the modules' messages up and delivers the server's commands, rules, registry,
  scenes and settings down. Reconnect: random 0..10 s, doubling to 5 min.
- **Scenes:** triggers `time`, `interval`, `value`, `event`, `manual`; conditions; actions
  `write`, `delay`, `scene`, `sms`, `alarm`. Stored in NVS, run on the hub with or without internet.
- **Phone (local API):** `/local/v1/info|nonce|state|command` signed like the modules
  (`hub/platform/local_sign.py`, id = hub id). One door for everything: switch a tag, run a scene,
  edit scenes and the module list, set the hub clock from the phone.
- **SMS (control and notices):** `HUB <counter> <alias.tag=value | s.<scene> | ack> <sig>`; the sender
  must be an allowed number; the counter must grow; 5 per 10 minutes. Alarm SMS (max 6 per hour, the
  same text once per 10 minutes) go to the contacts with "alarms" on: English (160 characters) or
  **Persian** (UCS2, 70 characters; setting `gsm.smsLang`). A scene action `sms` can carry any text.
- **Calendar:** scenes can carry `calendar` (Jalali months, days of the month, a date range, skip or
  only holidays). The fixed solar holidays are built in; the lunar ones come from the portal or the
  server (`holidays`). The algorithm is the one in `hub/jalali.py`.
- **Clock:** DS3231 first, then NTP, the server and the phone correct it. Time scenes need a valid
  clock (alarm `no_time`).

## Modules: three ways in

| Module | How | Registry entry |
|---|---|---|
| Networked (LAN W5500 or Wi-Fi) | signs in to this hub's MQTT server with its device id and secret | `id`, `secret` (portal / phone) or `secret_sha256` (from the server) |
| On the RS-485 bus | the hub asks it (Modbus RTU, coils 0..7, pulses in holding 2..9) | `id`, `rtu` = its Modbus address (no secret) |
| New, unknown | enrollment window (config switch 3 s, or the portal button) | added by itself |

The server sends the registry when the hub connects (the home's own devices, by the SHA-256 of
their secret; the hub never sees a secret from the server). RS-485 entries set in the portal stay:
the server cannot see the bus. Every module, whichever way in, goes up to the server as
`h/<hub>/up` and takes commands from the server, the phone, SMS and scenes the same way.

## Not in this version

- TLS to the server is written (certificate always checked, private CA optional) but only compiled,
  not tried against a real broker.
- HTTP/TCP device transports, hub-to-hub links, the relay / input outputs of the hub itself.
- Incoming Persian SMS (commands are signed ASCII).
- Not tested on real hardware.
