// Local API for the phone app on the home network (port 8080, plain HTTP, signed requests).
// Works with the internet down: nothing here calls the server. Same scheme as the modules and
// hub/platform/local_sign.py, with the HUB's id and key:
//
//   GET  /local/v1/info     {"hub_id","firmware","local","modules","online","time_ok"}   (no key needed)
//   GET  /local/v1/nonce    {"hub_id","nonce","ttl_s":30}
//   POST /local/v1/state    {"nonce","sig"}                      -> hub, modules, scenes, alarms
//   POST /local/v1/command  {"nonce","tag","value_json","sig"}
//
// sig = base64url(HMAC-SHA256(key, hub_id \n nonce \n command \n tag \n value_json)); for state the
// message is hub_id \n nonce \n state. A nonce works once, for 30 s, 16 open at most.
// "tag" says what to do:
//   <module>:<tag>   switch a module's tag (module = id or short alias), value_json true/false/number
//   scene:<id>       run a scene                     hub:ack      acknowledge alarms
//   hub:enroll       open module enrollment 2 min    hub:time     set the clock (value_json = unix seconds)
//   scenes:put       replace all scenes (value_json = the scenes array)
//   modules:put      replace the module registry (value_json = [{id,secret,name,alias}])

#include <WebServer.h>
#include <ArduinoJson.h>
#include <esp_random.h>
#include "core.h"

static WebServer *srv = nullptr;
static String nonceValue[NONCE_MAX];
static uint32_t nonceMadeMs[NONCE_MAX];

static void pruneNonces() {
  for (int i = 0; i < NONCE_MAX; i++)
    if (nonceValue[i].length() && millis() - nonceMadeMs[i] >= NONCE_TTL_MS) nonceValue[i] = "";
}

static int openNonces() {
  int n = 0;
  for (auto &s : nonceValue) n += s.length() > 0;
  return n;
}

static String issueNonce() {
  pruneNonces();
  for (int i = 0; i < NONCE_MAX; i++) {
    if (nonceValue[i].length()) continue;
    uint8_t r[16];
    esp_fill_random(r, sizeof r);
    nonceValue[i] = b64urlEncode(r, sizeof r);
    nonceMadeMs[i] = millis();
    return nonceValue[i];
  }
  return "";
}

static bool redeemNonce(const String &n) {              // works once; used, expired, unknown -> false
  pruneNonces();
  if (!n.length()) return false;
  for (int i = 0; i < NONCE_MAX; i++)
    if (nonceValue[i] == n) { nonceValue[i] = ""; return true; }
  return false;
}

static bool verify(const String &sig, const String &nonce, const char *kind, const String &tag = "",
                   const String &valueJson = "") {
  uint8_t key[64], mac[32];
  size_t kl = b64urlDecode(S.localKey, key, sizeof key);
  if (!kl) return false;
  String msg = S.hubId + "\n" + nonce + "\n" + kind;
  if (!strcmp(kind, "command")) msg += "\n" + tag + "\n" + valueJson;
  hmacSha256(key, kl, (const uint8_t *)msg.c_str(), msg.length(), mac);
  return sameText(b64urlEncode(mac, sizeof mac), sig);
}

static void sendJson(int code, JsonDocument &d) {
  String out;
  serializeJson(d, out);
  srv->send(code, "application/json", out);
}

static void fail(int code, const char *msg) {
  JsonDocument d;
  d["ok"] = false;
  d["error"] = msg;
  sendJson(code, d);
}

static void onInfo() {
  JsonDocument d;
  d["hub_id"] = S.hubId;
  d["firmware"] = FW_VERSION;
  d["local"] = S.localEnabled;
  d["modules"] = modules.size();
  d["online"] = modulesOnline();
  d["time_ok"] = clockValid();
  sendJson(200, d);
}

static void onNonce() {
  if (!S.localEnabled) return fail(403, "local control is off");
  String n = issueNonce();
  if (!n.length()) return fail(429, "too many open nonces");
  JsonDocument d;
  d["hub_id"] = S.hubId;
  d["nonce"] = n;
  d["ttl_s"] = NONCE_TTL_MS / 1000;
  sendJson(200, d);
}

static void onState() {
  if (!S.localEnabled) return fail(403, "local control is off");
  JsonDocument body;
  if (srv->arg("plain").length() > 512 || deserializeJson(body, srv->arg("plain"))) return fail(400, "bad request");
  String nonce = body["nonce"] | "";
  if (!redeemNonce(nonce)) return fail(401, "nonce");
  if (!verify(body["sig"] | "", nonce, "state")) return fail(401, "signature");
  JsonDocument d;
  d["ok"] = true;
  d["hub"] = serialized(hubStatusJson());
  d["modules"] = serialized(modulesStateJson());
  d["scenes"] = serialized(scenesSummaryJson());
  d["alarms"] = serialized(alarmsJson());
  sendJson(200, d);
}

static void onCommand() {
  if (!S.localEnabled) return fail(403, "local control is off");
  if (srv->arg("plain").length() > SCENES_MAX_BYTES + 512) return fail(413, "too big");
  JsonDocument body;
  if (deserializeJson(body, srv->arg("plain"))) return fail(400, "bad request");
  String nonce = body["nonce"] | "", tag = body["tag"] | "", valueJson = body["value_json"] | "";
  if (!redeemNonce(nonce)) return fail(401, "nonce");
  if (!verify(body["sig"] | "", nonce, "command", tag, valueJson)) return fail(401, "signature");
  String err;
  bool ok;
  if (tag == "scenes:put") {
    ok = scenesPut(valueJson, err);
  } else if (tag == "modules:put") {
    err = registryApply(valueJson);
    ok = err.isEmpty() && registrySave();
  } else if (tag == "hub:time") {
    long long t = valueJson.toInt();
    ok = t > 1735689600LL;
    if (ok && (!clockValid() || llabs((long long)nowUtc() - t) > 2)) clockSet((time_t)t, "phone");
    if (!ok) err = "time";
  } else {
    ok = execTarget(tag, valueJson, "local", err);
  }
  JsonDocument d;
  d["ok"] = ok;
  if (!ok) d["error"] = err;
  sendJson(ok ? 200 : 400, d);
}

void localBegin() {
  srv = new WebServer(S.localPort);
  srv->on("/local/v1/info", HTTP_GET, onInfo);
  srv->on("/local/v1/nonce", HTTP_GET, onNonce);
  srv->on("/local/v1/state", HTTP_POST, onState);
  srv->on("/local/v1/command", HTTP_POST, onCommand);
  srv->onNotFound([]() { fail(404, "not found"); });
  srv->begin();
}

void localLoop() {
  srv->handleClient();
  pruneNonces();
}
