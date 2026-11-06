"""Security alerts, a home's security scenarios and RF remotes of the consumer app (0021, 0022).

Alerts (backend/home_alerts.py opens them): the open alerts of the devices the caller sees,
marking one or all seen, clearing one or all. Anyone of the home who sees the device may.

RF remotes: a device whose template carries the rf_* roles (hub/platform/template.py) learns a
remote's key into a slot of its memory and sends a slot again. The home names its remotes
(433 or 315 MHz) and their keys here; learning and sending are writes through the control-safety
layer as the caller (owner or operator), like any command.
"""

from __future__ import annotations

import asyncio
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from backend.api.platform import OrgQuery, _my_level, _my_orgs, _my_rows
from backend.deps import ServicesDep, client_addr, require
from backend.errors import Conflict, Invalid, NotFound
from backend.rbac import Principal
from hub.platform.devices import platform_tag_path
from hub.storage.alerts import (
    SECURITY_MODES,
    AlertRecord,
    RemoteRecord,
    RfKeyRecord,
    security_default,
)

router = APIRouter(prefix="/api/platform", tags=["alerts"])
Viewer = Annotated[Principal, Depends(require("device.view"))]
ICON = r"^[a-z][a-z0-9_-]{0,39}$"
LEARN_S = 25.0                 # how long the module listens for the remote's key


# --- alerts --------------------------------------------------------------------------------------


class AlertOut(AlertRecord):
    device_name: str = ""
    room: str | None = None
    tag_name: dict[str, str] = {}          # the home's name for the sensor, else the maker's


async def _rows(svc: ServicesDep, p: Principal, org: str | None) -> list[Any]:
    orgs = await _my_orgs(svc, p, org)
    return await _my_rows(svc, p, orgs, limit=500) if orgs else []


async def _visible(svc: ServicesDep, p: Principal, org: str | None) -> list[str]:
    return [r.device_id for r in await _rows(svc, p, org)]


@router.get("/my/alerts")
async def alerts(svc: ServicesDep, p: Viewer, org: OrgQuery = None) -> list[AlertOut]:
    """Open alerts of the caller's devices, newest trip first, with the device's and the
    sensor's names (the alarm list shows where each comes from)."""
    rows = {r.device_id: r for r in await _rows(svc, p, org)}
    found = await svc.store.alerts.alerts(list(rows)) if rows else []
    if not found:
        return []
    ids = sorted({a.device_id for a in found})
    rooms = await svc.store.accounts.rooms(await _my_orgs(svc, p, org), ids)
    labels = await svc.store.home.labels(sorted({a.org_id for a in found}), ids)
    out = []
    for a in found:
        record = rows[a.device_id]
        names: dict[str, str] = {}
        try:
            template = await svc.store.platform.template(record.product_id, record.version)
            tag = next((t for t in template.tags if t.key == a.tag_key), None)
            names = dict(tag.display_name) if tag else {}
        except Exception:  # noqa: BLE001  # nosec B110 - the key stands in for the name
            pass
        label = labels.get((a.device_id, a.tag_key))
        if label and label.name:
            names = {"fa": label.name, "en": label.name}
        out.append(AlertOut(**a.model_dump(), device_name=record.name or record.identifier,
                            room=rooms.get(a.device_id), tag_name=names or {"en": a.tag_key}))
    return out


async def _mark(svc: ServicesDep, p: Principal, request: Request, alert_id: int | None,
                org: str | None, clear: bool) -> dict[str, Any]:
    ids = await _visible(svc, p, org)
    rows = await svc.store.alerts.mark(ids, alert_id, p.user_id, clear=clear) if ids else []
    if alert_id is not None and not rows:
        raise NotFound("alert not found")
    if rows and svc.home_alerts is not None:
        for org_id in {r.org_id for r in rows}:  # someone saw it: the siren stops
            await svc.home_alerts.silence(org_id)
    if rows:
        await svc.store.add_auth_audit(
            "security_alerts_cleared" if clear else "security_alert_seen", p.username,
            user_id=p.user_id, client_addr=client_addr(request),
            detail={"alerts": [r.alert_id for r in rows][:50]})
        for r in rows:
            svc.hub.bus.publish({"type": "alert", "device_id": r.device_id,
                                 "alert": r.model_dump(mode="json")})
    return {"changed": len(rows)}


