"""Security alerts and RF remotes (0021): a PIR, a door magnet and a smoke detector open alerts
the home sees live, marks seen and clears; an RF module learns remote keys into slots and sends
them, both through the control-safety layer (a native device simulator plays the module)."""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from backend.settings import Settings
from simulators.native_device import NativeDeviceSim
from tests.api.conftest import Backend, make_settings
from tests.api.test_accounts_api import account
from tests.api.test_claims_api import claim, labels, register
from tests.api.test_ingest_api import native_template, running
from tests.api.test_platform_api import PRODUCT, _product, _setup

pytestmark = [pytest.mark.integration, pytest.mark.postgres]


def _input(key: str, name: str, icon: str | None) -> dict[str, Any]:
    return {"key": key, "kind": "digital_input", "display_name": {"fa": name}, "data_type": "bool",
            "ui": {"icon": icon} if icon else {}}


def _param(key: str, role: str, lo: int, hi: int, **extra: Any) -> dict[str, Any]:
    return {"key": key, "kind": "parameter", "display_name": {"en": key}, "data_type": "uint16",
            "access": "read_write", "write_class": "command", "min": lo, "max": hi,
            "ui": {"role": role, "visible": False}} | extra


TAGS = [_input("pir", "چشمی راهرو", "motion"), _input("door", "مگنت در", "magnet"),
        _input("smoke", "دود", "smoke"), _input("garage", "ورودی ۴", None),
        _param("rf_band", "rf_band", 315, 433, states={315: "315 MHz", 433: "433 MHz"}),
        _param("rf_learn", "rf_learn", 1, 3), _param("rf_send", "rf_send", 1, 3),
        {"key": "rf_learnt", "kind": "variable", "display_name": {"en": "learnt"},
         "data_type": "uint16", "ui": {"role": "rf_learnt", "visible": False}}]


@pytest.fixture
def settings() -> Settings:
    return make_settings(signup_enabled=True, public_url="https://hub.test")


async def _device(b: Backend) -> tuple[dict[str, str], dict[str, str], str, str]:
    """(sara, omid, device_id, secret): a module with sensors and an RF part, sara's."""
    h = await _setup(b)
    template = native_template()
    template["tags"] = [*template["tags"], *TAGS]
    template["bindings"]["native"]["tags"] |= {t["key"]: {} for t in TAGS}
    pid = await _product(b, h["alice"], template, body=PRODUCT | {
        "code": "SEC-1", "identifier_pattern": "SEC-{000}"})
    await register(b, h["alice"], pid, 1, protocol="native")
    (row,) = await labels(b, h["alice"], pid, credentials=True)
    sara = await account(b, "sara@example.com", "Sara")
    omid = await account(b, "omid@example.com", "Omid")
    assert (await claim(b, sara, row["identifier"], row["claim_code"])).status_code == 200
    r = await b.client.patch(f"/api/platform/my/devices/{row['device_id']}", headers=sara,
                             json={"enabled": True})
    assert r.status_code == 200, r.text
    return sara, omid, row["device_id"], row["device_secret"]


async def _open(b: Backend, h: dict[str, str]) -> list[dict[str, Any]]:
    r = await b.client.get("/api/platform/my/alerts", headers=h)
    assert r.status_code == 200, r.text
    return r.json()


