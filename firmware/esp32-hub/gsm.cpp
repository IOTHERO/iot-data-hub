// GSM modem (SIM800 / SIM7600 / A7670: plain AT commands in text mode) and signed SMS commands.
// The modem runs in its own task, so a slow modem never stalls the hub; SMS in and out pass
// through two queues. SMS text is ASCII (GSM 7-bit): alarm texts are short English codes.
//
// Signed SMS (contract: docs/fa/platform/todo-smart-home.md section 3):
//   HUB <counter> <item> [<item> ...] <sig>
//   item:  <alias>.<tag>=<value>   (m1.relay_1=1)   |   s.<scene_id>   |   ack
//   sig:   first 8 bytes, hex, of HMAC-SHA256(smsKey, "<hubId> <counter> <items...>")
// The counter must grow with every message (a replay does nothing). The sender must also be a
// contact with "commands" on. A stranger gets no answer.

#include <HardwareSerial.h>
#include <Preferences.h>
#include <deque>
#include "core.h"

static HardwareSerial modem(2);
static SemaphoreHandle_t mtx;
struct Sms { String number, text; };
static std::deque<Sms> outbox, inbox;
static volatile bool up = false;
static volatile int csq = -1;
static String oper;
static bool started = false;

// ---------------------------------------------------------------- AT helpers (task only) -------
static String atRead(uint32_t timeoutMs, const char *a, const char *b = nullptr) {
  String s;
  uint32_t t0 = millis();
  while (millis() - t0 < timeoutMs) {
    while (modem.available()) s += (char)modem.read();
    if ((a && s.indexOf(a) >= 0) || (b && s.indexOf(b) >= 0)) break;
    delay(5);
  }
  return s;
}

static String at(const String &cmd, uint32_t timeoutMs = 2000) {
  while (modem.available()) modem.read();               // drop old unsolicited lines
  modem.print(cmd);
  modem.print("\r");
  return atRead(timeoutMs, "OK", "ERROR");
}

static void pulsePower() {
  if (PIN_GSM_PWRKEY < 0) return;
  pinMode(PIN_GSM_PWRKEY, OUTPUT);
  digitalWrite(PIN_GSM_PWRKEY, HIGH);                   // transistor to GND: HIGH = key pressed
  vTaskDelay(1200 / portTICK_PERIOD_MS);
  digitalWrite(PIN_GSM_PWRKEY, LOW);
  vTaskDelay(3000 / portTICK_PERIOD_MS);
}

static bool initModem() {
  for (int i = 0; i < 3; i++) {
    if (at("AT", 800).indexOf("OK") >= 0) break;
    if (i == 1) pulsePower();                           // no answer: press the power key
    if (i == 2) return false;
  }
  at("ATE0");
  at("AT+CMEE=1");
  String pin = at("AT+CPIN?", 3000);
  if (pin.indexOf("SIM PIN") >= 0 && S.simPin.length()) at("AT+CPIN=\"" + S.simPin + "\"", 5000);
  at("AT+CMGF=1");
  at("AT+CSCS=\"GSM\"");
  at("AT+CNMI=2,1,0,0,0");                              // new SMS: store and tell (+CMTI)
  at("AT+CPMS=\"SM\",\"SM\",\"SM\"");
  return true;
}

static void pollStatus() {
  String r = at("AT+CSQ");
  int p = r.indexOf("+CSQ:");
  if (p >= 0) csq = r.substring(p + 5).toInt();
  String reg = at("AT+CREG?");
  p = reg.indexOf("+CREG:");
  int comma = reg.indexOf(',', p);
  int stat = comma > 0 ? reg.substring(comma + 1).toInt() : 0;
  up = (stat == 1 || stat == 5) && csq > 0 && csq < 99;
  String op = at("AT+COPS?");
  int q1 = op.indexOf('"'), q2 = op.indexOf('"', q1 + 1);
  if (q1 >= 0 && q2 > q1) oper = op.substring(q1 + 1, q2);
}

