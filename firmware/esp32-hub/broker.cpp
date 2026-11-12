// The hub's network core.
//  1. A small MQTT server for the modules (PicoMQTT). A module sets its "server" to this hub with
//     its device id and secret; topics are the platform's own (d/<id>/telemetry|state|ack|...).
//  2. The module list: online state, address, firmware, latest values, offline alarms.
//  3. The link to the server (OPC platform) as ONE device, h/<hubId>/...  (contract document):
//       hub -> server   h/<hubId>/state        retained {"state":"online|offline",...}
//                       h/<hubId>/up           {"d":"<module>","k":"telemetry|state|ack|pairing|local_log|ota_status","p":{...}}
//                       h/<hubId>/alarm        {"code","text","at","active"}
//                       h/<hubId>/scene_log    {"entries":[{"at","scene","by"}]}
//       server -> hub   h/<hubId>/down         {"type":"cmd|rules|config|ota","d":"<module>","p":{...}}   passed to the module
//                                              {"type":"registry","modules":[{id,secret,name,alias}]}
//                                              {"type":"scenes","scenes":[...]}   {"type":"scene_run","id"}
//                                              {"type":"hubconfig",...}  {"type":"time","server_time"}  {"type":"ack"}
// When the server is gone nothing here stops: modules keep talking to the hub.

#include <WiFiClientSecure.h>
#include <PicoMQTT.h>
#include <ArduinoJson.h>
#include "core.h"

// ---------------------------------------------------------------- the module server ------------
static uint32_t enrollUntil = 0;
static uint32_t cmdSeq = 0;

void enrollmentOpen(uint16_t seconds) {
  enrollUntil = millis() + (uint32_t)seconds * 1000UL;
  if (!enrollUntil) enrollUntil = 1;
  hlog(2, "enrollment open for %u s", seconds);
}

uint16_t enrollmentLeft() {
  if (!enrollUntil) return 0;
  int32_t left = (int32_t)(enrollUntil - millis());
  if (left <= 0) { enrollUntil = 0; return 0; }
  return (uint16_t)(left / 1000 + 1);
}

static bool idOk(const String &s) {
  if (s.length() < 3 || s.length() > 32) return false;
  for (char c : s) if (!(isLowerCase(c) || isDigit(c) || c == '_' || c == '-')) return false;
  return true;
}

class LocalBroker : public PicoMQTT::ServerLocalSubscribe {
 public:
  using ServerLocalSubscribe::ServerLocalSubscribe;

 protected:
  // The module signs in with username = device id, password = device secret.
  PicoMQTT::ConnectReturnCode auth(const char *clientId, const char *user, const char *pass) override {
    String id = user ? user : "", secret = pass ? pass : "";
    Module *m = nullptr;
    for (auto &x : modules) if (x.id == id) m = &x;
    if (m) {
      if (moduleSecretOk(*m, secret)) return PicoMQTT::CRC_ACCEPTED;
      hlog(1, "module %s: wrong secret", id.c_str());
      return PicoMQTT::CRC_BAD_USERNAME_OR_PASSWORD;
    }
    if (enrollmentLeft() && idOk(id) && secret.length() && modules.size() < MAX_MODULES) {
      Module n;                                         // enrollment window open: accept and remember it
      n.id = id;
      n.secret = secret;
      n.name = id;
      for (int i = 1; i <= 99 && n.alias.isEmpty(); i++) {
        String a = "m" + String(i);
        bool used = false;
        for (auto &x : modules) if (x.alias == a) used = true;
        if (!used) n.alias = a;
      }
      modules.push_back(n);
      registrySave();
      hlog(2, "module %s enrolled as %s", id.c_str(), n.alias.c_str());
      return PicoMQTT::CRC_ACCEPTED;
    }
    hlog(2, "unknown module %s refused", id.c_str());
    return PicoMQTT::CRC_NOT_AUTHORIZED;
  }
};

static LocalBroker *broker = nullptr;

