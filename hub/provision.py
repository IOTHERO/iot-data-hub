"""``hub-provision``: write each board's identity on the production line.

The maker panel's label export with credentials (Labels / Production -> CSV) is a CSV with
``identifier, serial_number, claim_code, qr, device_id, device_secret``. This tool talks to one
board at a time over its USB serial port (or any pyserial URL, e.g. ``socket://`` for the
simulator) and writes ``device_id`` and ``device_secret`` into it:

    hub-provision --csv codes.csv --port COM5 [--server https://hub.example.com] [--repeat]

The board's side (firmware contract, one JSON object per line, 115200 8N1):

* ``{"cmd": "hello"}`` -> ``{"ok": true, "serial": "<its serial or null>", "provisioned": false,
  "firmware": "1.4.2"}``
* ``{"cmd": "provision", "device_id", "secret", "identifier", "server"?}`` -> the board keeps them
  in protected storage (encrypted NVS) and answers ``{"ok": true, "check": <proof>}`` where proof
  is the first 16 hex characters of HMAC-SHA256(secret, device_id). The secret never comes back.

Rules: a board that says it is already provisioned is refused (factory-reset it first); a row
already in the log is never written again (a second export issues new secrets and the old ones
stop working, so each row is used once); the log and the screen never show a secret. Delete the
CSV when the batch is done.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import hmac
import json
import logging
import sys
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol

log = logging.getLogger("hub.provision")

REQUIRED = ("identifier", "device_id", "device_secret")
LOG_FIELDS = ("at", "identifier", "serial_number", "device_id", "port", "firmware")


class ProvisionError(RuntimeError):
    """The board refused or did not prove it stored the identity; nothing is logged."""


def proof(secret: str, device_id: str) -> str:
    """What the board answers to show it holds the right secret (without sending it)."""
    return hmac.new(secret.encode(), device_id.encode(), hashlib.sha256).hexdigest()[:16]


class Link(Protocol):
    def ask(self, message: dict[str, Any]) -> dict[str, Any]: ...

    def close(self) -> None: ...


class SerialLink:
    """One JSON line out, one JSON line back, over a pyserial port or URL."""

    def __init__(self, port: str, baud: int = 115200, timeout_s: float = 5.0) -> None:
        import serial  # pyserial: already a runtime dependency (Modbus RTU)

        self._port = serial.serial_for_url(port, baudrate=baud, timeout=timeout_s)
        self._port.reset_input_buffer()

    def ask(self, message: dict[str, Any]) -> dict[str, Any]:
        self._port.write((json.dumps(message) + "\n").encode())
        self._port.flush()
        for _ in range(20):  # skip the board's own boot / log lines
            line = self._port.readline()
            if not line:
                raise ProvisionError("the board did not answer (port, cable, baud rate?)")
            text = line.decode("utf-8", "replace").strip()
            if text.startswith("{"):
                try:
                    answer = json.loads(text)
                except ValueError:
                    continue
                if isinstance(answer, dict):
                    return answer
        raise ProvisionError("the board answered only with log lines")

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


def read_rows(path: Path) -> list[Row]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit(
                f"{path.name}: no {', '.join(missing)} column - export the labels "
                "with credentials in the maker panel"
            )
        rows = [
            Row(
                r["identifier"].strip(),
                (r.get("serial_number") or "").strip(),
                (r.get("claim_code") or "").strip(),
                (r.get("qr") or "").strip(),
                r["device_id"].strip(),
                r["device_secret"].strip(),
            )
            for r in reader
        ]
    return [r for r in rows if r.device_id and r.device_secret]


def done_ids(log_path: Path) -> set[str]:
    if not log_path.exists():
        return set()
    with log_path.open(encoding="utf-8", newline="") as f:
        return {r["device_id"] for r in csv.DictReader(f) if r.get("device_id")}


def _append_log(log_path: Path, row: Row, port: str, firmware: str) -> None:
    new = not log_path.exists()
    with log_path.open("a", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=LOG_FIELDS)
        if new:
            w.writeheader()
        w.writerow(
            {
                "at": datetime.now(UTC).isoformat(timespec="seconds"),
                "identifier": row.identifier,
                "serial_number": row.serial_number,
                "device_id": row.device_id,
                "port": port,
                "firmware": firmware,
            }
        )


def pick(rows: Iterable[Row], used: set[str], board_serial: str | None) -> Row:
    """The board's own row when it reports its serial, else the next unused one."""
    free = [r for r in rows if r.device_id not in used]
    if board_serial:
        mine = [r for r in rows if r.serial_number == board_serial]
        if not mine:
            raise ProvisionError(f"serial {board_serial} is not in this CSV (another batch?)")
        if mine[0].device_id in used:
            raise ProvisionError(
                f"serial {board_serial} was provisioned already ({mine[0].identifier})"
            )
        return mine[0]
    if not free:
        raise ProvisionError("every row of this CSV is provisioned: export the next batch")
    return free[0]


def provision_one(
    link: Link, rows: list[Row], log_path: Path, port: str, server: str | None = None
) -> Row:
    hello = link.ask({"cmd": "hello"})
    if not hello.get("ok"):
        raise ProvisionError(f"the board refused hello: {hello.get('error', hello)}")
    if hello.get("provisioned"):
        raise ProvisionError("the board already holds an identity: factory-reset it first")
    row = pick(rows, done_ids(log_path), hello.get("serial") or None)
    message: dict[str, Any] = {
        "cmd": "provision",
        "device_id": row.device_id,
        "secret": row.device_secret,
        "identifier": row.identifier,
    }
    if server:
        message["server"] = server
    answer = link.ask(message)
    if not answer.get("ok"):
        raise ProvisionError(f"the board refused the identity: {answer.get('error', answer)}")
    if not hmac.compare_digest(
        str(answer.get("check", "")), proof(row.device_secret, row.device_id)
    ):
        raise ProvisionError("the board's proof does not match: the identity was not stored right")
    _append_log(log_path, row, port, str(hello.get("firmware") or ""))
    return row


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="hub-provision", description=__doc__.split("\n\n")[0])
    p.add_argument(
        "--csv", required=True, type=Path, help="the maker panel's export with credentials"
    )
    p.add_argument("--port", required=True, help="COM5, /dev/ttyUSB0 or a pyserial URL")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--server", help="the server address the board should use (optional)")
    p.add_argument("--log", type=Path, help="provisioned boards (default: <csv>.provisioned.csv)")
    p.add_argument("--repeat", action="store_true", help="one board after another until Ctrl+C")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    rows = read_rows(args.csv)
    log_path = args.log or args.csv.with_suffix(".provisioned.csv")
    log.info(
        "%d boards in %s, %d provisioned already", len(rows), args.csv.name, len(done_ids(log_path))
    )
    failed = 0
    while True:
        try:
            link = SerialLink(args.port, args.baud)
            try:
                row = provision_one(link, rows, log_path, args.port, args.server)
            finally:
                link.close()
            # the label: identifier and activation code (the secret is never shown)
            log.info(
                "OK  %s  serial %s  label: %s  %s",
                row.identifier,
                row.serial_number or "-",
                row.claim_code,
                row.qr,
            )
        except ProvisionError as e:
            failed += 1
            log.error("FAILED  %s", e)
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
