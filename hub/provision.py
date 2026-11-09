"""``hub-provision``: write each board's identity on the production line.

The maker panel's label export with credentials (Labels / Production -> CSV) is a CSV with
``identifier, serial_number, claim_code, qr, device_id, device_secret``. This tool talks to one
board at a time over its USB serial port (or any pyserial URL, e.g. ``socket://`` for the
simulator) and writes the identity through the board's own serial console - the TiTiRelay8
firmware's console (console.cpp), the same commands as that repository's tools/program_units.py:

    hub-provision --csv codes.csv --port COM5 --broker 192.168.1.173:8883 \
        --api https://192.168.1.173 [--mode wifi] [--repeat]

Console (115200 8N1, one command per line, answers start with "> "):
``show`` (``device id "<id>"`` and ``server ... secret set|empty``), ``id <device_id>``,
``secret <secret>``, ``server <host> <port> tls``, ``api <url>``, ``mode wifi|rs485``, ``save``,
``qr <link>``, ``serial <sn>``; a refusal starts with ``refused`` / ``unknown`` / ``storage``.

Rules: a board that already holds a device id is refused (``factory yes`` on its console first);
a row already in the log is never written again (a second export issues new secrets and the old
ones stop working, so each row is used once); after ``save`` the board must show the new device
id with its secret set; the log and the screen never show a secret. Delete the CSV when the batch
is done. The device CA (deploy/ca/ca.crt for a private CA) is set in the board's set-up portal.
"""

from __future__ import annotations

import argparse
import csv
import logging
import re
import sys
import time
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol

log = logging.getLogger("hub.provision")

REQUIRED = ("identifier", "device_id", "device_secret")
LOG_FIELDS = ("at", "identifier", "serial_number", "device_id", "mac", "port")
REFUSED = ("refused", "unknown", "storage")


class ProvisionError(RuntimeError):
    """The board refused or does not show what was written; nothing is logged."""


class Console(Protocol):
    banner: str

    def ask(self, line: str) -> str: ...

    def close(self) -> None: ...


class SerialConsole:
    """The board's line console over a pyserial port or URL: one command, its "> " answers."""

    def __init__(self, port: str, baud: int = 115200, boot_wait_s: float = 3.0,
                 reply_timeout_s: float = 3.0) -> None:
        import serial  # pyserial: already a runtime dependency (Modbus RTU)

        self._timeout = reply_timeout_s
        self._port = serial.serial_for_url(port, baudrate=baud, timeout=0.2)
        # opening the port resets an ESP32: wait for its boot banner (it carries the MAC)
        deadline = time.monotonic() + boot_wait_s
        text = b""
        while time.monotonic() < deadline or (not text and time.monotonic() < deadline + 2):
            chunk = self._port.read(256)
            text += chunk
            if text and not chunk and b"MAC" in text:
                break                          # the banner is in and the board went quiet
        self.banner = text.decode("utf-8", "replace")

    def ask(self, line: str) -> str:
        self._port.reset_input_buffer()
        self._port.write((line + "\n").encode())
        self._port.flush()
        answer: list[str] = []
        deadline = time.monotonic() + self._timeout
        while time.monotonic() < deadline:
            raw = self._port.readline().decode("utf-8", "replace").strip()
            if raw.startswith(">"):
                answer.append(raw[1:].strip())
                deadline = min(deadline, time.monotonic() + 0.3)   # a few more lines may follow
        return " | ".join(answer)

    def close(self) -> None:
        self._port.close()


@dataclass
class Row:
    identifier: str
    serial_number: str
    claim_code: str
    qr: str
    device_id: str
    device_secret: str


@dataclass
class Target:
    """Where the board should connect: the platform broker and the hub's HTTPS address."""

    broker_host: str
    broker_port: int = 8883
    tls: bool = True
    api: str | None = None
    mode: str | None = None


def read_rows(path: Path) -> list[Row]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit(f"{path.name}: no {', '.join(missing)} column - export the labels "
                             "with credentials in the maker panel")
        rows = [Row(r["identifier"].strip(), (r.get("serial_number") or "").strip(),
                    (r.get("claim_code") or "").strip(), (r.get("qr") or "").strip(),
                    r["device_id"].strip(), r["device_secret"].strip()) for r in reader]
    return [r for r in rows if r.device_id and r.device_secret]


def done_ids(log_path: Path) -> set[str]:
    if not log_path.exists():
        return set()
    with log_path.open(encoding="utf-8", newline="") as f:
        return {r["device_id"] for r in csv.DictReader(f) if r.get("device_id")}