// ---------------------------------------------------------------- server link -------------------
static WiFiClient plainNet;
static WiFiClientSecure tlsNet;
static PicoMQTT::Client *cloud = nullptr;
static String pfx;                                      // h/<hubId>/ with the topic prefix
static int cloudAttempt = 0;
static uint32_t cloudSessionStart = 0;
static uint32_t lostSince = 0;
static bool cloudWasUp = false, lostAlarmed = false;

// Attempt 0: random 0..10 s. Attempt k: 10 s * 2^(k-1), capped at 5 min, +-20 %.
static uint32_t reconnectDelayMs(int attempt) {
  if (attempt <= 0) return random(0, RECONNECT_FIRST_MAX_MS + 1);
  uint32_t base = RECONNECT_FIRST_MAX_MS << min(attempt - 1, 10);
  if (base > RECONNECT_CAP_MS) base = RECONNECT_CAP_MS;
  return base + (int32_t)(base * (int32_t)random(-20, 21) / 100);
}

bool cloudUp() { return cloud && cloud->connected(); }

void cloudPublishHub(const char *kind, const String &payload) {
  if (!cloudUp()) return;
  bool important = !strcmp(kind, "alarm") || !strcmp(kind, "ack");
  cloud->publish(pfx + kind, payload, important ? 1 : 0, false);
}

void cloudEnvelope(const String &moduleId, const char *kind, const String &payload) {
  if (!cloudUp()) return;
  String out = "{\"d\":\"" + moduleId + "\",\"k\":\"" + kind + "\",\"p\":" + (payload.length() ? payload : String("{}")) + "}";
  cloud->publish(pfx + "up", out, 0, false);
}

static String isoAfter(int seconds) {
  time_t t = nowUtc() + seconds;
  tm u;
  gmtime_r(&t, &u);
  char b[25];
  strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%SZ", &u);
  return String(b);
}

static void publishHubState() {
  JsonDocument d;
  d["state"] = "online";
  d["firmware"] = FW_VERSION;
  d["local_addr"] = netAddr();
  d["modules"] = modules.size();
  d["online"] = modulesOnline();
  d["time_ok"] = clockValid();
  String out;
  serializeJson(d, out);
  cloud->publish(pfx + "state", out, 1, true);
}

static void publishSnapshots() {                        // after (re)connecting: what the hub knows now
  for (auto &m : modules) {
    JsonDocument d;
    d["state"] = m.online ? "online" : "offline";
    d["firmware"] = m.firmware;
    d["local_addr"] = m.addr;
    String s;
    serializeJson(d, s);
    cloudEnvelope(m.id, "state", s);
    JsonDocument t;
    JsonObject v = t["values"].to<JsonObject>();
    for (auto &x : m.values) v[x.tag] = x.v;
    String ts;
    serializeJson(t, ts);
    cloudEnvelope(m.id, "telemetry", ts);
  }
}

static void toModule(const String &idOrAlias, const String &topic, const String &payload) {
  Module *m = findModule(idOrAlias);
  if (!m) { hlog(1, "server message for unknown module %s", idOrAlias.c_str()); return; }
  if (m->rtu) { rtuSend(*m, topic, payload); return; }        // on the RS-485 bus
  if (broker) broker->publish("d/" + m->id + "/" + topic, payload, 1, false);
}

static void applyHubConfig(JsonObjectConst c) {
  JsonDocument out;
  if (c["local"].is<JsonObjectConst>()) {
    JsonObject l = out["local"].to<JsonObject>();
    l["enabled"] = c["local"]["enabled"] | S.localEnabled;
    if ((c["local"]["key"] | "")[0]) l["key"] = c["local"]["key"];
    if (c["local"]["port"].is<int>()) l["port"] = c["local"]["port"];
  }
  if (c["sms"].is<JsonObjectConst>()) {
    JsonObject g = out["gsm"].to<JsonObject>();
    g["smsEnabled"] = c["sms"]["enabled"] | S.smsEnabled;
    if ((c["sms"]["key"] | "")[0]) g["smsKey"] = c["sms"]["key"];
    if (c["contacts"].is<JsonArrayConst>()) g["contacts"] = c["contacts"];
    if ((c["sms"]["lang"] | "")[0]) g["smsLang"] = c["sms"]["lang"];
  }
  if (c["holidays"].is<JsonArrayConst>()) out["holidays"] = c["holidays"];
  if (c["utc_offset_min"].is<int>()) out["net"]["utcOffsetMin"] = c["utc_offset_min"];
  String j;
  serializeJson(out, j);
  String bad = settingsApply(j);
  if (bad.length()) hlog(1, "hubconfig from server refused at %s", bad.c_str());
  else settingsSave();
}

