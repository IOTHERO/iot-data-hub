// TiTi Hub - central switch hub (ESP32-WROOM-32, W5500 LAN, Wi-Fi, GSM, DS3231).
//
// Online: modules connect to this hub (it is their MQTT server); the hub lists them, runs the
// schedules and scenes, and talks to the server (OPC platform) as one device: h/<hubId>/...
// Offline (internet or server lost): nothing stops. Modules keep talking to the hub over the
// local network, scenes and schedules keep running from the DS3231 clock, the phone app controls
// everything through the signed local API (port 8080), and SMS commands work through the modem.
//
// Parts: settings.cpp clock.cpp net.cpp broker.cpp scenes.cpp local.cpp gsm.cpp portal.cpp
// Settings: config.h (pins, limits) and core.h (interfaces). Web UI: data/ (LittleFS, separate).

#include <ArduinoJson.h>
#include <mbedtls/md.h>
#include <mbedtls/base64.h>
#include <esp_task_wdt.h>
#include <esp_system.h>
#include <stdarg.h>
#include "core.h"

bool g_configMode = false;
bool configMode() { return g_configMode; }

// ---------------------------------------------------------------- crypto helpers ---------------
String b64urlEncode(const uint8_t *data, size_t len) {
  std::vector<unsigned char> buf(4 * ((len + 2) / 3) + 1);
  size_t written = 0;
  mbedtls_base64_encode(buf.data(), buf.size(), &written, data, len);
  String s;
  for (size_t i = 0; i < written; i++) {
    char c = (char)buf[i];
    if (c == '=') break;
    s += (c == '+') ? '-' : (c == '/') ? '_' : c;
  }
  return s;
}

size_t b64urlDecode(const String &in, uint8_t *out, size_t outMax) {
  String s = in;
  s.replace("-", "+");
  s.replace("_", "/");
  while (s.length() % 4) s += '=';
  size_t written = 0;
  if (mbedtls_base64_decode(out, outMax, &written, (const unsigned char *)s.c_str(), s.length()) != 0) return 0;
  return written;
}

void hmacSha256(const uint8_t *key, size_t keyLen, const uint8_t *msg, size_t len, uint8_t out[32]) {
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), key, keyLen, msg, len, out);
}

bool sameText(const String &a, const String &b) {
  if (a.length() != b.length()) return false;
  uint8_t diff = 0;
  for (size_t i = 0; i < a.length(); i++) diff |= (uint8_t)(a[i] ^ b[i]);
  return diff == 0;
}

// ---------------------------------------------------------------- log ring ---------------------
static String logRing[LOG_LINES];
static uint32_t logSeq = 0;

void hlog(uint8_t level, const char *fmt, ...) {
  if (level > S.logLevel) return;
  char buf[160];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
  static const char tag[] = "EWID";
  String line = String(millis() / 1000) + " " + tag[min<int>(level, 3)] + " " + buf;
  Serial.println(line);
  logRing[++logSeq % LOG_LINES] = line;
}

String logTail(uint32_t &seq) {
  String out;
  uint32_t first = logSeq > LOG_LINES ? logSeq - LOG_LINES + 1 : 1;
  for (uint32_t i = max(seq + 1, first); i <= logSeq; i++) out += logRing[i % LOG_LINES] + "\n";
  seq = logSeq;
  return out;
}

// ---------------------------------------------------------------- alarms ----------------------
static std::vector<Alarm> alarms;

void alarmRaise(const char *code, const String &text, bool sms) {
  for (auto &a : alarms) {
    if (a.code == code) { a.text = text; return; }      // already raised: keep its state
  }
  if (alarms.size() >= MAX_ALARMS) alarms.erase(alarms.begin());
  Alarm a;
  a.code = code;
  a.text = text;
  a.at = nowUtc();
  alarms.push_back(a);
  hlog(1, "ALARM %s: %s", code, text.c_str());
  if (sms) smsAlarm(text);
  JsonDocument d;
  d["code"] = code;
  d["text"] = text;
  d["at"] = (long)a.at;
  d["active"] = true;
  String out;
  serializeJson(d, out);
  cloudPublishHub("alarm", out);
}

