"""Development stand-in for the hub's portal: serves data/ and fakes the /api the firmware offers,
so the web UI can be looked at and clicked through without a board.

    python firmware/esp32-hub/tools/mock_portal.py [port]      (admin password: admin)
"""

from __future__ import annotations

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

DATA = Path(__file__).resolve().parent.parent / "data"
T0 = time.time()
SETTINGS = {
    "deviceName": "TiTi Hub - Building A",
    "system": {"logLevel": 2, "adminPassSet": True, "adminPassDefault": True, "apPassSet": True},
    "id": {"hubId": "hub_demo_01", "hubSecretSet": True},
    "net": {
        "mode": 0,
        "ethDhcp": True,
        "ethIp": "",
        "ethGw": "",
        "ethMask": "255.255.255.0",
        "ethDns": "",
        "wifiSsid": "Office-WiFi",
        "wifiPassSet": True,
        "wifiSsid2": "",
        "wifiPass2Set": False,
        "hostname": "titi-hub",
        "ntp": "pool.ntp.org",
        "utcOffsetMin": 210,
    },
    "cloud": {
        "enabled": True,
        "host": "mqtt.example.com",
        "port": 1883,
        "prefix": "",
        "keepalive": 30,
        "lostAlarmS": 300,
        "tls": False,
        "caSet": False,
    },
    "modules": {"brokerPort": 1883, "offlineS": 90},
    "local": {"enabled": True, "port": 8080, "keySet": True},
    "gsm": {
        "enabled": True,
        "apn": "mcinet",
        "smsEnabled": True,
        "simPinSet": False,
        "smsKeySet": True,
        "contacts": [
            {"number": "+989121234567", "name": "Manager", "commands": True, "alarms": True}
        ],
    },
}
MODULES = [
    {
        "id": "d4k2m9q7x3p5r8t1v6w0",
        "name": "Lobby relays",
        "alias": "m1",
        "secretSet": True,
        "online": True,
        "age_s": 4,
        "addr": "192.168.1.51",
        "fw": "1.0.0",
        "cmd": "done",
        "values": {f"relay_{i}": i in (1, 4, 7) for i in range(1, 9)} | {"uptime_s": 86400.0},
    },
    {
        "id": "d7h3j8n2c5b9v1x4z6a0",
        "name": "Parking",
        "alias": "m2",
        "secretSet": True,
        "online": False,
        "age_s": 412,
        "addr": "192.168.1.52",
        "fw": "1.0.0",
        "cmd": "",
        "values": {f"relay_{i}": False for i in range(1, 9)},
    },
]
SCENES = [
    {
        "id": "evening",
        "name": "Evening on",
        "enabled": True,
        "trigger": {"type": "time", "at": "18:30"},
        "actions": [{"type": "write", "device": "m1", "tag": "relay_1", "value": True}],
    },
    {
        "id": "all_off",
        "name": "All off",
        "enabled": True,
        "trigger": {"type": "manual"},
        "actions": [{"type": "write", "device": "m1", "tag": "relay_1", "value": False}],
    },
]
ALARMS = [
    {
        "code": "module_d7h3j8n2c5b9v1x4z6a0",
        "text": "Module offline: m2",
        "at": int(T0) - 400,
        "acked": False,
    },
    {
        "code": "default_pass",
        "text": "Admin password is still the default",
        "at": int(T0) - 900,
        "acked": True,
    },
]
LOG = [
    "1 I TiTi Hub 0.1.0, reset: power-on",
    "3 I W5500 started",
    "5 I LAN address 192.168.1.60",
    "9 I module d4k2m9q7x3p5r8t1v6w0 online",
]
TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css",
    ".woff2": "font/woff2",
}


def state() -> dict:
    now = int(time.time())
    return {
        "hub": {
            "fw": "0.1.0",
            "uptime_s": int(now - T0) + 3600,
            "heap": 215000,
            "heap_min": 190000,
            "reset": "power-on",
            "config_mode": False,
            "hub_id": "hub_demo_01",
            "addr": "192.168.1.60",
            "cloud_enabled": True,
            "cloud_up": False,
            "eth_up": True,
            "wifi_up": True,
            "gsm_enabled": True,
            "gsm_up": True,
            "gsm_csq": 21,
            "gsm_operator": "MCI",
            "clock_valid": True,
            "clock_source": "rtc",
            "time": now,
            "utc_offset_min": 210,
            "rtc": True,
            "rtc_lost": False,
            "rtc_temp": 27.25,
            "modules": len(MODULES),
            "modules_online": sum(m["online"] for m in MODULES),
            "enroll_left": 0,
            "config_switch": False,
        },
        "net": {
            "eth": {"up": True, "link": True, "ip": "192.168.1.60", "mac": "AA:BB:CC:DD:EE:01"},
            "wifi": {"up": True, "ssid": "Office-WiFi", "rssi": -58, "ip": "192.168.1.61"},
            "ap": {"on": False, "clients": 0},
            "addr": "192.168.1.60",
        },
        "modules": MODULES,
        "scenes": [
            {
                "id": s["id"],
                "name": s["name"],
                "enabled": s["enabled"],
                "trigger": s["trigger"]["type"],
                "running": False,
            }
            for s in SCENES
        ],
        "alarms": ALARMS,
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code: int = 200) -> None:
        self._send(code, json.dumps(obj).encode())

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw)
        except ValueError:
            return None

    def _authed(self) -> bool:
        return self.headers.get("X-Auth") == "demo-token"

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/api/"):
            if not self._authed():
                return self._json({"error": "auth"}, 401)
            if path == "/api/state":
                return self._json(state())
            if path == "/api/settings":
                return self._json(SETTINGS)
            if path == "/api/scenes":
                return self._json(SCENES)
            if path == "/api/keys":
                return self._json({"hub_id": "hub_demo_01", "local": "x" * 43, "sms": "y" * 43})
            if path == "/api/log":
                return self._json({"seq": 1, "lines": "\n".join(LOG) + "\n"})
            if path == "/api/wifi/scan":
                return self._json(
                    {
                        "busy": False,
                        "nets": [
                            {"ssid": "Office-WiFi", "rssi": -58, "open": False},
                            {"ssid": "Guest", "rssi": -71, "open": True},
                        ],
                    }
                )
            return self._json({"error": "not found"}, 404)
        rel = "index.html" if path == "/" else path.lstrip("/")
        f = (DATA / rel).resolve()
        if DATA not in f.parents and f != DATA or not f.is_file():
            return self._send(404, b"not found", "text/plain")
        self._send(200, f.read_bytes(), TYPES.get(f.suffix, "application/octet-stream"))

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        body = self._body()
        if path == "/api/login":
            if body and body.get("password") == "admin":
                return self._json({"token": "demo-token"})
            return self._json({"error": "wrong"}, 401)
        if not self._authed():
            return self._json({"error": "auth"}, 401)
        if path == "/api/scenes" and isinstance(body, list):
            SCENES[:] = body
        if path == "/api/command" and body:
            target, _, tag = str(body.get("target", "")).partition(":")
            for m in MODULES:
                if target in (m["id"], m["alias"]) and tag in m["values"]:
                    m["values"][tag] = bool(body.get("value"))
        if path == "/api/alarms/ack":
            for a in ALARMS:
                a["acked"] = True
        return self._json({"ok": True})

    def log_message(self, *_: object) -> None:
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT") or (sys.argv[1] if len(sys.argv) > 1 else 8765))
    print(f"mock portal on http://127.0.0.1:{port}/  (password: admin)")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
