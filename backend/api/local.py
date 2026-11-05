"""Local control routes (backend.local): the phone's keys, the device's config and its log.

* ``GET  /api/platform/my/local-keys``          keys + home-network addresses for the app
* ``GET  /ingest/v1/devices/{id}/config``      the device's settings (local key, SMS) on start
* ``POST /ingest/v1/devices/{id}/local_log``   what the device carried out while cut off
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, Header, Request

from backend.deps import ServicesDep, client_addr, require
from backend.errors import Invalid
from backend.rbac import Principal
from hub.drivers.base import utcnow

router = APIRouter(tags=["local"])
Viewer = Annotated[Principal, Depends(require("device.view"))]


@router.get("/api/platform/my/local-keys")
async def my_local_keys(svc: ServicesDep, p: Viewer, request: Request) -> dict[str, Any]:
    """The devices this phone may switch over the home Wi-Fi when the internet is down: owner
    or operator access with ``device.operate``, and no access level that limits rooms, outputs
    or hours (the hub enforces those; a phone talking to the device directly could not). The
    app keeps the answer on the phone and fetches it again whenever it is online."""
    if svc.levels.limited(p):
        return {"devices": [], "limited": True, "fetched_at": utcnow().isoformat()}
    orgs = {g.org_id for g in p.grants if g.org_id and "device.operate" in
            p.role_permissions.get(g.role_id, frozenset())}
    if not orgs:
        return {"devices": [], "limited": False, "fetched_at": utcnow().isoformat()}
    rows, _ = await svc.store.platform.devices(orgs, limit=500)
    levels = await svc.store.accounts.access_levels(orgs, [r.device_id for r in rows])
    mine = [r for r in rows if levels.get(r.device_id) in ("owner", "operator")
            and r.protocol == "native" and r.parent_device_id is None
            and r.lifecycle == "active"]
    keys = await svc.local.ensure([r.device_id for r in mine])
    out = [{"device_id": r.device_id, "identifier": r.identifier, "name": r.name,
            "key": keys[r.device_id]["key"], "version": keys[r.device_id]["version"],
            "local_addr": keys[r.device_id]["local_addr"], "port": svc.local.config(
                keys[r.device_id])["port"]} for r in mine]
    if out:
        await svc.store.add_auth_audit("local_keys_fetched", p.username, user_id=p.user_id,
                                       client_addr=client_addr(request),
                                       detail={"devices": len(out)})
    return {"devices": out, "limited": False, "fetched_at": utcnow().isoformat()}


@router.get("/ingest/v1/devices/{device_id}/config")
async def device_config(device_id: str, svc: ServicesDep, request: Request,
                        authorization: Annotated[str | None, Header()] = None
                        ) -> dict[str, Any]:
    """The device fetches its settings (with its credential) after it starts: the local key
    (``enabled: false`` until a phone asked for one) and the SMS fallback."""
    from backend.api.ingest import _device

    await _device(svc, device_id, authorization, request)
    local = (await svc.store.home.local_keys([device_id])).get(device_id)
    sms = await svc.store.home.sms(device_id)
    return {"type": "config", "local": svc.local.config(local),
            "sms": {"enabled": True, "key": sms["key"], "device_id": device_id} if sms
            else {"enabled": False}}


@router.post("/ingest/v1/devices/{device_id}/local_log")
async def device_local_log(device_id: str, svc: ServicesDep, request: Request,
                           payload: Annotated[Any, Body()],
                           authorization: Annotated[str | None, Header()] = None
                           ) -> dict[str, Any]:
    from backend.api.ingest import _device

    await _device(svc, device_id, authorization, request)
    try:
        n = await svc.local.report_log(device_id, (payload or {}).get("entries")
                                       if isinstance(payload, dict) else None)
    except ValueError as exc:
        raise Invalid(str(exc), code="invalid_message") from None
    return {"accepted": n}
