// Settings and the module registry: NVS storage, JSON in and out, validation.
// Secrets (passwords, keys) are never sent to the portal: only a "...Set" flag. A backup file
// (withSecrets) carries them, so it must be kept private.

#include <Preferences.h>
#include <ArduinoJson.h>
#include <IPAddress.h>
#include <esp_random.h>
#include "core.h"

Settings S;
std::vector<Module> modules;

static Preferences prefs;
static const char *NS = "hub";

String newKey() {
  uint8_t r[32];
  esp_fill_random(r, sizeof r);
  return b64urlEncode(r, sizeof r);
}

// ---------------------------------------------------------------- helpers ---------------------
static bool validIp(const String &s) {
  IPAddress ip;
  return ip.fromString(s);
}

static bool validName(const String &s, size_t max) { return s.length() <= max; }

static bool validId(const String &s) {
  if (s.length() < 3 || s.length() > 32) return false;
  for (char c : s) if (!(isLowerCase(c) || isDigit(c) || c == '_' || c == '-')) return false;
  return true;
}

static bool validAlias(const String &s) {
  if (s.length() < 1 || s.length() > 8) return false;
  for (char c : s) if (!(isLowerCase(c) || isDigit(c))) return false;
  return true;
}

static bool validNumber(const String &s) {            // +989121234567 or 09121234567
  if (s.length() < 5 || s.length() > 16) return false;
  for (size_t i = 0; i < s.length(); i++)
    if (!(isDigit(s[i]) || (i == 0 && s[i] == '+'))) return false;
  return true;
}

// ---------------------------------------------------------------- settings JSON ---------------
String settingsJson(bool withSecrets) {
  JsonDocument d;
  d["deviceName"] = S.deviceName;
  JsonObject sys = d["system"].to<JsonObject>();
  sys["logLevel"] = S.logLevel;
  JsonObject id = d["id"].to<JsonObject>();
  id["hubId"] = S.hubId;
  JsonObject net = d["net"].to<JsonObject>();
  net["mode"] = S.netMode;
  net["ethDhcp"] = S.ethDhcp;
  net["ethIp"] = S.ethIp;
  net["ethGw"] = S.ethGw;
  net["ethMask"] = S.ethMask;
  net["ethDns"] = S.ethDns;
  net["wifiSsid"] = S.wifiSsid;
  net["wifiSsid2"] = S.wifiSsid2;
  net["hostname"] = S.hostname;
  net["ntp"] = S.ntp;
  net["utcOffsetMin"] = S.utcOffsetMin;
  JsonObject cl = d["cloud"].to<JsonObject>();
  cl["enabled"] = S.cloudEnabled;
  cl["host"] = S.cloudHost;
  cl["port"] = S.cloudPort;
  cl["prefix"] = S.cloudPrefix;
  cl["keepalive"] = S.cloudKeepalive;
  cl["lostAlarmS"] = S.cloudLostAlarmS;
  cl["tls"] = S.cloudTls;
  JsonObject mo = d["modules"].to<JsonObject>();
  mo["brokerPort"] = S.brokerPort;
  mo["offlineS"] = S.moduleOfflineS;
  JsonObject lo = d["local"].to<JsonObject>();
  lo["enabled"] = S.localEnabled;
  lo["port"] = S.localPort;
  JsonObject gs = d["gsm"].to<JsonObject>();
  gs["enabled"] = S.gsmEnabled;
  gs["apn"] = S.apn;
  gs["smsEnabled"] = S.smsEnabled;
  gs["smsLang"] = S.smsLang;
  JsonArray hol = d["holidays"].to<JsonArray>();
  for (auto &h : S.holidays) hol.add(h);
  JsonArray cs = gs["contacts"].to<JsonArray>();
  for (auto &c : S.contacts) {
    JsonObject o = cs.add<JsonObject>();
    o["number"] = c.number;
    o["name"] = c.name;
    o["commands"] = c.commands;
    o["alarms"] = c.alarms;
  }
  if (withSecrets) {
    sys["adminPass"] = S.adminPass;
    sys["apPass"] = S.apPass;
    id["hubSecret"] = S.hubSecret;
    cl["ca"] = S.cloudCa;
    net["wifiPass"] = S.wifiPass;
    net["wifiPass2"] = S.wifiPass2;
    lo["key"] = S.localKey;
    gs["simPin"] = S.simPin;
    gs["smsKey"] = S.smsKey;
  } else {
    sys["adminPassSet"] = S.adminPass.length() > 0;
    sys["adminPassDefault"] = S.adminPass == ADMIN_PASS_DEFAULT;
    sys["apPassSet"] = S.apPass.length() > 0;
    id["hubSecretSet"] = S.hubSecret.length() > 0;
    cl["caSet"] = S.cloudCa.length() > 0;
    net["wifiPassSet"] = S.wifiPass.length() > 0;
    net["wifiPass2Set"] = S.wifiPass2.length() > 0;
    lo["keySet"] = S.localKey.length() > 0;
    gs["simPinSet"] = S.simPin.length() > 0;
    gs["smsKeySet"] = S.smsKey.length() > 0;
  }
  String out;
  serializeJson(d, out);
  return out;
}

