// Scenes: the hub's own scheduler and scenario engine. It runs here, on the hub, whether the
// internet is up or not: this is what keeps a building working when the server is gone.
// The phone (local API), the server (scenes message) and the portal edit the same list.
//
// scene = {"id","name","enabled","cooldown_s","trigger":{...},"conditions":[...],"actions":[...]}
// trigger: {"type":"time","at":"HH:MM","weekdays":[0..6]}          0 = Saturday
//          {"type":"interval","every_s":60}
//          {"type":"value","device":"m1","tag":"relay_1","op":"eq","value":true,"for_s":0}
//          {"type":"event","event":"cloud_lost|cloud_back|module_offline|module_online","device":"m1"}
//          {"type":"manual"}                                       run by the phone, SMS or portal
// calendar (optional, any trigger except manual; Jalali dates, local time):
//          {"months":[1..12],"month_days":[1..31],"from":"MM/DD|YYYY/MM/DD","to":"...","holidays":"skip|only"}
// condition: {"device","tag","op","value"}   (op: eq ne lt le gt ge)
// action: {"type":"write","device","tag","value","pulse_s"} | {"type":"delay","s"} |
//         {"type":"scene","id"} | {"type":"sms","text"} | {"type":"alarm","text"}

#include <ArduinoJson.h>
#include "core.h"

static String store = "[]";
static uint32_t lastEval = 0;

struct SceneState {
  String id;
  uint32_t lastRunMs = 0;
  bool everRun = false;
  bool valueTrue = false;
  uint32_t valueSince = 0;
  bool valueFired = false;
  int lastMinute = -1;
  uint32_t lastInterval = 0;
};
static std::vector<SceneState> states;

struct Run { String id, by; uint8_t depth; size_t next; uint32_t resumeAt; };
static std::vector<Run> runs;
static std::vector<std::pair<String, String>> events;
struct LogE { time_t at; String scene, by; };
static std::vector<LogE> sceneLog;

static const char *ops[] = {"eq", "ne", "lt", "le", "gt", "ge"};

static bool compareOp(double a, const char *op, double b) {
  if (!strcmp(op, "eq")) return a == b;
  if (!strcmp(op, "ne")) return a != b;
  if (!strcmp(op, "lt")) return a < b;
  if (!strcmp(op, "le")) return a <= b;
  if (!strcmp(op, "gt")) return a > b;
  if (!strcmp(op, "ge")) return a >= b;
  return false;
}

static bool numberOf(JsonVariantConst v, double &out) {
  if (v.is<bool>()) { out = v.as<bool>() ? 1 : 0; return true; }
  if (v.is<float>()) { out = v.as<double>(); return true; }
  return false;
}

static bool readValue(const String &device, const String &tag, double &out) {
  Module *m = findModule(device);
  return m && m->online && moduleValue(*m, tag, out);
}

static bool conditionHolds(JsonObjectConst c) {
  double have = 0, want = 0;
  return readValue(c["device"] | "", c["tag"] | "", have) && numberOf(c["value"], want) &&
         compareOp(have, c["op"] | "", want);
}

static bool conditionsHold(JsonObjectConst scene) {
  for (JsonObjectConst c : scene["conditions"].as<JsonArrayConst>())
    if (!conditionHolds(c)) return false;
  return true;
}

// "MM/DD" (every year) or "YYYY/MM/DD" -> a sortable key; false when malformed.
static bool dateKey(const char *s, int &key, bool &yearly) {
  int a, b, c;
  if (strlen(s) == 10 && sscanf(s, "%d/%d/%d", &a, &b, &c) == 3 && b >= 1 && b <= 12 && c >= 1 && c <= 31) {
    key = a * 10000 + b * 100 + c;
    yearly = false;
    return true;
  }
  if (strlen(s) == 5 && sscanf(s, "%d/%d", &a, &b) == 2 && a >= 1 && a <= 12 && b >= 1 && b <= 31) {
    key = a * 100 + b;
    yearly = true;
    return true;
  }
  return false;
}

