"""The firmware rules the native device simulator shows: reconnect delays spread out (no
thundering herd after a power cut) and grow to a cap; a stable session starts them over."""

from __future__ import annotations

import asyncio
import random

from simulators.native_device import (
    DELAY_CAP_S,
    FIRST_DELAY_MAX_S,
    JITTER,
    reconnect_delay,
    run_forever,
)


def test_first_try_is_spread_over_ten_seconds() -> None:
    rng = random.Random(1)
    firsts = [reconnect_delay(0, rng) for _ in range(1000)]
    assert all(0 <= d <= FIRST_DELAY_MAX_S for d in firsts)
    assert max(firsts) - min(firsts) > 8                  # not all at once


def test_delays_double_up_to_the_cap_with_jitter() -> None:
    rng = random.Random(2)
    for attempt, base in ((1, 10), (2, 20), (3, 40), (6, 300), (20, 300)):
        d = reconnect_delay(attempt, rng)
        assert base * (1 - JITTER) <= d <= base * (1 + JITTER)
    assert max(reconnect_delay(50, rng) for _ in range(100)) <= DELAY_CAP_S * (1 + JITTER)


async def test_run_forever_backs_off_between_failed_sessions() -> None:
    stop = asyncio.Event()
    waits: list[float] = []

    async def session() -> None:
        raise ConnectionError("broker down")

    async def sleep(seconds: float) -> None:
        waits.append(seconds)
        if len(waits) == 4:
            stop.set()

    await run_forever(session, stop, random.Random(3), sleep)
    assert waits[0] <= FIRST_DELAY_MAX_S
    assert waits[1] < waits[2] < waits[3]                 # growing
