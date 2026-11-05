"""Signing of commands sent to a device over the home network (local control, migration 0020).

The phone and the device share the device's local key (32 random bytes, base64url, from the
hub). On the home Wi-Fi the phone first asks the device for a one-time nonce, then sends

    POST /local/v1/command  {"nonce": n, "tag": "relay_1", "value_json": "true", "sig": s}
    POST /local/v1/state    {"nonce": n, "sig": s}

with ``s = base64url(HMAC-SHA256(key, message))`` and the message the lines

    <device_id> \\n <nonce> \\n command \\n <tag> \\n <value_json>     (a command)
    <device_id> \\n <nonce> \\n state                                 (reading the values)

``value_json`` is the value exactly as signed (JSON text), so phone and device never disagree
about number formatting. A nonce works once and for NONCE_TTL_S: a recorded command cannot be
sent again, and someone on the same Wi-Fi without the key can do nothing.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets

NONCE_TTL_S = 30
KEY_BYTES = 32


def new_key() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(KEY_BYTES)).decode().rstrip("=")


def new_nonce() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip("=")


def _key_bytes(key: str) -> bytes:
    return base64.urlsafe_b64decode(key + "=" * (-len(key) % 4))


def message(device_id: str, nonce: str, kind: str, tag: str | None = None,
            value_json: str | None = None) -> bytes:
    parts = [device_id, nonce, kind]
    if kind == "command":
        parts += [tag or "", value_json or ""]
    return "\n".join(parts).encode("utf-8")


def sign(key: str, device_id: str, nonce: str, kind: str, tag: str | None = None,
         value_json: str | None = None) -> str:
    mac = hmac.new(_key_bytes(key), message(device_id, nonce, kind, tag, value_json),
                   hashlib.sha256).digest()
    return base64.urlsafe_b64encode(mac).decode().rstrip("=")


def verify(key: str, sig: str, device_id: str, nonce: str, kind: str, tag: str | None = None,
           value_json: str | None = None) -> bool:
    return hmac.compare_digest(sign(key, device_id, nonce, kind, tag, value_json), sig or "")
