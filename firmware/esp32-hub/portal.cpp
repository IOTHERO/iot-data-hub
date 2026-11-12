// The hub's web portal (port 80): settings, modules, scenes, alarms, clock, backup, updates.
// The pages are files on LittleFS (data/), separate from the firmware: they can be updated alone.
// Every /api call except login needs the session token (header X-Auth). Wrong passwords lock the
// login for a minute. In config mode (switch ON at power-up) the hub also opens its own Wi-Fi.

#include <WebServer.h>
#include <DNSServer.h>
#include <LittleFS.h>
#include <Update.h>
#include <ArduinoJson.h>
#include <esp_random.h>
#include "core.h"

static WebServer srv(PORTAL_PORT);
static DNSServer dns;
static bool cfgMode = false;
static bool fsOk = false;
static uint32_t restartAt = 0;

struct Token { String value; uint32_t expires = 0; };
static Token tokens[4];
static uint8_t tokenNext = 0;
static uint8_t failures = 0;
static uint32_t lockedUntil = 0;
static bool otaOk = false;
static String otaErr;

// ---------------------------------------------------------------- auth ------------------------
static String newToken() {
  uint8_t r[16];
  esp_fill_random(r, sizeof r);
  String t = b64urlEncode(r, sizeof r);
  tokens[tokenNext] = {t, millis() + 2UL * 3600UL * 1000UL};
  tokenNext = (tokenNext + 1) % 4;
  return t;
}

static bool authed() {
  String t = srv.header("X-Auth");
  if (!t.length()) return false;
  for (auto &k : tokens)
    if (k.value.length() && sameText(k.value, t) && (int32_t)(k.expires - millis()) > 0) return true;
  return false;
}

static bool needAuth() {
  if (authed()) return true;
  srv.send(401, "application/json", "{\"error\":\"auth\"}");
  return false;
}

static void sendJsonText(int code, const String &s) { srv.send(code, "application/json", s); }
static void ok() { sendJsonText(200, "{\"ok\":true}"); }
static void bad(const char *field) {
  JsonDocument d;
  d["ok"] = false;
  d["error"] = "invalid";
  d["field"] = field;
  String o;
  serializeJson(d, o);
  sendJsonText(400, o);
}

static bool body(JsonDocument &d) {
  return !deserializeJson(d, srv.arg("plain"));
}

static void onLogin() {
  if ((int32_t)(lockedUntil - millis()) > 0) return sendJsonText(429, "{\"error\":\"locked\"}");
  JsonDocument d;
  if (!body(d)) return sendJsonText(400, "{\"error\":\"json\"}");
  if (sameText(String(d["password"] | ""), S.adminPass)) {
    failures = 0;
    JsonDocument r;
    r["token"] = newToken();
    String o;
    serializeJson(r, o);
    return sendJsonText(200, o);
  }
  if (++failures >= 5) { lockedUntil = millis() + 60000; failures = 0; }
  sendJsonText(401, "{\"error\":\"wrong\"}");
}

// ---------------------------------------------------------------- API -------------------------
static void onState() {
  if (!needAuth()) return;
  JsonDocument d;
  d["hub"] = serialized(hubStatusJson());
  d["net"] = serialized(netJson());
  d["modules"] = serialized(modulesStateJson());
  d["scenes"] = serialized(scenesSummaryJson());
  d["alarms"] = serialized(alarmsJson());
  String o;
  serializeJson(d, o);
  sendJsonText(200, o);
}

static void onSettingsGet() {
  if (!needAuth()) return;
  sendJsonText(200, settingsJson(false));
}

static void onSettingsPost() {
  if (!needAuth()) return;
  String bad_ = settingsApply(srv.arg("plain"));
  if (bad_.length()) return bad(bad_.c_str());
  settingsSave();
  ok();
}

static void onModulesPost() {
  if (!needAuth()) return;
  String err = registryApply(srv.arg("plain"));
  if (err.length()) return bad(err.c_str());
  registrySave();
  ok();
}

static void onCommand() {
  if (!needAuth()) return;
  JsonDocument d;
  if (!body(d)) return bad("json");
  String err, target = d["target"] | "", v;
  serializeJson(d["value"], v);
  bool done;
  if (target.startsWith("scene:") || target.startsWith("hub:")) done = execTarget(target, v, "portal", err);
  else done = commandModule(target, v, d["pulse_s"] | 0.0f, "portal", err);
  JsonDocument r;
  r["ok"] = done;
  if (!done) r["error"] = err;
  String o;
  serializeJson(r, o);
  sendJsonText(done ? 200 : 400, o);
}

