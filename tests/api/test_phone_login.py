"""Sign-in with a mobile number: a one-time SMS code; the first correct one makes the account."""

from __future__ import annotations

import re

import pytest

from backend.sms import SmsOutbox
from tests.api.conftest import Backend, make_settings

pytestmark = [pytest.mark.integration, pytest.mark.postgres]


@pytest.fixture
def settings():
    return make_settings(signup_enabled=True, public_url="https://hub.test")


def _code(sms: SmsOutbox) -> str:
    match = re.match(r"(\d{6})", sms.sent[-1][2])
    assert match
    return match.group(1)


async def test_phone_signup_and_login(backend: Backend) -> None:
    b = backend
    sms = SmsOutbox()
    b.services.accounts.sms = sms
    assert (await b.client.post("/api/account/phone/code",
                                json={"phone": "0912 345 6789"})).status_code == 202
    wrong = await b.client.post("/api/account/phone/verify",
                                json={"phone": "09123456789", "code": "000000"})
    assert wrong.status_code == 403
    r = await b.client.post("/api/account/phone/verify",
                            json={"phone": "+989123456789", "code": _code(sms)})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    homes = await b.client.get("/api/account/organizations",
                               headers={"Authorization": f"Bearer {token}"})
    assert [m["personal"] for m in homes.json()] == [True]
    # a second time: the same account, not a new one
    await b.client.post("/api/account/phone/code", json={"phone": "09123456789"})
    code = _code(sms)
    again = await b.client.post("/api/account/phone/verify",
                                json={"phone": "09123456789", "code": code})
    assert again.status_code == 200
    # a code works once
    reuse = await b.client.post("/api/account/phone/verify",
                                json={"phone": "09123456789", "code": code})
    assert reuse.status_code == 403


async def test_no_sms_panel_and_bad_number(backend: Backend) -> None:
    r = await backend.client.post("/api/account/phone/code", json={"phone": "09123456789"})
    assert r.status_code >= 400
    backend.services.accounts.sms = SmsOutbox()
    r = await backend.client.post("/api/account/phone/code", json={"phone": "12345678"})
    assert r.json()["error"] == "invalid_phone"
