"""Security alerts of the homes (migrations 0021, 0022): a motion sensor (a hallway PIR), a door
or window magnet and a smoke detector are a burglar / fire alarm wherever they are - while the
home's security scenario for them is on:

* burglar (away from home): motion and magnets;  night (at home): magnets only;
* fire: smoke (on unless the home turns it off);
* offline: a device that guards the home (one with alarm sensors, or an edge hub) cut off from
  the server for ``OFFLINE_S``: the home cannot tell anyone itself, so the server does.

Zones and the siren are not fixed pins: any on/off input of any module is a zone by its type,
and the siren is whichever outputs of whichever modules the home picked (an 8-output module's
relay 3, while the zones are wired to an 8-input module). The siren sounds for the home's siren
time on every trip and stops when someone marks the alarm seen; it is switched through the
control-safety layer as the person who last set the home's security.

The hub hands every batch of samples to :meth:`HomeAlerts.on_samples` (``Hub.sample_hooks``):
a dictionary lookup per sample, nothing more, unless a watched sensor goes from idle to tripped.
Device states come through ``Hub.status_hooks`` (rare). Then the alert is opened (or counted on
the open one, which must be seen again), published on the live bus for the apps
(``{"type": "alert"}``) and, for a new alert, the home's SMS / call contacts are told (the SMS
gateway retries on its own). The people of the home mark it seen and clear it
(backend/api/alerts.py). A tripped sensor whose scenario is off only shows its state.

Which sensors: on/off inputs whose icon - the home's own (output_labels) or the template's -
is motion, magnet or smoke. The list is refreshed every minute and when asked (a label saved,
a device claimed, a scenario switched).
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import Iterable
from datetime import datetime
from typing import Any

from hub.drivers.base import DeviceState, DeviceStatus
from hub.models import Quality, Sample
from hub.platform.devices import platform_tag_path
from hub.platform.template import TagKind
from hub.storage.alerts import security_default

log = logging.getLogger(__name__)

KINDS = ("motion", "magnet", "smoke")
# which scenario makes a sensor of this kind an alarm
SCENARIOS = {"motion": ("burglar",), "magnet": ("burglar", "night"), "smoke": ("fire",),
             "offline": ("offline",)}
REFRESH_S = 60
OFFLINE_S = 180.0              # cut off this long before the home is told (a router restarts)
TEXT = {"motion": "هشدار دزدگیر: حرکت در {name}", "magnet": "هشدار دزدگیر: باز شدن {name}",
        "smoke": "هشدار حریق: دود در {name}",
        "offline": "قطع ارتباط: {name} به سرور وصل نیست"}


class HomeAlerts:
    def __init__(self, services: Any) -> None:
        self.svc = services
        # tag path -> (owner home, device id, tag key, kind, the sensor's name)
        self.watch: dict[str, tuple[str, str, str, str, str]] = {}
        # device id -> (owner home, its name): the devices whose connection guards the home
        self.guards: dict[str, tuple[str, str]] = {}
        self.modes: dict[str, dict[str, Any]] = {}          # home -> its security record
        self._sirens: dict[str, asyncio.Task[None]] = {}    # home -> the siren's switch-off
        self._switching_on: dict[str, int] = {}   # home -> siren "on" commands not answered yet
        self._last: dict[str, bool] = {}
        self._task: asyncio.Task[None] | None = None
        self._jobs: set[asyncio.Task[Any]] = set()
        self._cut: dict[str, asyncio.Task[None]] = {}       # device -> its offline countdown
        self._stale = asyncio.Event()

    async def start(self) -> None:
        await self.refresh()
        if self.on_samples not in self.svc.hub.sample_hooks:
            self.svc.hub.sample_hooks.append(self.on_samples)
        if self.on_status not in self.svc.hub.status_hooks:
            self.svc.hub.status_hooks.append(self.on_status)
        self._task = asyncio.create_task(self._loop(), name="home-alerts")

    async def stop(self) -> None:
        for hooks, fn in ((self.svc.hub.sample_hooks, self.on_samples),
                          (self.svc.hub.status_hooks, self.on_status)):
            with contextlib.suppress(ValueError):
                hooks.remove(fn)
        if self._task is not None:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
            self._task = None
        for task in [*self._cut.values(), *self._sirens.values()]:
            task.cancel()
        self._cut.clear()
        self._sirens.clear()
        for job in list(self._jobs):
            with contextlib.suppress(Exception):
                await job

    def changed(self) -> None:
        """Labels, owners or scenarios changed: refresh soon."""
        self._stale.set()

    def scenarios(self, org_id: str) -> dict[str, Any]:
        return self.modes.get(org_id) or security_default()

    def armed(self, org_id: str, kind: str) -> bool:
        modes = self.scenarios(org_id)
        return any(modes.get(m, False) for m in SCENARIOS.get(kind, ()))

    def set_scenarios(self, org_id: str, record: dict[str, Any]) -> None:
        self.modes[org_id] = dict(record)

    async def _loop(self) -> None:
        while True:
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(self._stale.wait(), REFRESH_S)
            self._stale.clear()
            try:
                await self.refresh()
            except Exception:  # noqa: BLE001 - the next round tries again
                log.exception("could not refresh the watched sensors")

    async def refresh(self) -> None:
        store = self.svc.store
        devices = await store.alerts.owned_devices()
        labels = await store.home.labels(sorted({d["org_id"] for d in devices})) if devices else {}
        watch: dict[str, tuple[str, str, str, str, str]] = {}
        guards: dict[str, tuple[str, str]] = {}
        for d in devices:
            if d["edge_hub"]:
                guards[d["device_id"]] = (d["org_id"], d["name"])
            try:
                template = await store.platform.template(d["product_id"], d["version"])
            except Exception:  # noqa: BLE001  # nosec B112 - a broken template only loses its sensors
                continue
            for t in template.tags:
                if t.kind is not TagKind.DIGITAL_INPUT or t.data_type != "bool":
                    continue
                label = labels.get((d["device_id"], t.key))
                icon = (label.icon if label and label.icon else None) or t.ui.icon
                if icon in KINDS:
                    name = (label.name if label and label.name else None) or \
                        t.display_name.get("fa") or t.display_name.get("en") or t.key
                    watch[platform_tag_path(d["device_id"], t.key)] = (
                        d["org_id"], d["device_id"], t.key, icon, name)
                    guards[d["device_id"]] = (d["org_id"], d["name"])
        for path in watch.keys() - self.watch.keys():         # newly watched: its state now
            sample = self.svc.hub.latest.get(path)
            self._last[path] = bool(sample and sample.value is True)
        for path in self.watch.keys() - watch.keys():
            self._last.pop(path, None)
        self.watch = watch
        self.guards = guards
        self.modes = await store.alerts.security()

    def on_samples(self, samples: Iterable[Sample]) -> None:
        """Hot path: only a watched sensor going from idle to tripped does any work."""
        watch = self.watch
        if not watch:
            return
        for s in samples:
            found = watch.get(s.tag)
            if found is None or s.quality is Quality.BAD:
                continue
            on = s.value is True
            was = self._last.get(s.tag, True)       # unknown: do not alarm on start-up
            self._last[s.tag] = on
            if on and not was and self.armed(found[0], found[3]):
                self._spawn(self._trip(found, s.timestamp))

    def on_status(self, status: DeviceStatus) -> None:
        """A guarding device went offline: count down; back online: stop counting."""
        found = self.guards.get(status.device_id)
        if found is None:
            return
        if status.state is DeviceState.ONLINE:
            task = self._cut.pop(status.device_id, None)
            if task is not None:
                task.cancel()
        elif status.device_id not in self._cut:
            self._cut[status.device_id] = asyncio.create_task(
                self._cut_off(status.device_id, found), name=f"cut-off:{status.device_id}")

    async def _cut_off(self, device_id: str, found: tuple[str, str]) -> None:
        try:
            await asyncio.sleep(OFFLINE_S)
            current = self.svc.hub.statuses.get(device_id)
            org_id, name = found
            if (current is not None and current.state is DeviceState.ONLINE) or \
                    not self.armed(org_id, "offline"):
                return
            await self._trip((org_id, device_id, "connection", "offline", name),
                             self.svc.hub.clock())
        finally:
            if self._cut.get(device_id) is asyncio.current_task():
                self._cut.pop(device_id, None)

    def _spawn(self, coro: Any) -> None:
        job = asyncio.create_task(coro)
        self._jobs.add(job)
        job.add_done_callback(self._jobs.discard)

    async def _trip(self, found: tuple[str, str, str, str, str], at: datetime) -> None:
        org_id, device_id, key, kind, name = found
        try:
            alert = await self.svc.store.alerts.trip(org_id, device_id, key, kind, at)
        except Exception:  # noqa: BLE001 - logged; the sensor's state is still on the screen
            log.exception("could not open the alert of %s.%s", device_id, key)
            return
        self.svc.hub.bus.publish({"type": "alert", "device_id": device_id,
                                  "alert": alert.model_dump(mode="json")})
        if kind != "offline":
            self._spawn(self.sound(org_id))       # every trip: the siren sounds (again)
        if alert.trips == 1:
            await self._tell_contacts(org_id, TEXT[kind].format(name=name))

    # --- the siren: whichever outputs of the home's modules the home picked --------------------

    async def _siren(self, org_id: str, on: bool) -> int:
        """Switch the home's siren outputs, through the control-safety layer as the person who
        last set the home's security (a real user, like a schedule); returns how many obeyed."""
        record = self.scenarios(org_id)
        if not record.get("sirens") or record.get("updated_by") is None:
            return 0
        who = await self.svc.automations._creator(record["updated_by"])
        if who is None:
            log.warning("siren of %s: the person who set it up can no longer sign in", org_id)
            return 0
        done = 0
        for x in record["sirens"]:
            path = platform_tag_path(x["device_id"], x["key"])
            try:
                result = await self.svc.control.request_write(
                    who, path, on, "alarm: siren " + ("on" if on else "off"), None)
                done += result.result == "applied"
                if result.result != "applied":
                    log.warning("siren %s %s: %s", path, on, result.result)
            except Exception:  # noqa: BLE001 - one siren failing must not stop the others
                log.exception("siren %s could not be switched", path)
        return done

    async def sound(self, org_id: str) -> None:
        """Siren on now, off after the home's siren time (or when someone marks it seen)."""
        if not self.scenarios(org_id).get("sirens"):
            return
        old = self._sirens.pop(org_id, None)
        if old is not None:
            old.cancel()

        async def later() -> None:
            await asyncio.sleep(float(self.scenarios(org_id).get("siren_s", 180)))
            if self._sirens.get(org_id) is asyncio.current_task():
                self._sirens.pop(org_id, None)
            await self._siren(org_id, False)

        # sounding from now on, before the "on" command is answered: a "seen" that comes while
        # the device is still confirming must find it and stop it
        task = asyncio.create_task(later(), name=f"siren:{org_id}")
        self._sirens[org_id] = task
        self._switching_on[org_id] = self._switching_on.get(org_id, 0) + 1
        try:
            await self._siren(org_id, True)
        finally:
            left = self._switching_on.pop(org_id, 1) - 1
            if left:
                self._switching_on[org_id] = left
        if org_id not in self._sirens and org_id not in self._switching_on:   # silenced meanwhile
            await self._siren(org_id, False)

    async def silence(self, org_id: str) -> None:
        """Someone saw the alarm (or cleared it): the siren stops."""
        task = self._sirens.pop(org_id, None)
        if task is None:
            return
        task.cancel()
        if org_id in self._switching_on:          # sound() switches it off once "on" is answered
            return
        await self._siren(org_id, False)

    async def _tell_contacts(self, org_id: str, text: str) -> None:
        if self.svc.sms is None:
            return
        try:
            contacts = await self.svc.store.home.contacts(org_id)
            for c in contacts[:10]:
                if c.sms:
                    await self.svc.sms.send(c.phone, text)
                if c.call:
                    await self.svc.sms.call(c.phone, text)
        except Exception:  # noqa: BLE001 - the alert stands even when no SMS goes out
            log.exception("alert SMS / call to the contacts of %s failed", org_id)