// The phone key and the SMS key, for pairing the admin app. Admin login only; never in a backup view.
static void onKeys() {
  if (!needAuth()) return;
  JsonDocument d;
  d["hub_id"] = S.hubId;
  d["local"] = S.localKey;
  d["sms"] = S.smsKey;
  String o;
  serializeJson(d, o);
  sendJsonText(200, o);
}

static void onScenesGet() { if (needAuth()) sendJsonText(200, scenesJson()); }

static void onScenesPost() {
  if (!needAuth()) return;
  String err;
  if (!scenesPut(srv.arg("plain"), err)) return bad(err.c_str());
  ok();
}

static void onSceneRun() {
  if (!needAuth()) return;
  JsonDocument d;
  if (!body(d)) return bad("json");
  String err;
  if (!sceneRun(d["id"] | "", "portal", err)) return bad(err.c_str());
  ok();
}

static void onTime() {
  if (!needAuth()) return;
  JsonDocument d;
  if (!body(d) || !d["utc"].is<long long>() || d["utc"].as<long long>() < 1735689600LL) return bad("utc");
  clockSet((time_t)d["utc"].as<long long>(), "portal");
  ok();
}

static void onWifiScan() {
  if (!needAuth()) return;
  if (srv.method() == HTTP_POST) { netScanStart(); return ok(); }
  sendJsonText(200, netScanJson());
}

static void onLog() {
  if (!needAuth()) return;
  uint32_t seq = srv.arg("seq").toInt();
  String lines = logTail(seq);
  JsonDocument d;
  d["seq"] = seq;
  d["lines"] = lines;
  String o;
  serializeJson(d, o);
  sendJsonText(200, o);
}

static void onBackup() {
  if (!needAuth()) return;
  JsonDocument d;
  d["settings"] = serialized(settingsJson(true));
  d["modules"] = serialized(registryJson(true));
  d["scenes"] = serialized(scenesJson());
  String o;
  serializeJson(d, o);
  srv.sendHeader("Content-Disposition", "attachment; filename=titi-hub-backup.json");
  sendJsonText(200, o);
}

static void onRestore() {
  if (!needAuth()) return;
  JsonDocument d;
  if (!body(d)) return bad("json");
  String s, m, sc;
  if (!d["settings"].isNull()) serializeJson(d["settings"], s);
  if (!d["modules"].isNull()) serializeJson(d["modules"], m);
  if (!d["scenes"].isNull()) serializeJson(d["scenes"], sc);
  String e;
  if (s.length() && (e = settingsApply(s)).length()) return bad(("settings." + e).c_str());
  if (m.length() && (e = registryApply(m)).length()) return bad(("modules." + e).c_str());
  String err;
  if (sc.length() && !scenesPut(sc, err)) return bad(("scenes." + err).c_str());
  settingsSave();
  registrySave();
  ok();
}

static void onRestart() {
  if (!needAuth()) return;
  ok();
  restartAt = millis() + 600;
}

static void onFactory() {
  if (!needAuth()) return;
  JsonDocument d;
  if (!body(d) || String(d["confirm"] | "") != "RESET") return bad("confirm");
  settingsFactory();
  ok();
  restartAt = millis() + 600;
}

// ---------------------------------------------------------------- OTA -------------------------
static void otaDone() {
  JsonDocument d;
  d["ok"] = otaOk;
  if (!otaOk) d["error"] = otaErr.length() ? otaErr : "failed";
  String o;
  serializeJson(d, o);
  sendJsonText(otaOk ? 200 : 400, o);
  if (otaOk) restartAt = millis() + 800;
}

static void otaUpload() {
  HTTPUpload &u = srv.upload();
  if (u.status == UPLOAD_FILE_START) {
    otaOk = false;
    otaErr = "";
    if (!authed()) { otaErr = "auth"; return; }
    bool fs = srv.arg("fs") == "1";
    if (!Update.begin(UPDATE_SIZE_UNKNOWN, fs ? U_SPIFFS : U_FLASH)) otaErr = Update.errorString();
  } else if (u.status == UPLOAD_FILE_WRITE) {
    if (!otaErr.length() && Update.write(u.buf, u.currentSize) != u.currentSize) otaErr = Update.errorString();
  } else if (u.status == UPLOAD_FILE_END) {
    if (!otaErr.length()) {
      if (Update.end(true)) otaOk = true;
      else otaErr = Update.errorString();
    }
  } else if (u.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
  }
}

