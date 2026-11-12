"""The owner can close a home he made (an empty one); the personal home stays."""

from __future__ import annotations

import pytest

from tests.api.conftest import Backend, make_settings

pytestmark = [pytest.mark.integration, pytest.mark.postgres]
PASSWORD = "Customer-Pass-2026"


@pytest.fixture
def settings():
    return make_settings(signup_enabled=True, public_url="https://hub.test",
                         email_verification="off")


async def test_owner_deletes_an_empty_home_but_not_the_personal_one(backend: Backend) -> None:
    b = backend
    await b.client.post("/api/account/signup", json={
        "email": "sara@example.test", "password": PASSWORD, "display_name": "Sara"})
    token = (await b.client.post("/api/auth/login", json={
        "username": "sara@example.test", "password": PASSWORD})).json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    villa = (await b.client.post("/api/account/homes", json={"name": "Villa"}, headers=h)).json()
    homes = (await b.client.get("/api/account/organizations", headers=h)).json()
    personal = next(m for m in homes if m["personal"])

    r = await b.client.delete(f"/api/account/homes/{personal['org_id']}", headers=h)
    assert r.status_code == 409
    r = await b.client.delete(f"/api/account/homes/{villa['org_id']}", headers=h)
    assert r.status_code == 204, r.text
    homes = (await b.client.get("/api/account/organizations", headers=h)).json()
    assert [m["org_id"] for m in homes] == [personal["org_id"]]
    r = await b.client.delete(f"/api/account/homes/{villa['org_id']}", headers=h)
    assert r.status_code == 404