// The calendar gate: months, days of the month, a date range and holidays, all in the Jalali calendar.
static bool calendarOk(JsonObjectConst scene) {
  JsonObjectConst cal = scene["calendar"];
  if (cal.isNull()) return true;
  if (!clockValid()) return false;                      // a calendar rule never guesses the date
  time_t t = nowLocal();
  tm lt;
  gmtime_r(&t, &lt);
  int jy, jm, jd;
  toJalali(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday, jy, jm, jd);
  auto listed = [](JsonArrayConst a, int v) {
    if (a.isNull() || a.size() == 0) return true;
    for (JsonVariantConst x : a) if (x.as<int>() == v) return true;
    return false;
  };
  if (!listed(cal["months"], jm) || !listed(cal["month_days"], jd)) return false;
  int fromK = 0, toK = 0;
  bool fromY = false, toY = false, hasFrom = false, hasTo = false;
  if ((cal["from"] | "")[0]) hasFrom = dateKey(cal["from"], fromK, fromY);
  if ((cal["to"] | "")[0]) hasTo = dateKey(cal["to"], toK, toY);
  if (hasFrom || hasTo) {
    int key = (hasFrom ? fromY : toY) ? jm * 100 + jd : jy * 10000 + jm * 100 + jd;
    if (hasFrom && hasTo && fromY && toY && fromK > toK) {   // a range over the new year (e.g. Azar to Farvardin)
      if (!(key >= fromK || key <= toK)) return false;
    } else {
      if (hasFrom && key < fromK) return false;
      if (hasTo && key > toK) return false;
    }
  }
  String pol = cal["holidays"] | "";
  if (pol == "skip" && isHoliday(jy, jm, jd)) return false;
  if (pol == "only" && !isHoliday(jy, jm, jd)) return false;
  return true;
}

static SceneState &stateOf(const String &id) {
  for (auto &s : states) if (s.id == id) return s;
  states.push_back(SceneState());
  states.back().id = id;
  return states.back();
}

// ---------------------------------------------------------------- store -----------------------
static bool validId(const String &s) {
  if (!s.length() || s.length() > 16) return false;
  for (char c : s) if (!(isLowerCase(c) || isDigit(c) || c == '_')) return false;
  return true;
}

static bool validOp(const char *op) {
  for (auto o : ops) if (!strcmp(op, o)) return true;
  return false;
}

static bool validCondition(JsonObjectConst c) {
  return (c["device"] | "")[0] && (c["tag"] | "")[0] && validOp(c["op"] | "") &&
         (c["value"].is<bool>() || c["value"].is<float>());
}

bool scenesPut(const String &json, String &err) {
  if (json.length() > SCENES_MAX_BYTES) { err = "too big"; return false; }
  JsonDocument d;
  if (deserializeJson(d, json) || !d.is<JsonArray>()) { err = "json"; return false; }
  std::vector<String> seen;
  for (JsonObjectConst s : d.as<JsonArrayConst>()) {
    if (seen.size() >= MAX_SCENES) { err = "too many scenes"; return false; }
    String id = s["id"] | "";
    if (!validId(id)) { err = "id"; return false; }
    for (auto &x : seen) if (x == id) { err = "duplicate id"; return false; }
    seen.push_back(id);
    if (String(s["name"] | "").length() > 31) { err = "name"; return false; }
    JsonObjectConst tr = s["trigger"];
    String type = tr["type"] | "";
    if (type == "time") {
      String at = tr["at"] | "";
      if (at.length() != 5 || at[2] != ':') { err = "time"; return false; }
    } else if (type == "interval") {
      if (!(tr["every_s"].is<int>()) || tr["every_s"].as<int>() < 5) { err = "interval"; return false; }
    } else if (type == "value") {
      if (!validCondition(tr)) { err = "value trigger"; return false; }
    } else if (type == "event") {
      String ev = tr["event"] | "";
      if (ev != "cloud_lost" && ev != "cloud_back" && ev != "module_offline" && ev != "module_online") { err = "event"; return false; }
    } else if (type != "manual") {
      err = "trigger"; return false;
    }
    for (JsonObjectConst c : s["conditions"].as<JsonArrayConst>())
      if (!validCondition(c)) { err = "condition"; return false; }
    JsonObjectConst cal = s["calendar"];
    if (!cal.isNull()) {
      for (JsonVariantConst m : cal["months"].as<JsonArrayConst>())
        if (m.as<int>() < 1 || m.as<int>() > 12) { err = "calendar.months"; return false; }
      for (JsonVariantConst m : cal["month_days"].as<JsonArrayConst>())
        if (m.as<int>() < 1 || m.as<int>() > 31) { err = "calendar.month_days"; return false; }
      int k;
      bool y;
      if ((cal["from"] | "")[0] && !dateKey(cal["from"], k, y)) { err = "calendar.from"; return false; }
      if ((cal["to"] | "")[0] && !dateKey(cal["to"], k, y)) { err = "calendar.to"; return false; }
      String pol = cal["holidays"] | "";
      if (pol.length() && pol != "skip" && pol != "only") { err = "calendar.holidays"; return false; }
    }
    JsonArrayConst acts = s["actions"];
    if (acts.isNull() || acts.size() == 0 || acts.size() > 16) { err = "actions"; return false; }
    for (JsonObjectConst a : acts) {
      String at = a["type"] | "";
      if (at == "write") {
        if (!(a["device"] | "")[0] || !(a["tag"] | "")[0]) { err = "write"; return false; }
        if (!(a["value"].is<bool>() || a["value"].is<float>())) { err = "write value"; return false; }
      } else if (at == "delay") {
        if (!a["s"].is<int>() || a["s"].as<int>() < 1 || a["s"].as<int>() > 86400) { err = "delay"; return false; }
      } else if (at == "scene") {
        if (!validId(a["id"] | "")) { err = "scene id"; return false; }
      } else if (at != "sms" && at != "alarm") {
        err = "action"; return false;
      }
    }
  }
  String out;
  serializeJson(d, out);
  if (!nvsWriteBlob("scenes", out)) { err = "storage"; return false; }
  store = out;
  states.clear();
  runs.clear();
  return true;
}