// Reads a string field only when present; returns false when absent.
static bool takeStr(JsonObjectConst o, const char *k, String &dst) {
  if (!o[k].is<const char *>()) return false;
  dst = o[k].as<String>();
  return true;
}

// Secret fields: empty means "keep"; the portal sends clearXxx = true to erase one.
static void takeSecret(JsonObjectConst o, const char *k, const char *clearK, String &dst) {
  String v;
  if (takeStr(o, k, v) && v.length()) dst = v;
  if (o[clearK] | false) dst = "";
}

String settingsApply(const String &json) {
  JsonDocument d;
  if (deserializeJson(d, json)) return "json";
  Settings n = S;                                       // work on a copy: all or nothing
  JsonObjectConst r = d.as<JsonObjectConst>();
  takeStr(r, "deviceName", n.deviceName);
  if (!validName(n.deviceName, 31) || !n.deviceName.length()) return "deviceName";

  JsonObjectConst sys = r["system"];
  if (!sys.isNull()) {
    if (sys["logLevel"].is<int>()) n.logLevel = constrain(sys["logLevel"].as<int>(), 0, 3);
    takeSecret(sys, "adminPass", "clearAdminPass", n.adminPass);
    takeSecret(sys, "apPass", "clearApPass", n.apPass);
    if (n.adminPass.length() < 4 || n.adminPass.length() > 32) return "system.adminPass";
    if (n.apPass.length() < 8 || n.apPass.length() > 63) return "system.apPass";
  }
  JsonObjectConst id = r["id"];
  if (!id.isNull()) {
    takeStr(id, "hubId", n.hubId);
    takeSecret(id, "hubSecret", "clearHubSecret", n.hubSecret);
    if (n.hubId.length() && !validId(n.hubId)) return "id.hubId";
    if (n.hubSecret.length() > 64) return "id.hubSecret";
  }
  JsonObjectConst net = r["net"];
  if (!net.isNull()) {
    if (net["mode"].is<int>()) n.netMode = constrain(net["mode"].as<int>(), 0, 3);
    if (net["ethDhcp"].is<bool>()) n.ethDhcp = net["ethDhcp"].as<bool>();
    takeStr(net, "ethIp", n.ethIp);
    takeStr(net, "ethGw", n.ethGw);
    takeStr(net, "ethMask", n.ethMask);
    takeStr(net, "ethDns", n.ethDns);
    if (!n.ethDhcp) {
      if (!validIp(n.ethIp)) return "net.ethIp";
      if (!validIp(n.ethMask)) return "net.ethMask";
      if (n.ethGw.length() && !validIp(n.ethGw)) return "net.ethGw";
    }
    if (n.ethDns.length() && !validIp(n.ethDns)) return "net.ethDns";
    takeStr(net, "wifiSsid", n.wifiSsid);
    takeStr(net, "wifiSsid2", n.wifiSsid2);
    takeSecret(net, "wifiPass", "clearWifiPass", n.wifiPass);
    takeSecret(net, "wifiPass2", "clearWifiPass2", n.wifiPass2);
    if (n.wifiSsid.length() > 32) return "net.wifiSsid";
    if (n.wifiSsid2.length() > 32) return "net.wifiSsid2";
    if (n.wifiPass.length() > 63) return "net.wifiPass";
    takeStr(net, "hostname", n.hostname);
    if (n.hostname.length() < 1 || n.hostname.length() > 23) return "net.hostname";
    takeStr(net, "ntp", n.ntp);
    if (n.ntp.length() > 39) return "net.ntp";
    if (net["utcOffsetMin"].is<int>()) n.utcOffsetMin = constrain(net["utcOffsetMin"].as<int>(), -720, 840);
  }
  JsonObjectConst cl = r["cloud"];
  if (!cl.isNull()) {
    if (cl["enabled"].is<bool>()) n.cloudEnabled = cl["enabled"].as<bool>();
    takeStr(cl, "host", n.cloudHost);
    takeStr(cl, "prefix", n.cloudPrefix);
    if (cl["port"].is<int>()) n.cloudPort = constrain(cl["port"].as<int>(), 1, 65535);
    if (cl["keepalive"].is<int>()) n.cloudKeepalive = constrain(cl["keepalive"].as<int>(), 5, 600);
    if (cl["lostAlarmS"].is<int>()) n.cloudLostAlarmS = constrain(cl["lostAlarmS"].as<int>(), 0, 86400);
    if (cl["tls"].is<bool>()) n.cloudTls = cl["tls"].as<bool>();
    String ca;
    if (takeStr(cl, "ca", ca) && ca.length()) {
      if (ca.length() > 3000 || ca.indexOf("BEGIN CERTIFICATE") < 0) return "cloud.ca";
      n.cloudCa = ca;
    }
    if (cl["clearCa"] | false) n.cloudCa = "";
    if (n.cloudHost.length() > 63) return "cloud.host";
    if (n.cloudPrefix.length() > 15) return "cloud.prefix";
    if (n.cloudEnabled && !n.cloudHost.length()) return "cloud.host";
    if (n.cloudEnabled && !n.hubId.length()) return "id.hubId";
  }
  JsonObjectConst mo = r["modules"];
  if (!mo.isNull()) {
    if (mo["brokerPort"].is<int>()) n.brokerPort = constrain(mo["brokerPort"].as<int>(), 1, 65535);
    if (mo["offlineS"].is<int>()) n.moduleOfflineS = constrain(mo["offlineS"].as<int>(), 20, 3600);
    if (n.brokerPort == PORTAL_PORT) return "modules.brokerPort";
  }
  JsonObjectConst lo = r["local"];
  if (!lo.isNull()) {
    if (lo["enabled"].is<bool>()) n.localEnabled = lo["enabled"].as<bool>();
    if (lo["port"].is<int>()) n.localPort = constrain(lo["port"].as<int>(), 1, 65535);
    String k;
    if (takeStr(lo, "key", k) && k.length()) {
      uint8_t buf[64];
      if (b64urlDecode(k, buf, sizeof buf) < 16) return "local.key";
      n.localKey = k;
    }
    if (lo["newKey"] | false) n.localKey = newKey();
    if (n.localPort == PORTAL_PORT || n.localPort == n.brokerPort) return "local.port";
  }
  JsonObjectConst gs = r["gsm"];
  if (!gs.isNull()) {
    if (gs["enabled"].is<bool>()) n.gsmEnabled = gs["enabled"].as<bool>();
    if (gs["smsEnabled"].is<bool>()) n.smsEnabled = gs["smsEnabled"].as<bool>();
    String lang;
    if (takeStr(gs, "smsLang", lang)) {
      if (lang != "en" && lang != "fa") return "gsm.smsLang";
      n.smsLang = lang;
    }
    takeStr(gs, "apn", n.apn);
    takeSecret(gs, "simPin", "clearSimPin", n.simPin);
    if (n.apn.length() > 31) return "gsm.apn";
    if (n.simPin.length() && (n.simPin.length() < 4 || n.simPin.length() > 8)) return "gsm.simPin";
    String k;
    if (takeStr(gs, "smsKey", k) && k.length()) {
      uint8_t buf[64];
      if (b64urlDecode(k, buf, sizeof buf) < 16) return "gsm.smsKey";
      n.smsKey = k;
    }
    if (gs["newKey"] | false) n.smsKey = newKey();
    if (gs["contacts"].is<JsonArrayConst>()) {
      n.contacts.clear();
      for (JsonObjectConst c : gs["contacts"].as<JsonArrayConst>()) {
        if (n.contacts.size() >= MAX_CONTACTS) return "gsm.contacts";
        Contact ct;
        ct.number = c["number"] | "";
        ct.name = c["name"] | "";
        ct.commands = c["commands"] | true;
        ct.alarms = c["alarms"] | true;
        if (!validNumber(ct.number) || ct.name.length() > 24) return "gsm.contacts";
        n.contacts.push_back(ct);
      }
    }
    if (n.smsEnabled && !n.smsKey.length()) n.smsKey = newKey();
  }
  if (r["holidays"].is<JsonArrayConst>()) {             // extra holidays: Jalali "YYYY/MM/DD"
    n.holidays.clear();
    for (JsonVariantConst v : r["holidays"].as<JsonArrayConst>()) {
      String h = v.as<String>();
      h.replace("-", "/");
      int y, m, dd;
      if (n.holidays.size() >= MAX_HOLIDAYS || h.length() != 10 || sscanf(h.c_str(), "%d/%d/%d", &y, &m, &dd) != 3 ||
          y < 1300 || y > 1500 || m < 1 || m > 12 || dd < 1 || dd > 31)
        return "holidays";
      n.holidays.push_back(h);
    }
  }
  S = n;
  return "";
}

