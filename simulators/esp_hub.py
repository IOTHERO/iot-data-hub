"""Reference model of the ESP32 central hub (firmware/esp32-hub): the contract the server sees.

The hub is ONE device for the server (h/<hub_id>/...) and the manager of its modules; modules are
ordinary native devices (simulators/native_device.py). This model keeps the behaviours that make
the hub work with no internet, so the server side (and the firmware) can be tested against them:

* up: every module message goes to the server as an envelope; down: commands, rules, config
  reach the module, and the server can replace the scenes, the hub settings and the clock;
* scenes (time / interval / value / event / manual, calendar with the Jalali calendar and holidays)
  run on the hub itself, with or without the server; what ran is reported afterwards (scene_log);
* the signed local API for the phone (hub/platform/local_sign.py with the hub's id);
* signed SMS commands with an allowed-number list, a growing counter and a rate limit.

    python -m simulators.esp_hub --mqtt 127.0.0.1:1883 --hub hub1 --secret s3cret
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import contextlib
import hashlib
import hmac
import json
import logging
import time
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

from hub import jalali
from hub.platform.local_sign import NONCE_TTL_S, new_key, new_nonce, verify
from simulators.native_device import NativeDeviceSim

log = logging.getLogger(__name__)
SMS_PER_10MIN = 5
OPS = {
    "eq": lambda a, b: a == b,
    "ne": lambda a, b: a != b,
    "lt": lambda a, b: a < b,
    "le": lambda a, b: a <= b,
    "gt": lambda a, b: a > b,
    "ge": lambda a, b: a >= b,
}


class EspHubSim:
    def __init__(
        self,
        hub_id: str,
        secret: str,
        *,
        prefix: str = "",
        offset_min: int = 210,
        clock: Callable[[], float] = time.time,
        module_offline_s: float = 90.0,
    ) -> None:
        self.hub_id, self.secret, self.prefix = hub_id, secret, prefix
        self.offset_min = offset_min
        self.clock = clock
        self.module_offline_s = module_offline_s
        self.local_key = new_key()
        self.sms_key = new_key()
        self.contacts: list[dict[str, Any]] = []
        self.holidays: list[str] = []  # extra Jalali holidays "YYYY/MM/DD"
        self.modules: dict[str, NativeDeviceSim] = {}
        self.alias: dict[str, str] = {}
        self.seen: dict[str, float] = {}  # module id -> hub time of its last message
        self.online: dict[str, bool] = {}
        self.scenes: list[dict[str, Any]] = []
        self.scene_log: list[dict[str, Any]] = []
        self.alarms: dict[str, str] = {}
        self.sent: list[tuple[str, str]] = []  # SMS the hub would send: (number, text)
        self.events: list[tuple[str, str]] = []
        self.sms_counter = 0
        self._sms_times: list[float] = []
        self._nonces: dict[str, float] = {}
        self._last_fire: dict[str, Any] = {}
        self._value_true: dict[str, bool] = {}
        self._client: Any = None
        self._down_task: asyncio.Task[None] | None = None

    # --- modules -----------------------------------------------------------------------------

    def add_module(self, sim: NativeDeviceSim, alias: str) -> None:
        self.modules[sim.device_id] = sim
        self.alias[alias] = sim.device_id
        self.seen[sim.device_id] = self.clock()
        self.online[sim.device_id] = True

    def _module(self, key: str) -> NativeDeviceSim | None:
        return self.modules.get(self.alias.get(key, key))

    async def module_message(self, module_id: str, kind: str, payload: dict[str, Any]) -> None:
        """A message from a module reached the hub: note it, pass it up."""
        self.seen[module_id] = self.clock()
        if kind == "state" and payload.get("state") == "offline":
            self._set_online(module_id, False)
        else:
            self._set_online(module_id, True)
        await self.publish("up", {"d": module_id, "k": kind, "p": payload})

    def _set_online(self, module_id: str, on: bool) -> None:
        if self.online.get(module_id) == on:
            return
        self.online[module_id] = on
        name = "module_online" if on else "module_offline"
        self.events.append((name, module_id))
        if not on:
            self.alarm_raise(f"module_{module_id}", f"Module offline: {module_id}")
        else:
            self.alarm_clear(f"module_{module_id}")

    def check_modules(self) -> None:
        for mid in self.modules:
            if self.online[mid] and self.clock() - self.seen[mid] > self.module_offline_s:
                self._set_online(mid, False)

    async def command_module(
        self, target: str, value: Any, pulse_s: float = 0, by: str = "local"
    ) -> bool:
        """'<module or alias>:<tag>' -> a command to the module; its replies go up."""
        key, _, tag = target.partition(":")
        sim = self._module(key)
        if sim is None or not self.online.get(sim.device_id):
            return False
        cmd = {"command_id": f"h{len(sim.executed) + 1}", "tag": tag, "value": value}
        if pulse_s:
            cmd["pulse_s"] = pulse_s
        for reply in sim.handle(cmd):
            kind = reply.pop("type")
            await self.module_message(sim.device_id, kind, reply)
        return True

    # --- server link -------------------------------------------------------------------------

    @property
    def cloud_up(self) -> bool:
        return self._client is not None

    def topic(self, kind: str) -> str:
        return f"{self.prefix}h/{self.hub_id}/{kind}"

    async def publish(self, kind: str, payload: dict[str, Any], *, retain: bool = False) -> None:
        if self._client is not None:  # nothing is queued for a server that is gone
            await self._client.publish(self.topic(kind), json.dumps(payload), qos=1, retain=retain)

    async def connect_cloud(self, host: str, port: int) -> None:
        import aiomqtt

        will = aiomqtt.Will(
            self.topic("state"), json.dumps({"state": "offline"}), qos=1, retain=True
        )
        client = aiomqtt.Client(
            host,
            port,
            username=self.hub_id,
            password=self.secret,
            identifier=f"hub-{self.hub_id}",
            will=will,
        )
        await client.__aenter__()
        await client.subscribe(self.topic("down"), qos=1)
        self._client = client
        await self.publish(
            "state",
            {
                "state": "online",
                "firmware": "sim",
                "modules": len(self.modules),
                "online": sum(self.online.values()),
                "time_ok": True,
            },
            retain=True,
        )
        for mid, sim in self.modules.items():  # what the hub knows, again
            await self.publish(
                "up",
                {
                    "d": mid,
                    "k": "state",
                    "p": {"state": "online" if self.online[mid] else "offline"},
                },
            )
            await self.publish(
                "up", {"d": mid, "k": "telemetry", "p": {"values": dict(sim.values)}}
            )
        if self.scene_log:
            entries, self.scene_log = self.scene_log, []
            await self.publish("scene_log", {"entries": entries})
        self._down_task = asyncio.create_task(self._down_loop(client))

    async def disconnect_cloud(self) -> None:
        client, self._client = self._client, None
        if self._down_task:
            self._down_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._down_task
        if client is not None:
            with contextlib.suppress(Exception):
                await client.__aexit__(None, None, None)

    async def _down_loop(self, client: Any) -> None:
        async for message in client.messages:
            with contextlib.suppress(ValueError):
                await self.on_down(json.loads(message.payload))

    async def on_down(self, msg: dict[str, Any]) -> None:
        kind = msg.get("type")
        if kind in ("cmd", "rules", "config", "ota"):
            sim = self._module(msg.get("d", ""))
            if sim is None:
                return
            if kind == "cmd":
                for reply in sim.handle(msg["p"]):
                    k = reply.pop("type")
                    await self.module_message(sim.device_id, k, reply)
            else:
                sim.receive(
                    {"type": kind, **msg.get("p", {})} if kind in ("rules", "config") else msg["p"]
                )
        elif kind == "scenes":
            self.put_scenes(msg["scenes"])
        elif kind == "scene_run":
            await self.run_scene(msg["id"], "server")
        elif kind == "hubconfig":
            self.apply_hubconfig(msg)
        elif kind == "ack":
            self.alarms.clear()

    def apply_hubconfig(self, msg: dict[str, Any]) -> None:
        if msg.get("local", {}).get("key"):
            self.local_key = msg["local"]["key"]
        if msg.get("sms", {}).get("key"):
            self.sms_key = msg["sms"]["key"]
            self.sms_counter = 0
        if "contacts" in msg:
            self.contacts = msg["contacts"]
        if "holidays" in msg:
            self.holidays = msg["holidays"]
        if "utc_offset_min" in msg:
            self.offset_min = msg["utc_offset_min"]

    # --- alarms ------------------------------------------------------------------------------

    def alarm_raise(self, code: str, text: str) -> None:
        if code in self.alarms:
            return
        self.alarms[code] = text
        for c in self.contacts:
            if c.get("alarms"):
                self.sent.append((c["number"], text))
        if self._client is not None:
            asyncio.get_running_loop().create_task(
                self.publish(
                    "alarm", {"code": code, "text": text, "at": int(self.clock()), "active": True}
                )
            )

    def alarm_clear(self, code: str) -> None:
        self.alarms.pop(code, None)

    # --- scenes ------------------------------------------------------------------------------

    def put_scenes(self, scenes: list[dict[str, Any]]) -> None:
        if len(scenes) > 24 or len({s["id"] for s in scenes}) != len(scenes):
            raise ValueError("bad scenes")
        self.scenes = scenes
        self._last_fire.clear()
        self._value_true.clear()

    def local_time(self) -> datetime:
        return datetime.fromtimestamp(self.clock() + self.offset_min * 60, UTC)

    def calendar_ok(self, scene: dict[str, Any]) -> bool:
        cal = scene.get("calendar")
        if not cal:
            return True
        d = self.local_time().date()
        jy, jm, jd = jalali.to_jalali(d)
        if cal.get("months") and jm not in cal["months"]:
            return False
        if cal.get("month_days") and jd not in cal["month_days"]:
            return False
        holiday = (
            jalali.fixed_holiday(d) is not None or f"{jy:04d}/{jm:02d}/{jd:02d}" in self.holidays
        )
        if cal.get("holidays") == "skip" and holiday:
            return False
        return not (cal.get("holidays") == "only" and not holiday)

    def _value(self, device: str, tag: str) -> Any:
        sim = self._module(device)
        return sim.values.get(tag) if sim and self.online.get(sim.device_id) else None

    def _holds(self, c: dict[str, Any]) -> bool:
        v = self._value(c["device"], c["tag"])
        return v is not None and OPS[c["op"]](v, c["value"])

    async def tick(self) -> list[str]:
        """One evaluation pass (the firmware does it once a second). Returns the scenes started."""
        started: list[str] = []
        lt = self.local_time()
        events, self.events = self.events, []
        for s in self.scenes:
            if not s.get("enabled", True):
                continue
            tr, fire = s["trigger"], False
            if tr["type"] == "time":
                weekday = jalali.weekday(lt.date())
                key = (lt.date(), lt.hour, lt.minute)
                fire = (
                    lt.strftime("%H:%M") == tr["at"]
                    and self._last_fire.get(s["id"]) != key
                    and (not tr.get("weekdays") or weekday in tr["weekdays"])
                )
                if fire:
                    self._last_fire[s["id"]] = key
            elif tr["type"] == "value":
                on = self._holds(tr)
                fire = on and not self._value_true.get(s["id"], False)
                self._value_true[s["id"]] = on
            elif tr["type"] == "event":
                fire = any(
                    e == tr["event"]
                    and (not tr.get("device") or self._module(tr["device"]) is self.modules.get(d))
                    for e, d in events
                )
            if (
                fire
                and all(self._holds(c) for c in s.get("conditions", []))
                and self.calendar_ok(s)
            ):
                await self.run_scene(s["id"], "trigger")
                started.append(s["id"])
        return started

    async def run_scene(self, scene_id: str, by: str) -> bool:
        scene = next((s for s in self.scenes if s["id"] == scene_id), None)
        if scene is None:
            return False
        self.scene_log.append({"at": int(self.clock()), "scene": scene_id, "by": by})
        if self._client is not None:
            entries, self.scene_log = self.scene_log, []
            await self.publish("scene_log", {"entries": entries})
        for a in scene["actions"]:
            if a["type"] == "write":
                await self.command_module(
                    f"{a['device']}:{a['tag']}", a["value"], a.get("pulse_s", 0), "scene"
                )
            elif a["type"] == "sms":
                self.sent.extend((c["number"], a["text"]) for c in self.contacts if c.get("alarms"))
            elif a["type"] == "alarm":
                self.alarm_raise(f"scene_{scene_id}", a["text"])
        return True

    # --- phone: signed local API -------------------------------------------------------------

    async def local_request(
        self, method: str, path: str, body: dict[str, Any] | None
    ) -> tuple[int, dict[str, Any]]:
        now = self.clock()
        self._nonces = {n: t for n, t in self._nonces.items() if now - t < NONCE_TTL_S}
        if method == "GET" and path == "/local/v1/info":
            return 200, {
                "hub_id": self.hub_id,
                "firmware": "sim",
                "local": True,
                "modules": len(self.modules),
                "online": sum(self.online.values()),
                "time_ok": True,
            }
        if method == "GET" and path == "/local/v1/nonce":
            if len(self._nonces) >= 16:
                return 429, {"ok": False, "error": "too many open nonces"}
            n = new_nonce()
            self._nonces[n] = now
            return 200, {"hub_id": self.hub_id, "nonce": n, "ttl_s": NONCE_TTL_S}
        if method != "POST" or not isinstance(body, dict):
            return 404, {"ok": False, "error": "not found"}
        nonce = str(body.get("nonce", ""))
        if self._nonces.pop(nonce, None) is None:
            return 401, {"ok": False, "error": "nonce"}
        if path == "/local/v1/state":
            if not verify(self.local_key, body.get("sig", ""), self.hub_id, nonce, "state"):
                return 401, {"ok": False, "error": "signature"}
            return 200, {
                "ok": True,
                "modules": [
                    {"id": i, "online": self.online[i], "values": dict(m.values)}
                    for i, m in self.modules.items()
                ],
                "scenes": [{"id": s["id"], "enabled": s.get("enabled", True)} for s in self.scenes],
                "alarms": [{"code": c, "text": t} for c, t in self.alarms.items()],
            }
        if path == "/local/v1/command":
            tag, value_json = str(body.get("tag", "")), str(body.get("value_json", ""))
            if not verify(
                self.local_key, body.get("sig", ""), self.hub_id, nonce, "command", tag, value_json
            ):
                return 401, {"ok": False, "error": "signature"}
            return await self._local_command(tag, value_json)
        return 404, {"ok": False, "error": "not found"}

    async def _local_command(self, tag: str, value_json: str) -> tuple[int, dict[str, Any]]:
        if tag == "scenes:put":
            try:
                self.put_scenes(json.loads(value_json))
            except (ValueError, KeyError):
                return 400, {"ok": False, "error": "scenes"}
            return 200, {"ok": True}
        if tag == "hub:ack":
            self.alarms.clear()
            return 200, {"ok": True}
        if tag.startswith("scene:"):
            ok = await self.run_scene(tag[6:], "local")
            return (200, {"ok": True}) if ok else (400, {"ok": False, "error": "unknown scene"})
        ok = await self.command_module(tag, json.loads(value_json))
        return (200, {"ok": True}) if ok else (400, {"ok": False, "error": "offline or unknown"})

    # --- phone: signed SMS -------------------------------------------------------------------

    async def sms(self, number: str, text: str) -> str | None:
        """`HUB <counter> <item>... <sig>` (as NativeDeviceSim.sms); the sender must be an allowed
        number; items: `m1.relay_1=1`, `s.<scene>`, `ack`. Returns the reply, or None."""
        allowed = any(c.get("commands") and c["number"][-9:] == number[-9:] for c in self.contacts)
        parts = text.strip().split()
        if not allowed or len(parts) < 4 or parts[0].upper() != "HUB" or not parts[1].isdigit():
            return None
        now = self.clock()
        self._sms_times = [t for t in self._sms_times if now - t < 600]
        if len(self._sms_times) >= SMS_PER_10MIN:
            return None
        counter, items, sig = int(parts[1]), parts[2:-1], parts[-1].lower()
        raw = base64.urlsafe_b64decode(self.sms_key + "=" * (-len(self.sms_key) % 4))
        signed = " ".join([self.hub_id, str(counter), *items]).encode()
        if (
            not hmac.compare_digest(hmac.new(raw, signed, hashlib.sha256).hexdigest()[:16], sig)
            or counter <= self.sms_counter
        ):
            return None
        self.sms_counter = counter
        self._sms_times.append(now)
        done = 0
        for item in items:
            key, _, raw_v = item.partition("=")
            if key == "ack":
                self.alarms.clear()
                done += 1
            elif key.startswith("s."):
                done += await self.run_scene(key[2:], "sms")
            else:
                value = (
                    raw_v in ("1", "on", "true")
                    if raw_v in ("0", "1", "on", "off", "true", "false")
                    else float(raw_v)
                )
                done += await self.command_module(key.replace(".", ":", 1), value, 0, "sms")
        return f"OK {done}/{len(items)}"


def sign_sms(sms_key: str, hub_id: str, counter: int, *items: str) -> str:
    """The text an app sends: HUB <counter> <items> <sig>."""
    raw = base64.urlsafe_b64decode(sms_key + "=" * (-len(sms_key) % 4))
    sig = hmac.new(
        raw, " ".join([hub_id, str(counter), *items]).encode(), hashlib.sha256
    ).hexdigest()[:16]
    return " ".join(["HUB", str(counter), *items, sig])


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="python -m simulators.esp_hub")
    p.add_argument("--mqtt", required=True, help="host:port of the server's broker")
    p.add_argument("--hub", required=True)
    p.add_argument("--secret", required=True)
    p.add_argument("--module", action="append", default=[], metavar="ID:SECRET:ALIAS")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    host, _, port = args.mqtt.rpartition(":")

    async def run() -> None:
        hub = EspHubSim(args.hub, args.secret)
        for spec in args.module:
            mid, secret, alias = spec.split(":")
            hub.add_module(
                NativeDeviceSim(mid, secret, {f"relay_{i}": False for i in range(1, 9)}), alias
            )
        await hub.connect_cloud(host, int(port))
        print("hub up; local key:", hub.local_key)
        while True:
            hub.check_modules()
            await hub.tick()
            await asyncio.sleep(1)

    asyncio.run(run())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