async def test_alarm_sensors_open_alerts_seen_and_cleared(backend: Backend) -> None:
    from backend.sms import SmsOutbox

    b = backend
    b.services.sms = outbox = SmsOutbox()
    sara, omid, device_id, secret = await _device(b)
    rows = (await b.client.get("/api/account/organizations", headers=sara)).json()
    home = next(m["org_id"] for m in rows if m["personal"])
    await b.client.post(f"/api/platform/organizations/{home}/contacts", headers=sara,
                        json={"name": "Ali", "phone": "09121234567", "sms": True})
    sim = NativeDeviceSim(device_id, secret, {"relay_1": False, "pir": False, "door": False,
                                              "smoke": False, "garage": False})
    alerts = b.services.home_alerts
    stop = asyncio.Event()
    async with running(sim.run_http(b.client, 0.05, stop)):
        await b.wait(lambda: f"platform.devices.{device_id}.pir" in b.services.hub.latest)
        await alerts.refresh()
        kinds = {v[2]: v[3] for v in alerts.watch.values()}
        assert kinds == {"pir": "motion", "door": "magnet", "smoke": "smoke"}   # not garage

        # the burglar alarm is off by default: the PIR only shows its state
        sim.report(pir=True)
        await asyncio.sleep(0.4)
        assert await _open(b, sara) == [] and outbox.sent == []
        sim.report(pir=False)
        await asyncio.sleep(0.2)
        r = await b.client.put(f"/api/platform/organizations/{home}/security", headers=sara,
                               json={"burglar": True})
        assert r.status_code == 200 and r.json()["burglar"] is True, r.text
        assert r.json()["sensors"] == {"motion": 1, "magnet": 1, "smoke": 1}
        assert r.json()["contacts"] == 1

        # armed, the PIR trips: an alert, live on the stream, one SMS to the contacts
        sim.report(pir=True)
        opened = await _wait_alerts(b, sara, 1)
        assert opened[0]["kind"] == "motion" and opened[0]["trips"] == 1
        assert opened[0]["tag_name"] == {"fa": "چشمی راهرو"} and opened[0]["device_name"]
        assert opened[0]["seen_at"] is None
        assert [k for k, _, _ in outbox.sent] == ["sms"] and "چشمی راهرو" in outbox.sent[0][2]
        assert await _open(b, omid) == []                     # not omid's device

        # seen; tripping again counts on the same alert and asks to be seen again
        aid = opened[0]["alert_id"]
        r = await b.client.post(f"/api/platform/my/alerts/{aid}/seen", headers=sara)
        assert r.json() == {"changed": 1}
        assert (await _open(b, sara))[0]["seen_at"] is not None
        sim.report(pir=False)
        await asyncio.sleep(0.2)
        sim.report(pir=True)
        for _ in range(100):
            if (await _open(b, sara))[0]["trips"] >= 2:
                break
            await asyncio.sleep(0.05)
        again = await _open(b, sara)
        assert again[0]["seen_at"] is None and len(outbox.sent) == 1   # no second SMS

        # the home names an input a magnet: it becomes an alarm too
        r = await b.client.put(f"/api/platform/my/devices/{device_id}/labels/garage",
                               headers=sara, json={"name": "در پارکینگ", "icon": "magnet"})
        assert r.status_code == 200, r.text
        await alerts.refresh()
        sim.report(garage=True, smoke=True)
        opened = await _wait_alerts(b, sara, 3)
        named = {a["kind"]: a["tag_name"] for a in opened}
        assert named["magnet"] == {"fa": "در پارکینگ", "en": "در پارکینگ"}   # the home's name
        assert sorted(a["kind"] for a in opened) == ["magnet", "motion", "smoke"]

        # someone else's id is unknown; clear one, then all
        assert (await b.client.post(f"/api/platform/my/alerts/{aid}/clear",
                                    headers=omid)).status_code == 404
        r = await b.client.post(f"/api/platform/my/alerts/{aid}/clear", headers=sara)
        assert r.json() == {"changed": 1} and len(await _open(b, sara)) == 2
        r = await b.client.post("/api/platform/my/alerts/clear", headers=sara)
        assert r.json() == {"changed": 2} and await _open(b, sara) == []
        stop.set()


async def _personal(b: Backend, h: dict[str, str]) -> str:
    rows = (await b.client.get("/api/account/organizations", headers=h)).json()
    return next(m["org_id"] for m in rows if m["personal"])


async def _wait_alerts(b: Backend, h: dict[str, str], n: int) -> list[dict[str, Any]]:
    for _ in range(100):
        rows = await _open(b, h)
        if len(rows) >= n:
            return rows
        await asyncio.sleep(0.05)
    raise AssertionError(f"expected {n} alerts, got {rows}")


async def test_alert_goes_on_the_live_bus(backend: Backend) -> None:
    """The stream (GET /api/platform/my/stream) forwards these as ``event: alert``."""
    b = backend
    sara, _, device_id, secret = await _device(b)
    sim = NativeDeviceSim(device_id, secret, {"pir": False, "door": False, "smoke": False})
    stop = asyncio.Event()
    home = await _personal(b, sara)
    await b.client.put(f"/api/platform/organizations/{home}/security", headers=sara,
                       json={"night": True})               # magnets only
    queue = b.services.hub.bus.subscribe()
    try:
        async with running(sim.run_http(b.client, 0.05, stop)):
            await b.wait(lambda: f"platform.devices.{device_id}.door" in b.services.hub.latest)
            await b.services.home_alerts.refresh()
            sim.report(door=True)
            event: dict[str, Any] = {}
            while event.get("type") != "alert":
                event = await asyncio.wait_for(queue.get(), 10) or {}
            assert event["device_id"] == device_id and event["alert"]["kind"] == "magnet"
            stop.set()
    finally:
        b.services.hub.bus.unsubscribe(queue)