// ---------------------------------------------------------------- NVS -------------------------
bool settingsLoad() {
  String j = nvsReadBlob("cfg");
  if (!j.length()) {
    S.localKey = newKey();                              // a first start gets its own phone key
    S.smsKey = newKey();
    return false;
  }
  String bad = settingsApply(j);
  if (bad.length()) hlog(0, "stored settings invalid at %s; defaults kept", bad.c_str());
  if (!S.localKey.length()) S.localKey = newKey();
  if (!S.smsKey.length()) S.smsKey = newKey();
  return bad.isEmpty();
}

bool settingsSave() { return nvsWriteBlob("cfg", settingsJson(true)); }

void settingsFactory() {
  prefs.begin(NS, false);
  prefs.clear();
  prefs.end();
}

// ---------------------------------------------------------------- registry --------------------
String registryJson(bool withSecrets) {
  JsonDocument d;
  JsonArray a = d.to<JsonArray>();
  for (auto &m : modules) {
    JsonObject o = a.add<JsonObject>();
    o["id"] = m.id;
    o["name"] = m.name;
    o["alias"] = m.alias;
    if (m.rtu) o["rtu"] = m.rtu;
    if (withSecrets) {
      if (m.secret.length()) o["secret"] = m.secret;
      if (m.secretHash.length()) o["secret_sha256"] = m.secretHash;
    } else {
      o["secretSet"] = m.secret.length() > 0 || m.secretHash.length() > 0;
    }
  }
  String out;
  serializeJson(d, out);
  return out;
}

