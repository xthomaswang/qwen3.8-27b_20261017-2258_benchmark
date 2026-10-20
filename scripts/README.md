# scripts/

Server launch and GPU-lock tooling for the benchmark. Only `serve.sh` without `--dry-run`
starts a server (and so loads a model). Everything else reads state or writes small config
files. The scripts run from any directory and are bash 3.2 compatible (macOS `/bin/bash`).

## One framework run, in order

Two terminals: A runs the server in the foreground, B runs everything else. After a pause,
message the agent-benchmark session before taking the first lock.

| Step | Command | If it fails |
| --- | --- | --- |
| 1. Lock | `scripts/gpu_lock.sh acquire "<purpose>" <eta-minutes>` | exit 2: the other side holds it; wait. Exit 3: we hold the lock, but port 8500 is up; ask the agent-benchmark session to stop its oMLX, then check `gpu_lock.sh status`. |
| 2. Check | `scripts/serve.sh <framework> <variant> <tier> --dry-run` | exit 4: fix the NOT READY lines first. |
| 3. Serve (A) | `scripts/serve.sh <framework> <variant> <tier>` | exit 5: lock or port problem; nothing was started. |
| 4. Wait (B) | `scripts/wait_ready.sh <port> <timeout-s>` | exit 1: timeout. Exit 3: the server died (it prints the log tail). |
| 5. Harness (B) | `agentbench run-all` against `http://127.0.0.1:<port>` | `run-all` is planned, not implemented yet (`harness/STATUS.md`). Until then, run the suites one by one. Use the model id and provenance from `logs/<framework>-<variant>-<tier>.cmd`. |
| 6. Stop (B) | `scripts/stop_server.sh <framework>` (or Ctrl-C in A) | exit 1: something still runs; it prints what. |
| 7. Release | `scripts/gpu_lock.sh release` | It refuses while one of our ports still listens. |

Example, oMLX 8-bit:

```bash
scripts/gpu_lock.sh acquire "oMLX 8bit gate + M1-M7" 90
scripts/serve.sh omlx spec-off 8bit --dry-run
scripts/serve.sh omlx spec-off 8bit        # terminal A
scripts/wait_ready.sh 8703 600             # terminal B
#   ... harness against http://127.0.0.1:8703, model "mlx-community--Qwen3.8-27B-8bit" ...
scripts/stop_server.sh omlx
scripts/gpu_lock.sh release
```

## Frameworks

| Framework | Variants | Tiers | Port | `model` in requests | One-time preparation |
| --- | --- | --- | --- | --- | --- |
| mlx-lm | `server` | 8bit 4bit | 8701 | omit it, or `"default_model"` | none |
| llama.cpp | `mtp-off` `mtp-on` `conc` (`-np 3 -kvu`) | 4bit (UD-Q4_K_M) | 8702 | `qwen3.8-27b` | none |
| omlx | `spec-off`; `spec-on` is a stub | 8bit 4bit | 8703 | `mlx-community--Qwen3.8-27B-<tier>` | `scripts/omlx_configure.sh` (done 2026-10-18) |
| lithos-metal | `dspark` `no-draft` | 4bit nvfp4 | 8704 | `Qwen3.8-27B-4bit` / `nvidia/Qwen3.8-27B-NVFP4` | 4bit: apply `lithos-metal/lm_head_rename.patch` (`lithos-metal/env.md` §4) |
| vllm-metal | `spec-off`; `spec-on` is a stub | 8bit 4bit | 8705 | `qwen3.8-27b-<tier>` | `scripts/make_procfix.sh <tier>` (both views exist) |

The launch commands are the ones in each `<framework>/env.md`. Deviations:

- **Logging.** Every server's stdout and stderr are tee'd into the run log. For llama.cpp,
  env.md's `--log-file` is therefore not passed (it would duplicate every line). Python servers
  get `PYTHONUNBUFFERED=1` so that the log keeps up.
- **Environment.** Every server runs with `HF_HUB_OFFLINE=1` and `HF_HOME` exported, under
  `caffeinate -ims -w <pid>` (ENVIRONMENT.md: no sleep during runs).
- **vLLM-Metal model path.** It serves `~/Developer/mlsys/models/derived/Qwen3.8-27B-<tier>-procfix`,
  not the bare snapshot. The 8-bit `processor_config.json` names `Qwen3VLImageProcessor`, which
  transformers 5.17/5.20 lacks. The 4-bit already ships `Qwen2VLImageProcessor`; its view only
  keeps the two tiers uniform.
- **lithos-metal 4bit.** It uses the official `mlx-community/Qwen3.8-27B-4bit` in place of
  env.md's locally re-quantized path.
- **Extra flags.** Words after `--` are appended to the command, e.g. `-- -lv 4`, or
  `-- --chat-template-kwargs '{"enable_thinking":false}'` (llama.cpp/env.md §3).
  `LLAMA_MMPROJ=0` drops `--mmproj` (the env.md fallback if MTP is disabled with an mmproj).
- **Readiness.** mlx-lm's `/health` answers ok while the model still loads, and oMLX loads on
  the first request. The harness warm-up absorbs that time; never time the first request.

## What a run writes (`logs/`, gitignored)

- `logs/<framework>-<variant>-<tier>-<YYYYmmdd-HHMMSS>.log`: the `.cmd` header, then server output.
- `logs/<framework>-<variant>-<tier>.cmd`: the latest run, for provenance. Comment lines carry
  the framework `git describe` and modified files, installed package versions, checkpoint
  commits, the model id and notes; the last line is the exact command (`cd … && env … <cmd>`).
