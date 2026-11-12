// Network: W5500 LAN + Wi-Fi station (+ the config access point), the host name and mDNS.
// The hub keeps working on a local network with no internet: nothing here needs the cloud.
// netMode: 0 LAN first (Wi-Fi as backup), 1 Wi-Fi first, 2 LAN only, 3 Wi-Fi only.

#include <WiFi.h>
#include <ETH.h>
#include <ESPmDNS.h>
#include <ArduinoJson.h>
#include "core.h"

static bool ethLink = false, ethIp = false;
static bool mdnsOn = false;
static bool cfgMode = false;
static uint32_t wifiLostAt = 0;
static bool wifiUseBackup = false;
static uint32_t lastWifiTry = 0;
static bool ethStarted = false, wifiStarted = false;

static bool wantEth() { return S.netMode != 3; }
static bool wantWifi() { return S.netMode != 2 && S.wifiSsid.length(); }

static void onEvent(arduino_event_id_t event, arduino_event_info_t) {
  switch (event) {
    case ARDUINO_EVENT_ETH_START: ETH.setHostname(S.hostname.c_str()); break;
    case ARDUINO_EVENT_ETH_CONNECTED: ethLink = true; hlog(2, "LAN link up"); break;
    case ARDUINO_EVENT_ETH_GOT_IP:
      ethIp = true;
      hlog(2, "LAN address %s", ETH.localIP().toString().c_str());
      if (S.netMode != 1) ETH.setDefault();
      break;
    case ARDUINO_EVENT_ETH_LOST_IP: ethIp = false; break;
    case ARDUINO_EVENT_ETH_DISCONNECTED: ethLink = false; ethIp = false; hlog(1, "LAN link down"); break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      hlog(2, "Wi-Fi address %s", WiFi.localIP().toString().c_str());
      wifiLostAt = 0;
      if (S.netMode == 1 || !ethIp) WiFi.STA.setDefault();
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      if (!wifiLostAt) wifiLostAt = millis();
      break;
    default: break;
  }
}

static void startEth() {
  if (ethStarted || !wantEth()) return;
  if (!S.ethDhcp) {
    IPAddress ip, gw, mask, dns;
    ip.fromString(S.ethIp);
    gw.fromString(S.ethGw);
    mask.fromString(S.ethMask);
    dns.fromString(S.ethDns.length() ? S.ethDns : S.ethGw);
    ETH.config(ip, gw, mask, dns);
  }
  pinMode(PIN_ETH_RST, OUTPUT);                         // a clean reset of the W5500
  digitalWrite(PIN_ETH_RST, LOW);
  delay(10);
  digitalWrite(PIN_ETH_RST, HIGH);
  delay(50);
  ethStarted = ETH.begin(ETH_PHY_W5500, 1, PIN_ETH_CS, PIN_ETH_INT, -1, SPI3_HOST, PIN_ETH_SCK,
                         PIN_ETH_MISO, PIN_ETH_MOSI);
  hlog(ethStarted ? 2 : 0, ethStarted ? "W5500 started" : "W5500 did not start");
}

static void startWifi() {
  if (wifiStarted) return;
  String ssid = wifiUseBackup && S.wifiSsid2.length() ? S.wifiSsid2 : S.wifiSsid;
  String pass = wifiUseBackup && S.wifiSsid2.length() ? S.wifiPass2 : S.wifiPass;
  if (!ssid.length()) return;
  WiFi.setHostname(S.hostname.c_str());
  WiFi.setAutoReconnect(true);
  WiFi.begin(ssid.c_str(), pass.c_str());
  wifiStarted = true;
  lastWifiTry = millis();
  hlog(2, "Wi-Fi connecting to %s", ssid.c_str());
}