static long long isoEpoch(const char *s) {
  int y, mo, d, h, mi, se;
  if (sscanf(s, "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &se) != 6) return 0;
  y -= mo <= 2;
  long long era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400;
  long long doy = (153 * (mo > 2 ? mo - 3 : mo + 9) + 2) / 5 + d - 1;
  long long days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
  return days * 86400 + h * 3600 + mi * 60 + se;
}

static void onDown(char *payload) {
  JsonDocument d;
  if (deserializeJson(d, payload)) return;
  String type = d["type"] | "";
  String dev = d["d"] | "";
  String p;
  if (!d["p"].isNull()) serializeJson(d["p"], p);
  if (type == "cmd" || type == "rules" || type == "config" || type == "ota") {
    toModule(dev, type, p);
  } else if (type == "registry") {
    String m;
    serializeJson(d["modules"], m);
    String bad = registryApply(m, true);
    if (bad.isEmpty()) registrySave();
    else hlog(1, "registry from server refused: %s", bad.c_str());
  } else if (type == "scenes") {
    String s, err;
    serializeJson(d["scenes"], s);
    if (!scenesPut(s, err)) hlog(1, "scenes from server refused: %s", err.c_str());
  } else if (type == "scene_run") {
    String err;
    sceneRun(d["id"] | "", "server", err);
  } else if (type == "hubconfig") {
    applyHubConfig(d.as<JsonObjectConst>());
  } else if (type == "time") {
    long long t = isoEpoch(d["server_time"] | "");
    if (t > 1735689600LL && (!clockValid() || llabs((long long)nowUtc() - t) > 5)) clockSet((time_t)t, "server");
  } else if (type == "ack") {
    alarmAckAll();
  }
}

static void onCloudConnected() {
  cloudSessionStart = millis();
  cloudWasUp = true;
  hlog(2, "server link up");
  publishHubState();
  publishSnapshots();
}

static void onCloudFailed() {                           // the contract's back-off: 0..10 s, then doubling
  cloudAttempt++;
  if (cloud) cloud->reconnect_interval_millis = reconnectDelayMs(cloudAttempt - 1);
}

static void onCloudDropped() {
  bool stable = millis() - cloudSessionStart >= RECONNECT_STABLE_MS;
  cloudAttempt = stable ? 0 : cloudAttempt + 1;
  if (cloud) cloud->reconnect_interval_millis = reconnectDelayMs(cloudAttempt ? cloudAttempt - 1 : 0);
  hlog(1, "server link down");
}

static void cloudBegin() {
  if (!S.cloudEnabled || !S.cloudHost.length() || !S.hubId.length()) return;
  pfx = S.cloudPrefix + "h/" + S.hubId + "/";
  if (S.cloudTls) {
    if (S.cloudCa.length()) tlsNet.setCACert(S.cloudCa.c_str());   // else: the built-in public CAs, never "insecure"
    cloud = new PicoMQTT::Client(tlsNet, S.cloudHost.c_str(), S.cloudPort, ("hub-" + S.hubId).c_str(),
                                 S.hubId.c_str(), S.hubSecret.c_str(), 5000, S.cloudKeepalive * 1000UL);
  } else {
    cloud = new PicoMQTT::Client(plainNet, S.cloudHost.c_str(), S.cloudPort, ("hub-" + S.hubId).c_str(),
                                 S.hubId.c_str(), S.hubSecret.c_str(), 5000, S.cloudKeepalive * 1000UL);
  }
  cloud->will.topic = pfx + "state";
  cloud->will.payload = "{\"state\":\"offline\"}";
  cloud->will.qos = 1;
  cloud->will.retain = true;
  cloud->connected_callback = onCloudConnected;
  cloud->disconnected_callback = onCloudDropped;
  cloud->connection_failure_callback = onCloudFailed;
  cloud->subscribe(pfx + "down", [](char *, char *payload) { onDown(payload); });
  cloud->reconnect_interval_millis = reconnectDelayMs(0);
  cloud->begin();
}

// ---------------------------------------------------------------- module messages ---------------
size_t modulesOnline() {
  size_t n = 0;
  for (auto &m : modules) n += m.online;
  return n;
}

static void setValue(Module &m, const String &tag, double v) {
  for (auto &x : m.values) if (x.tag == tag) { x.v = v; return; }
  if (m.values.size() < MAX_VALUES) m.values.push_back({tag, v});
}

// Time for a module that has no clock of its own (no NTP while the internet is down):
// config {"type":"time","server_time":"<iso utc>","utc_offset_min":N}. A module that does not
// know the type ignores it.
static void pushTime(Module &m) {
  if (!clockValid() || !broker) return;
  broker->publish("d/" + m.id + "/config",
                  "{\"type\":\"time\",\"server_time\":\"" + isoAfter(0) + "\",\"utc_offset_min\":" +
                      String(S.utcOffsetMin) + "}", 1, false);
}

static void markSeen(Module &m) {
  m.lastSeenMs = millis();
  if (!m.online) {
    m.online = true;
    pushTime(m);
    hlog(2, "module %s online", m.id.c_str());
    alarmClear(("module_" + m.id).c_str());
    sceneEvent("module_online", m.id);
  }
}

static void onModuleMessage(char *topic, char *payload) {
  // topic: d/<id>/<kind>[/<sub>] (modules use an empty topic prefix on the hub)
  if (strncmp(topic, "d/", 2)) return;
  char *slash = strchr(topic + 2, '/');
  if (!slash) return;
  String id(String(topic + 2).substring(0, slash - (topic + 2)));
  String kind = slash + 1;
  if (kind == "cmd" || kind == "rules" || kind == "config" || kind == "ota") return;   // our own traffic
  Module *m = nullptr;
  for (auto &x : modules) if (x.id == id) m = &x;
  if (!m) return;

  JsonDocument d;
  bool parsed = !deserializeJson(d, payload);
  bool offlineMsg = false;
  if (kind == "state" && parsed) {
    String st = d["state"] | "";
    if (st == "offline") offlineMsg = true;
    else {
      m->addr = d["local_addr"] | m->addr;
      m->firmware = d["firmware"] | m->firmware;
    }
  } else if (kind == "telemetry" && parsed) {
    for (JsonPairConst kv : d["values"].as<JsonObjectConst>()) {
      if (kv.value().is<bool>()) setValue(*m, kv.key().c_str(), kv.value().as<bool>() ? 1 : 0);
      else if (kv.value().is<float>()) setValue(*m, kv.key().c_str(), kv.value().as<double>());
    }
  } else if (kind == "ack" && parsed) {
    if (String(d["command_id"] | "") == m->lastCmdId) m->lastCmdStatus = d["status"] | "";
  }
  if (offlineMsg) {
    if (m->online) {
      m->online = false;
      alarmRaise(("module_" + m->id).c_str(), "Module offline: " + (m->alias.length() ? m->alias : m->id));
      sceneEvent("module_offline", m->id);
    }
  } else {
    markSeen(*m);
  }
  cloudEnvelope(id, kind == "ota/status" ? "ota_status" : kind.c_str(), String(payload));
}

void moduleMessage(const String &id, const char *kind, const String &payload) {
  String topic = "d/" + id + "/" + kind;
  std::vector<char> t(topic.c_str(), topic.c_str() + topic.length() + 1);
  std::vector<char> p(payload.c_str(), payload.c_str() + payload.length() + 1);
  onModuleMessage(t.data(), p.data());
}

bool commandModule(const String &target, const String &valueJson, float pulseS, const char *by, String &err) {
  int colon = target.indexOf(':');
  if (colon <= 0) { err = "target"; return false; }
  Module *m = findModule(target.substring(0, colon));
  String tag = target.substring(colon + 1);
  if (!m) { err = "unknown module"; return false; }
  if (!m->online) { err = "offline"; return false; }
  JsonDocument v;
  if (deserializeJson(v, valueJson) || !(v.is<bool>() || v.is<float>())) { err = "value"; return false; }
  JsonDocument d;
  String cid = "h" + String(++cmdSeq);
  d["command_id"] = cid;
  d["tag"] = tag;
  d["value"] = v.as<JsonVariantConst>();
  if (pulseS > 0) d["pulse_s"] = pulseS;
  if (clockValid()) d["expires_at"] = isoAfter(CMD_EXPIRE_S);
  String out;
  serializeJson(d, out);
  m->lastCmdId = cid;
  m->lastCmdStatus = "sent";
  if (m->rtu) {                                         // on the RS-485 bus
    if (!rtuSend(*m, "cmd", out)) { err = "bus"; return false; }
    hlog(2, "%s -> %s (rtu %u) %s=%s", by, m->id.c_str(), m->rtu, tag.c_str(), valueJson.c_str());
    return true;
  }
  if (!broker) { err = "no broker"; return false; }
  broker->publish("d/" + m->id + "/cmd", out, 1, false);
  hlog(2, "%s -> %s %s=%s", by, m->id.c_str(), tag.c_str(), valueJson.c_str());
  return true;
}

String modulesStateJson() {
  JsonDocument d;
  JsonArray a = d.to<JsonArray>();
  uint32_t now = millis();
  for (auto &m : modules) {
    JsonObject o = a.add<JsonObject>();
    o["id"] = m.id;
    o["name"] = m.name;
    o["alias"] = m.alias;
    o["secretSet"] = m.secret.length() > 0 || m.secretHash.length() > 0;
    if (m.rtu) o["rtu"] = m.rtu;
    o["online"] = m.online;
    o["age_s"] = m.lastSeenMs ? (long)((now - m.lastSeenMs) / 1000) : -1;
    o["addr"] = m.addr;
    o["fw"] = m.firmware;
    o["cmd"] = m.lastCmdStatus;
    JsonObject v = o["values"].to<JsonObject>();
    for (auto &x : m.values) {
      if (x.tag.startsWith("relay_") || x.tag.startsWith("in_")) v[x.tag] = x.v != 0;
      else v[x.tag] = x.v;
    }
  }
  String out;
  serializeJson(d, out);
  return out;
}

// ---------------------------------------------------------------- begin, loop ------------------
void brokerBegin() {
  broker = new LocalBroker(S.brokerPort);
  broker->subscribe("d/#", onModuleMessage);
  broker->begin();
  cloudBegin();
}

void brokerLoop() {
  broker->loop();
  if (cloud) cloud->loop();
  static uint32_t last = 0;
  uint32_t now = millis();
  if (now - last < 1000) return;
  last = now;
  static uint32_t lastPush = 0;
  if (now - lastPush > 6UL * 3600UL * 1000UL) {          // keep module clocks right
    lastPush = now;
    for (auto &m : modules) if (m.online) pushTime(m);
  }
  for (auto &m : modules) {                             // a silent module is offline
    if (m.online && now - m.lastSeenMs > (uint32_t)S.moduleOfflineS * 1000UL) {
      m.online = false;
      alarmRaise(("module_" + m.id).c_str(), "Module offline: " + (m.alias.length() ? m.alias : m.id));
      sceneEvent("module_offline", m.id);
    }
  }
  if (S.cloudEnabled && S.cloudLostAlarmS) {            // the server is gone: say so, keep working
    if (cloudUp()) {
      lostSince = 0;
      if (lostAlarmed) { lostAlarmed = false; alarmClear("cloud_lost"); sceneEvent("cloud_back", ""); }
    } else if (anyLink() || cloudWasUp) {
      if (!lostSince) lostSince = now;
      if (!lostAlarmed && now - lostSince > (uint32_t)S.cloudLostAlarmS * 1000UL) {
        lostAlarmed = true;
        alarmRaise("cloud_lost", "Server link lost (hub keeps working locally)");
        sceneEvent("cloud_lost", "");
      }
    }
  }
}