- `logs/<framework>.pid`: the server's PID. `serve.sh` execs into the server, so this is the
  real process. `stop_server.sh` signals only that PID, and only after checking that it is ours.

## Files

| File | Purpose |
| --- | --- |
| `gpu_lock.sh` | `acquire <purpose> <eta-min>` / `release [--force]` / `status` for `~/Developer/mlsys/experiments/.gpu-lock` (noclobber create; holder `local_ai-benchmark session`). The holder names the session, so `serve.sh` accepts, and `release` deletes, any lock of this session. Only the one who acquired it releases it. Tests set `GPU_LOCK_PATH` to a temporary file. |
| `serve.sh` | Checks, then the foreground launch (above). `--dry-run` prints the exact command and the `.cmd` content. |
| `wait_ready.sh` | Polls `/health` (and `/v1/models` for oMLX, vLLM, lithos, llama.cpp) every 2 s. |
| `stop_server.sh` | SIGINT, then SIGTERM, then SIGKILL for the pidfile's PID. Reports surviving children; `--children` stops them. |
| `omlx_configure.sh` | `hf-bench` links for complete tiers, plus `max_context_window: 131072` per model in `.bench-home/model_settings.json`. Idempotent; refuses while 8703 listens. |
| `make_procfix.sh` | Builds or verifies (`--check`) the vLLM-Metal procfix view. It never modifies an existing view and never links or writes the upstream `README.md`. |
| `hf_snapshot.py` | Resolves `refs/main` and checks the needed files against `trees/<commit>.json` sizes and the safetensors/GGUF headers. Leftover `.incomplete` blobs are ignored once the real file is complete. |
| `run_framework.sh` | One framework variant end to end, with the lock already held. It checks that the GPU is idle with no model resident, then serve → wait → warm-up. After that it runs one `agentbench run-all` per suite: wait for the battery (≥ 40 %, up to 90 min, server idle) → wait until quiet (≤ 10 min) → the suite, with the harness pre-flight → a monitor verdict. A suite the monitor saw disturbed moves to `raw/_unverified/` and is repeated once. At the end it regenerates `summary.md` and stops the server. Logs: `logs/run-<fw>-<tag>-<suite>.log`, `logs/monitor-<fw>-<tag>.events`. |
| `run_m8.sh` | M8, the interference study (METHODOLOGY.md, section 4), for one framework variant, with the lock already held. Same arguments as `run_framework.sh` minus the suites. One server launch runs blocks `B S1 B S2 … S7 B`: a clean baseline, then a load from `interference.py`, alternating. Per block: battery, strict quiet check with no load, then (scenario blocks) the load, its own monitor with the load PID exempt and the scenario's allowances, a 60 s settle; then M1 warm, M3 16K/cap 150 and a one-run M4, each verified and repeated once like `run_framework.sh`; then the load stops and the machine cools down. Tags `<tag>-m8-base` / `<tag>-m8-<scenario>`; `M8_DRY_RUN=1` prints the plan. Table: `agentbench m8-report`. |
| `interference.py` | The M8 loads: `start <scenario>` (cpu1, cpuhalf, cpuall, gpu, mem, disk, power) runs one process tree with a single root PID and a JSON pidfile; SIGTERM/SIGINT stop it cleanly, workers exit when their root is gone, the disk file is deleted. `stop`, `status --wait-ready`, `meta` (the raw-header record), `allowances`, `wait-power`. The power scenario never runs sudo: it prints the `pmset` command and waits. Stdlib only; run with `/usr/bin/python3 -I`. |
| `run_tier2.sh` | The Tier-2 block, with the lock already held: M6 for the three candidates (`m6-llama`, `m6-omlx`, `m6-vllm`), the 8-bit rows (`omlx-8bit`, `vllm-8bit`, `mlxlm-8bit`) and the text-only references (`mlxlm-4bit`, `lithos-dspark`, `lithos-nodraft`, `lithos-nvfp4`). Same rules as `run_tier1.sh`. |
| `quiet_check.sh` | The quiet-machine pre-flight, a wrapper for `quietlib.py check`. `--allow-pid` exempts a PID and its descendants. `--allow load,gpu,thermal,lowpower` accepts an M8 load's own side effects, by name, and prints them. `--settle S` waits up to S seconds for soft failures to clear. `--max-gpu-gb G` fails while another model is resident. `--min-battery PCT` fails below PCT %. Criteria: METHODOLOGY.md, "Quiet machine". |
| `quietlib.py` | `check`, `monitor` (TSV every 10 s, with state changes on stdout; v3 rows add the battery and thermal pressure levels), `verify` (moves result files whose window holds a DISTURBED sample, or a sampling gap) and `battery --min PCT --wait S`. A battery below 20 % during a suite counts as disturbed. `check` and `monitor` take M8's `--allow` (allowed reasons are logged as `allowed …` and never count; the monitor header records `allowances=`). Third-party apps are shown as `<app>`. Stdlib only; run with `/usr/bin/python3 -I`. |
| `redact.py` | Replaces third-party app names in older result files with `<app>`, the rule `quietlib.py` now applies at sample time. `--check` only reports. Run it on every results file before committing. |
| `lib.sh` | Shared helpers (ports, lock, PID ownership, quoting). |
| `download_models.sh` | Fetches the checkpoints into the shared HF cache. |

Exit codes: 0 ok · 1 failure or timeout · 2 usage, lock held (`acquire`) or PID not ours (`stop`)
· 3 port 8500 up (`acquire`) or server exited (`wait_ready`) · 4 not ready · 5 refused (lock or
ports) · 6 unsupported variant.
