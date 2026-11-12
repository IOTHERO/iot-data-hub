"""A "remember me" sign-in (the apps, the customer web app) is a long session without the idle
limit, and refreshing keeps it long; a normal sign-in is unchanged (12 hours, idle limit)."""

from __future__ import annotations

from datetime import timedelta

import pytest

from backend.security import hash_refresh_token
from tests.api.conftest import PASSWORD, Backend

pytestmark = [pytest.mark.integration, pytest.mark.postgres]


async def _lifetime(b: Backend, refresh_token: str) -> timedelta:
    s = await b.store.get_session_by_hash(hash_refresh_token(refresh_token))
    assert s is not None
    return s.expires_at - s.created_at


async def test_remembered_session_is_long_and_stays_long(backend: Backend) -> None:
    b = backend
    await b.user("anna", ("viewer", None, None))
    short = (await b.client.post("/api/auth/login", json={
        "username": "anna", "password": PASSWORD})).json()
    long_ = (await b.client.post("/api/auth/login", json={
        "username": "anna", "password": PASSWORD, "remember": True})).json()

    hours = b.services.settings.refresh_token_hours
    assert await _lifetime(b, short["refresh_token"]) <= timedelta(hours=hours, minutes=1)
    assert await _lifetime(b, long_["refresh_token"]) >= timedelta(days=89)

    # refreshing a remembered session gives a remembered one, a normal one stays normal
    again = (await b.client.post("/api/auth/refresh",
                                 json={"refresh_token": long_["refresh_token"]})).json()
    assert await _lifetime(b, again["refresh_token"]) >= timedelta(days=89)
    plain = (await b.client.post("/api/auth/refresh",
                                 json={"refresh_token": short["refresh_token"]})).json()
    assert await _lifetime(b, plain["refresh_token"]) <= timedelta(hours=hours, minutes=1)


async def test_remembered_session_has_no_idle_limit(backend: Backend) -> None:
    b = backend
    await b.user("berta", ("viewer", None, None))
    short = (await b.client.post("/api/auth/login", json={
        "username": "berta", "password": PASSWORD})).json()
    long_ = (await b.client.post("/api/auth/login", json={
        "username": "berta", "password": PASSWORD, "remember": True})).json()
    idle = timedelta(minutes=b.services.settings.session_idle_minutes + 5)
    for token in (short, long_):                   # both were last seen "long ago"
        s = await b.store.get_session_by_hash(hash_refresh_token(token["refresh_token"]))
        async with b.store._conn() as conn:
            await conn.execute(
                "UPDATE sessions SET last_seen_at = now() - %s WHERE session_id = %s",
                (idle, s.session_id))  # type: ignore[union-attr]
    assert (await b.client.post("/api/auth/refresh", json={
        "refresh_token": short["refresh_token"]})).status_code == 401       # ended by inactivity
    assert (await b.client.post("/api/auth/refresh", json={
        "refresh_token": long_["refresh_token"]})).status_code == 200       # remembered: stays
