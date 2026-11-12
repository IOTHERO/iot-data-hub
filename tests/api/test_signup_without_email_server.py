"""A hub without an SMTP server: a customer signs up and can sign in at once (no confirmation
link could ever arrive); with an SMTP server, or HUB_EMAIL_VERIFICATION=on, the link is needed."""

from __future__ import annotations

import pytest

from backend.settings import Settings
from tests.api.conftest import Backend, make_settings

pytestmark = [pytest.mark.integration, pytest.mark.postgres]
PASSWORD = "Customer-Pass-2026"


@pytest.fixture
def settings() -> Settings:
    return make_settings(signup_enabled=True, public_url="https://hub.test",
                         email_verification="auto")


async def test_auto_without_smtp_is_active_at_once(backend: Backend) -> None:
    b = backend
    assert b.services.settings.verify_email_required is False
    r = await b.client.post("/api/account/signup", json={
        "email": "ali@example.test", "password": PASSWORD, "display_name": "Ali"})
    assert r.status_code == 202 and r.json() == {"status": "active"}
    login = await b.client.post("/api/auth/login",
                                json={"username": "ali@example.test", "password": PASSWORD})
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    homes = await b.client.get("/api/account/organizations",
                               headers={"Authorization": f"Bearer {token}"})
    assert [m["personal"] for m in homes.json()] == [True]          # its own home exists


def test_the_modes() -> None:
    base = {"jwt_secret": "x" * 40}
    assert Settings.model_validate(base).verify_email_required is False          # auto, no SMTP
    assert Settings.model_validate(base | {"smtp_host": "mail.test"}
                                   ).verify_email_required is True               # auto, SMTP
    assert Settings.model_validate(base | {"email_verification": "on"}
                                   ).verify_email_required is True
    assert Settings.model_validate(base | {"smtp_host": "mail.test", "email_verification": "off"}
                                   ).verify_email_required is False
