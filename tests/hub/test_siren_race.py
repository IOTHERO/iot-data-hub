"""The siren against "seen" while it is still switching on: whoever comes first, the siren ends
off, and each output gets one "on" and one "off" (backend/home_alerts.py sound / silence)."""

from __future__ import annotations

import asyncio
from typing import Any

from backend.home_alerts import HomeAlerts


class _Siren(HomeAlerts):
    """HomeAlerts with the control-layer write replaced by a log and a gate on the "on"."""

    def __init__(self) -> None:
        super().__init__(services=None)
        self.modes["o1"] = {"sirens": [{"device_id": "d1", "key": "relay_1"}], "siren_s": 30}
        self.writes: list[bool] = []
        self.gate = asyncio.Event()

    async def _siren(self, org_id: str, on: bool) -> int:
        if on:
            await self.gate.wait()             # the device has not answered "on" yet
        self.writes.append(on)
        return 1


async def test_seen_while_the_siren_is_switching_on_turns_it_off_after_on() -> None:
    s = _Siren()
    sounding = asyncio.create_task(s.sound("o1"))
    await asyncio.sleep(0)                     # "on" sent, not answered
    await s.silence("o1")                      # someone marks the alarm seen meanwhile
    assert s.writes == []                      # no "off" may overtake the "on"
    s.gate.set()
    await sounding
    assert s.writes == [True, False]
    assert "o1" not in s._sirens and "o1" not in s._switching_on


async def test_seen_after_the_siren_is_on_turns_it_off_once() -> None:
    s = _Siren()
    s.gate.set()
    await s.sound("o1")
    await s.silence("o1")
    await s.silence("o1")                      # a second "seen" (clear all): nothing more
    assert s.writes == [True, False]


async def test_a_second_trip_while_switching_on_keeps_it_sounding() -> None:
    s = _Siren()
    first = asyncio.create_task(s.sound("o1"))
    await asyncio.sleep(0)
    second = asyncio.create_task(s.sound("o1"))   # another zone trips
    await asyncio.sleep(0)
    s.gate.set()
    await asyncio.gather(first, second)
    assert s.writes == [True, True]            # still sounding: no "off"
    task: Any = s._sirens["o1"]
    assert not task.done()
    await s.silence("o1")
    assert s.writes == [True, True, False]
