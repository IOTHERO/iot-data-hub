#pragma once
// Interfaces between the parts of the hub firmware. Light on purpose (no ArduinoJson here):
// JSON crosses part boundaries as text, so a part only includes the heavy libraries it uses.

#include <Arduino.h>
#include <vector>
#include <time.h>
#include "config.h"

// ------------------------------------------------------------------ settings --------------------
struct Contact {
  String number;           // +98912...
  String name;
  bool commands = true;    // may send signed SMS commands
  bool alarms = true;      // receives alarm SMS
};

struct Settings {
  String deviceName = PRODUCT_NAME;
  String hubId, hubSecret;                 // the hub's own identity on the server (h/<hubId>/...)
  String adminPass = ADMIN_PASS_DEFAULT;
  String apPass = AP_PASS_DEFAULT;
  uint8_t logLevel = 2;                    // 0 error, 1 warn, 2 info, 3 debug

  // network: netMode 0 = LAN first, 1 = Wi-Fi first, 2 = LAN only, 3 = Wi-Fi only
  uint8_t netMode = 0;
  bool ethDhcp = true;
  String ethIp, ethGw, ethMask = "255.255.255.0", ethDns;
  String wifiSsid, wifiPass, wifiSsid2, wifiPass2;
  String hostname = "titi-hub";
  String ntp = "pool.ntp.org";
  int16_t utcOffsetMin = DEFAULT_UTC_OFFSET_MIN;

  // server (cloud / OPC platform)
  bool cloudEnabled = false;
  String cloudHost;
  uint16_t cloudPort = 1883;
  String cloudPrefix;                      // topic prefix, as on the platform broker
  uint16_t cloudKeepalive = 30;
  uint16_t cloudLostAlarmS = CLOUD_LOST_ALARM_S;
  bool cloudTls = false;                   // TLS to the server (the certificate is always checked)
  String cloudCa;                          // private CA, PEM; empty = the built-in public CAs

  // modules (they connect to this hub as their MQTT server)
  uint16_t brokerPort = BROKER_PORT_DEFAULT;
  uint16_t moduleOfflineS = MODULE_OFFLINE_S_DEFAULT;

  // phone app on the home network
  bool localEnabled = true;
  uint16_t localPort = LOCAL_PORT_DEFAULT;
  String localKey;                         // base64url, 32 bytes; made on first start or sent by the server

  // GSM and SMS
  bool gsmEnabled = false;
  String apn, simPin;
  bool smsEnabled = false;
  String smsKey;                           // base64url, signs SMS commands
  std::vector<Contact> contacts;
};

extern Settings S;
bool settingsLoad();                                 // NVS; false = first start (defaults kept)
bool settingsSave();
void settingsFactory();                              // erase all (settings, registry, scenes)
String settingsJson(bool withSecrets);               // for the portal and for backup
String settingsApply(const String &json);            // validate + apply a (partial) change; "" = ok, else the bad field
String newKey();                                     // 32 random bytes, base64url
String nvsReadBlob(const char *key);                 // large JSON texts (registry, scenes)
bool nvsWriteBlob(const char *key, const String &value);

// ------------------------------------------------------------------ modules (registry) ----------
struct Value { String tag; double v = 0; };
struct Module {
  String id, secret, name, alias;          // alias: short name used in SMS ("m1")
  bool online = false;
  uint32_t lastSeenMs = 0;
  String addr, firmware;
  std::vector<Value> values;
  String lastCmdId, lastCmdStatus;         // the newest command and its ack
  bool alarmRaised = false;
};
extern std::vector<Module> modules;
bool registryLoad();
bool registrySave();
String registryJson(bool withSecrets);
String registryApply(const String &json);    // replace the registry from [{id,secret,name,alias}]
Module *findModule(const String &idOrAlias);
bool moduleValue(const Module &m, const String &tag, double &out);

