#pragma once
// TiTi Hub (central switch hub) - all compile-time settings in one place.
// ESP32-WROOM-32 + W5500 (LAN) + Wi-Fi + GSM modem (SIM800/SIM7600/A7670, AT commands) + DS3231.
// Change a pin or a limit here only. Runtime settings are stored in NVS and edited in the portal.

#include <Arduino.h>

#define FW_VERSION "0.1.0"
#define PRODUCT_NAME "TiTi Hub"

// ------------------------------------------------------------------ pins (ESP32-WROOM-32) ------
// W5500 on the VSPI bus. The RST line lets the firmware reset the chip after a hang.
#define PIN_ETH_CS    5
#define PIN_ETH_SCK   18
#define PIN_ETH_MISO  19
#define PIN_ETH_MOSI  23
#define PIN_ETH_INT   4
#define PIN_ETH_RST   13

// GSM modem: SIM800L on UART2. The module needs 3.4..4.4 V at up to 2 A bursts (a Li-ion cell or a
// 4 V buck with a 1000 uF capacitor next to it; NOT the 3.3 V pin). Its serial logic is 2.8 V:
// put a divider (1 k / 2 k) on ESP32 TX -> modem RX, ESP32 RX can read the modem TX directly.
// A SIM800L board switches on by itself when power arrives: there is no PWRKEY pin.
#define PIN_GSM_RX    16      // ESP32 RX  <- modem TXD
#define PIN_GSM_TX    17      // ESP32 TX  -> (divider) -> modem RXD
#define PIN_GSM_PWRKEY -1     // -1 for SIM800L (set a GPIO for SIM800C / SIM7600 boards that have one)
#define PIN_GSM_RST   26      // modem RST (active LOW pulse), -1 if not wired
#define GSM_BAUD      9600    // SIM800L starts in auto-baud; 9600 is the safe speed
#define GSM_MIN_VBAT_MV 3500  // below this the SIM800L resets while sending: alarm "gsm_power"

// DS3231 real-time clock on I2C (CR2032 keeps the time through a power cut).
#define PIN_I2C_SDA   21
#define PIN_I2C_SCL   22
#define PIN_RTC_SQW   34      // reserved: DS3231 alarm / 1 Hz output (input-only pin)

// LEDs (active HIGH through 1 k) and the config switch (to GND, internal pull-up).
#define PIN_LED_RUN     27
#define PIN_LED_CONNECT 14
#define PIN_LED_ALARM   33
#define PIN_CONFIG_SW   32

// RS-485 (Modbus RTU master for modules wired on a bus, e.g. DEVICE 8DO in RS-485 mode), UART1.
// DE+RE on GPIO2: LOW at boot = receive, as the transceiver needs. -1 in PIN_RS485_TX = no bus.
#define PIN_RS485_TX  15      // -> DI
#define PIN_RS485_RX  35      // <- RO (input-only pin)
#define PIN_RS485_DE  2       // DE+RE, HIGH = send
#define RS485_BAUD    9600
#define RTU_POLL_MS   500     // one module polled every 0.5 s, in turn
#define RTU_TIMEOUT_MS 120    // reply time per request
#define RTU_REPORT_MS 30000   // values sent up at least this often, else on change

// Reserved for later (nothing is driven on them now): GPIO 36, 39 (inputs only),
// GPIO 12 (MTDI strapping: keep LOW at boot), GPIO 0 (boot).

// ------------------------------------------------------------------ limits and timings ---------
#define MAX_MODULES        32      // modules in the registry
#define MAX_VALUES         16      // tags kept per module
#define MAX_CONTACTS       10      // phone numbers
#define MAX_SCENES         24
#define MAX_ALARMS         12
#define SCENES_MAX_BYTES   8192
#define REGISTRY_MAX_BYTES 4096

#define BROKER_PORT_DEFAULT 1883   // modules connect here (their "server")
#define PORTAL_PORT         80
#define LOCAL_PORT_DEFAULT  8080   // the phone app (home network, internet down)

#define MODULE_OFFLINE_S_DEFAULT 90    // a module silent this long is offline (alarm)
#define CLOUD_LOST_ALARM_S       300   // internet/server lost this long raises an info alarm
#define NONCE_MAX          16
#define NONCE_TTL_MS       30000UL
#define SMS_PER_10MIN      5           // contract: at most 5 SMS commands in 10 minutes
#define SMS_ALARM_PER_HOUR 6           // outgoing alarm SMS limit
#define CMD_EXPIRE_S       30          // a command to a module expires if not carried out

// Reconnect to the server after a cut: random 0..10 s, doubling to 5 min, +-20 % (contract).
#define RECONNECT_FIRST_MAX_MS 10000UL
#define RECONNECT_CAP_MS       300000UL
#define RECONNECT_STABLE_MS    60000UL

// Config mode: Wi-Fi access point and the portal address (same as the Relay-8 module).
#define AP_SSID_PREFIX "TiTi-HUB-"
#define AP_PASS_DEFAULT "titi1234"
#define AP_IP 192, 168, 1, 100
#define ADMIN_PASS_DEFAULT "admin"
#define DEFAULT_UTC_OFFSET_MIN 210     // Iran standard time (+3:30, no daylight saving)

#define MAX_HOLIDAYS      60           // extra holidays (Jalali dates) from the server or the portal
#define SMS_UCS2_CHARS    70           // one Persian (UCS2) SMS holds 70 characters

#define LOG_LINES 40                   // live log ring for the portal
