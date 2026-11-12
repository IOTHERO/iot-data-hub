"""Modules behind an ESP32 central hub (firmware/esp32-hub; contract in docs/fa/platform/
esp32-hub-for-opc-server.md).

A module (DEVICE 8DO / Relay-8 or any native device) works in one of two ways, and may switch
between them at any time:

* **standalone**: it signs in to the platform broker itself and uses ``d/<device_id>/...``;
* **behind a hub**: it talks to the hub on the building's LAN / Wi-Fi, and the hub, signed in as
  ONE device, carries its messages in an envelope:

      hub -> server  h/<hub_id>/state      retained {"state": "online|offline", ...}
                     h/<hub_id>/up         {"d": "<module>", "k": "telemetry|state|ack|..", "p": {}}
                     h/<hub_id>/alarm      {"code", "text", "at", "active"}
                     h/<hub_id>/scene_log  {"entries": [{"at", "scene", "by"}]}
      server -> hub  h/<hub_id>/down       {"type": "cmd|rules|config|ota", "d": "<id>", "p": {}}
                                           {"type": "time", "server_time": "<ISO UTC>"}

A hub may relay a module only when both have the same owner (the same home): a hub cannot speak
for someone else's device. The module keeps its own identity, tags, history and commands; only
the path changes. Whichever path a module used last is the one its commands take.
"""

from __future__ import annotations

import logging
import re
import time
from collections import deque
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

log = logging.getLogger(__name__)
ALLOW_CACHE_S = 60
UP_KINDS = ("telemetry", "state", "ack", "pairing", "local_log", "ota_status")
MAX_LOG = 100


def alias_of(identifier: str, used: set[str]) -> str:
    """A short name for SMS / the hub portal (lowercase letters and digits, at most 8): the end
    of the identifier (R8-000123 -> r8000123), made unique with a digit if needed."""
    base = re.sub(r"[^a-z0-9]", "", identifier.lower())[-8:] or "m"
    alias, n = base, 1
    while alias in used:
        n += 1
        alias = (base[: 8 - len(str(n))] + str(n))
    return alias