String scenesJson() { return store; }

String scenesSummaryJson() {
  JsonDocument d, out;
  deserializeJson(d, store);
  JsonArray a = out.to<JsonArray>();
  for (JsonObjectConst s : d.as<JsonArrayConst>()) {
    JsonObject o = a.add<JsonObject>();
    o["id"] = s["id"];
    o["name"] = s["name"];
    o["enabled"] = s["enabled"] | true;
    o["trigger"] = s["trigger"]["type"];
    bool running = false;
    for (auto &r : runs) if (r.id == (s["id"] | "")) running = true;
    o["running"] = running;
  }
  String res;
  serializeJson(out, res);
  return res;
}

void scenesBegin() {
  String s = nvsReadBlob("scenes");
  if (s.length()) store = s;
}

// ---------------------------------------------------------------- running ---------------------
void sceneNote(const String &id, const char *by) {
  if (sceneLog.size() >= 24) sceneLog.erase(sceneLog.begin());
  sceneLog.push_back({nowUtc(), id, by});
}

static bool startRun(const String &id, const char *by, uint8_t depth, String &err) {
  if (depth > 3) { err = "depth"; return false; }
  if (runs.size() >= 8) { err = "busy"; return false; }
  JsonDocument d;
  deserializeJson(d, store);
  for (JsonObjectConst s : d.as<JsonArrayConst>()) {
    if (String(s["id"] | "") != id) continue;
    if (!(s["enabled"] | true) && strcmp(by, "portal") && strcmp(by, "local") && strcmp(by, "sms")) {
      err = "disabled"; return false;
    }
    SceneState &st = stateOf(id);
    uint32_t cool = (s["cooldown_s"] | 0) * 1000UL;
    if (cool && st.everRun && millis() - st.lastRunMs < cool) { err = "cooldown"; return false; }
    st.lastRunMs = millis();
    st.everRun = true;
    runs.push_back({id, by, depth, 0, 0});
    sceneNote(id, by);
    hlog(2, "scene %s started by %s", id.c_str(), by);
    return true;
  }
  err = "unknown scene";
  return false;
}

bool sceneRun(const String &id, const char *by, String &err) { return startRun(id, by, 0, err); }

void sceneEvent(const char *event, const String &device) { events.push_back({event, device}); }

