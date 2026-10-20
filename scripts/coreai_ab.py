#!/usr/bin/env python3
"""Direct-call A/B: Core AI's llm-benchmark against mlx_lm.benchmark at the 4-bit tier.

Both tools run the same protocol (coreai/env.md, section 5): a random-token prompt with no
chat template, greedy decoding, batch 1, one untimed warm-up, then N trials with a cold
prefill each. Per prompt length the order is A B A B, with --idle seconds between runs.

The GPU lock must already be held (scripts/gpu_lock.sh). Each run is handled like a suite in
run_framework.sh: a quiet pre-flight (quiet_check.sh, stored in the header), the quiet
monitor over the whole block, and `quietlib.py verify` after each run. A disturbed run moves
to coreai/raw/_unverified/ and is repeated (--retries).

Output: one JSONL per run in coreai/raw/ (ab-<engine>-p<P>-...jsonl: a header with the
provenance and the pre-flight, then one result line), the tool logs in logs/coreai/, and a
markdown table on stdout (median, min and max over the trials of both repeats).

Stdlib only; run with /usr/bin/python3 -I. Usage:
  coreai_ab.py [--prompts 512,16384] [--gen 1024] [--trials 5] [--idle 60] [--retries 1]
  coreai_ab.py --table   (only print the table from the verified files in coreai/raw/)
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "coreai" / "raw"
LOGS = ROOT / "logs" / "coreai"
COREAI = HOME / "Developer/mlsys/serving/coreai-models"
MLXLM = HOME / "Developer/mlsys/serving/mlx-lm"
HF_HOME = HOME / "Developer/ml_source/huggingface"
BETA = "/Applications/Xcode-beta.app/Contents/Developer"  # Core AI builds against the 27.2 SDK (env.md)
M27 = HOME / "Developer/mlsys/models/coreai/qwen3_8_27b_qwen3_5_cfg_dynamic"
M4 = HF_HOME / "hub/models--mlx-community--Qwen3.8-27B-4bit/snapshots/10c35caafbb80f7dc6a7a432cdd11af10a6d4818"
PY = "/usr/bin/python3"
QUIET = ROOT / "scripts" / "quiet_check.sh"
QLIB = ROOT / "scripts" / "quietlib.py"
ORDER = ("coreai", "mlxlm", "coreai", "mlxlm")

REAL = re.compile(r"^\s*([\d.]+) real", re.M)
FOOTPRINT = re.compile(r"^\s*(\d+)\s+peak memory footprint", re.M)
MAXRSS = re.compile(r"^\s*(\d+)\s+maximum resident set size", re.M)
MLX_TRIAL = re.compile(r"Trial (\d+):\s+prompt_tps=([\d.]+), generation_tps=([\d.]+), "
                       r"peak_memory=([\d.]+), total_time=([\d.]+)")


def ts() -> str:
    return time.strftime("%T")


def tilde(s: str) -> str:
    """Public files carry ~ instead of the home directory (README, "Provenance")."""
    return s.replace(str(HOME), "~")


def sh(cmd: list[str], env: dict | None = None) -> str:
    r = subprocess.run(cmd, env=env, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def provenance() -> dict:
    py = str(MLXLM / ".venv/bin/python")
    return {
        "sw_vers": sh(["sw_vers"]),
        "xcode_default": sh(["xcodebuild", "-version"]),
        "xcode_coreai": sh(["xcodebuild", "-version"], env=dict(os.environ, DEVELOPER_DIR=BETA)),
        "coreai_models": sh(["git", "-C", str(COREAI), "describe", "--always", "--dirty"]),
        "mlx_lm": sh(["git", "-C", str(MLXLM), "describe", "--always", "--dirty"]),
        "mlx_lm_and_mlx_versions": sh([py, "-c", "import mlx.core as mx, mlx_lm; print(mlx_lm.__version__, mx.__version__)"]),
        "chip": sh(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "memory_bytes": int(sh(["sysctl", "-n", "hw.memsize"]) or 0),
        "models": {"coreai": tilde(str(M27)), "mlxlm": tilde(str(M4))},
    }


def command(engine: str, p: int, a: argparse.Namespace, json_out: Path) -> tuple[list[str], Path, dict]:
    if engine == "coreai":
        cmd = [str(COREAI / ".build/out/Products/Release/llm-benchmark"), "--model", str(M27),
               "-p", str(p), "-g", str(a.gen), "-n", str(a.trials), "--output-json", str(json_out)]
        return ["/usr/bin/time", "-l"] + cmd, COREAI, dict(os.environ, DEVELOPER_DIR=BETA, HF_HUB_OFFLINE="1")
    cmd = [str(MLXLM / ".venv/bin/mlx_lm.benchmark"), "--model", str(M4),
           "-p", str(p), "-g", str(a.gen), "-n", str(a.trials)]
    return ["/usr/bin/time", "-l"] + cmd, MLXLM, dict(os.environ, HF_HUB_OFFLINE="1", HF_HOME=str(HF_HOME))


def parse(engine: str, log: str, json_out: Path) -> dict:
    m, f, r = REAL.search(log), FOOTPRINT.search(log), MAXRSS.search(log)
    # The footprint leaves out clean mmap'd pages (Core AI maps its weights), so record the max RSS too.
    res: dict = {"real_s": float(m.group(1)) if m else None, "peak_footprint_bytes": int(f.group(1)) if f else None,
                 "max_rss_bytes": int(r.group(1)) if r else None}
    if engine == "coreai":
        j = json.loads(json_out.read_text(encoding="utf-8"))
        res.update(trials=[{"prompt_tps": t["prompt_tps"], "generation_tps": t["gen_tps"]} for t in j["trials"]],
                   prepare_s=j.get("prepare_seconds"), warmup_s=j.get("warmup_seconds"), cache_hit=j.get("cache_hit"),
                   tool_json=j)
    else:
        res["trials"] = [{"prompt_tps": float(pt), "generation_tps": float(gt), "peak_memory_gb": float(pm),
                          "total_s": float(tt)} for _, pt, gt, pm, tt in MLX_TRIAL.findall(log)]
    return res


def preflight(a: argparse.Namespace, first: bool) -> subprocess.CompletedProcess:
    """Wait until quiet_check passes (up to --wait s). The first run also requires an idle GPU."""
    cmd = [str(QUIET), "--allow-pid", str(os.getpid()), "--settle", str(a.settle), "--min-battery", "40"]
    if first:
        cmd += ["--max-gpu-gb", "6"]
    t0 = time.time()
    while True:
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 or time.time() - t0 > a.wait or "lock not held by us" in r.stdout:
            r.args = cmd
            return r
        time.sleep(30)


def run_one(engine: str, p: int, a: argparse.Namespace, prov: dict, mon_log: Path, first: bool) -> str:
    """One timed run. Returns 'ok', 'disturbed' or 'failed'."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    stem = f"ab-{engine}-p{p}-g{a.gen}-n{a.trials}-{stamp}"
    pre = preflight(a, first)
    if pre.returncode != 0:
        print(f"{ts()} {stem}: not quiet after {a.wait:.0f} s; stopping\n{pre.stdout}", flush=True)
        return "failed"
    created = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    t0 = time.time()
    json_out = LOGS / f"{stem}.tool.json"
    cmd, cwd, env = command(engine, p, a, json_out)
    log_path = LOGS / f"{stem}.log"
    print(f"{ts()} {stem}: start", flush=True)
    with log_path.open("w", encoding="utf-8") as f:
        rc = subprocess.run(cmd, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT).returncode
    log = log_path.read_text(encoding="utf-8", errors="replace")
    try:
        res = parse(engine, log, json_out) if rc == 0 else {"error": f"exit code {rc}; see logs/coreai/{log_path.name}"}
    except (OSError, ValueError, KeyError) as e:
        res, rc = {"error": f"unparsable output ({e}); see logs/coreai/{log_path.name}"}, rc or 1
    hdr = {"type": "header", "suite": "ab", "engine": engine, "created": created,
           "prompt_tokens": p, "generation_tokens": a.gen, "trials": a.trials,
           "command": tilde(" ".join(cmd)), "cwd": tilde(str(cwd)), "provenance": prov,
           "preflight": {"command": tilde(" ".join(pre.args)), "exit_code": pre.returncode,
                         "output": tilde(pre.stdout + pre.stderr)},
           "unverified": False}
    out = RAW / f"{stem}.jsonl"
    with out.open("w", encoding="utf-8") as f:
        f.write(json.dumps(hdr) + "\n")
        f.write(json.dumps({"type": "result", "exit_code": rc, **res}) + "\n")
    trials = res.get("trials") or []
    if trials:
        print(f"{ts()} {stem}: prompt {statistics.median(t['prompt_tps'] for t in trials):.1f} tok/s, "
              f"generation {statistics.median(t['generation_tps'] for t in trials):.2f} tok/s (medians)", flush=True)
    time.sleep(11)  # let the monitor take one more sample after the run
    v = subprocess.run([PY, "-I", str(QLIB), "verify", "--log", str(mon_log), "--raw-dir", str(RAW),
                        "--since", str(t0), "--move"], capture_output=True, text=True)
    print(v.stdout.strip(), flush=True)
    if rc != 0:
        return "failed"
    return "ok" if v.returncode == 0 else "disturbed"


