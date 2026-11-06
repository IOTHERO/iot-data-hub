"""hub-provision against the factory-board simulator, over pyserial's socket:// URL (the same
code path as a USB serial port): the identity goes in once, the board proves it without sending
the secret back, and the log never holds a secret."""

from __future__ import annotations

import asyncio
import contextlib
import csv
import threading
from collections.abc import Iterator
from pathlib import Path

import pytest

from hub.provision import ProvisionError, SerialLink, main, provision_one, read_rows
from hub.runtime import new_event_loop
from simulators.factory_board import FactoryBoard

pytestmark = pytest.mark.integration

SECRET_A = "s3cr3t-aaaaaaaaaaaaaaaaaaaaaaaa"
SECRET_B = "s3cr3t-bbbbbbbbbbbbbbbbbbbbbbbb"


@pytest.fixture
def codes(tmp_path: Path) -> Path:
    path = tmp_path / "codes.csv"
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["identifier", "serial_number", "claim_code", "qr", "device_id", "device_secret"]
        )
        w.writerow(
            [
                "CTRL-8R-0001",
                "SN-1",
                "AAAA-BBBB-CCCC",
                "https://x/#/claim/CTRL-8R-0001/AAAA",
                "d1aaaa",
                SECRET_A,
            ]
        )
        w.writerow(
            [
                "CTRL-8R-0002",
                "SN-2",
                "DDDD-EEEE-FFFF",
                "https://x/#/claim/CTRL-8R-0002/DDDD",
                "d2bbbb",
                SECRET_B,
            ]
        )
    return path


def _serve(board: FactoryBoard) -> Iterator[str]:
    """The board on its own thread and loop (hub-provision is a blocking command-line tool)."""
    loop = new_event_loop()
    ready = threading.Event()
    task: list[asyncio.Task[None]] = []

    async def start() -> None:
        started = asyncio.Event()
        task.append(asyncio.create_task(board.serve(ready=started)))
        await started.wait()
        ready.set()
        with contextlib.suppress(asyncio.CancelledError):
            await task[0]

    thread = threading.Thread(target=lambda: loop.run_until_complete(start()), daemon=True)
    thread.start()
    assert ready.wait(5)
    try:
        yield f"socket://127.0.0.1:{board.port}"
    finally:
        loop.call_soon_threadsafe(task[0].cancel)
        thread.join(5)
        loop.close()


@pytest.fixture
def board() -> FactoryBoard:
    return FactoryBoard()


@pytest.fixture
def port(board: FactoryBoard) -> Iterator[str]:
    yield from _serve(board)


def _once(port: str, codes: Path, log: Path, server: str | None = None):
    link = SerialLink(port, timeout_s=3)
    try:
        return provision_one(link, read_rows(codes), log, port, server)
    finally:
        link.close()


def test_identity_goes_in_and_the_log_has_no_secret(
    board: FactoryBoard, port: str, codes: Path, tmp_path: Path
) -> None:
    log = tmp_path / "done.csv"
    row = _once(port, codes, log, "https://hub.example.test")
    assert row.identifier == "CTRL-8R-0001"
    assert board.identity == {
        "device_id": "d1aaaa",
        "secret": SECRET_A,
        "identifier": "CTRL-8R-0001",
        "server": "https://hub.example.test",
    }
    text = log.read_text(encoding="utf-8")
    assert "d1aaaa" in text and SECRET_A not in text and "s3cr3t" not in text


def test_a_provisioned_board_is_refused_and_the_next_board_gets_the_next_row(
    board: FactoryBoard, port: str, codes: Path, tmp_path: Path
) -> None:
    log = tmp_path / "done.csv"
    _once(port, codes, log)
    with pytest.raises(ProvisionError, match="factory-reset"):
        _once(port, codes, log)  # the same board again
    board.answer({"cmd": "factory_reset"})  # "the next board" on the same port
    row = _once(port, codes, log)
    assert row.device_id == "d2bbbb"  # never the first row twice
    board.answer({"cmd": "factory_reset"})
    with pytest.raises(ProvisionError, match="every row"):
        _once(port, codes, log)


def test_a_board_that_knows_its_serial_gets_its_own_row(codes: Path, tmp_path: Path) -> None:
    board = FactoryBoard(serial="SN-2")
    for port in _serve(board):
        assert _once(port, codes, tmp_path / "done.csv").identifier == "CTRL-8R-0002"
    stranger = FactoryBoard(serial="SN-99")
    for port in _serve(stranger):
        with pytest.raises(ProvisionError, match="not in this CSV"):
            _once(port, codes, tmp_path / "done.csv")


def test_a_wrong_proof_is_not_logged(codes: Path, tmp_path: Path) -> None:
    broken = FactoryBoard(lie=True)
    log = tmp_path / "done.csv"
    for port in _serve(broken):
        with pytest.raises(ProvisionError, match="proof"):
            _once(port, codes, log)
    assert not log.exists()


def test_the_command_line(
    port: str, codes: Path, tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level("INFO", logger="hub.provision")
    assert main(["--csv", str(codes), "--port", port, "--log", str(tmp_path / "done.csv")]) == 0
    assert "OK  CTRL-8R-0001" in caplog.text and "AAAA-BBBB-CCCC" in caplog.text
    assert SECRET_A not in caplog.text


def test_an_export_without_credentials_is_explained(tmp_path: Path) -> None:
    path = tmp_path / "labels.csv"
    path.write_text(
        "identifier,serial_number,claim_code,qr\nCTRL-1,SN,AAAA,https://x\n", encoding="utf-8"
    )
    with pytest.raises(SystemExit, match="with credentials"):
        read_rows(path)
