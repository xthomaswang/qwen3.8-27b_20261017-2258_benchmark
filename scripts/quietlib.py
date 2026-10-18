#!/usr/bin/env python3
"""Quiet-machine checks for timed segments (METHODOLOGY.md, "Quiet machine").

Stdlib only; run with /usr/bin/python3 -I. Subcommands:

  check   [--allow-pid PID]... [--settle S] [--max-gpu-gb G]
          One-shot pre-flight, run while the server under test is idle. Prints a provenance
          block; exit 1 when the machine is not quiet. With --settle, soft failures (load, GPU
          busy, busy processes, build tools, thermal) are re-checked every 5 s for up to S
          seconds. Hard failures (lock, port 8500, power) fail at once. --max-gpu-gb (used
          before a server starts) also fails while more than G GB of GPU memory is in use,
          i.e. while another model is resident.
  monitor --log FILE [--interval S] [--allow-pid PID]... [--until-pid PID]
          Samples while a segment runs. Every sample is a TSV row in FILE; stdout gets one line
          per state change. Lock, port 8500, power, thermal and build tools mark a sample
          DISTURBED at once. Busy processes and foreign CPU only count when they persist for two
          consecutive samples (a one-sample daemon blip is logged as SPIKE). Load average is
          logged but not judged, since the server under test adds to it.
  verify  --log FILE --raw-dir DIR --since EPOCH [--move]
          For each result file in DIR created at or after EPOCH, looks for DISTURBED samples,
          or gaps in sampling, inside the file's time window (header `created` to mtime).
          --move sends those files, and their .md siblings, to DIR/_unverified/.
          Exit 1 if any file was disturbed.

--allow-pid PID exempts PID and all its descendants (the server under test, its engine
workers, the harness) from the per-process checks.

Thresholds (environment): QUIET_MAX_LOAD (1-min load, check only, default 2.5),
QUIET_MAX_PROC_CPU (any single foreign process, default 25 %), QUIET_MAX_FOREIGN_CPU
(sum over foreign processes, default 150 %), QUIET_MAX_GPU (GPU "Device Utilization %"
while our server is idle, check only, default 10 %). GPU figures come from the
AGXAccelerator PerformanceStatistics in ioreg (no sudo).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HOME = str(Path.home())
LOCK = os.environ.get("GPU_LOCK_PATH", f"{HOME}/Developer/mlsys/experiments/.gpu-lock")
LOCK_HOLDER = "local_ai-benchmark session"
PEER_PORT = 8500
MAX_LOAD = float(os.environ.get("QUIET_MAX_LOAD", "2.5"))
MAX_PROC_CPU = float(os.environ.get("QUIET_MAX_PROC_CPU", "25"))
MAX_FOREIGN_CPU = float(os.environ.get("QUIET_MAX_FOREIGN_CPU", "150"))
MAX_GPU = float(os.environ.get("QUIET_MAX_GPU", "10"))
IGNORED = {"WindowServer", "kernel_task"}  # always resident; kernel_task also does the server's driver work
BUILD_NAMES = {"clang", "clang++", "cc1", "cc1plus", "ld", "ld64", "ninja", "make", "gmake", "cmake",
               "swift-frontend", "swiftc", "rustc", "cargo", "xcodebuild"}
BUILD_ARGS = re.compile(r"mlc_llm (convert_weight|compile)|coreai\.llm\.export|\bhf download\b|"
                        r"huggingface-cli download|hf_transfer|snapshot_download|"
                        r"\bbrew (install|upgrade|reinstall)\b|\buv (sync|pip install)\b|\bpip3? install\b")
SETTLE_STEP = 5.0


def run(cmd: list[str], timeout: float = 20.0) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, f"{type(e).__name__}: {e}"


def tidy(s: str) -> str:
    return s.replace(HOME, "~")


def processes() -> list[tuple[int, int, float, str]]:
    """(pid, ppid, %cpu, executable path) for every process."""
    _, out = run(["ps", "-Ao", "pid=,ppid=,pcpu=,comm="])
    procs = []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4:
            try:
                procs.append((int(parts[0]), int(parts[1]), float(parts[2]), parts[3]))
            except ValueError:
                continue
    return procs


def allowed_tree(procs: list[tuple[int, int, float, str]], roots: list[int]) -> set[int]:
    children: dict[int, list[int]] = {}
    for pid, ppid, _, _ in procs:
        children.setdefault(ppid, []).append(pid)
    seen: set[int] = set()
    stack = [r for r in roots if r > 0]
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        stack.extend(children.get(p, []))
    return seen


def lock_purpose() -> str | None:
    try:
        text = Path(LOCK).read_text(encoding="utf-8")
    except OSError:
        return None
    if not re.search(rf"^holder: {re.escape(LOCK_HOLDER)}\s*$", text, re.M):
        return None
    m = re.search(r"^purpose: (.*)$", text, re.M)
    return m.group(1).strip() if m else ""


def peer_port_up() -> bool:
    rc, _ = run(["lsof", "-nP", f"-iTCP:{PEER_PORT}", "-sTCP:LISTEN"])
    return rc == 0


def thermal_warnings() -> list[str]:
    """Throttling indicators from `pmset -g therm`, judged by value: a speed or scheduler limit
    below 100, or a nonzero warning level. 'Note: No ... recorded' lines and other status lines
    are not warnings."""
    _, out = run(["pmset", "-g", "therm"])
    warn = []
    for ln in (x.strip() for x in out.splitlines()):
        if not ln or ln.startswith("Note: No "):
            continue
        lim = re.search(r"(CPU_Speed_Limit|CPU_Scheduler_Limit|GPU_Speed_Limit)\s*=\s*(\d+)", ln)
        lvl = re.search(r"(?i)warning level\D*(\d+)", ln)
        if (lim and int(lim.group(2)) < 100) or (lvl and int(lvl.group(1)) > 0):
            warn.append(ln)
    return warn


def gpu() -> tuple[int, float]:
    """(Device Utilization %, GB of GPU memory in use); (-1, -1.0) if ioreg has no figures."""
    _, out = run(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "AGXAccelerator"])
    util = re.search(r'"Device Utilization %"=(\d+)', out)
    mem = re.search(r'"In use system memory"=(\d+)', out)
    return (int(util.group(1)) if util else -1, round(int(mem.group(1)) / 1e9, 1) if mem else -1.0)


def power() -> tuple[bool, str]:
    _, batt = run(["pmset", "-g", "batt"])
    _, conf = run(["pmset", "-g"])
    src = re.search(r"drawing from '([^']+)'", batt)
    mode = re.search(r"^\s*powermode\s+(\d+)", conf, re.M)
    src_s = src.group(1) if src else "unknown"
    mode_s = mode.group(1) if mode else "?"
    ok = src_s == "AC Power" and mode_s in ("2", "?")
    return ok, f"{src_s}; powermode {mode_s}" + (" (High Power)" if mode_s == "2" else "")


def sample(allow: list[int]) -> dict:
    """One snapshot of everything the quiet rule looks at."""
    procs = processes()
    mine = allowed_tree(procs, allow + [os.getpid()])
    foreign = [(pid, cpu, comm) for pid, _, cpu, comm in procs
               if pid not in mine and os.path.basename(comm) not in IGNORED]
    busy = sorted((p for p in foreign if p[1] > MAX_PROC_CPU), key=lambda p: -p[1])
    top = sorted(foreign, key=lambda p: -p[1])[:4]
    _, cmdlines = run(["ps", "-wwAo", "pid=,command="])
    tools = []
    names = {pid: os.path.basename(comm) for pid, _, _, comm in procs}
    for line in cmdlines.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        pid, cmd = int(parts[0]), parts[1]
        if pid in mine:
            continue
        if names.get(pid) in BUILD_NAMES or BUILD_ARGS.search(cmd):
            tools.append(f"{pid} {tidy(cmd)[:110]}")
    _, la = run(["sysctl", "-n", "vm.loadavg"])
    try:
        load1 = float(la.strip("{} \n").split()[0])
    except (ValueError, IndexError):
        load1 = -1.0
    pwr_ok, pwr = power()
    g_util, g_mem = gpu()
    return {"t": time.time(), "lock": lock_purpose(), "peer_port": peer_port_up(), "load1": load1,
            "gpu_util": g_util, "gpu_mem_gb": g_mem,
            "foreign_cpu": round(sum(p[1] for p in foreign), 1), "busy": busy, "top": top, "tools": tools,
            "thermal": thermal_warnings(), "power_ok": pwr_ok, "power": pwr}


def name(comm: str) -> str:
    return os.path.basename(comm)


def problems(s: dict, judge_load: bool, max_gpu_gb: float | None = None) -> tuple[list[str], list[str]]:
    """(hard, soft) failure reasons for a sample. Hard: lock, port, power. Soft: the rest."""
    hard, soft = [], []
    if s["lock"] is None:
        hard.append("lock not held by us")
    if s["peer_port"]:
        hard.append(f"port {PEER_PORT} listening")
    if not s["power_ok"]:
        hard.append(f"power: {s['power']}")
    if judge_load and s["load1"] > MAX_LOAD:
        soft.append(f"load1 {s['load1']:.2f} > {MAX_LOAD}")
    if judge_load and s["gpu_util"] > MAX_GPU:   # judge_load: our server is idle, so the GPU should be too
        soft.append(f"GPU busy {s['gpu_util']}% > {MAX_GPU:.0f}%")
    if max_gpu_gb is not None and s["gpu_mem_gb"] > max_gpu_gb:
        soft.append(f"GPU memory in use {s['gpu_mem_gb']} GB > {max_gpu_gb} GB (another model resident?)")
    if s["busy"]:
        soft.append("busy: " + ", ".join(f"{name(c)}({pid}) {cpu:.0f}%" for pid, cpu, c in s["busy"]))
    if s["foreign_cpu"] > MAX_FOREIGN_CPU:
        soft.append(f"foreign CPU {s['foreign_cpu']:.0f}% > {MAX_FOREIGN_CPU:.0f}%")
    if s["tools"]:
        soft.append("tools: " + "; ".join(t.split(None, 1)[1][:60] for t in s["tools"]))
    if s["thermal"]:
        soft.append("thermal: " + "; ".join(s["thermal"]))
    return hard, soft


def report(s: dict, settle_note: str | None, verdict: bool) -> str:
    stamp = dt.datetime.fromtimestamp(s["t"]).astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    lines = [f"quiet_check: {stamp}",
             f"lock: held by us ({s['lock']})" if s["lock"] is not None else "lock: NOT held by us",
             f"port {PEER_PORT}: LISTENING (agent-benchmark oMLX is up)" if s["peer_port"] else f"port {PEER_PORT}: free",
             f"load1: {s['load1']:.2f} (max {MAX_LOAD})",
             f"gpu: {s['gpu_util']}% busy (max {MAX_GPU:.0f}), {s['gpu_mem_gb']} GB in use",
             f"foreign CPU: {s['foreign_cpu']:.1f}% total (max {MAX_FOREIGN_CPU:.0f}); top: "
             + ", ".join(f"{name(c)} {cpu:.1f}" for _, cpu, c in s["top"])]
    if s["busy"]:
        lines.append(f"busy foreign processes (>{MAX_PROC_CPU:.0f}% CPU):")
        lines += [f"  {pid} {cpu:.1f} {tidy(c)}" for pid, cpu, c in s["busy"]]
    else:
        lines.append("busy foreign processes: none")
    if s["tools"]:
        lines.append("build/convert/download tools: RUNNING")
        lines += [f"  {t}" for t in s["tools"]]
    else:
        lines.append("build/convert/download tools: none")
    lines.append("thermal: " + ("; ".join(s["thermal"]) if s["thermal"] else "no warning recorded"))
    lines.append(f"power: {s['power']}")
    if settle_note:
        lines.append(settle_note)
    lines.append("verdict: QUIET" if verdict else "verdict: NOT QUIET")
    return "\n".join(lines)


def cmd_check(a: argparse.Namespace) -> int:
    t0 = time.time()
    while True:
        s = sample(a.allow_pid)
        hard, soft = problems(s, judge_load=True, max_gpu_gb=a.max_gpu_gb)
        waited = time.time() - t0
        if hard or not soft or waited + SETTLE_STEP > a.settle:
            break
        time.sleep(SETTLE_STEP)
    ok = not hard and not soft
    note = None
    if a.settle > 0:
        if ok:
            note = f"settle: quiet after {waited:.0f} s (limit {a.settle:.0f} s)"
        elif hard:
            note = f"settle: not attempted (hard failure: {'; '.join(hard)})"
        else:
            note = f"settle: still not quiet after {waited:.0f} s (limit {a.settle:.0f} s): {'; '.join(soft)}"
    print(report(s, note, ok))
    return 0 if ok else 1


def cmd_monitor(a: argparse.Namespace) -> int:
    log = Path(a.log)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as f:
        f.write(f"# quietlib monitor v2 interval={a.interval} max_proc_cpu={MAX_PROC_CPU} "
                f"max_foreign_cpu={MAX_FOREIGN_CPU} allow={','.join(map(str, a.allow_pid))}\n")
        f.write("# iso\tepoch\tstate\tload1\tforeign_cpu\tgpu_util\tgpu_mem_gb\treasons\n")
        f.flush()
        state, prev_cpu = None, False
        while True:
            if a.until_pid and not pid_alive(a.until_pid):
                break
            s = sample(a.allow_pid)
            hard, soft = problems(s, judge_load=False)
            reasons = hard + soft
            cpu = bool(s["busy"]) or s["foreign_cpu"] > MAX_FOREIGN_CPU   # may be a short daemon blip
            instant = bool(hard or s["tools"] or s["thermal"])
            new = "DISTURBED" if instant or (cpu and prev_cpu) else ("SPIKE" if cpu else "QUIET")
            prev_cpu = cpu
            iso = dt.datetime.fromtimestamp(s["t"]).astimezone().isoformat(timespec="seconds")
            f.write(f"{iso}\t{s['t']:.1f}\t{new}\t{s['load1']:.2f}\t{s['foreign_cpu']:.1f}\t"
                    f"{s['gpu_util']}\t{s['gpu_mem_gb']}\t{tidy('; '.join(reasons))}\n")
            f.flush()
            if new != state:
                print(f"{iso[11:19]} {new}" + (f": {tidy('; '.join(reasons))}" if reasons else ""), flush=True)
                state = new
            time.sleep(max(0.5, a.interval - (time.time() - s["t"])))
    return 0


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def read_log(path: Path) -> tuple[float, list[tuple[float, str, str]]]:
    interval, rows = 10.0, []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            m = re.search(r"interval=([\d.]+)", line)
            if m:
                interval = float(m.group(1))
            continue
        parts = line.split("\t")
        if len(parts) >= 3:
            try:
                rows.append((float(parts[1]), parts[2], parts[-1] if len(parts) > 5 else ""))
            except ValueError:
                continue
    return interval, rows


def cmd_verify(a: argparse.Namespace) -> int:
    interval, rows = read_log(Path(a.log))
    raw = Path(a.raw_dir)
    bad = 0
    for f in sorted(raw.glob("*.jsonl")):
        try:
            hdr = json.loads(f.open(encoding="utf-8").readline())
            start = dt.datetime.fromisoformat(hdr["created"]).timestamp()
        except (OSError, ValueError, KeyError):
            continue
        if start < a.since - 1:
            continue
        end = f.stat().st_mtime
        inside = [r for r in rows if start - interval <= r[0] <= end + interval]
        disturbed = [r for r in inside if r[1] not in ("QUIET", "SPIKE")]
        edges = [start] + [r[0] for r in inside] + [end]
        gap = max((b - x for x, b in zip(edges, edges[1:])), default=0.0)
        why = None
        if disturbed:
            why = f"{len(disturbed)} disturbed sample(s), first at " \
                  f"{dt.datetime.fromtimestamp(disturbed[0][0]).strftime('%H:%M:%S')}: {disturbed[0][2]}"
        elif gap > 3 * interval:
            why = f"monitor gap of {gap:.0f} s (interval {interval:.0f} s)"
        if why is None:
            print(f"verify: {f.name}: quiet ({len(inside)} samples, {end - start:.0f} s)")
            continue
        bad += 1
        print(f"verify: {f.name}: DISTURBED, {why}")
        if a.move:
            dest = raw / "_unverified"
            dest.mkdir(exist_ok=True)
            for g in [f, f.with_suffix(".md")]:
                if g.exists():
                    g.rename(dest / g.name)
                    print(f"verify: moved {g.name} -> raw/_unverified/")
    return 1 if bad else 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="quietlib", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--allow-pid", type=int, action="append", default=[])
    c.add_argument("--settle", type=float, default=0.0)
    c.add_argument("--max-gpu-gb", type=float)
    m = sub.add_parser("monitor")
    m.add_argument("--log", required=True)
    m.add_argument("--interval", type=float, default=10.0)
    m.add_argument("--allow-pid", type=int, action="append", default=[])
    m.add_argument("--until-pid", type=int)
    v = sub.add_parser("verify")
    v.add_argument("--log", required=True)
    v.add_argument("--raw-dir", required=True)
    v.add_argument("--since", type=float, required=True)
    v.add_argument("--move", action="store_true")
    a = p.parse_args(argv)
    return {"check": cmd_check, "monitor": cmd_monitor, "verify": cmd_verify}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
