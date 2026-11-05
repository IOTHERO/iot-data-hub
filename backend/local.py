"""Local control: the phone switches devices over the home Wi-Fi while the internet is down.

* **Keys.** Each device has a local key (hub.platform.local_sign). The hub gives it to the device
  over its own connection (``{"type": "config", "local": {...}}``, also on
  ``GET /ingest/v1/devices/{id}/config``) and, through ``GET /api/platform/my/local-keys``, to
  the phones of members who may fully control it: owner and operator access, a role with
  ``device.operate``, and no access level with room / output / hour limits (those limits are
  enforced by the hub, which a phone on the Wi-Fi does not reach). Fetching is audited.
* **Rotation.** The key changes (version + 1, pushed to the device) when the device changes
  hands (claimed by a transfer, removed) and when a member of a home is removed or gets another
  role: an old phone's copy stops working the next time the device is online.
* **Address.** The device reports where it is on the home network (``local_addr`` in its state
  message); phones get it with the keys and also look for ``_titiswitch._tcp`` (mDNS).
* **Log.** What the device carried out locally reaches the hub afterwards
  (``{"type": "local_log", "entries": [...]}``) and is audited; its values arrive as telemetry.
"""

from __future__ import annotations

import ipaddress
import logging
from typing import Any

from hub.platform.local_sign import new_key

log = logging.getLogger(__name__)
LOCAL_PORT = 8080
MAX_LOG_ENTRIES = 200


def valid_addr(value: Any) -> str | None:
    """A private (home network) IPv4/IPv6 address, else None: a device cannot point phones at
    an address on the internet."""
    try:
        addr = ipaddress.ip_address(str(value).strip())
    except ValueError:
        return None
    return str(addr) if addr.is_private and not addr.is_loopback else None


class LocalControl:
    def __init__(self, svc: Any) -> None:
        self.svc = svc

    @property
    def store(self) -> Any:
        return self.svc.store

    def config(self, row: dict[str, Any] | None) -> dict[str, Any]:
        if row is None:
            return {"enabled": False}
        return {"enabled": True, "key": row["key"], "version": row["version"],
                "port": LOCAL_PORT}

    async def ensure(self, device_ids: list[str]) -> dict[str, dict[str, Any]]:
        """Every device gets a key the first time a phone asks; the device is told at once."""
        rows = await self.store.home.local_keys(device_ids)
        for device_id in device_ids:
            if device_id not in rows:
                rows[device_id] = await self.store.home.save_local_key(device_id, new_key())
                await self._push(device_id, rows[device_id])
        return rows

    async def rotate(self, device_ids: list[str], reason: str, actor: str = "hub") -> int:
        """New keys for the devices that have one (version + 1), pushed to each device."""
        existing = await self.store.home.local_keys(device_ids)
        for device_id in existing:
            row = await self.store.home.save_local_key(device_id, new_key())
            await self._push(device_id, row)
        if existing:
            await self.store.add_auth_audit("local_key_rotated", actor, detail={
                "devices": len(existing), "reason": reason})
        return len(existing)

    async def rotate_org(self, org_id: str, reason: str, actor: str = "hub") -> int:
        return await self.rotate(await self.store.home.org_device_ids(org_id), reason, actor)

    async def _push(self, device_id: str, row: dict[str, Any]) -> None:
        try:
            await self.svc.ingest.send_message(device_id, {"type": "config",
                                                           "local": self.config(row)})
        except Exception:  # noqa: BLE001 - the device also fetches it on its next start
            log.warning("local key of %s not pushed now (device offline?)", device_id)

    async def report_addr(self, device_id: str, value: Any) -> None:
        addr = valid_addr(value)
        if addr is not None:
            await self.store.home.set_local_addr(device_id, addr)

    async def report_log(self, device_id: str, entries: Any) -> int:
        if not isinstance(entries, list):
            raise ValueError('local_log is {"entries": [{"at", "tag", "value", "by"}...]}')
        kept = [{k: e.get(k) for k in ("at", "tag", "value", "by") if k in e}
                for e in entries[:MAX_LOG_ENTRIES] if isinstance(e, dict)]
        if kept:
            await self.store.add_auth_audit("local_commands_reported", device_id[:64],
                                            detail={"device_id": device_id, "entries": kept})
        return len(kept)
