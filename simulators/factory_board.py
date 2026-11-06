"""A fresh board on the production line, for ``hub-provision`` (hub/provision.py).

It speaks the provisioning contract - one JSON object per line - on a TCP port, which pyserial
reaches as ``socket://127.0.0.1:<port>``, the way a real board answers on its USB serial port. It
prints a boot line first, like firmware does, keeps what it was given, and proves it holds the
secret with HMAC-SHA256(secret, device_id)[:16].

    python -m simulators.factory_board --port 7700 [--serial SN-0001]
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import hashlib
import hmac
import json
import logging
from typing import Any

log = logging.getLogger("simulators.factory_board")


class FactoryBoard:
    def __init__(
        self, serial: str | None = None, firmware: str = "1.0.0", *, lie: bool = False
    ) -> None:
        self.serial = serial
        self.firmware = firmware
        self.lie = lie  # a broken board: stores a wrong secret
        self.identity: dict[str, Any] | None = None
        self.port = 0

    def answer(self, message: dict[str, Any]) -> dict[str, Any]:
        cmd = message.get("cmd")
        if cmd == "hello":
            return {
                "ok": True,
                "serial": self.serial,
                "provisioned": self.identity is not None,
                "firmware": self.firmware,
            }
        if cmd == "provision":
            if self.identity is not None:
                return {"ok": False, "error": "already provisioned"}
            device_id, secret = str(message.get("device_id", "")), str(message.get("secret", ""))
            if not device_id or len(secret) < 16:
                return {"ok": False, "error": "device_id and secret are required"}
            if self.lie:
                secret = secret[::-1]
            self.identity = {
                "device_id": device_id,
                "secret": secret,
                "identifier": message.get("identifier"),
                "server": message.get("server"),
            }
            check = hmac.new(secret.encode(), device_id.encode(), hashlib.sha256).hexdigest()[:16]
            return {"ok": True, "check": check}
        if cmd == "factory_reset":
            self.identity = None
            return {"ok": True}
        return {"ok": False, "error": f"unknown command {cmd!r}"}

    async def serve(
        self, host: str = "127.0.0.1", port: int = 0, ready: asyncio.Event | None = None
    ) -> None:
        async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            writer.write(f"boot: titiswitch {self.firmware}\n".encode())  # a log line first
            try:
                while line := await reader.readline():
                    try:
                        message = json.loads(line)
                        reply = self.answer(message) if isinstance(message, dict) else {"ok": False}
                    except ValueError:
                        reply = {"ok": False, "error": "bad json"}
                    writer.write((json.dumps(reply) + "\n").encode())
                    await writer.drain()
            finally:
                with contextlib.suppress(Exception):
                    writer.close()

        server = await asyncio.start_server(handle, host, port)
        self.port = server.sockets[0].getsockname()[1]
        if ready is not None:
            ready.set()
        async with server:
            await server.serve_forever()


def main(argv: list[str] | None = None) -> int:
    from hub.runtime import run

    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--port", type=int, default=7700)
    p.add_argument("--serial")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    board = FactoryBoard(args.serial)
    log.info("factory board on socket://127.0.0.1:%d", args.port)
    run(board.serve(port=args.port))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
