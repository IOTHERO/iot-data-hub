"""Simulated native device (the platform device contract, hub.drivers.native) for tests and
local development: holds tag values, sends telemetry, carries out commands and acks them,
over HTTP, TCP or MQTT, signed in with its device credential.

Faults for tests: ``refuse`` (ack failed), ``silent`` (no ack, no new value), ``ack_only``
(acks done but never reports the value).

Firmware rules it shows: local control over the home network (``serve_local``: nonce, signed
commands and state, hub.platform.local_sign; the log of what it did goes to the hub afterwards),
pairing mode (``pair_http``; MQTT ``d/<id>/pairing``) and reconnecting
after a random delay (``reconnect_delay`` / ``run_forever``): a power cut must not bring
thousands of devices back in the same second.

    python -m simulators.native_device --http http://127.0.0.1:8000 --device d… --secret …
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import contextlib
import hashlib
import hmac
import json
import logging
import random
import ssl
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

import httpx

log = logging.getLogger(__name__)

FIRST_DELAY_MAX_S = 10.0          # the first try after a cut: 0..10 s
DELAY_CAP_S = 300.0               # never wait longer than 5 minutes
JITTER = 0.2                      # +-20 % on every wait
STABLE_S = 60.0                   # a session this long resets the delay


def reconnect_delay(attempt: int, rng: random.Random | None = None) -> float:
    """Seconds to wait before reconnect try ``attempt`` (0 = the first after a cut): random
    0..10 s first, then doubling up to 5 minutes, always +-20 % random."""
    rng = rng or random.Random()  # noqa: S311 - spreading reconnects, not security
    if attempt <= 0:
        return rng.uniform(0, FIRST_DELAY_MAX_S)
    base = min(DELAY_CAP_S, FIRST_DELAY_MAX_S * 2 ** (attempt - 1))
    return max(0.0, base * rng.uniform(1 - JITTER, 1 + JITTER))


async def run_forever(session: Callable[[], Awaitable[Any]], stop: asyncio.Event,
                      rng: random.Random | None = None,
                      sleep: Callable[[float], Awaitable[None]] = asyncio.sleep) -> None:
    """Keep a session (run_tcp / run_mqtt) up: after it ends or fails, wait reconnect_delay;
    a session that lasted STABLE_S starts the delays over."""
    attempt = 0
    while not stop.is_set():
        started = time.monotonic()
        with contextlib.suppress(OSError, ConnectionError, TimeoutError):
            await session()
        if stop.is_set():
            return
        attempt = 0 if time.monotonic() - started >= STABLE_S else attempt + 1
        await sleep(reconnect_delay(attempt - 1 if attempt else 0, rng))


@dataclass
class NativeDeviceSim:
    device_id: str
    secret: str
    values: dict[str, Any] = field(default_factory=dict)
    refuse: bool = False
    silent: bool = False
    ack_only: bool = False
    executed: list[dict[str, Any]] = field(default_factory=list)
    firmware: str = "1.0.0"
    bad_image: bool = False                 # pretend the download is damaged
    rules: dict[str, Any] = field(default_factory=dict)    # the last {"type": "rules"} set
    sms_key: str | None = None              # from {"type": "config", "sms": {...}}
    sms_counter: int = 0                    # the last accepted message's counter (kept in flash)
    clock_offset_s: float = 0.0             # hub time - own time, from the rules' server_time
    local_log: list[dict[str, Any]] = field(default_factory=list)   # rules run while cut off
    local_key: str | None = None            # from {"type": "config", "local": {...}}
    local_done: list[dict[str, Any]] = field(default_factory=list)  # phone commands, to report
    _nonces: dict[str, float] = field(default_factory=dict, repr=False)
    _outbox: asyncio.Queue[dict[str, Any]] | None = field(default=None, repr=False)

    @property
    def outbox(self) -> asyncio.Queue[dict[str, Any]]:
        """Messages the device sends by itself (a changed input, a released momentary key)."""
        if self._outbox is None:
            self._outbox = asyncio.Queue()
        return self._outbox

    def report(self, **changes: Any) -> None:
        """A value changed on the device (an input, a local rule): telemetry goes out now."""
        self.values.update(changes)
        self.outbox.put_nowait({"type": "telemetry", "values": dict(changes)})

    def telemetry(self) -> dict[str, Any]:
        return {"values": dict(self.values)}

    # --- messages that are not commands --------------------------------------------------------

    def receive(self, message: dict[str, Any]) -> None:
        """``rules`` (kept, replacing the earlier set; ``server_time`` sets the clock of a
        device without NTP) and ``config`` (the SMS signing key)."""
        if message.get("type") == "rules":
            self.rules = message
            if message.get("server_time"):
                hub = datetime.fromisoformat(message["server_time"].replace("Z", "+00:00"))
                self.clock_offset_s = (hub - datetime.now(UTC)).total_seconds()
        elif message.get("type") == "config" and isinstance(message.get("local"), dict):
            local = message["local"]
            self.local_key = local.get("key") if local.get("enabled") else None
            self._nonces.clear()                 # nonces of the old key end with it
            if isinstance(message.get("sms"), dict):
                self.receive({"type": "config", "sms": message["sms"]})
        elif message.get("type") == "config" and isinstance(message.get("sms"), dict):
            sms = message["sms"]
            new = sms.get("key") if sms.get("enabled") else None
            if new != self.sms_key:
                self.sms_counter = 0         # a new key starts a new count
            self.sms_key = new

    def sms(self, text: str) -> list[str]:
        """An SMS command as the app writes it: ``HUB <counter> relay_1=1 relay_3=0 <sig>``;
        the values are 1/0 for on/off or numbers, the counter grows with every message (the app
        uses the time in seconds) and ``sig`` is the first 8 bytes, in hex, of
        HMAC-SHA256(key, "<device_id> <counter> <items...>"). Returns the tags set; a wrong
        signature, a counter not above the last one (a replayed message) or an unknown tag sets
        nothing (the device answers nothing to a stranger)."""
        parts = text.strip().split()
        if len(parts) < 4 or parts[0].upper() != "HUB" or self.sms_key is None or \
                not parts[1].isdigit():
            return []
        counter, items, sig = int(parts[1]), parts[2:-1], parts[-1].lower()
        raw = base64.urlsafe_b64decode(self.sms_key + "=" * (-len(self.sms_key) % 4))
        signed = " ".join([self.device_id, str(counter), *items]).encode()
        if not hmac.compare_digest(hmac.new(raw, signed, hashlib.sha256).hexdigest()[:16], sig) \
                or counter <= self.sms_counter:
            return []
        changes: dict[str, Any] = {}
        for item in items:
            key, _, raw = item.partition("=")
            if key not in self.values or not raw:
                return []
            old = self.values[key]
            if isinstance(old, bool):
                changes[key] = raw in ("1", "on", "true")
            else:
                try:
                    changes[key] = float(raw)
                except ValueError:
                    return []
        self.sms_counter = counter
        self.values.update(changes)
        return sorted(changes)

    def run_local(self, now_local: Any) -> list[str]:
        """While cut off from the hub: one pass over the local rules (value triggers on the
        device's own values, time triggers at their minute). Returns the rule ids that ran."""
        ran = []
        ops = {"eq": lambda a, b: a == b, "ne": lambda a, b: a != b, "lt": lambda a, b: a < b,
               "le": lambda a, b: a <= b, "gt": lambda a, b: a > b, "ge": lambda a, b: a >= b}
        weekday = (now_local.weekday() + 2) % 7          # 0 = Saturday, as the hub
        for rule in self.rules.get("rules", []):
            tr = rule["trigger"]
            if tr["type"] == "value":
                value = self.values.get(tr["tag"])
                fire = value is not None and ops[tr["op"]](value, tr["value"])
            elif tr["type"] == "time":
                fire = now_local.strftime("%H:%M") == tr["at"] and \
                    (tr.get("weekdays") is None or weekday in tr["weekdays"])
            else:
                fire = False
            fire = fire and all(ops[c["op"]](self.values.get(c["tag"]), c["value"])
                                for c in rule.get("conditions", []))
            if not fire:
                continue
            for action in rule["actions"]:
                if action["type"] == "write" and self.values.get(action["tag"]) != action["value"]:
                    self.values[action["tag"]] = action["value"]
            ran.append(rule["id"])
            self.local_log.append({"rule": rule["id"], "at": now_local.isoformat()})
        return ran

    def handle(self, command: dict[str, Any]) -> list[dict[str, Any]]:
        """Messages the device sends back for one command (acks, then telemetry)."""
        cid = command.get("command_id")
        if self.silent:
            return []
        if self.refuse:
            return [{"type": "ack", "command_id": cid, "status": "failed",
                     "error": "refused by the simulator"}]
        if any(c.get("command_id") == cid for c in self.executed):     # idempotent
            return [{"type": "ack", "command_id": cid, "status": "done"}]
        self.executed.append(command)
        if command.get("pulse_s") and command.get("value") is True:   # momentary: release
            tag = command["tag"]                                       # by itself, on time
            asyncio.get_running_loop().call_later(float(command["pulse_s"]),
                                                  lambda: self.report(**{tag: False}))
        out = [{"type": "ack", "command_id": cid, "status": "received"}]
        if self.ack_only:
            return out + [{"type": "ack", "command_id": cid, "status": "done"}]
        self.values[command["tag"]] = command["value"]
        return out + [{"type": "ack", "command_id": cid, "status": "done",
                       "value": command["value"]},
                      {"type": "telemetry", **self.telemetry()}]

    # --- local control (home network) ---------------------------------------------------------

    def local_request(self, method: str, path: str, body: dict[str, Any] | None
                      ) -> tuple[int, dict[str, Any]]:
        """The device's own small web server on the home Wi-Fi (firmware contract)."""
        from hub.platform.local_sign import NONCE_TTL_S, new_nonce, verify

        now = time.monotonic()
        self._nonces = {n: t for n, t in self._nonces.items() if now - t < NONCE_TTL_S}
        if method == "GET" and path == "/local/v1/info":
            return 200, {"device_id": self.device_id, "firmware": self.firmware,
                         "local": self.local_key is not None}
        if self.local_key is None:
            return 403, {"ok": False, "error": "local control is not set up"}
        if method == "GET" and path == "/local/v1/nonce":
            if len(self._nonces) >= 16:
                return 429, {"ok": False, "error": "too many open nonces"}
            nonce = new_nonce()
            self._nonces[nonce] = now
            return 200, {"device_id": self.device_id, "nonce": nonce, "ttl_s": NONCE_TTL_S}
        if method != "POST" or not isinstance(body, dict):
            return 404, {"ok": False, "error": "not found"}
        nonce = str(body.get("nonce", ""))
        if self._nonces.pop(nonce, None) is None:          # used, expired or never issued
            return 401, {"ok": False, "error": "nonce"}
        if path == "/local/v1/state":
            if not verify(self.local_key, body.get("sig", ""), self.device_id, nonce, "state"):
                return 401, {"ok": False, "error": "signature"}
            return 200, {"ok": True, "values": dict(self.values)}
        if path == "/local/v1/command":
            tag, value_json = str(body.get("tag", "")), str(body.get("value_json", ""))
            if not verify(self.local_key, body.get("sig", ""), self.device_id, nonce,
                          "command", tag, value_json):
                return 401, {"ok": False, "error": "signature"}
            if self.refuse:
                return 200, {"ok": False, "error": "refused by the device"}
            value = json.loads(value_json)
            self.values[tag] = value
            self.local_done.append({"at": datetime.now(UTC).isoformat(), "tag": tag,
                                    "value": value, "by": "local"})
            return 200, {"ok": True, "tag": tag, "value": value}
        return 404, {"ok": False, "error": "not found"}

    async def serve_local(self, host: str = "127.0.0.1", port: int = 0,
                        ready: asyncio.Event | None = None) -> None:
        """Serve local_request over plain HTTP/1.1 (one request per connection), as a
        microcontroller would; ``self.local_port`` is the bound port."""
        crlf = "\r\n"

        async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            try:
                head = await asyncio.wait_for(reader.readuntil((crlf * 2).encode()), 5)
                lines = head.decode("latin-1").split(crlf)
                method, path, _ = lines[0].split(" ", 2)
                length = next((int(h.split(":", 1)[1]) for h in lines[1:]
                               if h.lower().startswith("content-length:")), 0)
                raw = await reader.readexactly(min(length, 4096)) if length else b""
                body = json.loads(raw) if raw else None
                status, answer = self.local_request(method, path.split("?")[0], body)
            except (ValueError, asyncio.IncompleteReadError, TimeoutError):
                status, answer = 400, {"ok": False, "error": "bad request"}
            data = json.dumps(answer).encode()
            head_out = crlf.join([f"HTTP/1.1 {status} X", "Content-Type: application/json",
                                  f"Content-Length: {len(data)}", "Connection: close", "", ""])
            writer.write(head_out.encode() + data)
            with contextlib.suppress(Exception):
                await writer.drain()
                writer.close()

        server = await asyncio.start_server(handle, host, port)
        self.local_port = server.sockets[0].getsockname()[1]
        if ready is not None:
            ready.set()
        async with server:
            await server.serve_forever()

    async def report_local_http(self, client: httpx.AsyncClient) -> int:
        """Back online: tell the hub what the phone switched over the home network."""
        if not self.local_done:
            return 0
        r = await client.post(f"/ingest/v1/devices/{self.device_id}/local_log",
                              headers={"Authorization": f"Bearer {self.secret}"},
                              json={"entries": self.local_done})
        if r.status_code == 200:
            sent, self.local_done = len(self.local_done), []
            await client.post(f"/ingest/v1/devices/{self.device_id}/telemetry",
                              headers={"Authorization": f"Bearer {self.secret}"},
                              json=self.telemetry())
            return sent
        return 0

    # --- HTTP ---------------------------------------------------------------------------------

    async def pair_http(self, client: httpx.AsyncClient) -> int:
        """The owner held the pairing button: tell the hub (works before the device is claimed
        or enabled); returns the HTTP status."""
        r = await client.post(f"/ingest/v1/devices/{self.device_id}/pairing",
                              headers={"Authorization": f"Bearer {self.secret}"})
        return r.status_code

    async def run_http(self, client: httpx.AsyncClient, period_s: float = 0.1,
                       stop: asyncio.Event | None = None) -> None:
        """Send telemetry and fetch commands every period (client: base_url = the hub)."""
        stop = stop or asyncio.Event()
        base = f"/ingest/v1/devices/{self.device_id}"
        headers = {"Authorization": f"Bearer {self.secret}"}
        await client.post(f"{base}/telemetry", headers=headers, json=self.telemetry())
        while not stop.is_set():
            r = await client.get(f"{base}/commands", headers=headers)
            for command in r.json() if r.status_code == 200 else []:
                if command.get("type") == "ota":
                    await self._ota_http(client, headers, base, command)
                    continue
                if command.get("type") in ("rules", "config"):
                    self.receive(command)
                    continue
                for message in self.handle(command):
                    kind = message.pop("type")
                    await client.post(f"{base}/{kind}", headers=headers, json=message)
            while not self.outbox.empty():
                message = self.outbox.get_nowait()
                kind = message.pop("type")
                await client.post(f"{base}/{kind}", headers=headers, json=message)
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(stop.wait(), period_s)

    async def _ota_http(self, client: httpx.AsyncClient, headers: dict[str, str], base: str,
                        offer: dict[str, Any]) -> None:
        """Download, check the SHA-256, install (just the version here), report."""
        import hashlib

        job = offer["job_id"]
        await client.post(f"{base}/ota", headers=headers,
                          json={"job_id": job, "status": "downloading"})
        r = await client.get(offer["url"], headers=headers)
        digest = hashlib.sha256(r.content).hexdigest()
        ok = r.status_code == 200 and not self.bad_image and digest == offer["sha256"]
        if ok:
            self.firmware = offer["version"]
        await client.post(f"{base}/ota", headers=headers, json={
            "job_id": job, "status": "installed" if ok else "failed",
            "version": self.firmware, "error": None if ok else "checksum mismatch"})

    # --- TCP ----------------------------------------------------------------------------------

    async def run_tcp(self, host: str, port: int, *, tls: ssl.SSLContext | None = None,
                      ready: asyncio.Event | None = None) -> dict[str, Any]:
        """One session; returns the hub's answer to the sign-in when it refuses it."""
        reader, writer = await asyncio.open_connection(host, port, ssl=tls)

        async def send(message: dict[str, Any]) -> None:
            writer.write(json.dumps(message).encode() + b"\n")
            await writer.drain()

        try:
            await send({"device_id": self.device_id, "secret": self.secret})
            answer = json.loads(await reader.readline() or b"{}")
            if not answer.get("ok"):
                return answer
            await send({"type": "telemetry", **self.telemetry()})
            if ready is not None:
                ready.set()

            async def pump() -> None:
                while True:
                    await send(await self.outbox.get())
            pumping = asyncio.create_task(pump())
            while line := await reader.readline():
                message = json.loads(line)
                if message.get("type") == "command":
                    for reply in self.handle(message):
                        await send(reply)
                elif message.get("type") in ("rules", "config"):
                    self.receive(message)
            return answer
        finally:
            if "pumping" in locals():
                pumping.cancel()
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()

    # --- MQTT ---------------------------------------------------------------------------------

    async def run_mqtt(self, host: str, port: int, prefix: str = "",
                       ready: asyncio.Event | None = None) -> None:
        import aiomqtt

        base = f"{prefix}d/{self.device_id}"
        async with aiomqtt.Client(host, port, username=self.device_id, password=self.secret,
                                  identifier=f"sim-{self.device_id}") as client:
            for topic in ("cmd", "rules", "config"):
                await client.subscribe(f"{base}/{topic}", qos=1)
            await client.publish(f"{base}/telemetry", json.dumps(self.telemetry()), qos=1)
            if ready is not None:
                ready.set()

            async def pump() -> None:
                while True:
                    message = await self.outbox.get()
                    kind = message.pop("type")
                    await client.publish(f"{base}/{kind}", json.dumps(message), qos=1)
            pumping = asyncio.create_task(pump())
            try:
                async for message in client.messages:
                    command = json.loads(message.payload)
                    if str(message.topic).rsplit("/", 1)[-1] in ("rules", "config"):
                        self.receive(command)
                        continue
                    for reply in self.handle(command):
                        kind = reply.pop("type")
                        await client.publish(f"{base}/{kind}", json.dumps(reply), qos=1)
            finally:
                pumping.cancel()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m simulators.native_device")
    parser.add_argument("--device", required=True)
    parser.add_argument("--secret", required=True)
    parser.add_argument("--http", help="hub address, e.g. http://127.0.0.1:8000")
    parser.add_argument("--tcp", help="host:port of HUB_TCP_INGEST_PORT (plain TCP)")
    parser.add_argument("--value", action="append", default=[], metavar="TAG=JSON")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    values = {k: json.loads(v) for k, _, v in (a.partition("=") for a in args.value)}
    sim = NativeDeviceSim(args.device, args.secret, values)

    async def run() -> None:
        if args.tcp:
            host, _, port = args.tcp.rpartition(":")
            print(await sim.run_tcp(host, int(port)))
        elif args.http:
            async with httpx.AsyncClient(base_url=args.http, timeout=10) as client:
                await sim.run_http(client, period_s=1.0)

    asyncio.run(run())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
