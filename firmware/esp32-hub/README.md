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
| GSM modem | RX 16 (from modem TX), TX 17, PWRKEY 25, RST 26 | SIM800 / SIM7600 / A7670, AT commands, 115200 |
| DS3231 RTC | SDA 21, SCL 22, SQW 34 (reserved) | CR2032 keeps the time through a power cut |
| LED RUN / CONNECT / ALARM | 27 / 14 / 33 | active HIGH through 1 k |
| Config switch | 32 (to GND) | ON at power-up = config mode |
| Reserved | 35, 36, 39 (inputs only), 2, 15, 0, 12 | nothing driven; do not use 12 for outputs (strapping pin) |

Advice for the board: a 5 V / 2 A supply for the modem (SIM800 pulls 2 A bursts), a 1000 µF
capacitor at the modem, a prefer-4G modem (2G networks are being shut down), a battery or supercap
UPS for the whole hub (this is the part that must live through a power cut), 3.3 V level
check on the modem UART, and an antenna that is not inside a metal box.

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
- **SMS:** `HUB <counter> <alias.tag=value | s.<scene> | ack> <sig>`; sender must be an allowed
  number; counter must grow; 5 per 10 minutes. Alarm SMS (max 6 per hour) are short English texts.
- **Clock:** DS3231 first, then NTP, the server and the phone correct it. Time scenes need a valid
  clock (alarm `no_time`).

## Not in this version

- TLS to the server (plain MQTT only: use it inside a VPN or a trusted LAN until added).
- HTTP/TCP device transports, hub-to-hub links, RS-485 / Modbus master on the hub, the relay /
  input outputs of the hub itself (pins are reserved).
- Jalali months and holidays in scenes (weekdays only).
- Persian SMS text (GSM 7-bit ASCII only).
- Not tested on real hardware.
