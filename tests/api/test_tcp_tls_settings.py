"""The device TCP port can have its own certificate (HUB_TCP_TLS_CERT / KEY): behind a TLS reverse
proxy (deploy/: Caddy) the HTTP API stays plain while devices still connect over TLS."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from backend.settings import Settings
from backend.tcp_ingest import TcpIngest
from hub.pki import make_tls_certificate

SECRET = {"HUB_JWT_SECRET": "s" * 40}


def test_device_port_tls_without_https_on_the_api(tmp_path: Path) -> None:
    cert, key = make_tls_certificate(tmp_path, ["hub.example.test"])
    settings = Settings.from_env({**SECRET, "HUB_TCP_INGEST_PORT": "7000",
                                  "HUB_TCP_TLS_CERT": str(cert), "HUB_TCP_TLS_KEY": str(key)})
    assert settings.tls is False                     # hub-api itself: plain HTTP behind the proxy
    ingest: Any = object()
    tcp = TcpIngest.from_settings(ingest, settings)
    assert tcp is not None and tcp.ssl_context is not None


def test_the_api_certificate_is_used_when_the_port_has_none(tmp_path: Path) -> None:
    cert, key = make_tls_certificate(tmp_path, ["hub.example.test"])
    settings = Settings.from_env({**SECRET, "HUB_TCP_INGEST_PORT": "7000",
                                  "HUB_TLS_CERT": str(cert), "HUB_TLS_KEY": str(key)})
    tcp = TcpIngest.from_settings(object(), settings)  # type: ignore[arg-type]
    assert tcp is not None and tcp.ssl_context is not None


def test_no_certificate_at_all_is_refused() -> None:
    settings = Settings.from_env({**SECRET, "HUB_TCP_INGEST_PORT": "7000"})
    with pytest.raises(RuntimeError, match="HUB_TCP_TLS_CERT"):
        TcpIngest.from_settings(object(), settings)  # type: ignore[arg-type]