// ---------------------------------------------------------------- static files ----------------
static const char *mime(const String &p) {
  if (p.endsWith(".html")) return "text/html; charset=utf-8";
  if (p.endsWith(".js")) return "application/javascript; charset=utf-8";
  if (p.endsWith(".css")) return "text/css; charset=utf-8";
  if (p.endsWith(".woff2")) return "font/woff2";
  if (p.endsWith(".svg")) return "image/svg+xml";
  return "application/octet-stream";
}

static bool serveFile(String path) {
  if (path == "/") path = "/index.html";
  if (path.indexOf("..") >= 0) return false;
  bool gz = LittleFS.exists(path + ".gz");
  if (!gz && !LittleFS.exists(path)) return false;
  File f = LittleFS.open(gz ? path + ".gz" : path, "r");
  if (!f) return false;
  if (gz) srv.sendHeader("Content-Encoding", "gzip");
  srv.sendHeader("Cache-Control", path.startsWith("/static/") ? "max-age=86400" : "no-cache");
  srv.streamFile(f, mime(path));
  f.close();
  return true;
}

static void fallbackPage() {            // no web UI on flash yet: a page that can install it
  srv.send(200, "text/html; charset=utf-8",
           "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'>"
           "<title>TiTi Hub</title><body style='font-family:Arial;background:#0a0c11;color:#eee;padding:24px'>"
           "<h2>TiTi Hub</h2><p>Web UI image (LittleFS) is not installed. Upload littlefs.bin below "
           "(POST /api/ota?fs=1 with the X-Auth token), or flash it with the release scripts.</p>");
}

void portalBegin(bool configMode) {
  cfgMode = configMode;
  fsOk = LittleFS.begin(true);
  if (!fsOk) hlog(0, "LittleFS failed");
  const char *keys[] = {"X-Auth"};
  srv.collectHeaders(keys, 1);
  srv.on("/api/login", HTTP_POST, onLogin);
  srv.on("/api/state", HTTP_GET, onState);
  srv.on("/api/settings", HTTP_GET, onSettingsGet);
  srv.on("/api/settings", HTTP_POST, onSettingsPost);
  srv.on("/api/modules", HTTP_POST, onModulesPost);
  srv.on("/api/command", HTTP_POST, onCommand);
  srv.on("/api/keys", HTTP_GET, onKeys);
  srv.on("/api/scenes", HTTP_GET, onScenesGet);
  srv.on("/api/scenes", HTTP_POST, onScenesPost);
  srv.on("/api/scene/run", HTTP_POST, onSceneRun);
  srv.on("/api/alarms/ack", HTTP_POST, []() { if (needAuth()) { alarmAckAll(); ok(); } });
  srv.on("/api/enroll", HTTP_POST, []() { if (needAuth()) { enrollmentOpen(120); ok(); } });
  srv.on("/api/time", HTTP_POST, onTime);
  srv.on("/api/wifi/scan", HTTP_ANY, onWifiScan);
  srv.on("/api/log", HTTP_GET, onLog);
  srv.on("/api/backup", HTTP_GET, onBackup);
  srv.on("/api/restore", HTTP_POST, onRestore);
  srv.on("/api/restart", HTTP_POST, onRestart);
  srv.on("/api/factory", HTTP_POST, onFactory);
  srv.on("/api/ota", HTTP_POST, otaDone, otaUpload);
  srv.onNotFound([]() {
    String p = srv.uri();
    if (srv.method() == HTTP_GET && serveFile(p)) return;
    if (srv.method() == HTTP_GET && p == "/") return fallbackPage();
    if (cfgMode && srv.method() == HTTP_GET && !p.startsWith("/api/")) {   // captive portal: any name opens the page
      srv.sendHeader("Location", String("http://") + IPAddress(AP_IP).toString() + "/");
      return srv.send(302, "text/plain", "");
    }
    srv.send(404, "application/json", "{\"error\":\"not found\"}");
  });
  srv.begin();
  if (cfgMode) dns.start(53, "*", IPAddress(AP_IP));
}

void portalLoop() {
  if (cfgMode) dns.processNextRequest();
  srv.handleClient();
  if (restartAt && (int32_t)(millis() - restartAt) >= 0) {
    hlog(2, "restarting");
    delay(50);
    ESP.restart();
  }
}
