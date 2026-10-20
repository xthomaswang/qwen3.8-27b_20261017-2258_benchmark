#!/usr/bin/env python3
"""Interference loads for M8 (METHODOLOGY.md, section 4).

Stdlib only; run with /usr/bin/python3 -I (Python 3.9). Each load is one process tree with a single
root PID: this process supervises, its workers do the work. SIGTERM, SIGINT and SIGHUP stop the
whole tree; a worker also exits within ~0.1 s once its root is gone, so even a killed root leaves no
orphans. The pidfile (JSON) holds the root PID, the scenario, its effective parameters, the quietlib
allowances, the workers and any file the load wrote, so `stop` can clean up after a killed root.

  start <scenario> [--pidfile F] [--duration S] [--until-pid PID] [--dry-run] [options]
        Runs the load in the foreground until it is stopped (or for S seconds, or until PID exits).
        The pidfile says "ready" once the load is fully active. --dry-run prints the parameters.
  stop [--pidfile F] [--timeout S]         SIGTERM the root, wait, then remove any leftover worker or file
  status [--pidfile F] [--wait-ready S [--pid PID]]
        Exit 0 while the load runs and is ready; prints the state. --wait-ready also waits while the
        pidfile does not exist yet, unless PID (the starting process) has exited.
  meta (--pidfile F | --scenario base) [--field KEY] [KEY=VALUE ...]
        The record run_m8.sh stores in each raw header (harness --interference): scenario, parameters,
        allowances, load PID, plus the given keys. --field prints one value (e.g. load_pid).
  allowances <scenario>                    the quietlib --allow names for a scenario, comma-separated
  wait-power --want high|low [--wait S] [--hint CMD]
        Polls pmset until the energy mode matches: high = AC power in High Power mode (the quiet rule).

Scenarios (defaults; every effective value is stored in the pidfile and the raw header):
  cpu1     a background daemon such as suggestd   1 busy thread (--threads 1 --duty 1.0 --period 0.1)
  cpuhalf  another agent running pytest / mypy    8 busy threads (--threads 8)
  cpuall   a compile, worst case                  one busy thread per logical CPU (--threads <ncpu>)
  gpu      video, a browser or another model      MLX bf16 matmul loop in the mlx-lm venv
                                                  (--duty 0.5 --period 0.1 --size 4096 --python ...)
  mem      another large program                  40 GB allocated, filled with incompressible data,
                                                  re-read every 10 s (--gb 40 --retouch 10 --margin-gb 8)
  disk     a download or Spotlight indexing       paced write + read of one file with the page cache
                                                  bypassed (F_NOCACHE), deleted on stop (--write-mbps 200
                                                  --read-mbps 1000 --file-mb 8192 --block-mb 8
                                                  --dir $TMPDIR/m8-interference.noindex)
  power    low battery / Low Power Mode           never runs sudo: prints `sudo pmset -a lowpowermode 1`,
                                                  waits for it (--wait 1800 --poll 5), and fails if Low
                                                  Power Mode goes off early; on stop, prints the command
                                                  that restores this machine's recorded pmset values

Busy threads are worker processes (the GIL would serialize threads). The disk file lives in a
*.noindex directory so Spotlight does not index it (an mds burst would be a foreign disturbance).
At 200 MB/s the disk scenario writes about 85 GB per M8 block (~7 min with the settle); mind the
SSD wear before raising the rate.

Examples:
  /usr/bin/python3 -I scripts/interference.py start cpuall --pidfile logs/m8-load.pid &
  /usr/bin/python3 -I scripts/interference.py status --pidfile logs/m8-load.pid --wait-ready 300
  /usr/bin/python3 -I scripts/interference.py stop --pidfile logs/m8-load.pid
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = str(Path(__file__).resolve())
PIDFILE = HERE.parent / "logs" / "interference.pid"
MIB = 1 << 20
PAGE = os.sysconf("SC_PAGESIZE")
F_NOCACHE = getattr(fcntl, "F_NOCACHE", 48)   # macOS: bypass the unified buffer cache for this fd
NCPU = os.cpu_count() or 1
SCENARIOS = ("cpu1", "cpuhalf", "cpuall", "gpu", "mem", "disk", "power")
CPU = ("cpu1", "cpuhalf", "cpuall")
# quietlib --allow names: the load's own system-wide side effects. Its processes are exempt by PID
# anyway; load1 also counts our busy threads, Low Power Mode may raise it too.
ALLOW = {"cpu1": ["load"], "cpuhalf": ["load", "thermal"], "cpuall": ["load", "thermal"],
         "gpu": ["gpu", "load", "thermal"], "mem": ["load"], "disk": ["load"], "power": ["load", "lowpower"]}
DEFAULTS = {
    "cpu1": {"threads": 1, "duty": 1.0, "period": 0.1},
    "cpuhalf": {"threads": 8, "duty": 1.0, "period": 0.1},
    "cpuall": {"threads": NCPU, "duty": 1.0, "period": 0.1},
    "gpu": {"duty": 0.5, "period": 0.1, "size": 4096, "python": "~/Developer/mlsys/serving/mlx-lm/.venv/bin/python"},
    "mem": {"gb": 40.0, "retouch": 10.0, "margin_gb": 8.0},
    "disk": {"dir": "$TMPDIR/m8-interference.noindex", "file_mb": 8192, "write_mbps": 200.0, "read_mbps": 1000.0,
             "block_mb": 8},
    "power": {"wait": 1800.0, "poll": 5.0},
}
OPTS = {"threads": CPU, "duty": CPU + ("gpu",), "period": CPU + ("gpu",), "size": ("gpu",), "python": ("gpu",),
        "gb": ("mem",), "retouch": ("mem",), "margin_gb": ("mem",), "dir": ("disk",), "file_mb": ("disk",),
        "write_mbps": ("disk",), "read_mbps": ("disk",), "block_mb": ("disk",), "wait": ("power",), "poll": ("power",)}
GPU_READY_S = 180.0       # MLX import, Metal init and the first kernel compile
DISK_FREE_MARGIN = 20 << 30
ENABLE_CMD = "sudo pmset -a lowpowermode 1"
RESTORE_HINT = "sudo pmset -a lowpowermode 0 && sudo pmset -c powermode 2"


def ts() -> str:
    return time.strftime("%T")


def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def say(*a: object) -> None:
    print(ts(), *a, flush=True)


def ql():
    """quietlib (same directory, stdlib only): one definition of the pmset power state."""
    if str(HERE) not in sys.path:
        sys.path.insert(0, str(HERE))
    import quietlib
    return quietlib


def expand(path: str) -> Path:
    return Path(os.path.expanduser(path.replace("$TMPDIR", tempfile.gettempdir().rstrip("/"))))


# ------------------------------------------------------------------ processes and the pidfile
def alive(pid: int | None) -> bool:
    """Running, and not a zombie (an exited child its parent has not reaped yet still answers kill 0)."""
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    st = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return bool(st) and not st.startswith("Z")


def exists(pid: int) -> bool:
    """kill 0 alone: enough for a process that is not our child (its own parent reaps it), and it
    spawns nothing, so the load's supervision adds no work of its own."""
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def command_of(pid: int) -> str:
    r = subprocess.run(["ps", "-ww", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
    return r.stdout.strip()


def ours(pid: int) -> bool:
    """The PID runs this script (a recycled PID never does)."""
    return "interference.py" in command_of(pid)


def children_of(ppid: int) -> list[int]:
    r = subprocess.run(["ps", "-Ao", "pid=,ppid="], capture_output=True, text=True)
    out = []
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == str(ppid):
            out.append(int(parts[0]))
    return out


def kill_pids(pids: list[int], timeout: float = 3.0) -> list[int]:
    """SIGTERM, then SIGKILL after `timeout`; returns the PIDs still alive. Our own children are
    reaped on the way, so they do not linger as zombies."""
    for p in pids:
        try:
            os.kill(p, signal.SIGTERM)
        except OSError:
            pass
    end = time.monotonic() + timeout
    while True:
        for p in pids:
            try:
                os.waitpid(p, os.WNOHANG)
            except OSError:   # not our child: whoever its parent is reaps it
                pass
        left = [p for p in pids if alive(p)]
        if not left or time.monotonic() >= end:
            break
        time.sleep(0.1)
    for p in left:
        try:
            os.kill(p, signal.SIGKILL)
            os.waitpid(p, 0)
        except OSError:
            pass
    return [p for p in pids if alive(p)]


def read_pidfile(pf: Path) -> dict | None:
    try:
        rec = json.loads(pf.read_text(encoding="utf-8"))
        return rec if isinstance(rec, dict) else None
    except (OSError, ValueError):
        return None


def write_pidfile(pf: Path, rec: dict) -> None:
    pf.parent.mkdir(parents=True, exist_ok=True)
    tmp = pf.with_name(pf.name + ".tmp")
    tmp.write_text(json.dumps(rec, indent=1) + "\n", encoding="utf-8")
    os.replace(tmp, pf)   # readers never see a half-written file


def remove_pidfile(pf: Path, pid: int) -> None:
    rec = read_pidfile(pf)
    if rec is not None and rec.get("pid") == pid:
        pf.unlink(missing_ok=True)


def params_text(p: dict) -> str:
    return " ".join(f"{k}={v}" for k, v in p.items())


# ------------------------------------------------------------------ loads
class Stop(BaseException):
    """Raised by the signal handler, so a sleep or loop unwinds at once; the cleanup runs after."""


class LoadError(Exception):
    """The load could not start or stopped working; recorded as the exit reason."""


def on_signal(signum, _frame) -> None:
    raise Stop(signal.Signals(signum).name)


def spawn(python: str, args: list[str], stdout=None) -> subprocess.Popen:
    return subprocess.Popen([python, "-I", SCRIPT, "_worker", *args, "--parent", str(os.getpid())],
                            stdin=subprocess.DEVNULL, stdout=stdout, close_fds=True)


class Load:
    tick = 0.2

    def __init__(self, p: dict, rec: dict, save) -> None:
        self.p, self.rec, self.save = p, rec, save
        self.procs: list[subprocess.Popen] = []

    def begin(self) -> None:
        """Start the work; return once it is fully active."""

    def step(self) -> None:
        """One tick of work or supervision; raises LoadError when the load fails."""
        self.check_workers()
        time.sleep(self.tick)

    def hold(self, deadline: float | None, until_pid: int | None) -> str:
        next_check = 0.0
        while deadline is None or time.monotonic() < deadline:
            if until_pid and time.monotonic() >= next_check:
                if not exists(until_pid):
                    return f"process {until_pid} (--until-pid) exited"
                next_check = time.monotonic() + 1.0
            self.step()
        return "duration elapsed"

    def check_workers(self) -> None:
        for x in self.procs:
            if x.poll() is not None:
                raise LoadError(f"worker {x.pid} exited with code {x.returncode}")

    def record_workers(self) -> None:
        self.rec["children"] = [x.pid for x in self.procs]
        self.save()

    def cleanup(self) -> None:
        for x in self.procs:
            if x.poll() is None:
                x.terminate()
        end = time.monotonic() + 3.0
        for x in self.procs:
            try:
                x.wait(timeout=max(0.0, end - time.monotonic()))
            except subprocess.TimeoutExpired:
                x.kill()
                x.wait()


class CpuLoad(Load):
    def begin(self) -> None:
        for _ in range(self.p["threads"]):   # one at a time, so a stop midway still knows each worker
            self.procs.append(spawn(sys.executable, ["cpu", "--duty", str(self.p["duty"]), "--period", str(self.p["period"])]))
        self.record_workers()
        time.sleep(0.1)
        self.check_workers()


class GpuLoad(Load):
    def begin(self) -> None:
        py = str(expand(self.p["python"]))
        if not os.access(py, os.X_OK):
            raise LoadError(f"no python for the GPU load at {self.p['python']}")
        proc = spawn(py, ["gpu", "--duty", str(self.p["duty"]), "--period", str(self.p["period"]),
                          "--size", str(self.p["size"])], stdout=subprocess.PIPE)
        self.procs.append(proc)
        self.record_workers()
        end = time.monotonic() + GPU_READY_S
        while True:   # the worker prints "ready" after its first matmul (MLX init, kernel compile)
            r, _, _ = select.select([proc.stdout], [], [], 0.5)
            if r:
                line = proc.stdout.readline()
                if line.strip() == b"ready":
                    return
                if not line:
                    raise LoadError(f"GPU worker closed its output before it was ready (code {proc.poll()})")
                continue
            if proc.poll() is not None:
                raise LoadError(f"GPU worker exited with code {proc.returncode} before it was ready")
            if time.monotonic() > end:
                raise LoadError(f"GPU worker not ready after {GPU_READY_S:.0f} s")


def available_bytes() -> int | None:
    """free + inactive + speculative + purgeable pages from vm_stat: what a new allocation can get
    without pushing other programs out (approximate; None if vm_stat is unreadable)."""
    r = subprocess.run(["vm_stat"], capture_output=True, text=True)
    page = re.search(r"page size of (\d+) bytes", r.stdout)
    if not page:
        return None
    n = 0
    for key in ("Pages free", "Pages inactive", "Pages speculative", "Pages purgeable"):
        m = re.search(rf"^{key}:\s+(\d+)\.", r.stdout, re.M)
        n += int(m.group(1)) if m else 0
    return n * int(page.group(1))


class MemLoad(Load):
    CHUNK = 1 << 30
    PATTERN = 4 * MIB

    def begin(self) -> None:
        total = int(self.p["gb"] * 1e9)
        avail = available_bytes()
        if avail is not None and total > avail - self.p["margin_gb"] * 1e9:
            raise LoadError(f"{self.p['gb']:g} GB requested, but only {avail / 1e9:.1f} GB is available "
                            f"(free + inactive + speculative + purgeable; margin {self.p['margin_gb']:g} GB)")
        # Random bytes, so the memory compressor cannot shrink the pages; one pattern repeated is
        # enough because macOS compresses (and never deduplicates) page by page.
        pattern = os.urandom(min(self.PATTERN, total))
        self.chunks: list[bytes] = []
        left = total
        try:
            while left > 0:
                n = min(self.CHUNK, left)
                reps, rest = divmod(n, len(pattern))
                self.chunks.append(pattern * reps + pattern[:rest])   # one write pass touches every page
                left -= n
        except MemoryError:
            raise LoadError(f"allocation failed after {(total - left) / 1e9:.1f} GB")
        self.next = time.monotonic() + self.p["retouch"]

    def step(self) -> None:
        if self.p["retouch"] > 0 and time.monotonic() >= self.next:
            for c in self.chunks:
                c[::PAGE]   # one byte per page: keeps every page recently used, so it stays resident
            self.next = time.monotonic() + self.p["retouch"]
        time.sleep(self.tick)

    def cleanup(self) -> None:
        self.chunks = []


class DiskLoad(Load):
    tick = 0.05

    def __init__(self, p: dict, rec: dict, save) -> None:
        super().__init__(p, rec, save)
        self.dir, self.path, self.fd, self.made_dir = None, None, None, False
        self.written = self.nread = 0
        self.t0 = time.monotonic()

    def begin(self) -> None:
        d = expand(self.p["dir"])
        self.made_dir = not d.exists()
        d.mkdir(parents=True, exist_ok=True)
        self.dir = d
        self.blk = int(self.p["block_mb"]) * MIB   # page-aligned blocks: F_NOCACHE I/O stays direct
        self.size = max(self.blk, int(self.p["file_mb"] * MIB) // self.blk * self.blk)
        free = shutil.disk_usage(d).free
        if free < self.size + DISK_FREE_MARGIN:
            raise LoadError(f"only {free / 2**30:.0f} GiB free in {self.p['dir']}")
        self.path = d / f"load-{os.getpid()}.bin"
        self.rec["files"] = [str(self.path)]   # recorded before it exists, so `stop` can always remove it
        self.save()
        self.fd = os.open(str(self.path), os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
        fcntl.fcntl(self.fd, F_NOCACHE, 1)
        self.buf = os.urandom(self.blk)
        self.w_off = self.r_off = self.extent = 0
        self.wcred = self.rcred = 0.0
        self.t0 = time.monotonic()
        self.write_block()
        os.fsync(self.fd)
        self.last = self.last_sync = time.monotonic()

    def write_block(self) -> None:
        os.pwrite(self.fd, self.buf, self.w_off)
        self.extent = max(self.extent, self.w_off + self.blk)
        self.w_off = (self.w_off + self.blk) % self.size
        self.written += self.blk

    def read_block(self) -> None:
        if self.r_off + self.blk > self.extent:
            self.r_off = 0
        os.pread(self.fd, self.blk, self.r_off)
        self.r_off += self.blk
        self.nread += self.blk

    def step(self) -> None:
        now = time.monotonic()
        el, self.last = now - self.last, now
        w, r = self.p["write_mbps"] * 1e6, self.p["read_mbps"] * 1e6
        # credits pace the I/O to the target rates; at most ~1 s of backlog, so a slow moment never bursts
        self.wcred = min(self.wcred + w * el, max(w, self.blk))
        self.rcred = min(self.rcred + r * el, max(r, self.blk))
        while self.wcred >= self.blk:
            self.write_block()
            self.wcred -= self.blk
        while self.rcred >= self.blk:
            self.read_block()
            self.rcred -= self.blk
        if now - self.last_sync >= 1.0:
            os.fsync(self.fd)
            self.last_sync = now
        time.sleep(self.tick)

    def cleanup(self) -> None:
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
            el = max(1e-9, time.monotonic() - self.t0)
            say(f"interference: disk wrote {self.written / 1e9:.2f} GB ({self.written / 1e6 / el:.0f} MB/s), "
                f"read {self.nread / 1e9:.2f} GB ({self.nread / 1e6 / el:.0f} MB/s)")
        if self.path is not None:
            self.path.unlink(missing_ok=True)
        if self.made_dir and self.dir is not None:
            try:
                self.dir.rmdir()
            except OSError:
                pass


def pmset_custom() -> dict:
    """{power source: {"powermode": v, "lowpowermode": v}} from `pmset -g custom`."""
    _, out = ql().run(["pmset", "-g", "custom"])
    res: dict = {}
    cur = None
    for line in out.splitlines():
        if line.strip() and not line.startswith((" ", "\t")) and line.rstrip().endswith(":"):
            cur = line.strip()[:-1]
            res[cur] = {}
        elif cur is not None:
            m = re.match(r"\s*(powermode|lowpowermode)\s+(\d+)", line)
            if m:
                res[cur][m.group(1)] = m.group(2)
    return res


def restore_cmd(before: dict) -> str:
    """Turn Low Power Mode off, then put back each source's recorded values (on this machine AC is
    powermode 2 and battery 0, so `lowpowermode 0` alone would leave AC in Automatic)."""
    flags = {"AC Power": "-c", "Battery Power": "-b", "UPS Power": "-u"}
    parts = ["sudo pmset -a lowpowermode 0"]
    for src, vals in before.items():
        for key in ("lowpowermode", "powermode"):
            if src in flags and key in vals:
                parts.append(f"sudo pmset {flags[src]} {key} {vals[key]}")
    if len(parts) == 1:
        parts.append("sudo pmset -c powermode 2")
    return " && ".join(parts)


class PowerLoad(Load):
    def begin(self) -> None:
        q = ql()
        before = pmset_custom()
        self.rec["power_before"] = before
        self.rec["restore"] = restore_cmd(before)
        st = q.power_state()
        if not q.low_power(st):
            self.rec["action"] = f"run in a terminal: {ENABLE_CMD} (pmset -g now: {q.power_text(st)})"
            self.save()
            say(f"ACTION NEEDED: {self.rec['action']}; waiting up to {self.p['wait']:.0f} s")
            end = time.monotonic() + self.p["wait"]
            while not q.low_power(q.power_state()):
                if time.monotonic() >= end:
                    raise LoadError(f"Low Power Mode was not turned on within {self.p['wait']:.0f} s")
                time.sleep(self.p["poll"])
            self.rec.pop("action", None)
        self.rec["power_during"] = q.power_text(q.power_state())
        self.next = time.monotonic() + self.p["poll"]

    def step(self) -> None:
        if time.monotonic() >= self.next:
            q = ql()
            st = q.power_state()
            if not q.low_power(st):
                raise LoadError(f"Low Power Mode went off during the scenario ({q.power_text(st)})")
            self.next = time.monotonic() + self.p["poll"]
        time.sleep(self.tick)

    def cleanup(self) -> None:
        if "restore" in self.rec:
            say(f"power restore: {self.rec['restore']}")


LOADS = {"cpu1": CpuLoad, "cpuhalf": CpuLoad, "cpuall": CpuLoad, "gpu": GpuLoad, "mem": MemLoad,
         "disk": DiskLoad, "power": PowerLoad}


# ------------------------------------------------------------------ workers (children of the root)
def worker_cpu(duty: float, period: float, parent: int) -> None:
    x = 1
    while os.getppid() == parent:   # the root is gone: exit instead of spinning as an orphan
        t0 = time.monotonic()
        busy = t0 + duty * period
        while time.monotonic() < busy:
            for _ in range(1000):
                x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        rest = t0 + period - time.monotonic()
        if rest > 0:
            time.sleep(rest)


def worker_gpu(duty: float, period: float, size: int, parent: int) -> None:
    import mlx.core as mx   # only in the mlx-lm venv

    a = mx.random.normal((size, size)).astype(mx.bfloat16)
    b = mx.random.normal((size, size)).astype(mx.bfloat16)
    mx.eval(a @ b)
    print("ready", flush=True)
    while os.getppid() == parent:
        t0 = time.monotonic()
        busy = t0 + duty * period
        while time.monotonic() < busy:
            mx.eval(a @ b)   # synchronous: each matmul is one GPU command buffer
        rest = t0 + period - time.monotonic()
        if rest > 0:
            time.sleep(rest)


# ------------------------------------------------------------------ commands
def resolve(a: argparse.Namespace) -> dict:
    p = dict(DEFAULTS[a.scenario])
    for k, scen in OPTS.items():
        v = getattr(a, k)
        if v is None:
            continue
        if a.scenario not in scen:
            raise SystemExit(f"interference: --{k.replace('_', '-')} does not apply to {a.scenario}")
        p[k] = v
    bad = [k for k in ("threads", "period", "size", "gb", "file_mb", "block_mb", "poll") if k in p and p[k] <= 0]
    bad += [k for k in ("duty",) if k in p and not 0 < p[k] <= 1]
    bad += [k for k in ("retouch", "margin_gb", "write_mbps", "read_mbps", "wait") if k in p and p[k] < 0]
    if bad:
        raise SystemExit(f"interference: invalid {', '.join(bad)} for {a.scenario}")
    return p


def cleanup_stale(rec: dict) -> None:
    """Leftovers of a root that was killed: its workers (if still ours) and its files."""
    left = [c for c in rec.get("children", []) if alive(c) and ours(c)]
    if left:
        say(f"interference: stopping leftover workers {left} of pid {rec.get('pid')}")
        kill_pids(left)
    for f in rec.get("files", []):
        if Path(f).exists():
            Path(f).unlink(missing_ok=True)
            say(f"interference: removed leftover file {f}")


def cmd_start(a: argparse.Namespace) -> int:
    p = resolve(a)
    if a.dry_run:
        print(json.dumps({"scenario": a.scenario, "params": p, "allow": ALLOW[a.scenario]}))
        return 0
    pf = Path(a.pidfile)
    old = read_pidfile(pf)
    if old is not None:
        if alive(old.get("pid")) and ours(old["pid"]):
            print(f"interference: a load is already running ({old.get('scenario')}, pid {old['pid']}); stop it first",
                  file=sys.stderr)
            return 2
        cleanup_stale(old)
    rec = {"pid": os.getpid(), "scenario": a.scenario, "params": p, "allow": ALLOW[a.scenario], "state": "starting",
           "started": now_iso(), "until_pid": a.until_pid, "children": [], "files": []}

    def save() -> None:
        write_pidfile(pf, rec)

    save()
    say(f"interference: {a.scenario} starting (pid {os.getpid()}; {params_text(p)}; allowances {','.join(ALLOW[a.scenario])})")
    load = LOADS[a.scenario](p, rec, save)
    t0, rc = time.monotonic(), 0
    try:
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, on_signal)
        load.begin()
        rec.update(state="ready", ready=now_iso(), ready_after_s=round(time.monotonic() - t0, 2))
        save()
        say(f"interference: {a.scenario} ready after {rec['ready_after_s']:.1f} s")
        reason = load.hold(time.monotonic() + a.duration if a.duration else None, a.until_pid)
    except Stop as e:
        reason = f"stopped by {e}"
    except LoadError as e:
        reason, rc = str(e), 3
    finally:
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, signal.SIG_IGN)   # the cleanup itself must not be interrupted
        load.cleanup()
        stray = [c for c in children_of(os.getpid()) if ours(c)]   # a worker spawned while a signal arrived
        if stray:
            kill_pids(stray)
    say(f"interference: {a.scenario} {reason} after {time.monotonic() - t0:.1f} s")
    if rc:   # keep the reason for `status`; `stop` removes the file
        rec.update(state="exited", reason=reason, rc=rc, ended=now_iso())
        save()
    else:
        remove_pidfile(pf, os.getpid())
    return rc


def describe(rec: dict | None) -> tuple[str, str]:
    if rec is None:
        return "none", "interference: no load (no pidfile)"
    scen, pid = rec.get("scenario"), rec.get("pid")
    if rec.get("state") == "exited":
        return "exited", f"interference: {scen} (pid {pid}) exited: {rec.get('reason')}"
    if not alive(pid) or not ours(pid):
        return "dead", f"interference: {scen} pid {pid} is not running (no exit record: the root was killed)"
    if rec.get("state") != "ready":
        return "starting", f"interference: {scen} pid {pid} starting"
    return "ready", (f"interference: {scen} pid {pid} ready since {rec.get('ready', '?')[11:19]} "
                     f"({params_text(rec.get('params', {}))}; allowances {','.join(rec.get('allow', []))})")


def cmd_status(a: argparse.Namespace) -> int:
    pf, t0, shown = Path(a.pidfile), time.monotonic(), False
    while True:
        rec = read_pidfile(pf)
        state, line = describe(rec)
        if rec and rec.get("action") and not shown and state == "starting":
            say(f"ACTION NEEDED: {rec['action']}")
            shown = True
        if state == "ready":
            print(line, flush=True)
            return 0
        if state == "none" and a.wait_ready and (a.pid is None or alive(a.pid)):
            state = "starting"   # the load has not written its pidfile yet
        if state in ("exited", "dead", "none") or time.monotonic() - t0 >= a.wait_ready:
            print(line + (f" (not ready after {a.wait_ready:.0f} s)" if state == "starting" and a.wait_ready else ""),
                  flush=True)
            return 1
        time.sleep(0.2)


def cmd_stop(a: argparse.Namespace) -> int:
    pf = Path(a.pidfile)
    rec = read_pidfile(pf)
    if rec is None:
        print("interference: no load running (no pidfile)")
        return 0
    pid = rec.get("pid")
    if alive(pid) and ours(pid):
        os.kill(pid, signal.SIGTERM)
        end = time.monotonic() + a.timeout
        while alive(pid) and time.monotonic() < end:
            time.sleep(0.1)
        if alive(pid):
            print(f"interference: pid {pid} did not exit within {a.timeout:.0f} s; SIGKILL")
            kill_pids([pid], 0)
    elif alive(pid):
        print(f"interference: pid {pid} does not run interference.py (a recycled PID); not signalled")
    final = read_pidfile(pf) or {}
    if final.get("state") == "exited":
        print(f"interference: {rec.get('scenario')} had exited: {final.get('reason')}")
    cleanup_stale(rec)
    if rec.get("restore"):
        print(f"power restore: {rec['restore']}")
    survivors = [p for p in [pid] + list(rec.get("children", [])) if alive(p) and ours(p)]
    pf.unlink(missing_ok=True)
    print(f"interference: {rec.get('scenario')} (pid {pid}) stopped" if not survivors
          else f"interference: still running: {survivors}")
    return 1 if survivors else 0


def kv(text: str) -> tuple[str, object]:
    k, sep, v = text.partition("=")
    if not sep or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
        raise argparse.ArgumentTypeError(f"expected KEY=VALUE, got {text!r}")
    for conv in (int, float):
        try:
            return k, conv(v)
        except ValueError:
            pass
    return k, v


def cmd_meta(a: argparse.Namespace) -> int:
    if a.pidfile:
        rec = read_pidfile(Path(a.pidfile))
        state, line = describe(rec)
        if state != "ready":
            print(line, file=sys.stderr)
            return 1
        out = {"scenario": rec["scenario"], "params": rec["params"], "allow": rec["allow"], "load_pid": rec["pid"],
               "ready": rec.get("ready")}
        for k in ("power_before", "power_during"):
            if k in rec:
                out[k] = rec[k]
    else:
        out = {"scenario": a.scenario, "params": {}, "allow": [], "load_pid": None}
    out.update(dict(a.pairs))
    if a.field:
        v = out.get(a.field)
        print("" if v is None else (v if isinstance(v, str) else json.dumps(v)))
        return 0
    print(json.dumps(out, separators=(",", ":")))
    return 0


def cmd_wait_power(a: argparse.Namespace) -> int:
    q = ql()
    t0, last = time.monotonic(), -1e9
    hint = a.hint or (RESTORE_HINT if a.want == "high" else ENABLE_CMD)
    while True:
        st = q.power_state()
        ok = q.power_ok(st) if a.want == "high" else (st["source"] == "AC Power" and q.low_power(st))
        waited = time.monotonic() - t0
        if ok:
            say(f"power: {q.power_text(st)} ({a.want}: ok)")
            return 0
        if waited >= a.wait:
            say(f"power: {q.power_text(st)}; not {a.want} after {waited:.0f} s")
            return 1
        if time.monotonic() - last >= 300:
            say(f"ACTION NEEDED: power is {q.power_text(st)}; run in a terminal: {hint} "
                f"(waiting {waited:.0f}/{a.wait:.0f} s)")
            last = time.monotonic()
        time.sleep(max(0.05, min(a.poll, a.wait - waited)))


def cmd_worker(a: argparse.Namespace) -> int:
    signal.signal(signal.SIGINT, signal.SIG_DFL)   # a terminal Ctrl-C ends a worker quietly
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    if a.kind == "cpu":
        worker_cpu(a.duty, a.period, a.parent)
    else:
        worker_gpu(a.duty, a.period, a.size, a.parent)
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="interference", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    st = sub.add_parser("start", help="run a load in the foreground")
    st.add_argument("scenario", choices=SCENARIOS)
    st.add_argument("--pidfile", default=str(PIDFILE))
    st.add_argument("--duration", type=float, help="stop after S seconds (default: run until stopped)")
    st.add_argument("--until-pid", type=int, help="stop when this process exits (the runner)")
    st.add_argument("--dry-run", action="store_true", help="print the effective parameters and exit")
    st.add_argument("--threads", type=int)
    st.add_argument("--duty", type=float, help="busy share of each period, 0-1")
    st.add_argument("--period", type=float, help="duty-cycle period in seconds")
    st.add_argument("--size", type=int, help="gpu: matrix size")
    st.add_argument("--python", help="gpu: interpreter with mlx")
    st.add_argument("--gb", type=float, help="mem: GB (1e9 bytes) to allocate")
    st.add_argument("--retouch", type=float, help="mem: seconds between re-reads (0: never)")
    st.add_argument("--margin-gb", type=float, help="mem: refuse unless this much would stay available")
    st.add_argument("--dir", help="disk: directory of the load file")
    st.add_argument("--file-mb", type=float, help="disk: file size in MiB")
    st.add_argument("--write-mbps", type=float, help="disk: write rate, MB/s")
    st.add_argument("--read-mbps", type=float, help="disk: read rate, MB/s")
    st.add_argument("--block-mb", type=int, help="disk: I/O size in MiB")
    st.add_argument("--wait", type=float, help="power: seconds to wait for Low Power Mode")
    st.add_argument("--poll", type=float, help="power: seconds between pmset checks")
    for name, h in (("stop", "stop a load and clean up"), ("status", "state of a load")):
        x = sub.add_parser(name, help=h)
        x.add_argument("--pidfile", default=str(PIDFILE))
        if name == "stop":
            x.add_argument("--timeout", type=float, default=20.0)
        else:
            x.add_argument("--wait-ready", type=float, default=0.0,
                           help="wait up to S seconds for the load to be ready (also while there is no pidfile yet)")
            x.add_argument("--pid", type=int, help="with --wait-ready: the starting process; stop waiting if it exits")
    me = sub.add_parser("meta", help="the raw-header record of a block (JSON)")
    g = me.add_mutually_exclusive_group(required=True)
    g.add_argument("--pidfile", help="a running, ready load")
    g.add_argument("--scenario", help="a block without a load, e.g. base")
    me.add_argument("--field", help="print only this field (e.g. load_pid)")
    me.add_argument("pairs", nargs="*", type=kv, metavar="KEY=VALUE")
    al = sub.add_parser("allowances", help="quietlib --allow names for a scenario")
    al.add_argument("scenario", choices=SCENARIOS + ("base",))
    wp = sub.add_parser("wait-power", help="wait until pmset shows the wanted energy mode")
    wp.add_argument("--want", choices=["high", "low"], required=True)
    wp.add_argument("--wait", type=float, default=0.0)
    wp.add_argument("--poll", type=float, default=5.0)
    wp.add_argument("--hint", default="", help="the command to print while waiting")
    wk = sub.add_parser("_worker")
    wk.add_argument("kind", choices=["cpu", "gpu"])
    wk.add_argument("--duty", type=float, required=True)
    wk.add_argument("--period", type=float, required=True)
    wk.add_argument("--size", type=int, default=4096)
    wk.add_argument("--parent", type=int, required=True)
    a = ap.parse_args(argv)
    if a.cmd == "allowances":
        print(",".join(ALLOW.get(a.scenario, [])))
        return 0
    return {"start": cmd_start, "stop": cmd_stop, "status": cmd_status, "meta": cmd_meta,
            "wait-power": cmd_wait_power, "_worker": cmd_worker}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