def table() -> str:
    rows: dict[tuple[int, str], list[dict]] = {}
    for f in sorted(RAW.glob("ab-*.jsonl")):
        lines = [json.loads(x) for x in f.read_text(encoding="utf-8").splitlines() if x.strip()]
        hdr, res = lines[0], lines[1]
        if res.get("exit_code") == 0:
            rows.setdefault((hdr["prompt_tokens"], hdr["engine"]), []).append(res)

    def mmm(xs: list[float], nd: int) -> str:
        return f"{statistics.median(xs):.{nd}f} ({min(xs):.{nd}f}-{max(xs):.{nd}f})" if xs else "-"

    out = ["| prompt | engine | runs | trials | prompt tok/s | generation tok/s | peak footprint GB | max RSS GB |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for (p, eng), rs in sorted(rows.items()):
        tr = [t for r in rs for t in r["trials"]]
        fp = [r["peak_footprint_bytes"] / 1e9 for r in rs if r.get("peak_footprint_bytes")]
        rss = [r["max_rss_bytes"] / 1e9 for r in rs if r.get("max_rss_bytes")]
        out.append(f"| {p:,} | {eng} | {len(rs)} | {len(tr)} | {mmm([t['prompt_tps'] for t in tr], 1)} | "
                   f"{mmm([t['generation_tps'] for t in tr], 2)} | {mmm(fp, 1)} | {mmm(rss, 1)} |")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--prompts", default="512,16384")
    ap.add_argument("--gen", type=int, default=1024)
    ap.add_argument("--trials", type=int, default=5)
    ap.add_argument("--idle", type=float, default=60.0, help="seconds between runs")
    ap.add_argument("--retries", type=int, default=1, help="repeats of a disturbed run")
    ap.add_argument("--settle", type=float, default=90.0, help="quiet_check --settle per attempt")
    ap.add_argument("--wait", type=float, default=600.0, help="how long to wait for a quiet machine per run")
    ap.add_argument("--table", action="store_true", help="only print the table of the verified runs")
    a = ap.parse_args()
    if a.table:
        print(table())
        return 0
    RAW.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    prov = provenance()
    mon_log = RAW / f"monitor-ab-{time.strftime('%Y%m%d-%H%M%S')}.tsv"
    events = (LOGS / "monitor-ab.events").open("a", encoding="utf-8")
    mon = subprocess.Popen([PY, "-I", str(QLIB), "monitor", "--log", str(mon_log), "--interval", "10",
                            "--allow-pid", str(os.getpid()), "--until-pid", str(os.getpid())],
                           stdout=events, stderr=subprocess.STDOUT)
    time.sleep(11)
    failed, first = [], True
    try:
        for p in [int(x) for x in a.prompts.split(",")]:
            for i, engine in enumerate(ORDER):
                if not first:
                    print(f"{ts()} idle {a.idle:.0f} s", flush=True)
                    time.sleep(a.idle)
                for attempt in range(a.retries + 1):
                    state = run_one(engine, p, a, prov, mon_log, first)
                    first = False
                    if state != "disturbed":
                        break
                    print(f"{ts()} {engine} p{p}: disturbed; " + ("repeating" if attempt < a.retries else "giving up"),
                          flush=True)
                if state == "failed":
                    print(f"{ts()} stopping: {engine} p{p} failed", flush=True)
                    return 1
                if state != "ok":
                    failed.append(f"{engine}-p{p}-{i}")
    finally:
        mon.terminate()
    print(f"{ts()} A/B block done; disturbed on every attempt: {', '.join(failed) or 'none'}\n\n{table()}", flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
