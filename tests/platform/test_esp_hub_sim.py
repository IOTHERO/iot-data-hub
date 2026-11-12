"""The ESP32 central hub, end to end with no hardware: a real MQTT broker (the server's side), the
hub model (simulators/esp_hub.py) and native module simulators (the Relay-8 contract).

What matters most: when the server is gone the hub keeps the building working (scenes, phone,
SMS), and it tells the server afterwards."""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any

import aiomqtt
import pytest

from hub import jalali
from hub.platform.local_sign import sign
from simulators.esp_hub import EspHubSim, sign_sms
from simulators.mqtt_sim import EmbeddedBroker
from simulators.native_device import NativeDeviceSim

HUB, M1, M2 = "hub_test_01", "d_m1_aaaaaaaaaaaaaaaa", "d_m2_bbbbbbbbbbbbbbbb"


def relays(**on: bool) -> dict[str, Any]:
    return {f"relay_{i}": on.get(f"relay_{i}", False) for i in range(1, 9)}


class Clock:
    """Hub time in UTC seconds, set by the test (a time scene needs a time of day)."""

    def __init__(self, local: str, offset_min: int = 210) -> None:
        self.t = datetime.fromisoformat(local).replace(tzinfo=UTC).timestamp() - offset_min * 60

    def __call__(self) -> float:
        return self.t


@pytest.fixture
async def broker() -> AsyncIterator[EmbeddedBroker]:
    async with EmbeddedBroker() as b:
        yield b


@pytest.fixture
def hub() -> EspHubSim:
    h = EspHubSim(HUB, "s3cret", clock=Clock("2026-11-12T10:00:00"))
    h.add_module(NativeDeviceSim(M1, "x", relays()), "m1")
    h.add_module(NativeDeviceSim(M2, "y", relays()), "m2")
    h.contacts = [{"number": "+989121234567", "name": "Manager", "commands": True, "alarms": True}]
    return h


async def next_message(client: aiomqtt.Client, kind: str, timeout: float = 5) -> dict[str, Any]:
    async def wait() -> dict[str, Any]:
        async for m in client.messages:
            if str(m.topic).endswith("/" + kind):
                return json.loads(m.payload)
        raise AssertionError("closed")

    return await asyncio.wait_for(wait(), timeout)


async def test_hub_is_one_device_for_the_server_and_forwards_module_messages(
    broker: EmbeddedBroker, hub: EspHubSim
) -> None:
    async with aiomqtt.Client(broker.host, broker.port) as server:
        await server.subscribe(f"h/{HUB}/#", qos=1)
        await hub.connect_cloud(broker.host, broker.port)
        try:
            assert (await next_message(server, "state"))["state"] == "online"
            up = await next_message(server, "up")
            assert up["d"] in (M1, M2) and up["k"] in ("state", "telemetry")
            hub.modules[M1].values["relay_3"] = True  # a module reports a change
            await hub.module_message(M1, "telemetry", {"values": {"relay_3": True}})
            while True:
                up = await next_message(server, "up")
                if up["k"] == "telemetry" and up["p"]["values"].get("relay_3") is True:
                    assert up["d"] == M1
                    break
        finally:
            await hub.disconnect_cloud()


async def test_server_command_reaches_the_module_and_the_ack_goes_up(
    broker: EmbeddedBroker, hub: EspHubSim
) -> None:
    async with aiomqtt.Client(broker.host, broker.port) as server:
        await server.subscribe(f"h/{HUB}/up", qos=1)
        await hub.connect_cloud(broker.host, broker.port)
        try:
            cmd = {
                "type": "cmd",
                "d": M2,
                "p": {"command_id": "c1", "tag": "relay_5", "value": True},
            }
            await server.publish(f"h/{HUB}/down", json.dumps(cmd), qos=1)
            while True:
                up = await next_message(server, "up")
                if up["k"] == "ack" and up["p"].get("status") == "done":
                    assert up["d"] == M2 and up["p"]["command_id"] == "c1"
                    break
            assert hub.modules[M2].values["relay_5"] is True
            assert hub.modules[M1].values["relay_5"] is False  # only the addressed module
        finally:
            await hub.disconnect_cloud()