void alarmClear(const char *code) {
  for (size_t i = 0; i < alarms.size(); i++) {
    if (alarms[i].code != code) continue;
    JsonDocument d;
    d["code"] = code;
    d["active"] = false;
    d["at"] = (long)nowUtc();
    String out;
    serializeJson(d, out);
    cloudPublishHub("alarm", out);
    alarms.erase(alarms.begin() + i);
    return;
  }
}

void alarmAckAll() { for (auto &a : alarms) a.acked = true; }
bool alarmAny() { return !alarms.empty(); }
bool alarmUnacked() { for (auto &a : alarms) if (!a.acked) return true; return false; }

String alarmsJson() {
  JsonDocument d;
  JsonArray arr = d.to<JsonArray>();
  for (auto &a : alarms) {
    JsonObject o = arr.add<JsonObject>();
    o["code"] = a.code;
    o["text"] = a.text;
    o["at"] = (long)a.at;
    o["acked"] = a.acked;
  }
  String out;
  serializeJson(d, out);
  return out;
}

// ---------------------------------------------------------------- shared command entry ----------
// One door for the phone, SMS and the portal: "<module>:<tag>", "scene:<id>", "hub:ack", "hub:enroll".
bool execTarget(const String &target, const String &valueJson, const char *by, String &err) {
  if (target.startsWith("scene:")) return sceneRun(target.substring(6), by, err);
  if (target == "hub:ack") { alarmAckAll(); return true; }
  if (target == "hub:enroll") { enrollmentOpen(120); return true; }
  return commandModule(target, valueJson, 0, by, err);
}

// ---------------------------------------------------------------- LEDs, switch ----------------
static bool fault = false;

static bool blink(uint32_t now, uint32_t onMs, uint32_t periodMs) { return (now % periodMs) < onMs; }

static void ledsLoop() {
  uint32_t now = millis();
  bool run = g_configMode ? true : (fault ? blink(now, 100, 200) : blink(now, 500, 1000));
  bool conn;
  if (cloudUp()) conn = true;                           // steady: connected to the server
  else if (S.cloudEnabled && anyLink()) conn = blink(now, 500, 1000);    // waiting for the server
  else if (anyLink()) conn = blink(now, 100, 2000);     // local network only (working, no server set)
  else conn = false;
  bool alm = alarmUnacked() ? blink(now, 250, 500) : alarmAny();
  digitalWrite(PIN_LED_RUN, run);
  digitalWrite(PIN_LED_CONNECT, conn);
  digitalWrite(PIN_LED_ALARM, alm);
}

static bool readConfigSwitch() {                        // majority of 5 samples
  int low = 0;
  for (int i = 0; i < 5; i++) { low += digitalRead(PIN_CONFIG_SW) == LOW; delay(5); }
  return low >= 3;
}

// Switch gestures while running: ON for 3 s = open enrollment (pairing); toggled 5 times in 15 s
// = back to the default passwords (lost admin password, like the Relay-8 module).
static void switchLoop() {
  static bool was = false;
  static uint32_t since = 0, firstEdge = 0;
  static int edges = 0;
  static bool done = false;
  bool on = digitalRead(PIN_CONFIG_SW) == LOW;
  uint32_t now = millis();
  if (on && !was) {
    since = now;
    done = false;
    if (!edges || now - firstEdge > 15000) { edges = 0; firstEdge = now; }
    if (++edges >= 5) {
      S.adminPass = ADMIN_PASS_DEFAULT;
      S.apPass = AP_PASS_DEFAULT;
      settingsSave();
      hlog(1, "passwords reset by the config switch");
      delay(200);
      ESP.restart();
    }
  }
  if (on && !done && now - since > 3000 && !g_configMode) { done = true; enrollmentOpen(120); }
  was = on;
}

// ---------------------------------------------------------------- status ----------------------
static const char *resetReason() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power-on";
    case ESP_RST_SW: return "software";
    case ESP_RST_PANIC: return "panic";
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return "watchdog";
    case ESP_RST_BROWNOUT: return "brownout";
    default: return "other";
  }
}