// Carries out the next actions of one run; false = finished.
static bool stepRun(Run &r) {
  JsonDocument d;
  deserializeJson(d, store);
  JsonObjectConst scene;
  for (JsonObjectConst s : d.as<JsonArrayConst>()) if (String(s["id"] | "") == r.id) scene = s;
  if (scene.isNull()) return false;
  JsonArrayConst acts = scene["actions"];
  uint8_t budget = 8;
  while (r.next < acts.size() && budget--) {
    JsonObjectConst a = acts[r.next++];
    String type = a["type"] | "";
    String err;
    if (type == "write") {
      String v;
      serializeJson(a["value"], v);
      String target = String(a["device"] | "") + ":" + String(a["tag"] | "");
      if (!commandModule(target, v, a["pulse_s"] | 0.0f, "scene", err))
        hlog(1, "scene %s: %s failed (%s)", r.id.c_str(), target.c_str(), err.c_str());
    } else if (type == "delay") {
      r.resumeAt = millis() + (uint32_t)(a["s"] | 1) * 1000UL;
      return true;
    } else if (type == "scene") {
      startRun(a["id"] | "", "scene", r.depth + 1, err);
    } else if (type == "sms") {
      smsAlarm(String(a["text"] | "scene"));
    } else if (type == "alarm") {
      alarmRaise(("scene_" + r.id).c_str(), String(a["text"] | r.id), true);
    }
  }
  return r.next < acts.size();
}

// ---------------------------------------------------------------- loop ------------------------
static bool timeFires(JsonObjectConst tr, SceneState &st, const tm &lt) {
  if (!clockValid()) return false;
  char hhmm[6];
  snprintf(hhmm, sizeof hhmm, "%02d:%02d", lt.tm_hour, lt.tm_min);
  if (strcmp(hhmm, tr["at"] | "") != 0) return false;
  int minuteKey = lt.tm_yday * 1440 + lt.tm_hour * 60 + lt.tm_min;
  if (st.lastMinute == minuteKey) return false;         // once per matching minute
  JsonArrayConst days = tr["weekdays"];
  int weekday = (lt.tm_wday + 1) % 7;                   // C: Sunday = 0; hub: Saturday = 0
  bool dayOk = days.isNull() || days.size() == 0;
  for (JsonVariantConst x : days) if (x.as<int>() == weekday) dayOk = true;
  if (dayOk) st.lastMinute = minuteKey;
  return dayOk;
}

void scenesLoop() {
  uint32_t now = millis();
  // running scenes (delays)
  for (size_t i = 0; i < runs.size();) {
    if (now >= runs[i].resumeAt && !stepRun(runs[i])) runs.erase(runs.begin() + i);
    else i++;
  }
  if (cloudUp() && !sceneLog.empty()) {                 // tell the server what ran (also while it was away)
    JsonDocument d;
    JsonArray a = d["entries"].to<JsonArray>();
    for (auto &e : sceneLog) {
      JsonObject o = a.add<JsonObject>();
      o["at"] = (long)e.at;
      o["scene"] = e.scene;
      o["by"] = e.by;
    }
    String out;
    serializeJson(d, out);
    cloudPublishHub("scene_log", out);
    sceneLog.clear();
  }
  if (now - lastEval < 1000) return;
  lastEval = now;

  JsonDocument d;
  if (deserializeJson(d, store)) return;
  time_t t = nowLocal();
  tm lt;
  gmtime_r(&t, &lt);
  std::vector<std::pair<String, String>> ev;
  ev.swap(events);
  for (JsonObjectConst s : d.as<JsonArrayConst>()) {
    if (!(s["enabled"] | true)) continue;
    String id = s["id"] | "", err;
    JsonObjectConst tr = s["trigger"];
    String type = tr["type"] | "";
    SceneState &st = stateOf(id);
    bool fire = false;
    if (type == "time") fire = timeFires(tr, st, lt);
    else if (type == "interval") {
      uint32_t every = (tr["every_s"] | 60) * 1000UL;
      if (!st.lastInterval) st.lastInterval = now;
      if (now - st.lastInterval >= every) { st.lastInterval = now; fire = true; }
    } else if (type == "value") {
      bool on = conditionHolds(tr);
      if (on && !st.valueTrue) st.valueSince = now;
      st.valueTrue = on;
      if (!on) st.valueFired = false;
      if (on && !st.valueFired && now - st.valueSince >= (uint32_t)(tr["for_s"] | 0) * 1000UL) {
        st.valueFired = true;
        fire = true;
      }
    } else if (type == "event") {
      for (auto &e : ev)
        if (e.first == String(tr["event"] | "") &&
            (!(tr["device"] | "")[0] || findModule(tr["device"] | "") == findModule(e.second)))
          fire = true;
    }
    if (fire && conditionsHold(s) && calendarOk(s)) startRun(id, "trigger", 0, err);
  }
}