async def test_server_can_replace_scenes_hub_settings_and_run_a_scene(
    broker: EmbeddedBroker, hub: EspHubSim
) -> None:
    scene = {
        "id": "all_off",
        "enabled": True,
        "trigger": {"type": "manual"},
        "actions": [{"type": "write", "device": "m1", "tag": "relay_1", "value": False}],
    }
    hub.modules[M1].values["relay_1"] = True
    async with aiomqtt.Client(broker.host, broker.port) as server:
        await server.subscribe(f"h/{HUB}/scene_log", qos=1)
        await hub.connect_cloud(broker.host, broker.port)
        try:
            for msg in (
                {"type": "scenes", "scenes": [scene]},
                {"type": "hubconfig", "utc_offset_min": 0, "holidays": ["1405/08/21"]},
                {"type": "scene_run", "id": "all_off"},
            ):
                await server.publish(f"h/{HUB}/down", json.dumps(msg), qos=1)
            log = await next_message(server, "scene_log")
            assert log["entries"][0]["scene"] == "all_off" and log["entries"][0]["by"] == "server"
            assert hub.offset_min == 0 and hub.holidays == ["1405/08/21"]
            assert hub.modules[M1].values["relay_1"] is False
        finally:
            await hub.disconnect_cloud()


async def test_scenes_keep_running_without_the_server_and_are_reported_afterwards(
    broker: EmbeddedBroker, hub: EspHubSim
) -> None:
    clock = hub.clock
    assert isinstance(clock, Clock)
    hub.put_scenes(
        [
            {
                "id": "evening",
                "enabled": True,
                "trigger": {"type": "time", "at": "18:30"},
                "actions": [{"type": "write", "device": "m1", "tag": "relay_1", "value": True}],
            }
        ]
    )
    assert not hub.cloud_up  # never connected: the internet is gone
    clock.t += 8 * 3600 + 30 * 60  # 18:30 local
    assert await hub.tick() == ["evening"]
    assert hub.modules[M1].values["relay_1"] is True
    assert await hub.tick() == []  # once per matching minute
    async with aiomqtt.Client(broker.host, broker.port) as server:
        await server.subscribe(f"h/{HUB}/scene_log", qos=1)
        await hub.connect_cloud(broker.host, broker.port)  # the server is back
        try:
            log = await next_message(server, "scene_log")
            assert [e["scene"] for e in log["entries"]] == ["evening"]
        finally:
            await hub.disconnect_cloud()


async def test_silent_module_raises_an_alarm_sms_and_an_event_scene(hub: EspHubSim) -> None:
    hub.put_scenes(
        [
            {
                "id": "lost",
                "enabled": True,
                "trigger": {"type": "event", "event": "module_offline"},
                "actions": [{"type": "sms", "text": "Module offline"}],
            }
        ]
    )
    clock = hub.clock
    assert isinstance(clock, Clock)
    clock.t += 120  # no message for two minutes (limit 90 s)
    hub.check_modules()
    assert f"module_{M1}" in hub.alarms
    assert (
        await hub.tick() == ["lost", "lost"] or await hub.tick() == []
    )  # one run per module event
    assert ("+989121234567", f"Module offline: {M1}") in hub.sent
    await hub.module_message(M1, "telemetry", {"values": {}})  # it comes back
    assert f"module_{M1}" not in hub.alarms and hub.online[M1]


async def test_calendar_skips_holidays_and_follows_the_jalali_months(hub: EspHubSim) -> None:
    scene = {
        "id": "work",
        "enabled": True,
        "trigger": {"type": "time", "at": "07:00"},
        "calendar": {"months": [8], "holidays": "skip"},
        "actions": [{"type": "write", "device": "m1", "tag": "relay_2", "value": True}],
    }
    hub.put_scenes([scene])
    clock = hub.clock
    assert isinstance(clock, Clock)
    assert jalali.to_jalali(datetime(2026, 11, 12, tzinfo=UTC).date()) == (1405, 8, 21)
    hub.holidays = ["1405/08/21"]
    clock.t = Clock("2026-11-12T07:00:00").t
    assert await hub.tick() == []  # an extra holiday: skipped
    hub.holidays = []
    hub.put_scenes([scene])  # a new scene list starts the minute over
    assert await hub.tick() == ["work"]  # an ordinary day in Aban (month 8)
    hub.put_scenes([{**scene, "calendar": {"months": [9]}}])
    clock.t = Clock("2026-11-13T07:00:00").t
    assert await hub.tick() == []  # Aban is not Azar
    hub.put_scenes([{**scene, "calendar": {"holidays": "skip"}}])
    clock.t = Clock("2027-03-21T07:00:00").t  # 1406/01/01: Nowruz is a built-in holiday
    assert await hub.tick() == []