class HubRelay:
    def __init__(self, ingest: Any) -> None:
        self.ingest = ingest
        self.via: dict[str, str] = {}               # module id -> the hub it was last seen behind
        self.status: dict[str, dict[str, Any]] = {}      # hub id -> state, alarms, scene log
        self._allowed: dict[tuple[str, str], tuple[bool, float]] = {}
        self.counters = {"up": 0, "down": 0, "refused": 0}

    # --- who may relay whom -------------------------------------------------------------------

    async def allowed(self, hub_id: str, module_id: str) -> bool:
        key = (hub_id, module_id)
        now = time.monotonic()
        hit = self._allowed.get(key)
        if hit and hit[1] > now:
            return hit[0]
        owners = await self.ingest.svc.store.accounts.owner_orgs([hub_id, module_id])
        ok = hub_id != module_id and owners.get(hub_id) is not None \
            and owners.get(hub_id) == owners.get(module_id)
        self._allowed[key] = (ok, now + ALLOW_CACHE_S)
        if len(self._allowed) > 50_000:
            self._allowed.clear()
        return ok

    def forget(self, device_id: str) -> None:
        """Ownership changed (a reset, a new owner): ask again."""
        for key in [k for k in self._allowed if device_id in k]:
            del self._allowed[key]
        self.via.pop(device_id, None)

    def hub_online(self, hub_id: str) -> bool:
        return self.status.get(hub_id, {}).get("state") == "online"

    def route(self, module_id: str) -> str | None:
        """The hub a command for this module goes through, or None (standalone)."""
        hub_id = self.via.get(module_id)
        if hub_id is None or not self.hub_online(hub_id):
            return None
        if self.ingest.seen_via.get(module_id) != "hub":
            return None                                   # it came back on its own since
        return hub_id

    def _hub(self, hub_id: str) -> dict[str, Any]:
        return self.status.setdefault(hub_id, {"state": "offline", "alarms": {},
                                               "scene_log": deque(maxlen=MAX_LOG),
                                               "relayed": set()})

    # --- hub -> server ------------------------------------------------------------------------

    async def message(self, hub_id: str, kind: str, data: Any) -> None:
        hub_driver = self.ingest.driver(hub_id)
        if hub_driver is None:
            self.counters["refused"] += 1
            return
        if not isinstance(data, dict):
            raise ValueError("hub messages are JSON objects")
        status = self._hub(hub_id)
        if kind != "state" or data.get("state") == "online":
            await hub_driver.touch()                      # any message keeps the hub online
        if kind == "state":
            await self._state(hub_id, hub_driver, status, data)
        elif kind == "up":
            await self._up(hub_id, status, data)
        elif kind == "alarm":
            code = str(data.get("code") or "")[:64]
            if not code:
                raise ValueError("alarm needs a code")
            if data.get("active", True):
                status["alarms"][code] = {"text": str(data.get("text") or "")[:200],
                                          "at": data.get("at")}
                log.warning("hub %s alarm %s: %s", hub_id, code, data.get("text"))
            else:
                status["alarms"].pop(code, None)
            await self._hub_values(hub_driver, status)
        elif kind == "scene_log":
            entries = data.get("entries")
            if isinstance(entries, list):
                for e in entries[:MAX_LOG]:
                    if isinstance(e, dict):
                        status["scene_log"].append({k: e.get(k) for k in ("at", "scene", "by")})
        elif kind == "ack":
            pass                                          # reserved for hub-level commands
        else:
            raise ValueError(f"unknown hub message {kind}")

    async def _state(self, hub_id: str, driver: Any, status: dict[str, Any],
                     data: dict[str, Any]) -> None:
        was = status["state"]
        status["state"] = "online" if data.get("state") == "online" else "offline"
        for key, name in (("firmware", "firmware"), ("local_addr", "local_addr"),
                          ("modules", "module_count"), ("online", "online_count"),
                          ("time_ok", "time_ok")):
            if key in data:
                status[name] = data[key]
        status["seen_at"] = self.ingest.clock().isoformat()
        await self.ingest.state(driver, data)
        await self._hub_values(driver, status)
        if status["state"] == "online" and was != "online":
            await self.welcome(hub_id)
        if status["state"] == "offline":
            for module_id in [m for m, h in self.via.items() if h == hub_id]:
                module = self.ingest.driver(module_id)
                if module is not None and self.ingest.seen_via.get(module_id) == "hub":
                    await module.state({"state": "offline"})

    async def welcome(self, hub_id: str) -> None:
        """A hub that has just come (back): the time (its RTC may have drifted), the devices it
        may let in (the home's own, by the SHA-256 of their secret) and its phone key."""
        await self.down(hub_id, {"type": "time", "server_time": self.ingest.clock().isoformat()})
        try:
            await self.down(hub_id, {"type": "registry",
                                     "modules": await self.registry(hub_id)})
            await self.push_hubconfig(hub_id)
        except Exception:                         # noqa: BLE001 - the hub keeps what it has
            log.exception("hub %s: registry / settings not sent", hub_id)

    async def registry(self, hub_id: str) -> list[dict[str, Any]]:
        owners = await self.ingest.svc.store.accounts.owner_orgs([hub_id])
        owner = owners.get(hub_id)
        if owner is None:
            return []
        rows = await self.ingest.svc.store.claims.hub_registry(owner, hub_id)
        out, used = [], set()
        for r in rows:
            if self.ingest.driver(r["device_id"]) is None:
                continue                              # not claimed / not switched on
            alias = alias_of(r["identifier"], used)
            used.add(alias)
            out.append({"id": r["device_id"], "secret_sha256": r["secret_hash"],
                        "name": r["identifier"][:31], "alias": alias})
        return out[:32]                               # the hub holds 32 modules

    async def push_hubconfig(self, hub_id: str) -> None:
        """The hub's local key for the phones (backend.local) and the time zone."""
        keys = await self.ingest.svc.local.ensure([hub_id])
        await self.send_hubconfig(hub_id, self.ingest.svc.local.config(keys.get(hub_id)))

    async def send_hubconfig(self, hub_id: str, local: dict[str, Any]) -> None:
        offset = datetime.now(ZoneInfo(self.ingest.svc.settings.timezone)).utcoffset()
        await self.down(hub_id, {"type": "hubconfig", "local": local,
                                 "utc_offset_min": int(offset.total_seconds() // 60)
                                 if offset is not None else 210})

    async def scenes(self, hub_id: str, scenes: list[dict[str, Any]]) -> None:
        """The owner's scenes for the hub. The hub runs them (also with no internet); the
        server never runs the same scenes itself (no double run)."""
        self._hub(hub_id)["scenes"] = scenes
        await self.down(hub_id, {"type": "scenes", "scenes": scenes})

    async def run_scene(self, hub_id: str, scene_id: str) -> None:
        await self.down(hub_id, {"type": "scene_run", "id": scene_id})

    async def _hub_values(self, driver: Any, status: dict[str, Any]) -> None:
        """The hub's own tags (firmware/esp32-hub/product-template.json), where its product has
        them: modules online / total and active alarms."""
        values = {"modules_online": status.get("online_count"),
                  "modules_total": status.get("module_count"),
                  "alarms_active": len(status["alarms"])}
        known = {t.name for t in driver.device.tags}
        values = {k: v for k, v in values.items() if k in known and isinstance(v, int)}
        if values:
            try:
                await self.ingest.telemetry(driver, {"values": values})
            except ValueError:
                pass

    async def _up(self, hub_id: str, status: dict[str, Any], data: dict[str, Any]) -> None:
        module_id, kind, payload = str(data.get("d") or ""), data.get("k"), data.get("p")
        if kind not in UP_KINDS or not module_id:
            raise ValueError("up is {d, k, p}")
        if not await self.allowed(hub_id, module_id):
            self.counters["refused"] += 1
            log.info("hub %s may not relay %s (another owner)", hub_id, module_id)
            return
        if kind == "pairing":
            self.ingest.svc.claims.pairing_started(module_id)
            return
        driver = self.ingest.driver(module_id)
        if driver is None:
            self.counters["refused"] += 1
            return
        self.counters["up"] += 1
        self.via[module_id] = hub_id
        self.ingest.seen_via[module_id] = "hub"
        status["relayed"].add(module_id)
        payload = payload if isinstance(payload, dict) else {}
        if kind == "telemetry":
            await self.ingest.telemetry(driver, payload)
        elif kind == "state":
            await self.ingest.state(driver, payload)
        elif kind == "ack":
            await self.ingest.ack(driver, payload, "hub")
        elif kind == "ota_status":
            await self.ingest.ota(driver, payload)
        elif kind == "local_log":
            await self.ingest.svc.local.report_log(module_id, payload.get("entries"))

    # --- server -> hub ------------------------------------------------------------------------

    async def down(self, hub_id: str, message: dict[str, Any]) -> None:
        mqtt = self.ingest.mqtt
        if mqtt is None or not mqtt.connected:
            raise ConnectionError("platform broker not connected")
        self.counters["down"] += 1
        await mqtt.publish(f"h/{hub_id}/down", message)

    async def to_module(self, hub_id: str, module_id: str, kind: str,
                        payload: dict[str, Any]) -> None:
        await self.down(hub_id, {"type": kind, "d": module_id, "p": payload})

    def summary(self, hub_id: str) -> dict[str, Any]:
        s = self.status.get(hub_id)
        if s is None:
            return {"state": "unknown", "modules": [], "alarms": [], "scene_log": [],
                    "scenes": []}
        return {"state": s["state"], "firmware": s.get("firmware"),
                "scenes": s.get("scenes", []),
                "local_addr": s.get("local_addr"), "seen_at": s.get("seen_at"),
                "module_count": s.get("module_count"), "online_count": s.get("online_count"),
                "modules": sorted(m for m in s["relayed"] if self.via.get(m) == hub_id),
                "alarms": [{"code": c} | a for c, a in s["alarms"].items()],
                "scene_log": list(s["scene_log"])[-20:]}