void netBegin(bool configMode) {
  cfgMode = configMode;
  WiFi.onEvent(onEvent);
  WiFi.persistent(false);
  bool sta = wantWifi();
  if (configMode) {
    WiFi.mode(WIFI_AP_STA);                             // STA stays on so the portal can scan networks
    WiFi.softAPConfig(IPAddress(AP_IP), IPAddress(AP_IP), IPAddress(255, 255, 255, 0));
    uint8_t mac[6];
    WiFi.macAddress(mac);
    char ssid[32];
    snprintf(ssid, sizeof ssid, AP_SSID_PREFIX "%02X%02X", mac[4], mac[5]);
    WiFi.softAP(ssid, S.apPass.c_str());
    hlog(2, "config access point %s", ssid);
  } else {
    WiFi.mode(sta ? WIFI_STA : WIFI_OFF);
  }
  startEth();
  if (sta) startWifi();
}

static void startMdns() {
  if (mdnsOn || !anyLink()) return;
  if (!MDNS.begin(S.hostname.c_str())) return;
  MDNS.addService("http", "tcp", PORTAL_PORT);
  MDNS.addService("titihub", "tcp", S.localPort);       // the app finds the hub by this name
  if (S.hubId.length()) MDNS.addServiceTxt("titihub", "tcp", "id", S.hubId.c_str());
  MDNS.addServiceTxt("titihub", "tcp", "fw", FW_VERSION);
  mdnsOn = true;
}

void netLoop() {
  uint32_t now = millis();
  if (wantWifi() && wifiStarted && WiFi.status() != WL_CONNECTED && wifiLostAt &&
      now - wifiLostAt > 30000 && now - lastWifiTry > 30000 && S.wifiSsid2.length()) {
    wifiUseBackup = !wifiUseBackup;                     // try the other network
    wifiStarted = false;
    WiFi.disconnect();
    startWifi();
  }
  startMdns();
}

bool ethUp() { return ethIp; }
bool wifiUp() { return WiFi.status() == WL_CONNECTED; }
bool apOn() { return cfgMode; }
bool anyLink() { return ethIp || wifiUp(); }

String netAddr() {
  bool preferWifi = S.netMode == 1;
  if (preferWifi && wifiUp()) return WiFi.localIP().toString();
  if (ethIp) return ETH.localIP().toString();
  if (wifiUp()) return WiFi.localIP().toString();
  return "";
}

void netScanStart() {
  if (WiFi.getMode() == WIFI_OFF) WiFi.mode(WIFI_STA);
  WiFi.scanDelete();
  WiFi.scanNetworks(true);
}

String netScanJson() {
  int n = WiFi.scanComplete();
  JsonDocument d;
  d["busy"] = n == WIFI_SCAN_RUNNING;
  JsonArray a = d["nets"].to<JsonArray>();
  for (int i = 0; i < n && i < 20; i++) {
    JsonObject o = a.add<JsonObject>();
    o["ssid"] = WiFi.SSID(i);
    o["rssi"] = WiFi.RSSI(i);
    o["open"] = WiFi.encryptionType(i) == WIFI_AUTH_OPEN;
  }
  String out;
  serializeJson(d, out);
  return out;
}

String netJson() {
  JsonDocument d;
  JsonObject e = d["eth"].to<JsonObject>();
  e["up"] = ethIp;
  e["link"] = ethLink;
  e["ip"] = ethIp ? ETH.localIP().toString() : "";
  e["mac"] = ETH.macAddress();
  JsonObject w = d["wifi"].to<JsonObject>();
  w["up"] = wifiUp();
  w["ssid"] = wifiUp() ? WiFi.SSID() : "";
  w["rssi"] = wifiUp() ? WiFi.RSSI() : 0;
  w["ip"] = wifiUp() ? WiFi.localIP().toString() : "";
  JsonObject a = d["ap"].to<JsonObject>();
  a["on"] = cfgMode;
  a["clients"] = cfgMode ? WiFi.softAPgetStationNum() : 0;
  d["addr"] = netAddr();
  String out;
  serializeJson(d, out);
  return out;
}
