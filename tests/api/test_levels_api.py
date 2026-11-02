"""Access levels of a home (0018): ticks, scope (rooms, groups, single outputs), hours, own
scenes only; enforced by the server (lists, views, the control-safety layer), without
escalation, and the last owner of a home stays an owner."""

from __future__ import annotations

from datetime import datetime
from typing import Any

import pytest

from backend.settings import Settings
from hub import jalali
from tests.api.conftest import Backend, make_settings
from tests.api.test_accounts_api import account, last_link
from tests.api.test_home_api import _home
from tests.api.test_ingest_api import owned_device

pytestmark = [pytest.mark.integration, pytest.mark.postgres]


@pytest.fixture
def settings() -> Settings:
    return make_settings(signup_enabled=True, public_url="https://hub.test",
                         tcp_ingest_port=0, tcp_ingest_insecure=True,
                         tcp_ingest_host="127.0.0.1", broker_hook_token="h" * 32)


async def _join(b: Backend, owner: dict[str, str], org: str, email: str, name: str,
                role: str) -> dict[str, str]:
    r = await b.client.post(f"/api/platform/organizations/{org}/invitations", headers=owner,
                            json={"email": email, "role": role})
    assert r.status_code == 201, r.text
    h = await account(b, email, name)
    r = await b.client.post("/api/account/invitations/accept", headers=h,
                            json={"token": last_link(b, email, "invitation")})
    assert r.status_code == 200, r.text
    return h


async def _write(b: Backend, h: dict[str, str], device_id: str, key: str) -> dict[str, Any]:
    r = await b.client.post("/api/control/write", headers=h, json={
        "tag": f"platform.devices.{device_id}.{key}", "value": True, "reason": "test"})
    assert r.status_code == 200, r.text
    return r.json()


def _writable(view: dict[str, Any]) -> dict[str, bool]:
    return {t["key"]: t["writable"] for t in view["tags"] if t["key"].startswith("relay_")}


async def test_levels_scope_hours_and_ticks(backend: Backend) -> None:
    b = backend
    _, sara, _, device_id, _ = await owned_device(b)
    home = await _home(b, sara)
    base = f"/api/platform/organizations/{home}"
    listed = (await b.client.get(f"{base}/levels", headers=sara)).json()
    assert "scene.run" in listed["permissions"] and len(listed["built_in"]) == 3
    owner_perms = next(x for x in listed["built_in"] if x["role_id"] == "customer_owner")
    assert set(owner_perms["permissions"]) == set(listed["permissions"])

    # a gardener: sees the device, switches relay 1 only; no scenes, no energy
    gardener_level = {"name": "باغبان", "permissions": ["device.view", "device.operate"],
                      "scope": {"outputs": [{"device_id": device_id, "key": "relay_1"}]}}
    r = await b.client.post(f"{base}/levels", headers=sara, json=gardener_level)
    assert r.status_code == 201, r.text
    level = r.json()["role_id"]
    assert (await b.client.post(f"{base}/levels", headers=sara, json=gardener_level)
            ).status_code == 409                                       # same name
    assert (await b.client.post(f"{base}/levels", headers=sara, json=gardener_level | {
        "name": "x", "permissions": ["device.operate"]})).status_code == 422   # no device.view
    gardener = await _join(b, sara, home, "gardener@example.com", "Gardener", level)
    view = (await b.client.get(f"/api/platform/my/devices/{device_id}/view",
                               headers=gardener)).json()
    writable = _writable(view)
    assert writable["relay_1"] is True and not any(v for k, v in writable.items()
                                                    if k != "relay_1")
    assert len((await b.client.get("/api/platform/my/views", headers=gardener)).json()) == 1
    r = await _write(b, gardener, device_id, "relay_2")
    assert r["result"] == "rejected_rbac" and "access level" in r["message"]
    energy = (await b.client.get("/api/platform/my/energy", headers=gardener)).json()
    assert energy["devices"] == []                                     # no energy tick
    scene = (await b.client.post(f"{base}/scenes", headers=sara, json={
        "name": "s", "actions": [{"type": "write", "device_id": device_id, "tag": "relay_1",
                                  "value": True}]})).json()
    assert (await b.client.post(f"{base}/scenes/{scene['scene_id']}/run",
                                headers=gardener)).status_code == 404  # no scene tick

    # outside his hours: nothing is writable and the safety layer refuses
    today = jalali.weekday(datetime.now(jalali_tz()).date())
    other_days = [d for d in range(7) if d != today]
    r = await b.client.put(f"{base}/levels/{level}", headers=sara, json=gardener_level | {
        "schedule": {"weekdays": other_days, "from": "00:00", "to": "23:59"}})
    assert r.status_code == 200, r.text
    view = (await b.client.get(f"/api/platform/my/devices/{device_id}/view",
                               headers=gardener)).json()
    assert not any(_writable(view).values())
    r = await _write(b, gardener, device_id, "relay_1")
    assert r["result"] == "rejected_rbac" and "hours" in r["message"]

    # a room he is not given: the device is not his to see at all
    await b.client.put(f"{base}/levels/{level}", headers=sara, json=gardener_level | {
        "scope": {"rooms": ["انبار"]}})
    assert (await b.client.get("/api/platform/my/devices", headers=gardener)).json() == []
    assert (await b.client.get(f"/api/platform/my/devices/{device_id}/view",
                               headers=gardener)).status_code == 404
    await b.client.put(f"/api/platform/my/devices/{device_id}/room", headers=sara,
                       json={"room": "انبار"})
    b.services.levels.forget()
    assert len((await b.client.get("/api/platform/my/devices", headers=gardener)).json()) == 1

    # a level in use is not deleted; the owner gives him another one first
    assert (await b.client.delete(f"{base}/levels/{level}", headers=sara)).status_code == 409
    members = (await b.client.get(f"{base}/members", headers=sara)).json()
    grant = next(m for m in members if m["email"] == "gardener@example.com")["user_role_id"]
    r = await b.client.patch(f"{base}/members/{grant}", headers=sara,
                             json={"role": "customer_viewer"})
    assert r.status_code == 200, r.text
    assert (await b.client.delete(f"{base}/levels/{level}", headers=sara)).status_code == 204


