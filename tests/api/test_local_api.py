"""Local control (0020): keys for the phones that may fully control a device, the device's
config and address, signed commands over the home network (nonce, no replay, no guessing),
key rotation when the device changes hands, and the log reported afterwards."""

from __future__ import annotations

import asyncio
import json
from typing import Any

import httpx
import pytest

from backend.settings import Settings
from hub.platform.local_sign import sign
from simulators.native_device import NativeDeviceSim
from tests.api.conftest import Backend, make_settings
from tests.api.test_ingest_api import owned_device, running

pytestmark = [pytest.mark.integration, pytest.mark.postgres]


@pytest.fixture
def settings() -> Settings:
    return make_settings(signup_enabled=True, public_url="https://hub.test")


async def _keys(b: Backend, h: dict[str, str]) -> list[dict[str, Any]]:
    r = await b.client.get("/api/platform/my/local-keys", headers=h)
    assert r.status_code == 200, r.text
    return r.json()["devices"]


async def _command(lan: httpx.AsyncClient, device_id: str, key: str, tag: str,
                   value: Any) -> httpx.Response:
    nonce = (await lan.get("/local/v1/nonce")).json()["nonce"]
    value_json = json.dumps(value)
    return await lan.post("/local/v1/command", json={
        "nonce": nonce, "tag": tag, "value_json": value_json,
        "sig": sign(key, device_id, nonce, "command", tag, value_json)})


async def test_phone_switches_the_device_over_the_home_network(backend: Backend) -> None:
    b = backend
    _, sara, omid, device_id, secret = await owned_device(b)
    auth = {"Authorization": f"Bearer {secret}"}
    (entry,) = await _keys(b, sara)
    assert entry["device_id"] == device_id and len(entry["key"]) == 43
    assert entry["version"] == 1 and entry["local_addr"] is None
    assert await _keys(b, omid) == []                         # not his device
    cfg = (await b.client.get(f"/ingest/v1/devices/{device_id}/config", headers=auth)).json()
    assert cfg["local"]["enabled"] and cfg["local"]["key"] == entry["key"]
    assert (await b.client.get(f"/ingest/v1/devices/{device_id}/config")).status_code == 401

    # the device says where it is on the home network; an internet address is ignored
    for addr in ("8.8.8.8", "192.168.1.50"):
        await b.client.post(f"/ingest/v1/devices/{device_id}/state", headers=auth,
                            json={"state": "online", "local_addr": addr})
    assert (await _keys(b, sara))[0]["local_addr"] == "192.168.1.50"

    sim = NativeDeviceSim(device_id, secret, {"relay_1": False})
    sim.receive(cfg)
    ready = asyncio.Event()
    async with running(sim.serve_local("127.0.0.1", 0, ready)):
        await asyncio.wait_for(ready.wait(), 5)
        async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{sim.local_port}") as lan:
            assert (await lan.get("/local/v1/info")).json()["local"] is True
            r = await _command(lan, device_id, entry["key"], "relay_1", True)
            assert r.json() == {"ok": True, "tag": "relay_1", "value": True}
            assert sim.values["relay_1"] is True

            # a guest on the Wi-Fi: no key, a guessed key, a replayed command
            r = await _command(lan, device_id, "A" * 43, "relay_1", False)
            assert r.status_code == 401 and sim.values["relay_1"] is True
            nonce = (await lan.get("/local/v1/nonce")).json()["nonce"]
            body = {"nonce": nonce, "tag": "relay_1", "value_json": "false",
                    "sig": sign(entry["key"], device_id, nonce, "command", "relay_1", "false")}
            assert (await lan.post("/local/v1/command", json=body)).json()["ok"] is True
            replay = await lan.post("/local/v1/command", json=body)
            assert replay.status_code == 401 and replay.json()["error"] == "nonce"
            # the signature covers the value: changing it breaks the signature
            nonce = (await lan.get("/local/v1/nonce")).json()["nonce"]
            body = {"nonce": nonce, "tag": "relay_1", "value_json": "true",
                    "sig": sign(entry["key"], device_id, nonce, "command", "relay_1", "false")}
            assert (await lan.post("/local/v1/command", json=body)).status_code == 401

            nonce = (await lan.get("/local/v1/nonce")).json()["nonce"]
            r = await lan.post("/local/v1/state", json={
                "nonce": nonce, "sig": sign(entry["key"], device_id, nonce, "state")})
            assert r.json()["values"]["relay_1"] is False

    # back online: what the phone did over the Wi-Fi reaches the hub and its audit log
    assert await sim.report_local_http(b.client) == 2
    events = [a for a in await b.store.list_auth_audit() if a.event == "local_commands_reported"]
    assert events and len(events[0].detail["entries"]) == 2
    assert any(a.event == "local_keys_fetched" for a in await b.store.list_auth_audit())


async def test_the_key_changes_when_the_device_changes_hands(backend: Backend) -> None:
    b = backend
    _, sara, _, device_id, secret = await owned_device(b)
    old = (await _keys(b, sara))[0]["key"]
    r = await b.client.post(f"/api/platform/my/devices/{device_id}/transfer", headers=sara)
    assert r.status_code == 200
    r = await b.client.delete(f"/api/platform/my/devices/{device_id}", headers=sara)
    assert r.status_code == 200
    rows = await b.store.home.local_keys([device_id])
    assert rows[device_id]["version"] == 2 and rows[device_id]["key"] != old
    assert any(a.event == "local_key_rotated" for a in await b.store.list_auth_audit())
    assert await _keys(b, sara) == []                           # no longer hers