// ------------------------------------------------------------------ alarms, log -----------------
struct Alarm { String code, text; time_t at = 0; bool acked = false; bool active = true; };
void alarmRaise(const char *code, const String &text, bool sms = true);
void alarmClear(const char *code);
void alarmAckAll();
bool alarmAny();                             // any active alarm
bool alarmUnacked();                         // any not yet acknowledged
String alarmsJson();
void hlog(uint8_t level, const char *fmt, ...);
String logTail(uint32_t &seq);               // lines newer than seq, newline separated

// ------------------------------------------------------------------ clock ------------------------
void clockBegin();                           // DS3231, then NTP when a link is up
void clockLoop();
bool clockValid();
time_t nowUtc();
time_t nowLocal();                           // UTC + utcOffsetMin
void clockSet(time_t utc, const char *source);   // sets system time and the RTC
bool rtcPresent();
bool rtcLostPower();
float rtcTempC();
String clockSource();

// ------------------------------------------------------------------ network ---------------------
void netBegin(bool configMode);
void netLoop();
bool ethUp();
bool wifiUp();
bool apOn();
bool anyLink();
String netAddr();                            // main IP address, "" when none
String netJson();
void netScanStart();                         // Wi-Fi scan in the background
String netScanJson();                        // {"busy":bool,"nets":[{ssid,rssi,open}]}

// ------------------------------------------------------------------ broker, server link ---------
void brokerBegin();
void brokerLoop();
bool cloudUp();
void enrollmentOpen(uint16_t seconds);
uint16_t enrollmentLeft();
// target: "<module id or alias>:<tag>"; value is JSON text (true, 1, 25.5); pulse_s 0 = none.
bool commandModule(const String &target, const String &valueJson, float pulseS, const char *by, String &err);
void cloudPublishHub(const char *kind, const String &payload);   // h/<hubId>/<kind>
void cloudEnvelope(const String &moduleId, const char *kind, const String &payload);
String modulesStateJson();                   // [{id,name,alias,online,age_s,addr,fw,values:{}}]
size_t modulesOnline();

// ------------------------------------------------------------------ scenes ------------------------
void scenesBegin();
void scenesLoop();
bool sceneRun(const String &id, const char *by, String &err);
String scenesJson();                         // the stored scenes (JSON array text)
String scenesSummaryJson();                  // [{id,name,enabled,running}]
bool scenesPut(const String &json, String &err);
void sceneNote(const String &id, const char *by);   // log entry for the server (sent when online)
// events for "event" triggers: cloud_lost, cloud_back, module_offline, module_online (device = module id)
void sceneEvent(const char *event, const String &device);

// ------------------------------------------------------------------ local API (phone) -------------
void localBegin();
void localLoop();
// shared by the local API and SMS: execute "<target>" with a value (command, "scene:<id>", "hub:ack").
bool execTarget(const String &target, const String &valueJson, const char *by, String &err);

// ------------------------------------------------------------------ GSM / SMS ---------------------
void gsmBegin();
void gsmLoop();
bool gsmUp();
int gsmSignal();                             // 0..31 from AT+CSQ, -1 unknown
String gsmOperator();
void smsSend(const String &to, const String &text);
void smsAlarm(const String &text);           // to every contact with alarms on (rate limited)
bool smsCommand(const String &from, const String &text, String &reply);   // parse + run a signed SMS

// ------------------------------------------------------------------ portal ------------------------
void portalBegin(bool configMode);
void portalLoop();

// ------------------------------------------------------------------ crypto helpers (hub.ino) ------
String b64urlEncode(const uint8_t *data, size_t len);
size_t b64urlDecode(const String &in, uint8_t *out, size_t outMax);
void hmacSha256(const uint8_t *key, size_t keyLen, const uint8_t *msg, size_t len, uint8_t out[32]);
bool sameText(const String &a, const String &b);     // constant time for equal lengths
String hubStatusJson();                      // the dashboard's numbers (uptime, heap, links, ...)
bool configMode();
extern bool g_configMode;
