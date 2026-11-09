"""A fresh TiTiRelay8 board on the production line, for ``hub-provision`` (hub/provision.py).

It speaks the board's serial console (the TiTiRelay8 firmware's console.cpp) on a TCP port,
which pyserial reaches as ``socket://127.0.0.1:<port>``, the way the real board answers on its
USB serial port: a boot banner with the MAC, one command per line, answers starting with "> ",
edits kept in a draft until ``save``.

    python -m simulators.factory_board --port 7700 [--mac 24:6F:28:AA:BB:CC]
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import logging
from dataclasses import dataclass, field

log = logging.getLogger("simulators.factory_board")


@dataclass
class _Settings:
    device_id: str = ""
    secret: str = ""
    host: str = ""
    port: int = 0
    tls: bool = False
    api: str = ""
    mode: str = "unset"


@dataclass
class FactoryBoard:
    mac: str = "24:6F:28:AA:BB:CC"
    firmware: str = "1.4.2"
    broken_storage: bool = False        # a faulty board: save fails
    saved: _Settings = field(default_factory=_Settings)
    draft: _Settings | None = None
    qr: str = ""
    serial: str = ""
    port: int = 0

    def _d(self) -> _Settings:
        if self.draft is None:
            self.draft = _Settings(**vars(self.saved))
        return self.draft

    def _show(self) -> list[str]:
        s = self.draft or self.saved
        out = [f"model TiTiRelay8 fw {self.firmware}{'  (unsaved changes)' if self.draft else ''}",
               f'mode {s.mode}  device id "{s.device_id}"  api "{s.api}"']
        if s.host:
            out.append(f'server 1: platform {s.host}:{s.port}{" tls" if s.tls else ""} '
                       f'user "{s.device_id}" secret {"set" if s.secret else "empty"}')
        out.append(f'label: serial "{self.serial}", qr {"stored" if self.qr else "empty"}')
        return out

    def run(self, line: str) -> list[str]:
        cmd, _, arg = line.strip().partition(" ")
        arg = arg.strip()
        if cmd == "show":
            return self._show()
        if cmd == "id" and arg:
            self._d().device_id = arg
            return ["device id set (also the server username)"]
        if cmd == "secret" and arg:
            self._d().secret = arg
            return ["secret set"]
        if cmd == "server" and arg:
            parts = arg.split()
            d = self._d()
            d.host = parts[0]
            port = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
            d.tls = (len(parts) > 2 and parts[2] == "tls") or port == 8883
            d.port = port or (8883 if d.tls else 1883)
            return ["platform server set"]
        if cmd == "api":
            self._d().api = arg
            return ["hub address set"]
        if cmd == "mode":
            if arg not in ("wifi", "rs485"):
                return ["mode wifi | mode rs485"]
            self._d().mode = arg
            return ["mode set"]
        if cmd == "save":
            if self.draft is None:
                return ["nothing to save"]
            if self.broken_storage:
                return ["storage error"]
            if not self.draft.device_id or not self.draft.secret or not self.draft.host:
                return ["refused: device id, secret and server are required"]
            self.saved, self.draft = self.draft, None
            return ["saved; restart to use"]
        if cmd == "qr":
            if not arg.startswith(("http://", "https://")) or len(arg) > 200:
                return ["refused: an http(s) link up to 200 characters"]
            self.qr = arg
            return ["label QR stored"]
        if cmd == "serial":
            if len(arg) > 40:
                return ["refused: up to 40 characters"]
            self.serial = arg
            return ["serial number stored"]
        if cmd == "factory" and arg == "yes":
            self.saved, self.draft = _Settings(), None
            return ["factory reset"]
        return ["unknown command (help)"]

    async def serve(self, host: str = "127.0.0.1", port: int = 0,
                    ready: asyncio.Event | None = None) -> None:
        async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            # a reset on every port opening: the ESP32 boots for a moment, then its banner (sent
            # at once it would be emptied by the port's opening, which drops waiting input)
            await asyncio.sleep(0.15)
            writer.write(f"TiTiRelay8 {self.firmware} boot, MAC {self.mac}\r\n".encode())
            try:
                while line := await reader.readline():
                    for out in self.run(line.decode("utf-8", "replace")):
                        writer.write(f"> {out}\r\n".encode())
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
    p.add_argument("--mac", default="24:6F:28:AA:BB:CC")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    board = FactoryBoard(mac=args.mac)
    log.info("factory board on socket://127.0.0.1:%d", args.port)
    run(board.serve(port=args.port))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
