"""A DEVICE 8DO behind the ESP32 central hub, and the same device standalone, end to end: the
server (MqttIngest + HubRelay), a real MQTT broker, the hub's reference model
(simulators.esp_hub) and a native module (simulators.native_device).

* behind the hub: its values arrive through h/<hub>/up, an owner's command goes through the
  control-safety layer to h/<hub>/down and its ack comes back the same way;
* the hub is cut off: the module counts as offline; standalone again: commands go to
  d/<module>/cmd straight;
* a hub of another owner cannot speak for the module.
"""

from __future__ import annotations

import asyncio

import pytest

from backend.mqtt_ingest import MqttIngest, acl_allows
from hub.models import Broker
from simulators.esp_hub import EspHubSim
from simulators.mqtt_sim import EmbeddedBroker
from simulators.native_device import NativeDeviceSim
from tests.api.conftest import Backend
from tests.api.test_claims_api import claim
from tests.api.test_ingest_api import commands, owned_device, running, settings, write

pytestmark = [pytest.mark.integration, pytest.mark.postgres]
__all__ = ["settings"]


async def _hub_of(b: Backend, owner: dict[str, str]) -> tuple[str, str]:
    """The second manufactured unit, claimed by ``owner`` and switched on: it plays the hub."""
    row = b.second                                       # type: ignore[attr-defined]
    r = await claim(b, owner, row["identifier"], row["claim_code"])
    assert r.status_code == 200, r.text
    r = await b.client.patch(f"/api/platform/my/devices/{row['device_id']}", headers=owner,
                             json={"enabled": True, "connection": {"transports": ["mqtt"]}})
    assert r.status_code == 200, r.text
    return row["device_id"], row["device_secret"]


def test_acl_lets_a_hub_use_its_own_topics_only() -> None:
    assert acl_allows("hub1", "h/hub1/up", "publish")
    assert acl_allows("hub1", "h/hub1/down", "subscribe")
    assert not acl_allows("hub1", "h/hub2/up", "publish")
    assert not acl_allows("hub1", "h/hub1/down", "publish")


async def test_module_behind_the_hub_then_standalone(backend: Backend) -> None:
    b = backend
    _, sara, _, module_id, module_secret = await owned_device(b, transports=["mqtt"])
    hub_id, hub_secret = await _hub_of(b, sara)
    relay_tag = f"platform.devices.{module_id}.relay_3"
    async with EmbeddedBroker() as broker:
        mqtt = MqttIngest(b.services.ingest, Broker(broker_id="platform", host=broker.host,
                                                    port=broker.port))
        b.services.ingest.mqtt = mqtt
        await mqtt.start()
        try:
            await b.wait(lambda: mqtt.connected)
            await asyncio.sleep(0.2)
            module = NativeDeviceSim(module_id, module_secret, {"relay_3": False})
            hub = EspHubSim(hub_id, hub_secret)
            hub.add_module(module, "m1")
            await hub.connect_cloud(broker.host, broker.port)
            try:
                await b.wait(lambda: relay_tag in b.services.hub.latest)
                relay = b.services.ingest.relay
                assert relay.route(module_id) == hub_id
                # the server told the hub the time, which devices may sign in (by the SHA-256
                # of their secret, never the secret) and the key for the phones
                await b.wait(lambda: hub.registry and hub.server_time
                             and hub.local_key_from_server)
                assert [m["id"] for m in hub.registry] == [module_id]
                assert "secret" not in hub.registry[0]
                assert hub.module_may_sign_in(module_id, module_secret)
                assert not hub.module_may_sign_in(module_id, "wrong")
                # the owner sends the hub its scenes and runs one
                scene = {"id": "night", "name": "Night", "enabled": True,
                         "trigger": {"type": "manual"},
                         "actions": [{"type": "write", "device": "m1", "tag": "relay_3",
                                      "value": False}]}
                r = await b.client.put(f"/api/platform/my/devices/{hub_id}/hub/scenes",
                                       headers=sara, json={"scenes": [scene]})
                assert r.status_code == 200, r.text
                await b.wait(lambda: [x["id"] for x in hub.scenes] == ["night"])
                result = await write(b, sara, relay_tag, True)
                assert result["result"] == "applied", result
                assert module.values["relay_3"] is True
                cmd = (await commands(b, sara, module_id))[0]
                assert cmd["status"] == "confirmed" and cmd["transport"] == "hub"
                status = (await b.client.get(f"/api/platform/my/devices/{hub_id}/hub",
                                             headers=sara)).json()
                assert status["state"] == "online" and status["modules"] == [module_id]
                behind = (await b.client.get(f"/api/platform/my/devices/{module_id}/hub",
                                             headers=sara)).json()
                assert behind["behind_hub"] == hub_id
                # the hub reports an alarm and what its scenes did while it was cut off
                await hub.publish("alarm", {"code": "gsm_power", "text": "low", "active": True})
                await hub.publish("scene_log", {"entries": [{"at": "2026-11-12T10:00:00Z",
                                                             "scene": "night", "by": "time"}]})
                await b.wait(lambda: relay.summary(hub_id)["alarms"]
                             and relay.summary(hub_id)["scene_log"])
            finally:
                await hub.disconnect_cloud()                # the will: the hub is offline
            await b.wait(lambda: not relay.hub_online(hub_id))
            assert relay.route(module_id) is None
            # standalone: the same module signs in to the platform broker itself
            ready = asyncio.Event()
            async with running(module.run_mqtt(broker.host, broker.port, ready=ready)):
                await asyncio.wait_for(ready.wait(), 5)
                await asyncio.sleep(0.3)
                result = await write(b, sara, relay_tag, False)
                assert result["result"] == "applied", result
            cmd = (await commands(b, sara, module_id))[0]
            assert cmd["status"] == "confirmed" and cmd["transport"] == "mqtt"
        finally:
            await mqtt.stop()
            b.services.ingest.mqtt = None


async def test_a_hub_of_another_owner_cannot_relay(backend: Backend) -> None:
    b = backend
    _, sara, omid, module_id, _ = await owned_device(b, transports=["mqtt"])
    hub_id, _ = await _hub_of(b, omid)                    # omid's hub, sara's module
    relay = b.services.ingest.relay
    assert await relay.allowed(hub_id, module_id) is False
    await relay.message(hub_id, "up", {"d": module_id, "k": "telemetry",
                                       "p": {"values": {"relay_3": True}}})
    assert f"platform.devices.{module_id}.relay_3" not in b.services.hub.latest
    assert relay.counters["refused"] == 1
