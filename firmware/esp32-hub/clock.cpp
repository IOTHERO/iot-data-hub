// Clock: DS3231 RTC (I2C) keeps the time through a power cut; NTP corrects it when a link is up;
// the server can set it too. Time-based scenes need a valid clock (see clockValid()).

#include <Wire.h>
#include <sys/time.h>
#include <esp_sntp.h>
#include "core.h"

#define DS3231_ADDR 0x68

static bool rtcOk = false;
static bool rtcOsf = false;           // oscillator stopped flag: the time is not trustworthy
static float tempC = NAN;
static String source = "none";
static bool valid = false;
static volatile bool ntpSynced = false;
static bool ntpStarted = false;
static uint32_t lastTick = 0, lastTemp = 0;

static uint8_t bcd2bin(uint8_t v) { return v - 6 * (v >> 4); }
static uint8_t bin2bcd(uint8_t v) { return v + 6 * (v / 10); }

// Days from civil date (H. Hinnant): epoch seconds of a UTC calendar time without timegm().
static time_t epochFromCivil(int y, int mo, int d, int h, int mi, int s) {
  y -= mo <= 2;
  int64_t era = (y >= 0 ? y : y - 399) / 400;
  int64_t yoe = y - era * 400;
  int64_t doy = (153 * (mo > 2 ? mo - 3 : mo + 9) + 2) / 5 + d - 1;
  int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return (time_t)((era * 146097 + doe - 719468) * 86400 + h * 3600 + mi * 60 + s);
}

static bool i2cRead(uint8_t reg, uint8_t *buf, uint8_t n) {
  Wire.beginTransmission(DS3231_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((int)DS3231_ADDR, (int)n) != n) return false;
  for (uint8_t i = 0; i < n; i++) buf[i] = Wire.read();
  return true;
}

static bool rtcRead(time_t &utc) {
  uint8_t b[7];
  if (!i2cRead(0x00, b, 7)) return false;
  int year = 2000 + bcd2bin(b[6]);
  utc = epochFromCivil(year, bcd2bin(b[5] & 0x1F), bcd2bin(b[4]), bcd2bin(b[2] & 0x3F),
                       bcd2bin(b[1] & 0x7F), bcd2bin(b[0] & 0x7F));
  return true;
}

static bool rtcWrite(time_t utc) {
  tm t;
  gmtime_r(&utc, &t);
  Wire.beginTransmission(DS3231_ADDR);
  Wire.write(0x00);
  Wire.write(bin2bcd(t.tm_sec));
  Wire.write(bin2bcd(t.tm_min));
  Wire.write(bin2bcd(t.tm_hour));
  Wire.write(bin2bcd(t.tm_wday + 1));
  Wire.write(bin2bcd(t.tm_mday));
  Wire.write(bin2bcd(t.tm_mon + 1));
  Wire.write(bin2bcd(t.tm_year - 100));
  if (Wire.endTransmission() != 0) return false;
  uint8_t st;                                           // clear the "oscillator stopped" flag
  if (i2cRead(0x0F, &st, 1)) {
    Wire.beginTransmission(DS3231_ADDR);
    Wire.write(0x0F);
    Wire.write(st & 0x7F);
    Wire.endTransmission();
  }
  rtcOsf = false;
  return true;
}

static void setSystemTime(time_t utc) {
  timeval tv = {utc, 0};
  settimeofday(&tv, nullptr);
}

static void onNtp(timeval *) { ntpSynced = true; }

void clockBegin() {
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(100000);
  uint8_t st;
  rtcOk = i2cRead(0x0F, &st, 1);
  if (rtcOk) {
    rtcOsf = st & 0x80;
    time_t t;
    if (rtcRead(t) && !rtcOsf && t > 1735689600) {      // 2025-01-01: anything older is not a real time
      setSystemTime(t);
      valid = true;
      source = "rtc";
    }
    hlog(2, "RTC found%s", rtcOsf ? ", lost power" : "");
  } else {
    hlog(1, "RTC not found");
  }
  sntp_set_time_sync_notification_cb(onNtp);
}

void clockSet(time_t utc, const char *src) {
  setSystemTime(utc);
  if (rtcOk) rtcWrite(utc);
  valid = true;
  source = src;
  hlog(2, "clock set from %s", src);
}

bool clockValid() { return valid; }
time_t nowUtc() { return time(nullptr); }
time_t nowLocal() { return time(nullptr) + (time_t)S.utcOffsetMin * 60; }
bool rtcPresent() { return rtcOk; }
bool rtcLostPower() { return rtcOk && rtcOsf; }
float rtcTempC() { return tempC; }
String clockSource() { return source; }

void clockLoop() {
  uint32_t now = millis();
  if (anyLink() && !ntpStarted && S.ntp.length()) {     // SNTP polls by itself every hour
    configTime(0, 0, S.ntp.c_str());
    ntpStarted = true;
  }
  if (ntpSynced) {
    ntpSynced = false;
    time_t t = time(nullptr);
    if (t > 1735689600) {
      time_t r;
      bool drift = !rtcOk || !rtcRead(r) || llabs((long long)(r - t)) > 2 || rtcOsf;
      if (rtcOk && drift) rtcWrite(t);
      valid = true;
      source = "ntp";
    }
  }
  if (now - lastTick < 1000) return;
  lastTick = now;
  if (rtcOk && now - lastTemp > 30000) {
    lastTemp = now;
    uint8_t b[2];
    if (i2cRead(0x11, b, 2)) tempC = (int8_t)b[0] + (b[1] >> 6) * 0.25f;
  }
  if (rtcOk && rtcOsf && !valid) alarmRaise("rtc_lost", "RTC lost its time (battery?). Waiting for NTP or the server.");
  else alarmClear("rtc_lost");
  if (!valid && now > 90000) alarmRaise("no_time", "No valid clock: time scenes will not run.", false);
  else alarmClear("no_time");
}
