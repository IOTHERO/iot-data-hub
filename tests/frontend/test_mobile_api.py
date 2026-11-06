"""The Flutter app (mobile/lib) may call only routes the hub has: every `/api/...` path in its
source, with the method where it is written next to it, must match a route of backend/api.

Static (no database): the routers are read from the modules, the paths from the Dart strings.
Interpolations become one path segment; one glued to a word (`views$q`) is a query string.
"""

from __future__ import annotations

import importlib
import pkgutil
import re
from pathlib import Path

from fastapi.routing import APIRoute

import backend.api

ROOT = Path(__file__).resolve().parents[2]
DART = ROOT / "mobile" / "lib"
INTERP = r"\$(?:\{[^}]*\}|[A-Za-z_]\w*)"
STR = r"((?:\$\{[^}]*\}|\\.|[^'\\])*)"          # a '…' Dart string; ${a['x']} inside
CALL = re.compile(r"'(GET|POST|PUT|PATCH|DELETE)',\s*'" + STR + "'")
BASE = re.compile(r"(_base|base|_path)\s*(?:=>|=)\s*'(/api/" + STR[1:] + "'")
LITERAL = re.compile(r"'(/api/" + STR[1:] + "'")


def routes() -> list[tuple[set[str], re.Pattern[str], str]]:
    out = []
    for info in pkgutil.iter_modules(backend.api.__path__):
        module = importlib.import_module(f"backend.api.{info.name}")
        router = getattr(module, "router", None)
        for route in getattr(router, "routes", []):
            if isinstance(route, APIRoute) and route.path.startswith("/api"):
                pattern = re.sub(r"\\\{[^}]+\\\}", "[^/]+", re.escape(route.path))
                out.append((set(route.methods), re.compile(pattern + "$"),
                            re.sub(r"\{[^}]+\}", "X", route.path)))
    return out


def normalize(path: str) -> str:
    path = re.sub(r"(?<=[^/])" + INTERP, "", path)     # glued to a word: a query string
    path = re.sub(INTERP, "X", path)
    return path.split("?")[0].rstrip("/")


def used() -> list[tuple[str | None, str, str]]:
    """(method or None, path, file) for each API path in the app."""
    out = []
    for file in DART.rglob("*.dart"):
        text = file.read_text(encoding="utf-8")
        bases = {name: value for name, value in BASE.findall(text)}
        seen = set()
        for method, path in CALL.findall(text):
            for name, value in bases.items():
                for ref in (f"${{{name}}}", f"${name}"):
                    if path.startswith(ref) and not path[len(ref):len(ref) + 1].isalnum():
                        path = value + path[len(ref):]
                        break
            if path.startswith("/api/"):
                out.append((method, normalize(path), file.name))
                seen.add(path)
        for path in LITERAL.findall(text):
            if path not in seen and path not in bases.values():
                out.append((None, normalize(path), file.name))
        out += [(None, normalize(v), file.name) for v in bases.values()]
    return out


def test_every_api_path_of_the_mobile_app_exists() -> None:
    table = routes()
    assert len(table) > 100
    calls = used()
    assert len(calls) > 50                        # the app's calls were found
    missing = []
    for method, path, file in calls:
        hits = [methods for methods, pattern, _ in table if pattern.match(path)]
        if not hits:
            # a base path that is extended later (`$_path/messages`): some route starts with it
            if method is None and any(raw.startswith(path + "/") for _, _, raw in table):
                continue
            missing.append(f"{file}: {method or '?'} {path}")
        elif method and not any(method in m for m in hits):
            missing.append(f"{file}: {method} {path} (method)")
    assert not missing, "the app calls routes the hub does not have:\n" + "\n".join(missing)
