"""The Flutter app (mobile/) uses the web app's translation files: the copies must be equal."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_mobile_translations_are_the_apps() -> None:
    for lang in ("fa", "en"):
        app = (ROOT / "app" / "i18n" / f"{lang}.json").read_bytes()
        mobile = (ROOT / "mobile" / "assets" / "i18n" / f"{lang}.json").read_bytes()
        assert mobile == app, f"copy app/i18n/{lang}.json to mobile/assets/i18n/"