@router.post("/my/alerts/{alert_id}/seen")
async def alert_seen(alert_id: int, svc: ServicesDep, p: Viewer, request: Request
                     ) -> dict[str, Any]:
    return await _mark(svc, p, request, alert_id, None, clear=False)


@router.post("/my/alerts/{alert_id}/clear")
async def alert_clear(alert_id: int, svc: ServicesDep, p: Viewer, request: Request
                      ) -> dict[str, Any]:
    return await _mark(svc, p, request, alert_id, None, clear=True)


@router.post("/my/alerts/seen")
async def alerts_seen(svc: ServicesDep, p: Viewer, request: Request, org: OrgQuery = None
                      ) -> dict[str, Any]:
    return await _mark(svc, p, request, None, org, clear=False)


@router.post("/my/alerts/clear")
async def alerts_clear(svc: ServicesDep, p: Viewer, request: Request, org: OrgQuery = None
                       ) -> dict[str, Any]:
    return await _mark(svc, p, request, None, org, clear=True)


# --- security scenarios (0022) --------------------------------------------------------------------


class SirenRef(BaseModel):
    device_id: str = Field(pattern=r"^[a-z][a-z0-9_]{0,63}$")
    key: str = Field(pattern=r"^[a-z][a-z0-9_]{0,63}$")


class SecurityIn(BaseModel):
    burglar: bool | None = Field(default=None, description="away: motion and magnets are alarms")
    night: bool | None = Field(default=None, description="at home: magnets only")
    fire: bool | None = Field(default=None, description="smoke detectors")
    offline: bool | None = Field(default=None, description="a guarding device cut off")
    sirens: list[SirenRef] | None = Field(default=None, max_length=8, description=(
        "the siren: outputs of any of the home's modules (module + relay), not fixed pins"))
    siren_s: int | None = Field(default=None, ge=10, le=1800, description="how long it sounds")


class SirenOut(SirenRef):
    device_name: str = ""
    name: str = ""                     # the home's name for the output, else the maker's


class Zone(BaseModel):
    device_id: str
    device_name: str
    key: str
    name: str
    kind: str                          # motion | magnet | smoke


class Recipient(BaseModel):
    """A contact of the home by name only: the numbers are kept in the home settings."""
    contact_id: int
    name: str
    sms: bool
    call: bool


class RecipientsIn(BaseModel):
    sms: list[int] = Field(default=[], max_length=10)
    call: list[int] = Field(default=[], max_length=10)


class SecurityOut(BaseModel):
    burglar: bool
    night: bool
    fire: bool
    offline: bool
    sirens: list[SirenOut] = []
    siren_s: int = 180
    sensors: dict[str, int] = {}       # how many of each kind the home has (motion, magnet, ...)
    zones: list[Zone] = []             # every alarm input, on whichever module it is wired
    contacts: int = 0                  # how many get the SMS / call
    recipients: list[Recipient] = []   # the home's contacts by name: who gets the alarms


def _home(p: Principal, org_id: str, permission: str) -> None:
    if not p.can_in_org(permission, org_id):
        raise NotFound("home not found")


async def _security(svc: ServicesDep, org_id: str) -> SecurityOut:
    record = (await svc.store.alerts.security([org_id])).get(org_id) or security_default()
    sensors: dict[str, int] = {}
    zones: list[Zone] = []
    if svc.home_alerts is not None:
        guards = svc.home_alerts.guards
        for org, device_id, key, kind, name in svc.home_alerts.watch.values():
            if org == org_id:
                sensors[kind] = sensors.get(kind, 0) + 1
                zones.append(Zone(device_id=device_id, key=key, name=name, kind=kind,
                                  device_name=guards.get(device_id, ("", device_id))[1]))
    zones.sort(key=lambda z: (z.device_name, z.name))
    people = await svc.store.home.contacts(org_id)
    contacts = sum(1 for c in people if c.sms or c.call)
    recipients = [Recipient(contact_id=c.contact_id, name=c.name, sms=c.sms, call=c.call)
                  for c in people]
    sirens = []
    if record["sirens"]:
        labels = await svc.store.home.labels([org_id])
        for x in record["sirens"]:
            out = SirenOut(device_id=x["device_id"], key=x["key"], name=x["key"])
            try:
                device = await svc.store.platform.device(None, x["device_id"])
                template = await svc.store.platform.template(device.product_id, device.version)
                tag = next((t for t in template.tags if t.key == x["key"]), None)
                label = labels.get((x["device_id"], x["key"]))
                out.device_name = device.name or device.identifier
                maker = (tag.display_name.get("fa") or tag.display_name.get("en")) if tag else None
                out.name = (label.name if label and label.name else None) or maker or x["key"]
            except Exception:  # noqa: BLE001  # nosec B110 - the key stands in for the name
                pass
            sirens.append(out)
    return SecurityOut(**{k: record[k] for k in SECURITY_MODES}, sirens=sirens,
                       siren_s=record["siren_s"], sensors=sensors, zones=zones, contacts=contacts,
                       recipients=recipients)