static void readUnread() {
  String r = at("AT+CMGL=\"REC UNREAD\"", 6000);
  int pos = 0;
  while ((pos = r.indexOf("+CMGL:", pos)) >= 0) {
    int eol = r.indexOf('\n', pos);
    if (eol < 0) break;
    String head = r.substring(pos, eol);
    int idx = head.substring(6).toInt();
    int q[4], k = 0, from = 0;                          // the sender is the 3rd quoted field
    while (k < 4 && (from = head.indexOf('"', from)) >= 0) { q[k++] = from++; }
    String number = k >= 4 ? head.substring(q[2] + 1, q[3]) : "";
    int next = r.indexOf("+CMGL:", eol);
    String body = r.substring(eol + 1, next < 0 ? r.length() : next);
    body.replace("\r", "");
    body.replace("OK", "");
    body.trim();
    xSemaphoreTake(mtx, portMAX_DELAY);
    if (inbox.size() < 8) inbox.push_back({number, body});
    xSemaphoreGive(mtx);
    at("AT+CMGD=" + String(idx));
    pos = eol;
  }
}

static bool sendOne(const Sms &m) {
  modem.print("AT+CMGS=\"" + m.number + "\"\r");
  if (atRead(5000, ">").indexOf('>') < 0) { modem.write(27); return false; }
  modem.print(m.text);
  modem.write(26);                                      // Ctrl-Z ends the message
  return atRead(40000, "+CMGS", "ERROR").indexOf("+CMGS") >= 0;
}

static void gsmTask(void *) {
  uint32_t lastStatus = 0, lastPoll = 0;
  bool ready = false;
  for (;;) {
    if (!ready) {
      ready = initModem();
      if (!ready) { up = false; vTaskDelay(30000 / portTICK_PERIOD_MS); continue; }
      pollStatus();
    }
    uint32_t now = millis();
    if (now - lastStatus > 20000) { lastStatus = now; pollStatus(); if (csq < 0) ready = false; }
    if (modem.available()) {                            // a +CMTI line: read at once
      String s = atRead(200, "\n");
      if (s.indexOf("+CMTI") >= 0) lastPoll = 0;
    }
    if (now - lastPoll > 10000 || lastPoll == 0) { lastPoll = now ? now : 1; readUnread(); }
    Sms m;
    bool have = false;
    xSemaphoreTake(mtx, portMAX_DELAY);
    if (!outbox.empty() && up) { m = outbox.front(); outbox.pop_front(); have = true; }
    xSemaphoreGive(mtx);
    if (have && !sendOne(m)) hlog(1, "SMS to %s failed", m.number.c_str());
    vTaskDelay(100 / portTICK_PERIOD_MS);
  }
}

// ---------------------------------------------------------------- public ----------------------
void gsmBegin() {
  if (!S.gsmEnabled || started) return;
  mtx = xSemaphoreCreateMutex();
  modem.setRxBufferSize(1024);
  modem.begin(GSM_BAUD, SERIAL_8N1, PIN_GSM_RX, PIN_GSM_TX);
  xTaskCreatePinnedToCore(gsmTask, "gsm", 6144, nullptr, 1, nullptr, 0);
  started = true;
}

bool gsmUp() { return started && up; }
int gsmSignal() { return csq; }
String gsmOperator() { return oper; }

void smsSend(const String &to, const String &text) {
  if (!started || !to.length()) return;
  xSemaphoreTake(mtx, portMAX_DELAY);
  if (outbox.size() < 10) outbox.push_back({to, text.substring(0, 160)});
  xSemaphoreGive(mtx);
}

static uint32_t alarmWindowStart = 0;
static int alarmCount = 0;
static String lastAlarmText;
static uint32_t lastAlarmAt = 0;

