#!/usr/bin/env python3
"""Run a heavy CPU command under the benchmark's CPU-courtesy policy.

Policy (coordinator, 2026-10-18 01:45 EDT):
- GPU lock held by "local_ai-benchmark": never run. If the command is already
  running, SIGSTOP its whole process group until the lock is released.
- GPU lock held by anyone else: nice 19 and at most 8 parallel jobs.
- No lock: full speed (18 jobs).

The command receives JOBS, CMAKE_BUILD_PARALLEL_LEVEL and TVM_NUM_THREADS in its
environment. With --restartable, a run that started at full speed is terminated
and relaunched with 8 jobs when another session takes the lock (safe for
ninja/scikit-build builds, which resume incrementally).

Usage: heavy.py [--restartable] -- <command...>
"""
import datetime
import os
import signal
import subprocess
import sys
import time

LOCK = os.path.expanduser("~/Developer/mlsys/experiments/.gpu-lock")
FULL_JOBS = 18
COURTESY_JOBS = 8
POLL = 30


def log(msg):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[heavy {ts}] {msg}", flush=True)


def state():
    try:
        with open(LOCK, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return "none"
    except OSError:
        return "ours"
    for line in text.splitlines():
        if line.startswith("holder:"):
            return "ours" if "local_ai-benchmark" in line else "other"
    return "ours"  # unreadable or half-written lock: be conservative


def renice(pgid):
    subprocess.run(["renice", "19", "-g", str(pgid)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    args = sys.argv[1:]
    restartable = False
    if args and args[0] == "--restartable":
        restartable = True
        args = args[1:]
    if args and args[0] == "--":
        args = args[1:]
    if not args:
        print(__doc__)
        return 2
    while True:
        s = state()
        while s == "ours":
            log("lock held by local_ai-benchmark: waiting")
            time.sleep(POLL)
            s = state()
        jobs = FULL_JOBS if s == "none" else COURTESY_JOBS
        niceness = 0 if s == "none" else 19
        env = dict(os.environ, JOBS=str(jobs), CMAKE_BUILD_PARALLEL_LEVEL=str(jobs),
                   TVM_NUM_THREADS=str(jobs))
        log(f"start (lock={s}, jobs={jobs}, nice={niceness}): {' '.join(args)}")
        t0 = time.time()

        def pre(n=niceness):
            os.setpgrp()
            if n:
                os.nice(n)

        p = subprocess.Popen(args, env=env, preexec_fn=pre)
        pgid = p.pid
        paused = False
        cur_nice = niceness
        restart = False
        stopped_s = 0.0
        stop_t = None
        while True:
            try:
                rc = p.wait(timeout=POLL)
                break
            except subprocess.TimeoutExpired:
                pass
            s = state()
            if s == "ours" and not paused:
                os.killpg(pgid, signal.SIGSTOP)
                paused = True
                stop_t = time.time()
                log("lock taken by local_ai-benchmark: SIGSTOP process group")
                continue
            if s != "ours" and paused:
                if s == "other" and cur_nice < 19:
                    renice(pgid)
                    cur_nice = 19
                os.killpg(pgid, signal.SIGCONT)
                paused = False
                stopped_s += time.time() - stop_t
                log(f"lock now '{s}': SIGCONT")
            if s == "other" and not paused:
                if cur_nice < 19:
                    renice(pgid)
                    cur_nice = 19
                    log("lock held by another session: reniced to 19")
                if jobs > COURTESY_JOBS and restartable:
                    log("restarting with 8 jobs")
                    os.killpg(pgid, signal.SIGTERM)
                    p.wait()
                    restart = True
                    break
        if restart:
            continue
        wall = time.time() - t0
        log(f"exit {rc}; wall {wall:.0f} s, paused {stopped_s:.0f} s, active {wall - stopped_s:.0f} s")
        return rc


if __name__ == "__main__":
    sys.exit(main())
