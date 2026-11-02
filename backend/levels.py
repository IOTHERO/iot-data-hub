"""Access levels of a home (migration 0018): what a member on a custom level may do, on which
devices and outputs, and when.

A level is a role of one home (``lvl_...``): its permissions are ordinary role permissions, so
every existing check (``can_in_org``, ``orgs_with``) already knows them. The limits on top are
enforced here, on the server:

* **scope** — rooms, groups (whole devices) and single outputs; other devices of the home are
  not visible to the member at all (lists, views, live stream, history), and outputs outside
  the scope are not writable;
* **schedule** — Jalali weekdays and hours (Tehran) in which the member may operate; outside
  them every write is refused by the control-safety layer, also the writes of scenes and
  automations the member made (they run with his rights);
* **own_only** — he changes only the scenes and automations he made.

A member who also has a built-in role in the same home (owner, member, viewer) is not limited
there. Users without any custom level never reach a query here (``limited`` is false).
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from hub import jalali

TEHRAN = ZoneInfo("Asia/Tehran")
CACHE_S = 10.0
# the ticks a home's owner chooses from, in the order the app shows them
HOME_PERMISSIONS = ("device.view", "device.operate", "scene.run", "automation.manage",
                    "timer.manage", "energy.view", "device.share", "org.members",
                    "home.settings", "ticket.manage")
BUILT_IN = ("customer_owner", "customer_member", "customer_viewer")


@dataclass(frozen=True)
class Limits:
    """One member's limits in one home. ``devices``: devices with every output allowed;
    ``outputs``: single (device_id, key) outputs; both None = every device of the home."""

    devices: frozenset[str] | None
    outputs: frozenset[tuple[str, str]] | None
    schedule: dict[str, Any] | None
    own_only: bool

    @property
    def everything(self) -> bool:
        return self.devices is None and self.outputs is None

    def sees(self, device_id: str) -> bool:
        return self.everything or device_id in (self.devices or ()) or any(
            d == device_id for d, _ in self.outputs or ())

    def may_write(self, device_id: str, key: str) -> bool:
        return self.everything or device_id in (self.devices or ()) or \
            (device_id, key) in (self.outputs or ())

    def in_hours(self, now: datetime) -> bool:
        s = self.schedule
        if not s:
            return True
        local = now.astimezone(TEHRAN)
        if s.get("weekdays") is not None and jalali.weekday(local.date()) not in s["weekdays"]:
            return False
        start, end = s.get("from"), s.get("to")
        if not start or not end:
            return True
        hm = local.strftime("%H:%M")
        return start <= hm < end if start <= end else (hm >= start or hm < end)


class LevelService:
    def __init__(self, svc: Any) -> None:
        self.svc = svc
        self._cache: dict[tuple[str, str], tuple[float, Limits | None]] = {}

    @staticmethod
    def limited(principal: Any) -> bool:
        """Has the caller any custom level at all? (No: nothing here costs a query.)"""
        return any(g.role_id.startswith("lvl_") for g in principal.grants)

    def forget(self) -> None:
        """A level, a group or a room changed: read the limits again."""
        self._cache.clear()

    async def limits(self, principal: Any, org_id: str) -> Limits | None:
        """The caller's limits in this home; None = not limited there."""
        roles = [g.role_id for g in principal.grants if g.org_id == org_id]
        if not roles or not all(r.startswith("lvl_") for r in roles):
            return None                      # a built-in role (or none): no extra limits
        key = (org_id, ",".join(sorted(roles)))
        now = time.monotonic()
        hit = self._cache.get(key)
        if hit is not None and now - hit[0] < CACHE_S:
            return hit[1]
        levels = list((await self.svc.store.home.levels_by_role(roles)).values())
        result = await self._resolve(org_id, levels) if levels else None
        if len(self._cache) > 5000:
            self._cache.clear()
        self._cache[key] = (now, result)
        return result

    async def _resolve(self, org_id: str, levels: list[Any]) -> Limits | None:
        whole: set[str] = set()
        outputs: set[tuple[str, str]] = set()
        everything = False
        schedules: list[dict[str, Any] | None] = []
        own_only = all(lv.own_only for lv in levels)
        for lv in levels:
            scope = lv.scope or {}
            schedules.append(lv.schedule)
            if not (scope.get("rooms") or scope.get("groups") or scope.get("outputs")):
                everything = True
                continue
            if scope.get("rooms"):
                rows, _ = await self.svc.store.platform.devices({org_id}, limit=500)
                rooms = await self.svc.store.accounts.rooms({org_id},
                                                            [r.device_id for r in rows])
                whole |= {d for d, room in rooms.items() if room in scope["rooms"]}
            if scope.get("groups"):
                wanted = {int(g) for g in scope["groups"]}
                for g in await self.svc.store.home.groups([org_id]):
                    if g.group_id in wanted:
                        whole |= set(g.device_ids)
            for o in scope.get("outputs") or []:
                outputs.add((o["device_id"], o["key"]))
        # several levels: the widest of each (a member rarely has more than one)
        schedule = None if any(s is None for s in schedules) else schedules[0]
        if everything:
            return Limits(None, None, schedule, own_only)
        return Limits(frozenset(whole), frozenset(outputs), schedule, own_only)

    async def visible(self, principal: Any, orgs: set[str], device_ids: list[str]
                      ) -> dict[str, Limits | None]:
        """Of these devices of the caller's homes, the ones he may see, each with its limits
        (None = none). Only for a limited caller; others see what access_levels gives."""
        out: dict[str, Limits | None] = {}
        for org in sorted(orgs):
            lim = await self.limits(principal, org)
            levels = await self.svc.store.accounts.access_levels({org}, device_ids)
            for d in levels:
                if lim is None:
                    out[d] = None                  # a home that does not limit him wins
                elif d not in out and lim.sees(d):
                    out[d] = lim
        return out

    async def device(self, principal: Any, orgs: set[str], device_id: str
                     ) -> tuple[bool, Limits | None]:
        """(may he see it, its limits) for one device; unlimited callers: (True, None)."""
        if not self.limited(principal):
            return True, None
        seen = await self.visible(principal, orgs, [device_id])
        return device_id in seen, seen.get(device_id)

    async def may_operate(self, principal: Any, org_id: str, device_id: str, key: str,
                          now: datetime) -> str | None:
        """None if allowed; else why not (for the refusal message)."""
        lim = await self.limits(principal, org_id)
        if lim is None:
            return None
        if not lim.may_write(device_id, key):
            return "this output is outside your access level"
        if not lim.in_hours(now):
            return "outside the hours of your access level"
        return None

    async def owns(self, principal: Any, org_id: str, created_by: int | None) -> bool:
        """May he change a scene or automation made by ``created_by``?"""
        lim = await self.limits(principal, org_id)
        return lim is None or not lim.own_only or created_by == principal.user_id
