"""RetryingSms: an alarm SMS the gateway refuses is tried again in the background; given up
after the last retry (counted for the health check); the caller is never kept waiting."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field

from backend.sms import RetryingSms


@dataclass
class Flaky:
    enabled: bool = True
    fail_first: int = 0
    tries: list[tuple[str, str]] = field(default_factory=list)

    async def send(self, to: str, text: str) -> bool:
        self.tries.append(("sms", to))
        return len(self.tries) > self.fail_first

    async def call(self, to: str, text: str) -> bool:
        self.tries.append(("call", to))
        return len(self.tries) > self.fail_first


async def _settle(sms: RetryingSms) -> None:
    for _ in range(200):
        if not sms.pending and (sms._task is None or sms._task.done()):  # noqa: SLF001
            return
        await asyncio.sleep(0.01)


async def test_a_refused_sms_is_retried_until_it_goes_out() -> None:
    gateway = Flaky(fail_first=2)
    sms = RetryingSms(gateway, delays=(0.01, 0.01, 0.01))
    assert await sms.send("09111111111", "fire") is False          # first try failed
    await _settle(sms)
    assert gateway.tries == [("sms", "09111111111")] * 3 and sms.given_up == 0


async def test_given_up_after_the_last_retry() -> None:
    gateway = Flaky(fail_first=99)
    sms = RetryingSms(gateway, delays=(0.01, 0.01))
    assert await sms.call("09111111111", "fire") is False
    await _settle(sms)
    assert len(gateway.tries) == 3 and sms.given_up == 1
    await sms.close()


async def test_a_working_gateway_is_not_queued() -> None:
    sms = RetryingSms(Flaky())
    assert await sms.send("09111111111", "ok") is True
    assert not sms.pending and sms._task is None                    # noqa: SLF001