async def test_rf_remote_learn_send_and_limits(backend: Backend) -> None:
    b = backend
    sara, omid, device_id, secret = await _device(b)
    base = f"/api/platform/my/devices/{device_id}/remotes"
    sim = NativeDeviceSim(device_id, secret, {"rf_band": 433, "rf_learnt": 0})
    stop = asyncio.Event()
    async with running(sim.run_http(b.client, 0.05, stop)):
        await b.wait(lambda: f"platform.devices.{device_id}.rf_learnt" in b.services.hub.latest)
        listed = (await b.client.get(base, headers=sara)).json()
        assert listed == {"supported": True, "bands": [315, 433], "slots": 3, "remotes": []}
        assert (await b.client.get(base, headers=omid)).status_code == 404
        assert (await b.client.post(base, headers=sara, json={"name": "x", "band": 868})
                ).json()["error"] == "rf_band"
        remote = (await b.client.post(base, headers=sara, json={"name": "درب پارکینگ",
                                                               "band": 315})).json()
        rid = remote["remote_id"]
        keys = []
        for name in ("باز", "بسته", "توقف"):
            r = await b.client.post(f"{base}/{rid}/keys", headers=sara, json={"name": name})
            assert r.status_code == 201, r.text
            keys.append(r.json())
        assert [k["slot"] for k in keys] == [1, 2, 3]
        r = await b.client.post(f"{base}/{rid}/keys", headers=sara, json={"name": "چهارم"})
        assert r.json()["error"] == "rf_full"

        # not learnt yet: no send; learning switches the module to 315 MHz and slot 1
        k1 = keys[0]["key_id"]
        assert (await b.client.post(f"{base}/{rid}/keys/{k1}/send", headers=sara)
                ).json()["error"] == "rf_not_learnt"
        r = await b.client.post(f"{base}/{rid}/keys/{k1}/learn", headers=sara)
        assert r.json()["result"] == "learnt", r.text
        assert sim.values["rf_band"] == 315 and sim.rf_memory[1].startswith("315:")
        r = await b.client.post(f"{base}/{rid}/keys/{k1}/send", headers=sara)
        assert r.json()["result"] == "applied", r.text
        assert sim.rf_sent == [1]

        # nobody presses a key on the remote: the learning ends without a code
        sim.rf_press_s = None
        from backend.api import alerts as api

        api.LEARN_S, saved = 1.0, api.LEARN_S
        try:
            r = await b.client.post(f"{base}/{rid}/keys/{keys[1]['key_id']}/learn", headers=sara)
        finally:
            api.LEARN_S = saved
        assert r.json()["result"] == "timeout"

        # every learn and send went through the control-safety layer as sara
        writes = [(c["tag"].rsplit(".", 1)[-1], c["value"]) for c in sim.executed]
        assert writes[:3] == [("rf_band", 315), ("rf_learn", 1), ("rf_send", 1)]
        listed = (await b.client.get(base, headers=sara)).json()
        assert [k["learnt_at"] is not None for k in listed["remotes"][0]["keys"]] == \
            [True, False, False]
        stop.set()

    # renaming, deleting; a released device takes its remotes with it
    r = await b.client.put(f"{base}/{rid}/keys/{k1}", headers=sara, json={"name": "باز کن"})
    assert r.json()["name"] == "باز کن"
    assert (await b.client.delete(f"{base}/{rid}/keys/{k1}", headers=sara)).status_code == 204
    assert (await b.client.delete(f"{base}/{rid}/keys/{k1}", headers=sara)).status_code == 404
    r = await b.client.delete(f"/api/platform/my/devices/{device_id}", headers=sara)
    assert r.status_code == 200, r.text
    assert await b.services.store.alerts.remotes(device_id) == []


async def test_device_without_rf_module(backend: Backend) -> None:
    b = backend
    h = await _setup(b)
    pid = await _product(b, h["alice"], native_template(), body=PRODUCT | {
        "code": "NAT-8R", "identifier_pattern": "NAT-{000}"})
    await register(b, h["alice"], pid, 1, protocol="native")
    (row,) = await labels(b, h["alice"], pid, credentials=True)
    sara = await account(b, "sara@example.com", "Sara")
    await claim(b, sara, row["identifier"], row["claim_code"])
    base = f"/api/platform/my/devices/{row['device_id']}/remotes"
    assert (await b.client.get(base, headers=sara)).json() == {
        "supported": False, "bands": [], "slots": 0, "remotes": []}
    assert (await b.client.post(base, headers=sara, json={"name": "x", "band": 433})
            ).status_code == 404


