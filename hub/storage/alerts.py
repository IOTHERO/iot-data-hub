"""Security alerts and RF remotes (0021). Service code: backend checks the caller's homes and
the device's access level first.

* An alert per tripped sensor (motion, magnet, smoke) of a home, or a guarding device cut off
  (offline); another trip while it is open counts on it and asks to be seen again. Seen and
  cleared keep who and when. The home's security scenarios say which of them are alarms.
* An RF module's remotes and their keys: which slot of the module's memory holds which key.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from typing import Any

from psycopg.types.json import Jsonb
from pydantic import BaseModel

# a home's security scenarios (0022) and what they are before the home changes them
SECURITY_DEFAULTS = {"burglar": False, "night": False, "fire": True, "offline": True}
SECURITY_MODES = tuple(SECURITY_DEFAULTS)


def security_default() -> dict[str, Any]:
    """A home's security record before it changes anything: no siren outputs, 3 minutes."""
    return dict(SECURITY_DEFAULTS) | {"sirens": [], "siren_s": 180, "updated_by": None}


class AlertRecord(BaseModel):
    alert_id: int
    org_id: str
    device_id: str
    tag_key: str
    kind: str
    started_at: datetime
    last_at: datetime
    trips: int = 1
    seen_at: datetime | None = None
    seen_by: int | None = None
    cleared_at: datetime | None = None


class RfKeyRecord(BaseModel):
    key_id: int
    remote_id: int
    device_id: str
    slot: int
    name: str
    icon: str | None = None
    position: int = 0
    learnt_at: datetime | None = None


class RemoteRecord(BaseModel):
    remote_id: int
    device_id: str
    name: str
    band: int
    icon: str | None = None
    keys: list[RfKeyRecord] = []