async def test_levels_no_escalation_own_only_last_owner(backend: Backend) -> None:
    b = backend
    _, sara, _, device_id, _ = await owned_device(b)
    home = await _home(b, sara)
    base = f"/api/platform/organizations/{home}"
    # a manager of members who cannot change the home's settings
    r = await b.client.post(f"{base}/levels", headers=sara, json={
        "name": "مدیر اعضا", "permissions": ["device.view", "org.members", "automation.manage"],
        "own_only": True})
    manager = await _join(b, sara, home, "manager@example.com", "Manager", r.json()["role_id"])
    r = await b.client.post(f"{base}/levels", headers=manager, json={
        "name": "بالاتر", "permissions": ["device.view", "home.settings"]})
    assert r.status_code == 403 and r.json()["error"] == "escalation"
    r = await b.client.post(f"{base}/invitations", headers=manager,
                            json={"email": "x@example.com", "role": "customer_owner"})
    assert r.status_code == 403 and r.json()["error"] == "escalation"
    assert (await b.client.post(f"{base}/levels", headers=manager, json={
        "name": "مهمان", "permissions": ["device.view"]})).status_code == 201

    # own scenes and automations only
    auto = {"name": "a", "trigger": {"type": "time", "at": "08:00"},
            "actions": [{"type": "write", "device_id": device_id, "tag": "relay_1",
                         "value": True}]}
    owners = (await b.client.post(f"{base}/automations", headers=sara, json=auto)).json()
    r = await b.client.put(f"{base}/automations/{owners['automation_id']}", headers=manager,
                           json=auto | {"name": "b"})
    assert r.status_code == 403 and r.json()["error"] == "not_yours"
    assert (await b.client.delete(f"{base}/automations/{owners['automation_id']}",
                                  headers=manager)).status_code == 403
    mine = await b.client.post(f"{base}/automations", headers=manager, json=auto)
    assert mine.status_code == 201, mine.text
    assert (await b.client.put(f"{base}/automations/{mine.json()['automation_id']}",
                               headers=manager, json=auto | {"name": "c"})).status_code == 200

    # the last owner of the home stays an owner
    members = (await b.client.get(f"{base}/members", headers=sara)).json()
    owner_grant = next(m for m in members if m["role_id"] == "customer_owner")["user_role_id"]
    r = await b.client.patch(f"{base}/members/{owner_grant}", headers=sara,
                             json={"role": "customer_member"})
    assert r.status_code == 409 and r.json()["error"] == "last_owner"
    r = await b.client.patch(f"{base}/members/{owner_grant}", headers=manager,
                             json={"role": "customer_viewer"})
    assert r.status_code in (403, 409)
    assert (await b.client.patch(f"{base}/members/{owner_grant}", headers=sara,
                                 json={"role": "lvl_nope00000000"})).status_code == 422


def jalali_tz() -> Any:
    from zoneinfo import ZoneInfo

    return ZoneInfo("Asia/Tehran")