async def test_security_scenarios_decide_and_reach_the_device(backend: Backend) -> None:
    """Night mode: magnets only; the scenarios go to the device with its local rules; only
    people who may operate the home switch them; a guard cut off is an alarm (offline)."""
    from backend import home_alerts

    b = backend
    sara, omid, device_id, secret = await _device(b)
    home = await _personal(b, sara)
    base = f"/api/platform/organizations/{home}/security"
    r = await b.client.get(base, headers=sara)
    assert {k: r.json()[k] for k in ("burglar", "night", "fire", "offline")} == {
        "burglar": False, "night": False, "fire": True, "offline": True}
    assert (await b.client.get(base, headers=omid)).status_code == 404
    assert (await b.client.put(base, headers=omid, json={"burglar": False})).status_code == 404
    r = await b.client.put(base, headers=sara, json={"night": True})
    assert r.json()["night"] is True and r.json()["fire"] is True     # the rest unchanged
    rules = (await b.client.get(f"/api/platform/my/devices/{device_id}/local-rules",
                                headers=sara)).json()
    assert rules["security"] == {"burglar": False, "night": True, "fire": True, "offline": True,
                                 "sirens": []}

    sim = NativeDeviceSim(device_id, secret, {"pir": False, "door": False, "smoke": False})
    stop = asyncio.Event()
    alerts = b.services.home_alerts
    async with running(sim.run_http(b.client, 0.05, stop)):
        await b.wait(lambda: f"platform.devices.{device_id}.pir" in b.services.hub.latest)
        await alerts.refresh()
        assert device_id in alerts.guards
        sim.report(pir=True)                                # people move about: no alarm
        await asyncio.sleep(0.4)
        assert await _open(b, sara) == []
        sim.report(door=True)                               # a door opens at night: alarm
        assert [a["kind"] for a in await _wait_alerts(b, sara, 1)] == ["magnet"]
        stop.set()

    # the device stops talking: after the grace time, a connection-loss alert
    from hub.drivers.base import DeviceState, DeviceStatus

    saved, home_alerts.OFFLINE_S = home_alerts.OFFLINE_S, 0.3
    try:
        alerts.on_status(DeviceStatus(device_id=device_id, state=DeviceState.OFFLINE))
        b.services.hub.statuses[device_id] = DeviceStatus(device_id=device_id,
                                                          state=DeviceState.OFFLINE)
        rows = await _wait_alerts(b, sara, 2)
    finally:
        home_alerts.OFFLINE_S = saved
    offline = next(a for a in rows if a["kind"] == "offline")
    assert offline["device_id"] == device_id and offline["tag_key"] == "connection"
    # back online quickly: no alert (a router restarting)
    await b.client.post(f"/api/platform/my/alerts/{offline['alert_id']}/clear", headers=sara)
    home_alerts.OFFLINE_S = 0.5
    try:
        alerts.on_status(DeviceStatus(device_id=device_id, state=DeviceState.OFFLINE))
        alerts.on_status(DeviceStatus(device_id=device_id, state=DeviceState.ONLINE))
        await asyncio.sleep(0.8)
    finally:
        home_alerts.OFFLINE_S = saved
    assert [a["kind"] for a in await _open(b, sara)] == ["magnet"]