class AlertStore:
    def __init__(self, store: Any) -> None:
        self._store = store

    def _conn(self) -> Any:
        return self._store._conn()

    # --- security alerts ----------------------------------------------------------------------

    async def trip(self, org_id: str, device_id: str, tag_key: str, kind: str,
                   at: datetime) -> AlertRecord:
        """A sensor tripped: a new alert, or one more trip on its open one (seen again)."""
        async with self._conn() as conn:
            row = await (await conn.execute(
                "INSERT INTO security_alerts "
                "(org_id, device_id, tag_key, kind, started_at, last_at) "
                "VALUES (%s,%s,%s,%s,%s,%s) "
                "ON CONFLICT (device_id, tag_key) WHERE cleared_at IS NULL DO UPDATE SET "
                "trips = security_alerts.trips + 1, last_at = EXCLUDED.last_at, "
                "seen_at = NULL, seen_by = NULL RETURNING *",
                (org_id, device_id, tag_key, kind, at, at))).fetchone()
        return AlertRecord.model_validate(row)

    async def alerts(self, device_ids: Sequence[str], *, open_only: bool = True,
                     limit: int = 100) -> list[AlertRecord]:
        """The alerts of these devices (the ones the caller sees), newest first."""
        where = "device_id = ANY(%s)" + (" AND cleared_at IS NULL" if open_only else "")
        async with self._conn() as conn:
            rows = await (await conn.execute(
                f"SELECT * FROM security_alerts WHERE {where} "  # noqa: S608  # nosec B608 - fixed text
                "ORDER BY last_at DESC LIMIT %s", (list(device_ids), limit))).fetchall()
        return [AlertRecord.model_validate(r) for r in rows]

    async def mark(self, device_ids: Sequence[str], alert_id: int | None, user_id: int | None, *,
                   clear: bool) -> list[AlertRecord]:
        """Seen (or cleared, which is also seen): one alert, or every open one of the devices."""
        sets = "seen_at = coalesce(seen_at, now()), seen_by = coalesce(seen_by, %s)"
        if clear:
            sets += ", cleared_at = now(), cleared_by = %s"
        args: list[Any] = [user_id] + ([user_id] if clear else []) + [list(device_ids)]
        where = "device_id = ANY(%s) AND cleared_at IS NULL"
        if alert_id is not None:
            where += " AND alert_id = %s"
            args.append(alert_id)
        async with self._conn() as conn:
            rows = await (await conn.execute(
                f"UPDATE security_alerts SET {sets} WHERE {where} RETURNING *",  # noqa: S608  # nosec B608 - fixed text
                args)).fetchall()
        return [AlertRecord.model_validate(r) for r in rows]

    async def owned_devices(self) -> list[dict[str, Any]]:
        """Every device that has an owner home: device_id, org_id, name, product_id, version and
        whether it is an edge hub (the sensors to watch; service use)."""
        async with self._conn() as conn:
            return list(await (await conn.execute(
                "SELECT a.device_id, a.org_id, d.name, pd.product_id, pd.version, "
                "p.kind = 'edge_hub' AS edge_hub FROM device_access a "
                "JOIN platform_devices pd USING (device_id) JOIN devices d USING (device_id) "
                "JOIN products p ON p.product_id = pd.product_id "
                "WHERE a.level='owner' AND a.revoked_at IS NULL AND pd.retired_at IS NULL"
            )).fetchall())

    # --- security scenarios (0022) ------------------------------------------------------------

    async def security(self, org_ids: Sequence[str] | None = None) -> dict[str, dict[str, Any]]:
        """org -> its scenarios, siren outputs and siren time, and who changed them last (homes
        that never changed them are absent: ``security_default()``)."""
        sql = ("SELECT org_id, burglar, night, fire, offline, sirens, siren_s, updated_by "
               "FROM home_security")
        args: list[Any] = []
        if org_ids is not None:
            sql += " WHERE org_id = ANY(%s)"
            args.append(list(org_ids))
        async with self._conn() as conn:
            rows = await (await conn.execute(sql, args)).fetchall()
        return {r["org_id"]: {k: bool(r[k]) for k in SECURITY_MODES} | {
            "sirens": list(r["sirens"] or []), "siren_s": int(r["siren_s"]),
            "updated_by": r["updated_by"]} for r in rows}

    async def save_security(self, org_id: str, values: dict[str, Any], user_id: int | None
                            ) -> dict[str, Any]:
        """Save the whole record (``values`` as ``security()`` gives it, changed)."""
        record = security_default() | {k: v for k, v in values.items() if k in security_default()}
        async with self._conn() as conn:
            await conn.execute(
                "INSERT INTO home_security (org_id, burglar, night, fire, offline, sirens, "
                "siren_s, updated_by) VALUES (%s,%s,%s,%s,%s,%s,%s,%s) "
                "ON CONFLICT (org_id) DO UPDATE SET "
                "burglar=EXCLUDED.burglar, night=EXCLUDED.night, fire=EXCLUDED.fire, "
                "offline=EXCLUDED.offline, sirens=EXCLUDED.sirens, siren_s=EXCLUDED.siren_s, "
                "updated_by=EXCLUDED.updated_by, updated_at=now()",
                (org_id, *(bool(record[k]) for k in SECURITY_MODES),
                 Jsonb([{"device_id": x["device_id"], "key": x["key"]} for x in record["sirens"]]),
                 int(record["siren_s"]), user_id))
        return record | {"updated_by": user_id}

    async def forget_device(self, device_id: str) -> None:
        """The device changed hands: its open alerts end, its remotes and keys go, and it is no
    longer a siren of its old home."""
        async with self._conn() as conn, conn.transaction():
            await conn.execute("UPDATE security_alerts SET cleared_at = now() "
                               "WHERE device_id=%s AND cleared_at IS NULL", (device_id,))
            await conn.execute("DELETE FROM rf_keys WHERE device_id=%s", (device_id,))
            await conn.execute("DELETE FROM rf_remotes WHERE device_id=%s", (device_id,))
            await conn.execute(                   # no longer a siren of its old home
                "UPDATE home_security SET sirens = (SELECT coalesce(jsonb_agg(x), '[]'::jsonb) "
                "FROM jsonb_array_elements(sirens) x WHERE x->>'device_id' <> %s) "
                "WHERE sirens @> %s", (device_id, Jsonb([{"device_id": device_id}])))

    # --- RF remotes -----------------------------------------------------------------------------

    async def remotes(self, device_id: str) -> list[RemoteRecord]:
        async with self._conn() as conn:
            remotes = await (await conn.execute(
                "SELECT * FROM rf_remotes WHERE device_id=%s ORDER BY remote_id",
                (device_id,))).fetchall()
            keys = await (await conn.execute(
                "SELECT * FROM rf_keys WHERE device_id=%s ORDER BY position, key_id",
                (device_id,))).fetchall()
        out = [RemoteRecord.model_validate(r) for r in remotes]
        by_id = {r.remote_id: r for r in out}
        for k in keys:
            if k["remote_id"] in by_id:
                by_id[k["remote_id"]].keys.append(RfKeyRecord.model_validate(k))
        return out

    async def save_remote(self, device_id: str, remote_id: int | None, *, name: str, band: int,
                          icon: str | None, user_id: int | None) -> RemoteRecord | None:
        async with self._conn() as conn:
            if remote_id is None:
                row = await (await conn.execute(
                    "INSERT INTO rf_remotes (device_id, name, band, icon, created_by) "
                    "VALUES (%s,%s,%s,%s,%s) RETURNING *",
                    (device_id, name, band, icon, user_id))).fetchone()
            else:
                row = await (await conn.execute(
                    "UPDATE rf_remotes SET name=%s, band=%s, icon=%s "
                    "WHERE remote_id=%s AND device_id=%s RETURNING *",
                    (name, band, icon, remote_id, device_id))).fetchone()
        return RemoteRecord.model_validate(row) if row else None

    async def delete_remote(self, device_id: str, remote_id: int) -> bool:
        async with self._conn() as conn:
            cur = await conn.execute("DELETE FROM rf_remotes WHERE remote_id=%s AND device_id=%s",
                                     (remote_id, device_id))
        return cur.rowcount > 0

    async def add_key(self, device_id: str, remote_id: int, *, name: str, icon: str | None,
                      first_slot: int, last_slot: int) -> RfKeyRecord | None:
        """A new key in the lowest free slot of the module; None when its memory is full."""
        async with self._conn() as conn, conn.transaction():
            await conn.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (f"rf:{device_id}",))
            used = {r["slot"] for r in await (await conn.execute(
                "SELECT slot FROM rf_keys WHERE device_id=%s", (device_id,))).fetchall()}
            slot = next((n for n in range(first_slot, last_slot + 1) if n not in used), None)
            if slot is None:
                return None
            position = len(await (await conn.execute(
                "SELECT 1 FROM rf_keys WHERE remote_id=%s", (remote_id,))).fetchall())
            row = await (await conn.execute(
                "INSERT INTO rf_keys (remote_id, device_id, slot, name, icon, position) "
                "SELECT remote_id, device_id, %s, %s, %s, %s FROM rf_remotes "
                "WHERE remote_id=%s AND device_id=%s RETURNING *",
                (slot, name, icon, min(position, 1000), remote_id, device_id))).fetchone()
        return RfKeyRecord.model_validate(row) if row else None

    async def key(self, device_id: str, key_id: int) -> tuple[RfKeyRecord, int] | None:
        """A key and its remote's band."""
        async with self._conn() as conn:
            row = await (await conn.execute(
                "SELECT k.*, r.band FROM rf_keys k JOIN rf_remotes r USING (remote_id) "
                "WHERE k.key_id=%s AND k.device_id=%s", (key_id, device_id))).fetchone()
        return (RfKeyRecord.model_validate(row), int(row["band"])) if row else None

    async def save_key(self, device_id: str, key_id: int, *, name: str, icon: str | None
                       ) -> RfKeyRecord | None:
        async with self._conn() as conn:
            row = await (await conn.execute(
                "UPDATE rf_keys SET name=%s, icon=%s WHERE key_id=%s AND device_id=%s RETURNING *",
                (name, icon, key_id, device_id))).fetchone()
        return RfKeyRecord.model_validate(row) if row else None

    async def learnt(self, device_id: str, key_id: int) -> RfKeyRecord | None:
        async with self._conn() as conn:
            row = await (await conn.execute(
                "UPDATE rf_keys SET learnt_at=now() WHERE key_id=%s AND device_id=%s RETURNING *",
                (key_id, device_id))).fetchone()
        return RfKeyRecord.model_validate(row) if row else None

    async def delete_key(self, device_id: str, key_id: int) -> bool:
        async with self._conn() as conn:
            cur = await conn.execute("DELETE FROM rf_keys WHERE key_id=%s AND device_id=%s",
                                     (key_id, device_id))
        return cur.rowcount > 0