void smsAlarm(const String &text) {
  if (!started || !S.smsEnabled) return;
  uint32_t now = millis();
  if (now - alarmWindowStart > 3600000UL || !alarmWindowStart) { alarmWindowStart = now ? now : 1; alarmCount = 0; }
  if (alarmCount >= SMS_ALARM_PER_HOUR) return;
  if (text == lastAlarmText && now - lastAlarmAt < 600000UL) return;   // same text: once per 10 min
  lastAlarmText = text;
  lastAlarmAt = now;
  alarmCount++;
  for (auto &c : S.contacts) if (c.alarms) smsSend(c.number, S.deviceName.substring(0, 12) + ": " + text);
}

// ---------------------------------------------------------------- signed commands --------------
static String last9(const String &n) { return n.length() > 9 ? n.substring(n.length() - 9) : n; }

static String hex8(const uint8_t *mac) {
  char b[17];
  for (int i = 0; i < 8; i++) snprintf(b + i * 2, 3, "%02x", mac[i]);
  return String(b);
}

bool smsCommand(const String &from, const String &text, String &reply) {
  reply = "";
  static uint32_t recent[SMS_PER_10MIN];
  static uint8_t recentN = 0;
  bool allowed = false;
  for (auto &c : S.contacts) if (c.commands && last9(c.number) == last9(from)) allowed = true;
  if (!allowed || !S.smsEnabled || !S.smsKey.length()) return false;
  String t = text;
  t.trim();
  std::vector<String> w;
  for (int i = 0; i < (int)t.length();) {               // split on spaces
    int j = t.indexOf(' ', i);
    if (j < 0) j = t.length();
    if (j > i) w.push_back(t.substring(i, j));
    i = j + 1;
  }
  if (w.size() < 4 || !w[0].equalsIgnoreCase("HUB")) return false;
  uint32_t now = millis();
  recentN = min<uint8_t>(recentN, SMS_PER_10MIN);       // at most 5 commands in 10 minutes
  uint8_t live = 0;
  for (uint8_t i = 0; i < recentN; i++) if (now - recent[i] < 600000UL) recent[live++] = recent[i];
  recentN = live;
  if (recentN >= SMS_PER_10MIN) return false;
  uint32_t counter = (uint32_t)w[1].toInt();
  String signedText = S.hubId + " " + w[1];
  for (size_t i = 2; i + 1 < w.size(); i++) signedText += " " + w[i];
  uint8_t key[64], mac[32];
  size_t kl = b64urlDecode(S.smsKey, key, sizeof key);
  if (!kl) return false;
  hmacSha256(key, kl, (const uint8_t *)signedText.c_str(), signedText.length(), mac);
  Preferences p;
  p.begin("hub", false);
  uint32_t last = p.getUInt("smsctr", 0);
  bool ok = sameText(hex8(mac), w.back()) && counter > last;
  if (!ok) { p.end(); return false; }                   // wrong signature or a replay: silence
  p.putUInt("smsctr", counter);
  p.end();
  recent[recentN++] = now;
  int done = 0, total = 0;
  for (size_t i = 2; i + 1 < w.size(); i++) {
    total++;
    String item = w[i], err, target, value = "true";
    int eq = item.indexOf('=');
    String key2 = eq < 0 ? item : item.substring(0, eq);
    if (eq >= 0) value = item.substring(eq + 1);
    if (value == "1" || value == "on") value = "true";
    else if (value == "0" || value == "off") value = "false";
    if (key2 == "ack") target = "hub:ack";
    else if (key2.startsWith("s.")) target = "scene:" + key2.substring(2);
    else { int dot = key2.indexOf('.'); if (dot < 0) continue; target = key2.substring(0, dot) + ":" + key2.substring(dot + 1); }
    if (execTarget(target, value, "sms", err)) done++;
  }
  reply = "OK " + String(done) + "/" + String(total);
  return true;
}

void gsmLoop() {
  if (!started) return;
  Sms m;
  bool have = false;
  xSemaphoreTake(mtx, portMAX_DELAY);
  if (!inbox.empty()) { m = inbox.front(); inbox.pop_front(); have = true; }
  xSemaphoreGive(mtx);
  if (!have) return;
  String reply;
  if (smsCommand(m.number, m.text, reply) && reply.length()) smsSend(m.number, reply);
}