String registryApply(const String &json, bool keepLocalRtu) {
  JsonDocument d;
  if (deserializeJson(d, json) || !d.is<JsonArray>()) return "json";
  std::vector<Module> next;
  for (JsonObjectConst o : d.as<JsonArrayConst>()) {
    if (next.size() >= MAX_MODULES) return "too many";
    Module m;
    m.id = o["id"] | "";
    m.name = o["name"] | "";
    m.alias = o["alias"] | "";
    int rtu = o["rtu"] | 0;
    if (rtu < 0 || rtu > 247) return "rtu";
    m.rtu = (uint8_t)rtu;
    String secret = o["secret"] | "";
    String hash = o["secret_sha256"] | "";
    hash.toLowerCase();
    if (hash.length() && hash.length() != 64) return "secret_sha256";
    if (!validId(m.id)) return "id";
    if (m.name.length() > 31) return "name";
    if (m.alias.length() && !validAlias(m.alias)) return "alias";
    for (auto &x : next)
      if (x.id == m.id || (m.alias.length() && x.alias == m.alias)) return "duplicate";
    Module *old = findModule(m.id);
    if (old && old->id == m.id) {                       // keep the live state of a known module
      Module keep = *old;
      keep.name = m.name;
      keep.alias = m.alias;
      if (o["rtu"].is<int>() || !keepLocalRtu) keep.rtu = m.rtu;     // the server does not know rtu
      if (secret.length()) { keep.secret = secret; keep.secretHash = ""; }
      else if (hash.length()) { keep.secretHash = hash; keep.secret = ""; }
      m = keep;
    } else {
      m.secret = secret;
      m.secretHash = secret.length() ? "" : hash;
    }
    // a bus module (rtu) needs no secret: it never signs in, the hub asks it
    if ((!m.secret.length() && !m.secretHash.length() && !m.rtu) || m.secret.length() > 64) return "secret";
    for (auto &x : next)
      if (m.rtu && x.rtu == m.rtu) return "rtu duplicate";
    next.push_back(m);
  }
  if (keepLocalRtu) {                                    // RS-485 modules the server does not list stay
    for (auto &old : modules) {
      if (!old.rtu) continue;
      bool listed = false;
      for (auto &x : next) listed |= x.id == old.id;
      if (!listed && next.size() < MAX_MODULES) next.push_back(old);
    }
  }
  modules = next;
  return "";
}

// Blobs (not strings): an NVS string is limited to about 4000 bytes, a blob is not.
String nvsReadBlob(const char *key) {
  prefs.begin(NS, true);
  size_t n = prefs.getBytesLength(key);
  String out;
  if (n && out.reserve(n)) {
    std::vector<char> buf(n + 1);
    prefs.getBytes(key, buf.data(), n);
    buf[n] = 0;
    out = String(buf.data());
  }
  prefs.end();
  return out;
}

bool nvsWriteBlob(const char *key, const String &value) {
  prefs.begin(NS, false);
  bool ok = prefs.putBytes(key, value.c_str(), value.length()) == value.length();
  prefs.end();
  return ok;
}

bool registryLoad() {
  String j = nvsReadBlob("mods");
  if (!j.length()) return false;
  return registryApply(j).isEmpty();
}

bool registrySave() { return nvsWriteBlob("mods", registryJson(true)); }

Module *findModule(const String &idOrAlias) {
  for (auto &m : modules)
    if (m.id == idOrAlias || (m.alias.length() && m.alias == idOrAlias)) return &m;
  return nullptr;
}

bool moduleValue(const Module &m, const String &tag, double &out) {
  for (auto &v : m.values)
    if (v.tag == tag) { out = v.v; return true; }
  return false;
}
