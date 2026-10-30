"""Load test of the platform: N devices on the native contract, homes with app users, commands
and changes measured end to end, the server's CPU and memory sampled.

Two processes, so the simulated devices do not share the hub's CPU:

    python scripts/load_test.py serve   --devices 1000 --state load.json     # the hub
    python scripts/load_test.py devices --state load.json --minutes 3       # devices + users

``serve`` starts a throw-away PostgreSQL (pgserver), a hub with the TCP device port, a maker
with an 8-relay product, the devices, one home per ``--per-home`` devices with its owner, and
writes their credentials to the state file. ``devices`` connects every device (TCP or HTTP,
``--http-share``), sends telemetry (``--telemetry-s`` apart, with jitter) and runs, for the
test's length:

* commands: owners switch random relays (``--commands-per-s``) through POST /api/control/write;
  measured: hub to device (the device receives it) and the full round trip (applied);
* changes: devices change an input (``--changes-per-s``); measured: the device sends it until
  the owner's app gets it over the live stream (/api/platform/my/stream);
* app users refreshing their home screen (devices, then every device's view).

The report: percentiles, the share within the limits (commands 5 s, changes 10 s), failures,
and the hub's and PostgreSQL's CPU and memory (from the server's samples in the state folder).
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import csv
import io
import json
import logging
import random
import statistics
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

PASSWORD = "Load-Test-Pass-2026"          # local throw-away accounts of the test only
RELAYS = 8
INPUTS = 4


def template() -> dict[str, Any]:
    tags = [{"key": f"relay_{i}", "kind": "digital_output", "display_name": {"en": f"Relay {i}"},
             "data_type": "bool", "access": "read_write"} for i in range(1, RELAYS + 1)]
    tags += [{"key": f"in_{i}", "kind": "digital_input", "display_name": {"en": f"Input {i}"},
              "data_type": "bool"} for i in range(1, INPUTS + 1)]
    tags += [{"key": "power", "kind": "analog_input", "display_name": {"en": "Power"},
              "data_type": "float32", "unit": "kW"},
             {"key": "temperature", "kind": "analog_input", "display_name": {"en": "Temp"},
              "data_type": "float32", "unit": "°C"}]
    return {"tags": tags, "bindings": {"native": {
        "connection": {"command_timeout_s": 10, "stale_after_s": 180},
        "tags": {t["key"]: {} for t in tags}}}}


# --- the server ---------------------------------------------------------------------------------


async def serve(args: argparse.Namespace) -> None:
    import pgserver
    import uvicorn

    from backend.app import create_app
    from backend.security import hash_password
    from backend.services import Services
    from backend.settings import Settings
    from hub.config_loader import load_config
    from hub.platform.devices import ProductIn
    from hub.platform.template import ProductTemplate
    from hub.runtime import Hub
    from hub.storage.migrate import migrate
    from hub.storage.postgres import PostgresStore

    state = Path(args.state).resolve()  # noqa: ASYNC240 - start-up, before the hub runs
    work = state.parent / f"{state.stem}.data"
    (work / "config" / "devices").mkdir(parents=True, exist_ok=True)  # noqa: ASYNC240
    if args.broker_port:                     # the platform broker (devices -> broker -> hub)
        (work / "config" / "brokers.yaml").write_text(  # noqa: ASYNC240
            "brokers:\n  - broker_id: load_broker\n    host: 127.0.0.1\n"
            f"    port: {args.broker_port}\n    tls: false\n    keepalive_s: 60\n",
            encoding="utf-8")
    server = pgserver.get_server(str(work / "db"), cleanup_mode=None)
    url = server.get_uri()
    migrate(url)
    settings = Settings.model_validate({
        "jwt_secret": "l" * 40, "data_key": "k" * 40, "control_enabled": True,
        "config_dir": work / "config", "spool_dir": None, "app_dir": ROOT / "app",
        "maker_dir": ROOT / "maker", "frontend_dir": ROOT / "frontend",
        # one client address drives every simulated user and device: the per-address limits
        # are for the internet, not for this test (the users of a real hub have their own)
        "rate_limit_per_min": 100_000, "account_ip_per_hour": 10_000,
        "tcp_ingest_port": args.tcp_port, "tcp_ingest_host": "127.0.0.1",
        "tcp_ingest_insecure": True,
        "platform_broker": "load_broker" if args.broker_port else None})
    store = PostgresStore(url, max_size=args.db_pool)
    await store.open()
    hub = Hub(load_config(work / "config", env={}), store=store)
    svc = Services.build(settings, load_config(work / "config", env={}), store, hub)
    await svc.start()

    t0 = time.monotonic()
    p = store.platform
    await p.create_organization("maker", "Load Maker", "manufacturer")
    product = await p.create_product({"maker"}, "maker", ProductIn(
        code="LT-8R", name="Load test 8R", identifier_pattern="LT-{00000}"), None)
    await p.save_draft({"maker"}, product.product_id, ProductTemplate.model_validate(template()),
                       None, None)
    await p.publish({"maker"}, product.product_id, 1, None)
    entries = [(f"LT-{i:05d}", None) for i in range(1, args.devices + 1)]
    devices = await p.register_devices({"maker"}, product.product_id, 1, protocol="native",
                                       entries=entries, batch=None, warranty_months=12,
                                       connection={}, options={}, enabled=False, user_id=None)
    admin = await store.create_user("load.admin", "Admin", hash_password(PASSWORD),
                                    must_change_password=False)
    await store.grant_role(admin.user_id, "admin", None, None, None)
    from backend.rbac import Principal

    principal = Principal(user=admin, session_id=None, grants=tuple(await store.grants(
        admin.user_id)), role_permissions=await store.role_permissions())
    rows = list(csv.DictReader(io.StringIO(await svc.claims.labels(
        principal, product.product_id, device_ids=None, batch=None, credentials=True,
        client_addr=None))))
    secrets = {r["device_id"]: r["device_secret"] for r in rows}
    pw = hash_password(PASSWORD)                 # one hash for every test owner (fast setup)
    homes: list[dict[str, Any]] = []
    out_devices = []
    for start in range(0, len(devices), args.per_home):
        n = len(homes)
        user = await store.accounts.create_user(
            username=f"u_load_{n}", display_name=f"Owner {n}", password_hash=pw,
            email=f"load{n}@example.test", language="en", verified_at=hub.clock())
        org = await store.accounts.ensure_personal_org(user, f"Home {n}")
        ids = []
        for d in devices[start:start + args.per_home]:
            await store.accounts.set_owner(d.device_id, org, None)
            _, model = await p.update_device(None, d.device_id, enabled=True)
            await hub.apply_platform_device(d.device_id, model)
            ids.append(d.device_id)
            out_devices.append({"id": d.device_id, "secret": secrets[d.device_id], "home": n})
        homes.append({"email": f"load{n}@example.test", "org": org, "devices": ids})
    setup_s = time.monotonic() - t0
    state.write_text(json.dumps({"devices": out_devices, "homes": homes, "password": PASSWORD,
                                 "api": f"http://127.0.0.1:{args.port}",
                                 "tcp": ["127.0.0.1", args.tcp_port], "setup_s": setup_s,
                                 "mqtt": ["127.0.0.1", args.broker_port]
                                 if args.broker_port else None}),
                     encoding="utf-8")
    print(f"ready: {len(out_devices)} devices, {len(homes)} homes in {setup_s:.0f} s", flush=True)

    stats_file = state.parent / f"{state.stem}.server.jsonl"

    async def sample() -> None:
        import psutil

        me = psutil.Process()
        db_dir = str(work / "db").lower().replace("/", "\\")

        def postgres() -> list[Any]:          # pgserver runs PostgreSQL detached
            found = []
            for proc in psutil.process_iter(["name", "cmdline"]):
                with contextlib.suppress(Exception):
                    if "postgres" in (proc.info["name"] or "").lower() and any(
                            db_dir in str(a).lower().replace("/", "\\")
                            for a in proc.info["cmdline"] or []):
                        found.append(proc)
            return found
        pg = postgres()
        for c in [me, *pg]:
            with contextlib.suppress(Exception):
                c.cpu_percent(None)
        with stats_file.open("w", encoding="utf-8") as f:
            while True:
                await asyncio.sleep(5)
                pg = postgres() or pg
                hub_cpu = me.cpu_percent(None)
                pg_cpu = pg_rss = 0.0
                for c in pg:
                    with contextlib.suppress(Exception):
                        pg_cpu += c.cpu_percent(None)
                        pg_rss += c.memory_info().rss
                online = sum(1 for s in hub.statuses.values()
                             if str(s.state) == "online")
                f.write(json.dumps({
                    "t": time.time(), "hub_cpu": hub_cpu,
                    "hub_rss_mb": me.memory_info().rss / 2**20,
                    "pg_cpu": pg_cpu, "pg_rss_mb": pg_rss / 2**20, "online": online,
                    "buffer": len(getattr(hub, "_buffer", ())),
                    "loop_lag_ms": await lag()}) + "\n")
                f.flush()

    async def lag() -> float:
        t = asyncio.get_running_loop().time()
        await asyncio.sleep(0)
        return (asyncio.get_running_loop().time() - t) * 1000

    app = create_app(svc)
    web = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=args.port,
                                        log_level="warning", loop="none", lifespan="off",
                                        limit_concurrency=300 if sys.platform == "win32"
                                        else 10_000))      # as backend.server does
    async def profile() -> None:            # --profile N: N seconds of cProfile, the top list
        if not args.profile:
            return
        import cProfile
        import pstats

        await asyncio.sleep(args.profile_after)
        prof = cProfile.Profile()
        prof.enable()
        await asyncio.sleep(args.profile)
        prof.disable()
        out = io.StringIO()
        pstats.Stats(prof, stream=out).sort_stats("cumulative").print_stats(60)
        pstats.Stats(prof, stream=out).sort_stats("tottime").print_stats(40)
        state.with_name(f"{state.stem}.profile.txt").write_text(out.getvalue(),  # noqa: ASYNC240
                                                                encoding="utf-8")
        print("profile written", flush=True)

    await asyncio.gather(web.serve(), sample(), profile())


# --- the devices and the app users ---------------------------------------------------------------


class Stats:
    def __init__(self) -> None:
        self.cmd_device: list[float] = []      # hub -> device received
        self.cmd_applied: list[float] = []     # request -> applied (ack + value back)
        self.cmd_failed: dict[str, int] = {}
        self.change: list[float] = []          # device change -> owner's app
        self.change_lost = 0
        self.screen: list[float] = []          # home screen refresh
        self.errors: dict[str, int] = {}

    def err(self, kind: str) -> None:
        self.errors[kind] = self.errors.get(kind, 0) + 1


async def run_devices(args: argparse.Namespace) -> None:
    import httpx

    from simulators.native_device import NativeDeviceSim

    logging.getLogger("httpx").setLevel(logging.WARNING)
    state = json.loads(Path(args.state).read_text(encoding="utf-8"))  # noqa: ASYNC240
    stats = Stats()
    host, port = state["tcp"]
    api = state["api"]
    received: dict[tuple[str, str, Any], float] = {}

    class Sim(NativeDeviceSim):
        def handle(self, command: dict[str, Any]) -> list[dict[str, Any]]:
            if "tag" in command:
                received.setdefault((self.device_id, command["tag"], command.get("value")),
                                    time.monotonic())
            return super().handle(command)

    # one client process simulates the homes of its part (``--part i --parts n``): one Python
    # process cannot play a thousand devices and their users without becoming the bottleneck
    mine = {i for i in range(len(state["homes"])) if i % args.parts == args.part}
    state["devices"] = [d for d in state["devices"] if d["home"] in mine]
    share = 1 / args.parts
    sims: dict[str, Sim] = {}
    for d in state["devices"]:
        values: dict[str, Any] = {f"relay_{i}": False for i in range(1, RELAYS + 1)}
        values |= {f"in_{i}": False for i in range(1, INPUTS + 1)}
        values |= {"power": round(random.uniform(0.1, 3), 2), "temperature": 30.0}
        sims[d["id"]] = Sim(d["id"], d["secret"], values)
    order = sorted(sims)
    random.shuffle(order)
    http_ids = set(order[:int(len(sims) * args.http_share)])
    mqtt_ids = set(order[len(http_ids):len(http_ids) + int(len(sims) * args.mqtt_share)])
    stop = asyncio.Event()
    limits = httpx.Limits(max_connections=args.pool, max_keepalive_connections=args.pool)
    client = httpx.AsyncClient(base_url=api, timeout=30, limits=limits)

    # 1. devices connect (all at once: the worst case after a power cut)
    t_connect = time.monotonic()
    tasks = []
    for device_id, sim in sims.items():
        if device_id in http_ids:
            tasks.append(asyncio.create_task(sim.run_http(client, args.http_poll_s, stop)))
        elif device_id in mqtt_ids:
            tasks.append(asyncio.create_task(mqtt_forever(sim, *state["mqtt"], stop, stats)))
        else:
            tasks.append(asyncio.create_task(tcp_forever(sim, host, port, stop, stats)))

    async def telemetry(sim: Sim) -> None:          # a periodic reading, with jitter
        await asyncio.sleep(random.uniform(0, args.telemetry_s))
        while not stop.is_set():
            sim.report(power=round(random.uniform(0.1, 3), 2),
                       temperature=round(random.uniform(24, 40), 1))
            await asyncio.sleep(args.telemetry_s * random.uniform(0.8, 1.2))
    tasks += [asyncio.create_task(telemetry(s)) for s in sims.values()]

    # 2. the owners sign in (each home's app)
    tokens: dict[int, str] = {}
    sem = asyncio.Semaphore(20)

    async def login(i: int, home: dict[str, Any]) -> None:
        async with sem:
            r = await client.post("/api/auth/login", json={"username": home["email"],
                                                            "password": state["password"]})
            if r.status_code == 200:
                tokens[i] = r.json()["access_token"]
            else:
                stats.err(f"login {r.status_code}")
    await asyncio.gather(*(login(i, h) for i, h in enumerate(state["homes"]) if i in mine))
    home_of = {d["id"]: d["home"] for d in state["devices"]}
    print(f"{len(tokens)} owners signed in", flush=True)

    # wait for every device online
    def auth(token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    server_stats = Path(args.state).with_suffix("").with_name(
        Path(args.state).stem + ".server.jsonl")
    all_online = None
    for _ in range(240):
        await asyncio.sleep(1)
        last = _last_server_sample(server_stats)
        if last and last.get("online", 0) >= args.total_devices:
            all_online = time.monotonic() - t_connect
            break
    print(f"online: {(_last_server_sample(server_stats) or {}).get('online')} of {len(sims)}"
          f" after {all_online or 'timeout'} s", flush=True)

    # 3. live streams of some homes (the app open), matching changes to their arrival
    pending: dict[tuple[str, str, Any], float] = {}
    streams = random.sample(sorted(tokens), min(round(args.streams * share), len(tokens)))
    streamed_homes = set(streams)

    async def stream(i: int) -> None:
        while not stop.is_set():
            try:
                async with client.stream("GET", "/api/platform/my/stream", headers=auth(tokens[i]),
                                         timeout=None) as r:
                    event = None
                    async for line in r.aiter_lines():
                        if line.startswith("event: "):
                            event = line[7:]
                        elif line.startswith("data: ") and event == "samples":
                            now = time.monotonic()
                            for s in json.loads(line[6:]):
                                parts = s["tag"].split(".")
                                key = (parts[2], parts[3], s.get("value"))
                                t = pending.pop(key, None)
                                if t is not None:
                                    stats.change.append(now - t)
                        if stop.is_set():
                            return
            except Exception:  # noqa: BLE001 - reconnect, as the app does
                stats.err("stream")
                await asyncio.sleep(1)
    tasks += [asyncio.create_task(stream(i)) for i in streams]
    await asyncio.sleep(3)

    # 4. the test: commands, changes, home screens
    deadline = time.monotonic() + args.minutes * 60
    flip: dict[tuple[str, str], bool] = {}

    async def command_once() -> None:
        device_id = random.choice(list(sims))
        tag = f"relay_{random.randint(1, RELAYS)}"
        value = not flip.get((device_id, tag), False)
        flip[(device_id, tag)] = value
        token = tokens.get(home_of[device_id])
        if token is None:
            return
        received.pop((device_id, tag, value), None)
        t0 = time.monotonic()
        try:
            r = await client.post("/api/control/write", headers=auth(token), json={
                "tag": f"platform.devices.{device_id}.{tag}", "value": value, "reason": "load"})
        except Exception as exc:  # noqa: BLE001
            stats.cmd_failed[type(exc).__name__] = stats.cmd_failed.get(type(exc).__name__, 0) + 1
            return
        t1 = time.monotonic()
        result = r.json().get("result") if r.status_code == 200 else f"http {r.status_code}"
        if result == "applied":
            stats.cmd_applied.append(t1 - t0)
        else:
            stats.cmd_failed[str(result)] = stats.cmd_failed.get(str(result), 0) + 1
        got = received.get((device_id, tag, value))
        if got is not None:
            stats.cmd_device.append(got - t0)

    async def change_once() -> None:
        homes = [d for d, h in home_of.items() if h in streamed_homes]
        device_id = random.choice(homes)
        tag = f"in_{random.randint(1, INPUTS)}"
        sim = sims[device_id]
        value = not sim.values[tag]
        pending[(device_id, tag, value)] = time.monotonic()
        sim.report(**{tag: value})

    async def screen(i: int) -> None:
        while time.monotonic() < deadline:
            t0 = time.monotonic()
            try:
                # as the app's home screen: the devices, then every view in one request
                await client.get("/api/platform/my/devices", headers=auth(tokens[i]))
                await client.get("/api/platform/my/views", headers=auth(tokens[i]))
                stats.screen.append(time.monotonic() - t0)
            except Exception:  # noqa: BLE001
                stats.err("screen")
            await asyncio.sleep(args.screen_s * random.uniform(0.7, 1.3))

    async def at_rate(rate: float, job: Any) -> None:
        running: set[asyncio.Task[Any]] = set()
        while time.monotonic() < deadline:
            t = asyncio.create_task(job())
            running.add(t)
            t.add_done_callback(running.discard)
            await asyncio.sleep(random.expovariate(rate))
        await asyncio.gather(*running, return_exceptions=True)

    print(f"test: {args.minutes} min, {args.commands_per_s} commands/s, "
          f"{args.changes_per_s} changes/s, {args.users} users", flush=True)
    t_test = time.time()
    await asyncio.gather(at_rate(args.commands_per_s * share, command_once),
                         at_rate(args.changes_per_s * share, change_once),
                         *(screen(i) for i in random.sample(sorted(tokens),
                                                            min(round(args.users * share),
                                                                len(tokens)))))
    await asyncio.sleep(12)                        # the last changes still on their way
    stats.change_lost = len([t for t in pending.values() if time.monotonic() - t > 10])
    stop.set()
    for t in tasks:
        t.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    await client.aclose()
    part = Path(args.state).with_name(f"{Path(args.state).stem}.part{args.part}.json")
    part.write_text(json.dumps({"stats": stats.__dict__, "devices": len(sims),  # noqa: ASYNC240
                                "http": len(http_ids), "mqtt": len(mqtt_ids),
                                "online_s": all_online, "t_test": t_test,
                                "setup_s": state.get("setup_s")}), encoding="utf-8")
    if args.parts == 1:
        report(args, stats, len(sims), len(http_ids), all_online, server_stats, t_test,
               state.get("setup_s"))


def merge(args: argparse.Namespace) -> None:
    """The report of every client part together."""
    stem = Path(args.state).stem
    parts = [json.loads(Path(args.state).with_name(f"{stem}.part{i}.json").read_text("utf-8"))
             for i in range(args.parts)]
    total = Stats()
    for prt in parts:
        for key, value in prt["stats"].items():
            if isinstance(value, list):
                getattr(total, key).extend(value)
            elif isinstance(value, dict):
                for k, v in value.items():
                    getattr(total, key)[k] = getattr(total, key).get(k, 0) + v
            else:
                setattr(total, key, getattr(total, key) + value)
    onl = [prt["online_s"] for prt in parts if prt["online_s"]]
    args.mqtt_count = sum(prt.get("mqtt", 0) for prt in parts)
    report(args, total, sum(prt["devices"] for prt in parts), sum(prt["http"] for prt in parts),
           max(onl) if len(onl) == len(parts) else None,
           Path(args.state).with_name(f"{stem}.server.jsonl"),
           min(prt["t_test"] for prt in parts), parts[0]["setup_s"])


async def mqtt_forever(sim: Any, host: str, port: int, stop: asyncio.Event, stats: Stats
                       ) -> None:
    await asyncio.sleep(random.uniform(0, 5))
    while not stop.is_set():
        try:
            await sim.run_mqtt(host, port)
        except Exception:  # noqa: BLE001 - reconnect with backoff, as firmware should
            stats.err("mqtt")
        await asyncio.sleep(random.uniform(1, 3))


async def tcp_forever(sim: Any, host: str, port: int, stop: asyncio.Event, stats: Stats) -> None:
    await asyncio.sleep(random.uniform(0, 2))     # the devices come up within two seconds
    while not stop.is_set():
        try:
            await sim.run_tcp(host, port)
        except Exception:  # noqa: BLE001 - reconnect with backoff, as firmware should
            stats.err("tcp")
        await asyncio.sleep(random.uniform(1, 3))


def _last_server_sample(path: Path) -> dict[str, Any] | None:
    try:
        lines = path.read_text(encoding="utf-8").strip().splitlines()
        return json.loads(lines[-1]) if lines else None
    except (OSError, ValueError):
        return None


def pct(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q / 100 * (len(values) - 1))))]


def report(args: argparse.Namespace, s: Stats, devices: int, http_devices: int,
           all_online: float | None, server_stats: Path, t_test: float,
           setup_s: float | None) -> None:
    def line(name: str, values: list[float], limit: float) -> str:
        if not values:
            return f"{name:<34} no samples"
        within = sum(v <= limit for v in values) / len(values) * 100
        return (f"{name:<34} n={len(values):<6} p50={pct(values, 50):.3f}s "
                f"p95={pct(values, 95):.3f}s p99={pct(values, 99):.3f}s "
                f"max={max(values):.3f}s  within {limit:g}s: {within:.2f}%")

    samples = []
    with contextlib.suppress(OSError):
        for raw in server_stats.read_text(encoding="utf-8").splitlines():
            row = json.loads(raw)
            if row["t"] >= t_test:
                samples.append(row)
    out = [
        "",
        f"=== load test: {devices} devices ({getattr(args, 'mqtt_count', 0)} MQTT, "
        f"{devices - http_devices - getattr(args, 'mqtt_count', 0)} TCP, {http_devices} HTTP "
        f"polling every {args.http_poll_s:g} s), telemetry every {args.telemetry_s:g} s ===",
        f"setup of the hub (devices, homes): {setup_s:.0f} s" if setup_s else "",
        f"all devices online after: {all_online:.1f} s" if all_online else
        "not every device came online",
        line("command: hub -> device", s.cmd_device, 5),
        line("command: request -> applied", s.cmd_applied, 5),
        f"{'command failures':<34} {s.cmd_failed or 'none'}",
        line("change: device -> owner's app", s.change, 10),
        f"{'changes not seen within 10 s':<34} {s.change_lost}",
        line("home screen (devices + views)", s.screen, 3),
        f"{'client errors':<34} {s.errors or 'none'}",
    ]
    if samples:
        def m(key: str) -> str:
            v = [r[key] for r in samples]
            return f"avg {statistics.mean(v):.0f} / max {max(v):.0f}"
        out += [f"{'hub CPU % (100 = one core)':<34} {m('hub_cpu')}",
                f"{'hub memory MB':<34} {m('hub_rss_mb')}",
                f"{'PostgreSQL CPU %':<34} {m('pg_cpu')}",
                f"{'PostgreSQL memory MB':<34} {m('pg_rss_mb')}",
                f"{'samples waiting for the database':<34} {m('buffer')}",
                f"{'devices online during the test':<34} min {min(r['online'] for r in samples)}"]
    text = "\n".join(x for x in out if x != "")
    print(text, flush=True)
    Path(args.state).with_name(Path(args.state).stem + ".report.txt").write_text(
        text + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python scripts/load_test.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("serve")
    s.add_argument("--devices", type=int, default=1000)
    s.add_argument("--per-home", type=int, default=10)
    s.add_argument("--state", default="load.json")
    s.add_argument("--port", type=int, default=8095)
    s.add_argument("--tcp-port", type=int, default=7095)
    s.add_argument("--db-pool", type=int, default=10)
    s.add_argument("--broker-port", type=int, default=0, help="the platform MQTT broker")
    s.add_argument("--profile", type=float, default=0, help="seconds of cProfile")
    s.add_argument("--profile-after", type=float, default=120)
    d = sub.add_parser("devices")
    d.add_argument("--state", default="load.json")
    d.add_argument("--minutes", type=float, default=3)
    d.add_argument("--telemetry-s", type=float, default=30)
    d.add_argument("--http-share", type=float, default=0.1)
    d.add_argument("--mqtt-share", type=float, default=0.0, help="needs serve --broker-port")
    d.add_argument("--http-poll-s", type=float, default=2)
    d.add_argument("--commands-per-s", type=float, default=5)
    d.add_argument("--changes-per-s", type=float, default=5)
    d.add_argument("--streams", type=int, default=50)
    d.add_argument("--users", type=int, default=30)
    d.add_argument("--screen-s", type=float, default=15)
    d.add_argument("--pool", type=int, default=200, help="HTTP connections of the client")
    d.add_argument("--parts", type=int, default=1, help="client processes in all")
    d.add_argument("--part", type=int, default=0, help="this process's number (0..parts-1)")
    d.add_argument("--total-devices", type=int, default=1000)
    r = sub.add_parser("report")
    r.add_argument("--state", default="load.json")
    r.add_argument("--parts", type=int, default=1)
    for a in ("http_poll_s", "telemetry_s"):
        r.add_argument("--" + a.replace("_", "-"), type=float, default=3 if "poll" in a else 30)
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    from hub.runtime import run

    if args.cmd == "serve":
        run(serve(args))                 # the hub's own loop (selector on Windows: psycopg)
    elif args.cmd == "report":
        merge(args)
    else:
        # the devices: the default loop, without the 512-socket limit of select() on Windows;
        # MQTT (aiomqtt) needs the selector loop, so a part with MQTT devices stays < 500
        if args.mqtt_share:
            run(run_devices(args))
        else:
            asyncio.run(run_devices(args))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