def _append_log(log_path: Path, row: Row, mac: str, port: str) -> None:
    new = not log_path.exists()
    with log_path.open("a", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=LOG_FIELDS)
        if new:
            w.writeheader()
        w.writerow({"at": datetime.now(UTC).isoformat(timespec="seconds"),
                    "identifier": row.identifier, "serial_number": row.serial_number,
                    "device_id": row.device_id, "mac": mac, "port": port})


def next_row(rows: Iterable[Row], used: set[str]) -> Row:
    for r in rows:
        if r.device_id not in used:
            return r
    raise ProvisionError("every row of this CSV is provisioned: export the next batch")


def _shown_device_id(show: str) -> str:
    m = re.search(r'device id "([^"]*)"', show)
    return m.group(1) if m else ""


def _step(console: Console, line: str, shown: str) -> str:
    answer = console.ask(line)
    if not answer or answer.lower().startswith(REFUSED):
        raise ProvisionError(f"the board refused {shown}: {answer or 'no answer'}")
    return answer


def provision_one(console: Console, rows: list[Row], log_path: Path, port: str,
                  target: Target) -> Row:
    before = console.ask("show")
    if not before:
        raise ProvisionError("the board did not answer (port, cable, baud rate, firmware?)")
    if _shown_device_id(before):
        raise ProvisionError("the board already holds a device id: 'factory yes' on its "
                             "console first")
    row = next_row(rows, done_ids(log_path))
    steps = [
        (f"id {row.device_id}", f"id {row.device_id}"),
        (f"secret {row.device_secret}", "secret ********"),
        (f"server {target.broker_host} {target.broker_port}{' tls' if target.tls else ''}",
         "server"),
    ]
    if target.api:
        steps.append((f"api {target.api}", "api"))
    if target.mode:
        steps.append((f"mode {target.mode}", "mode"))
    steps.append(("save", "save"))
    if row.qr:
        steps.append((f"qr {row.qr}", "qr <label link>"))
    if row.serial_number:
        steps.append((f"serial {row.serial_number}", "serial"))
    for line, shown in steps:
        _step(console, line, shown)
    after = console.ask("show")
    if _shown_device_id(after) != row.device_id or "secret set" not in after:
        raise ProvisionError("the board does not show the new device id with its secret set")
    m = re.search(r"MAC ([0-9A-Fa-f:]{17})", console.banner)
    _append_log(log_path, row, m.group(1) if m else "", port)
    return row


def _target(args: argparse.Namespace) -> Target:
    host, _, port = args.broker.partition(":")
    return Target(host, int(port) if port else (1883 if args.no_tls else 8883),
                  not args.no_tls, args.api, args.mode)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="hub-provision", description=__doc__.split("\n\n")[0])
    p.add_argument("--csv", required=True, type=Path,
                   help="the maker panel's export with credentials")
    p.add_argument("--port", required=True, help="COM5, /dev/ttyUSB0 or a pyserial URL")
    p.add_argument("--broker", required=True, help="the platform MQTT broker host[:port]")
    p.add_argument("--no-tls", action="store_true", help="plain MQTT (development only)")
    p.add_argument("--api", help="the hub's HTTPS address (rules, settings, firmware updates)")
    p.add_argument("--mode", choices=["wifi", "rs485"], help="preset the link (else the portal)")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--boot-wait", type=float, default=3.0, help="seconds for the boot banner")
    p.add_argument("--log", type=Path, help="provisioned boards (default: <csv>.provisioned.csv)")
    p.add_argument("--repeat", action="store_true", help="one board after another until Ctrl+C")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    rows = read_rows(args.csv)
    log_path = args.log or args.csv.with_suffix(".provisioned.csv")
    target = _target(args)
    log.info("%d boards in %s, %d provisioned already", len(rows), args.csv.name,
             len(done_ids(log_path)))
    failed = 0
    while True:
        try:
            console = SerialConsole(args.port, args.baud, args.boot_wait)
            try:
                row = provision_one(console, rows, log_path, args.port, target)
            finally:
                console.close()
            # the label: identifier and activation code (the secret is never shown)
            log.info("OK  %s  serial %s  label: %s  %s", row.identifier,
                     row.serial_number or "-", row.claim_code, row.qr)
        except ProvisionError as e:
            failed += 1
            log.error("FAILED  %s (the row stays free)", e)
        except OSError as e:
            failed += 1
            log.error("FAILED  port %s: %s", args.port, e)
        if not args.repeat:
            return 1 if failed else 0
        try:
            input("next board on the port, then Enter (Ctrl+C to stop) ")
        except (KeyboardInterrupt, EOFError):
            log.info("")
            return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