async def _check_sirens(svc: ServicesDep, org_id: str, sirens: list[SirenRef]) -> None:
    """A siren must be an on/off output of one of the home's own modules."""
    owners = await svc.store.accounts.owner_orgs(sorted({x.device_id for x in sirens}))
    for x in sirens:
        if owners.get(x.device_id) != org_id:
            raise Invalid(f"{x.device_id} is not a device of this home", code="siren_device")
        record = await svc.store.platform.device(None, x.device_id)
        template = await svc.store.platform.template(record.product_id, record.version)
        tag = next((t for t in template.tags if t.key == x.key), None)
        if tag is None or tag.kind != "digital_output" or tag.access != "read_write":
            raise Invalid(f"{x.key} of {x.device_id} is not an on/off output",
                          code="siren_output")


@router.get("/organizations/{org_id}/security")
async def security(org_id: str, svc: ServicesDep, p: Viewer) -> SecurityOut:
    """The home's security scenarios, its siren, its alarm zones (on whichever module each is
    wired) and how many contacts are told."""
    _home(p, org_id, "device.view")
    return await _security(svc, org_id)


@router.put("/organizations/{org_id}/security")
async def save_security(org_id: str, body: SecurityIn, svc: ServicesDep, p: Viewer,
                        request: Request) -> SecurityOut:
    """Switch scenarios on or off, pick the siren outputs and time (anyone of the home who may
    operate its devices: the family arms the alarm when it leaves). The devices get the
    scenarios and their siren outputs with their local rules at once."""
    _home(p, org_id, "device.operate")
    if body.sirens:
        await _check_sirens(svc, org_id, body.sirens)
    current = (await svc.store.alerts.security([org_id])).get(org_id) or security_default()
    wanted = current | {k: v for k, v in body.model_dump().items() if v is not None}
    saved = await svc.store.alerts.save_security(org_id, wanted, p.user_id)
    if svc.home_alerts is not None:
        svc.home_alerts.set_scenarios(org_id, saved)
        if body.burglar is False or body.night is False:     # disarmed: a sounding siren stops
            await svc.home_alerts.silence(org_id)
    await svc.store.add_auth_audit(
        "security_mode_changed", p.username, user_id=p.user_id, client_addr=client_addr(request),
        detail={"org_id": org_id, "sirens": len(saved["sirens"])}
        | {k: saved[k] for k in SECURITY_MODES})
    from backend.api.home import push_local_rules

    await push_local_rules(svc, org_id)
    svc.hub.bus.publish({"type": "security", "org_id": org_id,
                         "modes": {k: saved[k] for k in SECURITY_MODES}})
    return await _security(svc, org_id)


@router.put("/organizations/{org_id}/security/recipients")
async def alarm_recipients(org_id: str, body: RecipientsIn, svc: ServicesDep, p: Viewer,
                           request: Request) -> SecurityOut:
    """Pick by name who of the home's contacts gets the alarms (SMS, call). Whoever may change
    the home's settings (its contacts and numbers) may do this."""
    _home(p, org_id, "home.settings")
    known = {c.contact_id for c in await svc.store.home.contacts(org_id)}
    if not set(body.sms) | set(body.call) <= known:
        raise NotFound("contact not found")
    await svc.store.home.set_alarm_recipients(org_id, body.sms, body.call)
    await svc.store.add_auth_audit("contact_saved", p.username, user_id=p.user_id,
                                   client_addr=client_addr(request),
                                   detail={"org_id": org_id, "alarm_sms": len(body.sms),
                                           "alarm_call": len(body.call)})
    return await _security(svc, org_id)


# --- RF remotes -----------------------------------------------------------------------------------


class RemoteIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    band: int = Field(description="315 or 433 (MHz), as the device's rf_band offers")
    icon: str | None = Field(default=None, pattern=ICON)


class KeyIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    icon: str | None = Field(default=None, pattern=ICON)


