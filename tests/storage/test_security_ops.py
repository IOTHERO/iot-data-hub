"""Encrypted backups, HTTPS from hub-api, and the security commands of hub-admin."""

from __future__ import annotations

import asyncio
import ssl
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
import pytest
import uvicorn
from fastapi import FastAPI

from backend import admin
from hub.maintenance import Maintenance, MaintenanceSettings, find_pg_dump
from hub.models import DEVICE_ADAPTER
from hub.pki import application_uri, certificate_expiry, make_tls_certificate
from simulators.mqtt_sim import free_port
from tests.hub.builders import modbus_device

pytestmark = pytest.mark.postgres
KEY = "b" * 40
NOW = datetime(2026, 10, 10, 12, 30, tzinfo=UTC)


async def test_encrypted_backup_restores(store: Any, database_url: str, tmp_path: Path,
                                         monkeypatch: pytest.MonkeyPatch) -> None:
    await store.sync_config([DEVICE_ADAPTER.validate_python(modbus_device())])
    m = Maintenance(store, MaintenanceSettings(backup_dir=tmp_path, data_key=KEY),
                    database_url=database_url, clock=lambda: NOW)
    path = await m.run_backup()
    assert path is not None and path.name.endswith(".dump.enc")
    assert not list(tmp_path.glob("*.dump"))                      # no plain copy left behind
    assert b"write_audit" not in path.read_bytes()                 # really encrypted
    event = (await store.events("backup_ok", 1))[0]
    assert event["detail"]["encrypted"] is True

    monkeypatch.setenv("HUB_DATA_KEY", KEY)
    plain = tmp_path / "restored.dump"
    assert admin.main(["decrypt-backup", str(path), str(plain)]) == 0
    restore = str(Path(find_pg_dump()).with_name(Path(find_pg_dump()).name.replace(
        "pg_dump", "pg_restore")))
    listing = subprocess.run([restore, "--list", str(plain)], capture_output=True, text=True,
                             check=True).stdout
    assert "TABLE DATA public devices" in listing

    monkeypatch.setenv("HUB_DATA_KEY", "c" * 40)
    with pytest.raises(Exception, match="HUB_DATA_KEY"):
        admin.main(["decrypt-backup", str(path), str(tmp_path / "x.dump")])


async def test_https_serving(tmp_path: Path) -> None:
    cert, key = make_tls_certificate(tmp_path, ["127.0.0.1", "hub.kish.local"])
    app = FastAPI()

    @app.get("/ping")
    async def ping() -> dict[str, str]:
        return {"ok": "yes"}

    port = free_port()
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, loop="none",
                                           lifespan="off", log_level="warning",
                                           ssl_certfile=str(cert), ssl_keyfile=str(key)))
    task = asyncio.create_task(server.serve())
    try:
        while not server.started:
            await asyncio.sleep(0.02)
        context = ssl.create_default_context(cafile=str(cert))
        async with httpx.AsyncClient(verify=context) as client:
            r = await client.get(f"https://127.0.0.1:{port}/ping")
            assert r.json() == {"ok": "yes"}
        async with httpx.AsyncClient() as client:              # not trusted by default
            with pytest.raises(httpx.ConnectError):
                await client.get(f"https://127.0.0.1:{port}/ping")
    finally:
        server.should_exit = True
        await task


def test_make_tls_cert_command(tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
                               capsys: pytest.CaptureFixture[str]) -> None:
    monkeypatch.delenv("HUB_DATABASE_URL", raising=False)
    assert admin.main(["make-tls-cert", "--name", "hub.kish.local", "--name", "10.0.0.5",
                       "--out", str(tmp_path)]) == 0
    out = capsys.readouterr().out
    assert "HUB_TLS_CERT=" in out
    cert = tmp_path / "hub-https.crt.pem"
    days = (certificate_expiry(cert) - datetime.now(UTC)).days
    assert 800 < days <= 825 and application_uri(cert) is None


async def test_verify_audit_and_reset_mfa_commands(store: Any, database_url: str,
                                                   monkeypatch: pytest.MonkeyPatch,
                                                   capsys: pytest.CaptureFixture[str]) -> None:
    user = await store.create_user("op.one", "Op", "h")
    await store.update_user(user.user_id, totp_enabled=True, totp_secret_enc="v1.x")
    await store.add_auth_audit("login_ok", "op.one", user_id=user.user_id)
    monkeypatch.setenv("HUB_DATABASE_URL", database_url)
    assert await asyncio.to_thread(admin.main, ["verify-audit"]) == 0
    assert "auth_audit: OK" in capsys.readouterr().out
    assert await asyncio.to_thread(admin.main, ["reset-mfa", "op.one"]) == 0
    assert (await store.get_user(user.user_id)).totp_enabled is False  # type: ignore[union-attr]


async def test_create_customer_signs_in_without_e_mail(store: Any, database_url: str,
                                                       monkeypatch: pytest.MonkeyPatch) -> None:
    """hub-admin create-customer: verified at once, with its own home (sites with no e-mail
    server, testing); the same address twice and a weak password are refused."""
    monkeypatch.setenv("HUB_DATABASE_URL", database_url)
    monkeypatch.setenv("HUB_ADMIN_PASSWORD", "Customer-Pass-2026")
    args = ["create-customer", "--email", "Ali@Example.test", "--display-name", "Ali"]
    assert await asyncio.to_thread(admin.main, args) == 0
    user = await store.get_user_by_email("ali@example.test")
    assert user is not None and user.email_verified_at is not None
    homes = await store.accounts.memberships(user.user_id)
    assert [m.personal for m in homes] == [True]
    assert await asyncio.to_thread(admin.main, args) == 1             # already has an account
    monkeypatch.setenv("HUB_ADMIN_PASSWORD", "short")
    with pytest.raises(SystemExit, match="password rejected"):
        await asyncio.to_thread(admin.main, ["create-customer", "--email", "b@example.test",
                                             "--display-name", "B"])


async def test_create_maker_makes_the_organization_and_its_administrator(
        store: Any, database_url: str, monkeypatch: pytest.MonkeyPatch) -> None:
    """hub-admin create-maker: a manufacturer and a maker-panel administrator who can sign in at
    once; run again for an existing organization it only adds the role."""
    monkeypatch.setenv("HUB_DATABASE_URL", database_url)
    monkeypatch.setenv("HUB_ADMIN_PASSWORD", "Maker-Pass-2026x")
    args = ["create-maker", "--org-id", "kish_smart", "--name", "Kish Smart",
            "--email", "m@example.test", "--display-name", "M"]
    assert await asyncio.to_thread(admin.main, args) == 0
    orgs = {o.org_id: o.kind for o in await store.platform.organizations(None)}
    assert orgs["kish_smart"] == "manufacturer"
    user = await store.get_user_by_email("m@example.test")
    assert user is not None and user.email_verified_at is not None
    grants = await store.grants(user.user_id)
    assert [(g.role_id, g.org_id) for g in grants] == [("manufacturer_admin", "kish_smart")]
    assert await asyncio.to_thread(admin.main, args) == 0            # again: no second user
    assert await asyncio.to_thread(admin.main, [*args[:2], "Bad-Id", *args[3:]]) == 1