async def test_siren_is_any_output_of_the_home(backend: Backend) -> None:
    """The siren is whichever output the home picks (here relay 1 of the module); a trip of an
    armed zone sounds it through the control layer, "seen" silences it; someone else's output
    or an input cannot be a siren; the device learns which of its outputs is a siren."""
    b = backend
    sara, _, device_id, secret = await _device(b)
    home = await _personal(b, sara)
    base = f"/api/platform/organizations/{home}/security"
    bad = await b.client.put(base, headers=sara, json={"sirens": [{"device_id": device_id,
                                                                   "key": "pir"}]})
    assert bad.json()["error"] == "siren_output"
    bad = await b.client.put(base, headers=sara, json={"sirens": [{"device_id": "dnotmine000",
                                                                   "key": "relay_1"}]})
    assert bad.json()["error"] == "siren_device"
    r = await b.client.put(base, headers=sara, json={
        "burglar": True, "siren_s": 30, "sirens": [{"device_id": device_id, "key": "relay_1"}]})
    assert r.status_code == 200, r.text
    (siren,) = r.json()["sirens"]
    assert (siren["device_id"], siren["key"], siren["name"]) == (device_id, "relay_1", "رله 1")
    assert siren["device_name"]
    assert r.json()["siren_s"] == 30
    rules = (await b.client.get(f"/api/platform/my/devices/{device_id}/local-rules",
                                headers=sara)).json()
    assert rules["security"]["sirens"] == ["relay_1"] and rules["security"]["burglar"] is True

    sim = NativeDeviceSim(device_id, secret, {"relay_1": False, "pir": False, "door": False,
                                              "smoke": False})
    stop = asyncio.Event()
    async with running(sim.run_http(b.client, 0.05, stop)):
        await b.wait(lambda: f"platform.devices.{device_id}.pir" in b.services.hub.latest)
        await b.services.home_alerts.refresh()
        zones = (await b.client.get(base, headers=sara)).json()["zones"]
        assert {(z["key"], z["kind"]) for z in zones} == {("pir", "motion"), ("door", "magnet"),
                                                          ("smoke", "smoke")}
        sim.report(door=True)
        (alert,) = await _wait_alerts(b, sara, 1)
        await b.wait(lambda: sim.values["relay_1"] is True)            # the siren sounds
        await b.client.post(f"/api/platform/my/alerts/{alert['alert_id']}/seen", headers=sara)
        await b.wait(lambda: sim.values["relay_1"] is False)           # seen: it stops
        stop.set()
    writes = [c["tag"].rsplit(".", 1)[-1] for c in sim.executed]
    assert writes == ["relay_1", "relay_1"]                              # on, then off


async def test_alarm_recipients_are_picked_by_name(backend: Backend) -> None:
    """The numbers live in the home's contacts; the security section picks people by name and
    shows no number; only whoever may change the home's settings picks them."""
    b = backend
    sara, omid, _, _ = await _device(b)
    home = await _personal(b, sara)
    base = f"/api/platform/organizations/{home}"
    ids = []
    for name, phone in (("Ali", "09121111111"), ("Mina", "09122222222")):
        r = await b.client.post(f"{base}/contacts", headers=sara,
                                json={"name": name, "phone": phone, "sms": False})
        ids.append(r.json()["contact_id"])
    r = await b.client.put(f"{base}/security/recipients", headers=sara,
                           json={"sms": [ids[1]], "call": [ids[0], ids[1]]})
    assert r.status_code == 200, r.text
    people = {x["name"]: (x["sms"], x["call"]) for x in r.json()["recipients"]}
    assert people == {"Ali": (False, True), "Mina": (True, True)}
    assert "0912" not in r.text and r.json()["contacts"] == 2           # names only
    assert (await b.client.put(f"{base}/security/recipients", headers=sara,
                               json={"sms": [999999]})).status_code == 404
    assert (await b.client.put(f"{base}/security/recipients", headers=omid,
                               json={"sms": ids})).status_code == 404


async def test_member_phone_lives_with_the_member(backend: Backend) -> None:
    """A member's number is set on the home's access page: the members list shows it, it is one
    of the home's contacts (by the member's name) for the alarms; cleared, it goes."""
    b = backend
    sara, omid, _, _ = await _device(b)
    home = await _personal(b, sara)
    base = f"/api/platform/organizations/{home}"
    (me,) = (await b.client.get(f"{base}/members", headers=sara)).json()
    assert me["phone"] is None
    # the same number typed before as a plain contact becomes the member's own
    await b.client.post(f"{base}/contacts", headers=sara,
                        json={"name": "x", "phone": "09125555555"})
    r = await b.client.put(f"{base}/members/{me['user_role_id']}/phone", headers=sara,
                           json={"phone": "+989125555555"})
    assert r.status_code == 200 and r.json()["phone"] == "09125555555", r.text
    (me,) = (await b.client.get(f"{base}/members", headers=sara)).json()
    assert me["phone"] == "09125555555"
    contacts = (await b.client.get(f"{base}/contacts", headers=sara)).json()["contacts"]
    assert [(c["name"], c["member_id"] is not None, c["sms"]) for c in contacts] == [
        ("Sara", True, True)]
    security = (await b.client.get(f"{base}/security", headers=sara)).json()
    names = [x["name"] for x in security["recipients"]]
    assert names == ["Sara"]
    assert (await b.client.put(f"{base}/members/{me['user_role_id']}/phone", headers=omid,
                               json={"phone": "09126666666"})).status_code == 404
    r = await b.client.put(f"{base}/members/{me['user_role_id']}/phone", headers=sara,
                           json={"phone": None})
    assert r.json()["phone"] is None
    assert (await b.client.get(f"{base}/contacts", headers=sara)).json()["contacts"] == []