class Remotes(BaseModel):
    supported: bool
    bands: list[int] = []
    slots: int = 0                 # how many keys the module's memory holds
    remotes: list[RemoteRecord] = []


async def _rf(svc: ServicesDep, device_id: str) -> dict[str, Any] | None:
    """The device's rf_* tags by role, or None when it has no RF module."""
    record = await svc.store.platform.device(None, device_id)
    template = await svc.store.platform.template(record.product_id, record.version)
    roles = {t.ui.role: t for t in template.tags if t.ui.role and t.ui.role.startswith("rf_")}
    return roles if len(roles) == 4 else None


def _slots(rf: dict[str, Any]) -> tuple[int, int]:
    learn, send = rf["rf_learn"], rf["rf_send"]
    return int(max(learn.min, send.min)), int(min(learn.max, send.max))


async def _level(svc: ServicesDep, p: Principal, device_id: str, operate: bool) -> None:
    level = await _my_level(svc, p, device_id, "device.operate" if operate else "device.view")
    if level is None or (operate and level not in ("owner", "operator")):
        raise NotFound("device not found")


@router.get("/my/devices/{device_id}/remotes")
async def remotes(device_id: str, svc: ServicesDep, p: Viewer) -> Remotes:
    """The home's remotes of an RF module and their keys (``supported`` false: no module)."""
    await _level(svc, p, device_id, operate=False)
    rf = await _rf(svc, device_id)
    if rf is None:
        return Remotes(supported=False)
    first, last = _slots(rf)
    return Remotes(supported=True, bands=sorted(rf["rf_band"].states or {}),
                   slots=max(0, last - first + 1),
                   remotes=await svc.store.alerts.remotes(device_id))


async def _rf_for_change(svc: ServicesDep, p: Principal, device_id: str) -> dict[str, Any]:
    await _level(svc, p, device_id, operate=True)
    rf = await _rf(svc, device_id)
    if rf is None:
        raise NotFound("this device has no RF module")
    return rf


@router.post("/my/devices/{device_id}/remotes", status_code=201)
async def add_remote(device_id: str, body: RemoteIn, svc: ServicesDep, p: Viewer,
                     request: Request) -> RemoteRecord:
    return await _save_remote(device_id, None, body, svc, p, request)


@router.put("/my/devices/{device_id}/remotes/{remote_id}")
async def save_remote(device_id: str, remote_id: int, body: RemoteIn, svc: ServicesDep,
                      p: Viewer, request: Request) -> RemoteRecord:
    return await _save_remote(device_id, remote_id, body, svc, p, request)


async def _save_remote(device_id: str, remote_id: int | None, body: RemoteIn,
                       svc: ServicesDep, p: Principal, request: Request) -> RemoteRecord:
    rf = await _rf_for_change(svc, p, device_id)
    if body.band not in (rf["rf_band"].states or {}):
        raise Invalid(f"this module listens on {sorted(rf['rf_band'].states or {})} MHz",
                      code="rf_band")
    saved = await svc.store.alerts.save_remote(device_id, remote_id, name=body.name.strip(),
                                               band=body.band, icon=body.icon,
                                               user_id=p.user_id)
    if saved is None:
        raise NotFound("remote not found")
    await svc.store.add_auth_audit("rf_remote_saved", p.username, user_id=p.user_id,
                                   client_addr=client_addr(request),
                                   detail={"device_id": device_id, "remote_id": saved.remote_id})
    return saved


@router.delete("/my/devices/{device_id}/remotes/{remote_id}", status_code=204)
async def delete_remote(device_id: str, remote_id: int, svc: ServicesDep, p: Viewer,
                        request: Request) -> None:
    await _rf_for_change(svc, p, device_id)
    if not await svc.store.alerts.delete_remote(device_id, remote_id):
        raise NotFound("remote not found")
    await svc.store.add_auth_audit("rf_remote_deleted", p.username, user_id=p.user_id,
                                   client_addr=client_addr(request),
                                   detail={"device_id": device_id, "remote_id": remote_id})