String hubStatusJson() {
  JsonDocument d;
  d["fw"] = FW_VERSION;
  d["uptime_s"] = millis() / 1000;
  d["heap"] = ESP.getFreeHeap();
  d["heap_min"] = ESP.getMinFreeHeap();
  d["reset"] = resetReason();
  d["config_mode"] = g_configMode;
  d["hub_id"] = S.hubId;
  d["addr"] = netAddr();
  d["cloud_enabled"] = S.cloudEnabled;
  d["cloud_up"] = cloudUp();
  d["eth_up"] = ethUp();
  d["wifi_up"] = wifiUp();
  d["gsm_enabled"] = S.gsmEnabled;
  d["gsm_up"] = gsmUp();
  d["gsm_csq"] = gsmSignal();
  d["gsm_operator"] = gsmOperator();
  d["clock_valid"] = clockValid();
  d["clock_source"] = clockSource();
  d["time"] = (long)nowUtc();
  d["utc_offset_min"] = S.utcOffsetMin;
  d["rtc"] = rtcPresent();
  d["rtc_lost"] = rtcLostPower();
  d["rtc_temp"] = rtcTempC();
  d["modules"] = modules.size();
  d["modules_online"] = modulesOnline();
  d["enroll_left"] = enrollmentLeft();
  d["config_switch"] = digitalRead(PIN_CONFIG_SW) == LOW;
  String out;
  serializeJson(d, out);
  return out;
}

// ---------------------------------------------------------------- setup, loop -----------------
static void healthLoop() {
  static uint32_t last = 0, lowSince = 0;
  uint32_t now = millis();
  if (now - last < 2000) return;
  last = now;
  if (ESP.getFreeHeap() < 20000) { if (!lowSince) lowSince = now; } else lowSince = 0;
  if (lowSince && now - lowSince > 30000) { hlog(0, "free memory low: restart"); delay(100); ESP.restart(); }
  fault = ESP.getFreeHeap() < 30000 || (!anyLink() && now > 60000);
  if (S.gsmEnabled && now > 180000 && !gsmUp()) alarmRaise("gsm_down", "GSM modem not registered", false);
  else alarmClear("gsm_down");
  if (now > 60000 && !anyLink()) alarmRaise("no_link", "No network link", false);
  else alarmClear("no_link");
  if (g_configMode && now > 600000) alarmRaise("config_on", "Config switch is still ON", false);
  else alarmClear("config_on");
  if (S.adminPass == ADMIN_PASS_DEFAULT) alarmRaise("default_pass", "Admin password is still the default", false);
  else alarmClear("default_pass");
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED_RUN, OUTPUT);
  pinMode(PIN_LED_CONNECT, OUTPUT);
  pinMode(PIN_LED_ALARM, OUTPUT);
  pinMode(PIN_CONFIG_SW, INPUT_PULLUP);
  digitalWrite(PIN_LED_RUN, HIGH);                      // lamp test while starting
  digitalWrite(PIN_LED_CONNECT, HIGH);
  digitalWrite(PIN_LED_ALARM, HIGH);
  bool first = !settingsLoad();
  registryLoad();
  hlog(2, "%s %s, reset: %s%s", PRODUCT_NAME, FW_VERSION, resetReason(), first ? " (first start)" : "");
  if (first) settingsSave();                            // keep the keys made on the first start
  g_configMode = readConfigSwitch() || first;           // a blank hub opens the portal by itself
  delay(300);
  digitalWrite(PIN_LED_CONNECT, LOW);
  digitalWrite(PIN_LED_ALARM, LOW);
  clockBegin();
  netBegin(g_configMode);
  scenesBegin();
  brokerBegin();
  localBegin();
  gsmBegin();
  portalBegin(g_configMode);
  esp_task_wdt_config_t wdt = {.timeout_ms = 20000, .idle_core_mask = 0, .trigger_panic = true};
  esp_task_wdt_reconfigure(&wdt);
  esp_task_wdt_add(nullptr);
}

void loop() {
  esp_task_wdt_reset();
  netLoop();
  clockLoop();
  brokerLoop();
  scenesLoop();
  localLoop();
  gsmLoop();
  portalLoop();
  switchLoop();
  healthLoop();
  ledsLoop();
  delay(2);
}
