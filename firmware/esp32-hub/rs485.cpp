// RS-485 bus: the hub as Modbus RTU master (UART1) for modules that are wired, not networked,
// e.g. DEVICE 8DO (TiTiRelay8) in RS-485 mode. A bus module is a registry entry with "rtu":
// <its Modbus address>. The hub asks each one in turn and makes it look like an MQTT module to
// everything above: its values go through the same path (moduleMessage -> scenes, portal, the
// server as h/<hub>/up), and commands for it (server, phone, SMS, scenes) become Modbus writes.
//
// DEVICE 8DO map (TiTiRelay8 README "Modbus RTU map", start addresses 0):
//   coils 0..7 = relay_1..relay_8 (FC1 read, FC5 write)
//   holding 2..9 = pulse relay 1..8 in 0.1 s (FC6)
// One request at a time, a reply within RTU_TIMEOUT_MS; a module that does not answer goes
// offline by the hub's usual silence rule (MODULE_OFFLINE_S_DEFAULT).

#include <ArduinoJson.h>
#include "core.h"

static HardwareSerial bus(1);
static bool busOn = false;
static size_t nextIdx = 0;
static uint32_t lastPoll = 0;

struct RtuSeen { String id; uint8_t coils = 0; bool known = false; uint32_t sentAt = 0; };
static std::vector<RtuSeen> seen;

static RtuSeen &seenOf(const String &id) {
  for (auto &s : seen) if (s.id == id) return s;
  seen.push_back(RtuSeen{id});
  return seen.back();
}

static uint16_t crc16(const uint8_t *p, size_t n) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < n; i++) {
    crc ^= p[i];
    for (uint8_t b = 0; b < 8; b++) crc = (crc & 1) ? (crc >> 1) ^ 0xA001 : crc >> 1;
  }
  return crc;
}

// Send one request and read the reply into rx; true with a valid reply of `want` bytes.
static bool transact(uint8_t *req, size_t n, uint8_t *rx, size_t want) {
  uint16_t c = crc16(req, n);
  req[n] = c & 0xFF;
  req[n + 1] = c >> 8;
  while (bus.available()) bus.read();                   // drop line noise from before
  digitalWrite(PIN_RS485_DE, HIGH);
  bus.write(req, n + 2);
  bus.flush();                                          // wait until the last bit has left
  digitalWrite(PIN_RS485_DE, LOW);
  size_t got = 0;
  uint32_t t0 = millis();
  while (got < want && millis() - t0 < RTU_TIMEOUT_MS) {
    if (bus.available()) rx[got++] = bus.read();
    else delay(1);
    if (got == 5 && (rx[1] & 0x80)) break;              // exception reply: 5 bytes
  }
  if (got < 5 || rx[0] != req[0]) return false;
  if (rx[1] & 0x80) {
    hlog(1, "rtu %u: exception %u", req[0], rx[2]);
    return false;
  }
  if (got != want) return false;
  uint16_t rc = crc16(rx, want - 2);
  return rx[want - 2] == (rc & 0xFF) && rx[want - 1] == (rc >> 8);
}

static bool readCoils(uint8_t addr, uint8_t &out) {
  uint8_t req[8] = {addr, 0x01, 0, 0, 0, 8}, rx[6];
  if (!transact(req, 6, rx, 6) || rx[2] != 1) return false;
  out = rx[3];
  return true;
}

static bool writeCoil(uint8_t addr, uint16_t coil, bool on) {
  uint8_t req[8] = {addr, 0x05, (uint8_t)(coil >> 8), (uint8_t)coil, (uint8_t)(on ? 0xFF : 0), 0}, rx[8];
  return transact(req, 6, rx, 8);
}

static bool writeHolding(uint8_t addr, uint16_t reg, uint16_t v) {
  uint8_t req[8] = {addr, 0x06, (uint8_t)(reg >> 8), (uint8_t)reg, (uint8_t)(v >> 8), (uint8_t)v}, rx[8];
  return transact(req, 6, rx, 8);
}

static void report(Module &m, uint8_t coils, bool force) {
  RtuSeen &s = seenOf(m.id);
  if (!s.known) {                                        // first answer (again): online
    moduleMessage(m.id, "state", "{\"state\":\"online\",\"firmware\":\"rtu\"}");
  }
  if (force || !s.known || coils != s.coils || millis() - s.sentAt > RTU_REPORT_MS) {
    JsonDocument d;
    JsonObject v = d["values"].to<JsonObject>();
    char key[10];
    for (uint8_t r = 0; r < 8; r++) {
      snprintf(key, sizeof key, "relay_%u", r + 1);
      v[key] = (bool)((coils >> r) & 1);
    }
    String out;
    serializeJson(d, out);
    moduleMessage(m.id, "telemetry", out);
    s.sentAt = millis();
  }
  s.coils = coils;
  s.known = true;
}

void rtuBegin() {
  if (PIN_RS485_TX < 0) return;
  pinMode(PIN_RS485_DE, OUTPUT);
  digitalWrite(PIN_RS485_DE, LOW);
  bus.begin(RS485_BAUD, SERIAL_8N1, PIN_RS485_RX, PIN_RS485_TX);
  busOn = true;
  hlog(2, "RS-485 bus at %u baud", RS485_BAUD);
}

void rtuLoop() {
  if (!busOn || modules.empty() || millis() - lastPoll < RTU_POLL_MS) return;
  lastPoll = millis();
  for (size_t tries = 0; tries < modules.size(); tries++) {
    Module &m = modules[nextIdx++ % modules.size()];
    if (!m.rtu) continue;
    uint8_t coils;
    if (readCoils(m.rtu, coils)) report(m, coils, false);
    else seenOf(m.id).known = false;                    // silence: offline after the usual time
    return;
  }
}

// cmd {"command_id","tag":"relay_N","value":bool,"pulse_s"} -> a write, then the acks the server
// expects (received, done with the value / failed) and fresh values.
bool rtuSend(Module &m, const String &topic, const String &payload) {
  if (!busOn) return false;
  if (topic != "cmd") return true;                       // rules / config / ota: not on the bus
  JsonDocument d;
  if (deserializeJson(d, payload)) return false;
  String id = d["command_id"] | "", tag = d["tag"] | "";
  auto ack = [&](const char *status, const char *error, int value) {
    if (!id.length()) return;
    JsonDocument a;
    a["command_id"] = id;
    a["status"] = status;
    if (value >= 0) a["value"] = value == 1;
    if (error) a["error"] = error;
    String out;
    serializeJson(a, out);
    moduleMessage(m.id, "ack", out);
  };
  int relay = tag.startsWith("relay_") ? tag.substring(6).toInt() : 0;
  JsonVariantConst v = d["value"];
  if (relay < 1 || relay > 8 || !(v.is<bool>() || v.is<int>())) {
    ack("failed", relay < 1 || relay > 8 ? "unknown_tag" : "bad_value", -1);
    return false;
  }
  bool on = v.is<bool>() ? v.as<bool>() : v.as<int>() != 0;
  ack("received", nullptr, -1);
  float pulse = d["pulse_s"] | 0.0f;
  bool ok = (on && pulse > 0 && pulse <= 6553)
                ? writeHolding(m.rtu, 2 + relay - 1, (uint16_t)(pulse * 10))
                : writeCoil(m.rtu, relay - 1, on);
  if (!ok) {
    ack("failed", "no_reply", -1);
    return false;
  }
  ack("done", nullptr, on ? 1 : 0);
  uint8_t coils;
  if (readCoils(m.rtu, coils)) report(m, coils, true);
  return true;
}