@router.post("/my/devices/{device_id}/remotes/{remote_id}/keys", status_code=201)
async def add_key(device_id: str, remote_id: int, body: KeyIn, svc: ServicesDep,
                  p: Viewer) -> RfKeyRecord:
    """A key in the module's next free slot; it works once learnt (``.../learn``)."""
    rf = await _rf_for_change(svc, p, device_id)
    first, last = _slots(rf)
    if not any(r.remote_id == remote_id for r in await svc.store.alerts.remotes(device_id)):
        raise NotFound("remote not found")
    key = await svc.store.alerts.add_key(device_id, remote_id, name=body.name.strip(),
                                         icon=body.icon, first_slot=first, last_slot=last)
    if key is None:
        raise Conflict("the module's memory is full", code="rf_full")
    return key


@router.put("/my/devices/{device_id}/remotes/{remote_id}/keys/{key_id}")
async def save_key(device_id: str, remote_id: int, key_id: int, body: KeyIn, svc: ServicesDep,
                   p: Viewer) -> RfKeyRecord:
    await _rf_for_change(svc, p, device_id)
    key = await svc.store.alerts.save_key(device_id, key_id, name=body.name.strip(),
                                          icon=body.icon)
    if key is None or key.remote_id != remote_id:
        raise NotFound("key not found")
    return key


@router.delete("/my/devices/{device_id}/remotes/{remote_id}/keys/{key_id}", status_code=204)
async def delete_key(device_id: str, remote_id: int, key_id: int, svc: ServicesDep,
                     p: Viewer) -> None:
    await _rf_for_change(svc, p, device_id)
    found = await svc.store.alerts.key(device_id, key_id)
    if found is None or found[0].remote_id != remote_id:
        raise NotFound("key not found")
    await svc.store.alerts.delete_key(device_id, key_id)


async def _key(svc: ServicesDep, device_id: str, remote_id: int, key_id: int
               ) -> tuple[RfKeyRecord, int]:
    found = await svc.store.alerts.key(device_id, key_id)
    if found is None or found[0].remote_id != remote_id:
        raise NotFound("key not found")
    return found


@router.post("/my/devices/{device_id}/remotes/{remote_id}/keys/{key_id}/learn")
async def learn_key(device_id: str, remote_id: int, key_id: int, svc: ServicesDep, p: Viewer,
                    request: Request) -> dict[str, Any]:
    """The module listens on the remote's band and learns the next key pressed into this key's
    slot; the answer comes when it reports that slot (``learnt``) or after 25 s (``timeout``).
    ``rejected_*`` / ``failed``: the control-safety layer or the device said no."""
    rf = await _rf_for_change(svc, p, device_id)
    key, band = await _key(svc, device_id, remote_id, key_id)
    addr = client_addr(request)
    started = svc.hub.clock()
    for role, value in (("rf_band", band), ("rf_learn", key.slot)):
        path = platform_tag_path(device_id, rf[role].key)
        current = svc.hub.latest.get(path)
        if role == "rf_band" and current is not None and current.value == band:
            continue                                # already listening on this band
        result = await svc.control.request_write(p, path, value, "app: learn RF key", addr)
        if result.result != "applied":
            return {"result": result.result, "message": result.message}
    path = platform_tag_path(device_id, rf["rf_learnt"].key)
    loop = asyncio.get_running_loop()
    ends = loop.time() + LEARN_S
    while loop.time() < ends:
        sample = svc.hub.latest.get(path)
        if sample is not None and sample.value == key.slot and \
                (sample.received_at or sample.timestamp) >= started:
            learnt = await svc.store.alerts.learnt(device_id, key_id)
            await svc.store.add_auth_audit("rf_key_learnt", p.username, user_id=p.user_id,
                                           client_addr=addr,
                                           detail={"device_id": device_id, "slot": key.slot})
            return {"result": "learnt", "key": learnt.model_dump(mode="json") if learnt else None}
        await asyncio.sleep(0.25)
    return {"result": "timeout", "message": "no key was pressed on the remote"}


@router.post("/my/devices/{device_id}/remotes/{remote_id}/keys/{key_id}/send")
async def send_key(device_id: str, remote_id: int, key_id: int, svc: ServicesDep, p: Viewer,
                   request: Request) -> dict[str, Any]:
    """Press the key: the module sends the code it learnt into the key's slot."""
    rf = await _rf_for_change(svc, p, device_id)
    key, _ = await _key(svc, device_id, remote_id, key_id)
    if key.learnt_at is None:
        raise Conflict("this key has not been learnt yet", code="rf_not_learnt")
    result = await svc.control.request_write(p, platform_tag_path(device_id, rf["rf_send"].key),
                                             key.slot, "app: RF key", client_addr(request))
    return {"result": result.result, "message": result.message}