async def local_call(
    hub: EspHubSim, tag: str, value_json: str, key: str | None = None
) -> tuple[int, dict[str, Any]]:
    _, n = await hub.local_request("GET", "/local/v1/nonce", None)
    sig = sign(key or hub.local_key, HUB, n["nonce"], "command", tag, value_json)
    return await hub.local_request(
        "POST",
        "/local/v1/command",
        {"nonce": n["nonce"], "tag": tag, "value_json": value_json, "sig": sig},
    )


async def test_phone_controls_modules_through_the_hub_with_no_server(hub: EspHubSim) -> None:
    assert not hub.cloud_up
    code, body = await local_call(hub, "m1:relay_4", "true")
    assert (code, body) == (200, {"ok": True}) and hub.modules[M1].values["relay_4"] is True
    code, _ = await local_call(hub, "m1:relay_4", "false", key="A" * 43)  # wrong key
    assert code == 401 and hub.modules[M1].values["relay_4"] is True
    _, n = await hub.local_request("GET", "/local/v1/nonce", None)  # a replayed nonce
    sig = sign(hub.local_key, HUB, n["nonce"], "state")
    assert (await hub.local_request("POST", "/local/v1/state", {"nonce": n["nonce"], "sig": sig}))[
        0
    ] == 200
    assert (await hub.local_request("POST", "/local/v1/state", {"nonce": n["nonce"], "sig": sig}))[
        0
    ] == 401
    code, state = await hub.local_request("POST", "/local/v1/state", await _signed_state(hub))
    assert code == 200 and {m["id"] for m in state["modules"]} == {M1, M2}


async def _signed_state(hub: EspHubSim) -> dict[str, str]:
    _, n = await hub.local_request("GET", "/local/v1/nonce", None)
    return {"nonce": n["nonce"], "sig": sign(hub.local_key, HUB, n["nonce"], "state")}


async def test_phone_edits_scenes_and_runs_one_through_the_hub(hub: EspHubSim) -> None:
    scenes = [
        {
            "id": "dark",
            "enabled": True,
            "trigger": {"type": "manual"},
            "actions": [{"type": "write", "device": "m2", "tag": "relay_6", "value": True}],
        }
    ]
    assert (await local_call(hub, "scenes:put", json.dumps(scenes)))[0] == 200
    assert (await local_call(hub, "scene:dark", "true"))[0] == 200
    assert hub.modules[M2].values["relay_6"] is True
    assert (await local_call(hub, "scene:nope", "true"))[0] == 400


async def test_signed_sms_controls_the_hub_from_an_allowed_number_only(hub: EspHubSim) -> None:
    number = "+989121234567"
    text = sign_sms(hub.sms_key, HUB, 100, "m1.relay_1=1", "m2.relay_2=1")
    assert await hub.sms(number, text) == "OK 2/2"
    assert hub.modules[M1].values["relay_1"] is True and hub.modules[M2].values["relay_2"] is True
    assert await hub.sms(number, text) is None  # replayed: nothing
    assert (
        await hub.sms("+989000000000", sign_sms(hub.sms_key, HUB, 101, "m1.relay_1=0")) is None
    )  # stranger
    assert await hub.sms(number, sign_sms("B" * 43, HUB, 102, "m1.relay_1=0")) is None  # wrong key
    assert hub.modules[M1].values["relay_1"] is True
    for i in range(110, 120):  # at most 5 in 10 minutes
        await hub.sms(number, sign_sms(hub.sms_key, HUB, i, "ack"))
    assert len(hub._sms_times) == 5  # noqa: SLF001
