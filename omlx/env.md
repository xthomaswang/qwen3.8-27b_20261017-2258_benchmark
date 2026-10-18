# oMLX v0.7.1rc1: environment and launch plan

Prepared 2026-10-17, 23:20–23:40. No model was loaded and no weights were downloaded.
`file:line` references point into `~/Developer/mlsys/serving/omlx_0.7` at tag
`v0.7.1rc1` (commit `7a5a3d75ce7463300bdfa5fedccd34348f60ff46`, a grafted shallow clone).

## Status / remaining work

| Item | State |
| --- | --- |
| `.venv` (uv, CPython 3.12.14) | created |
| Python deps (`uv pip install -e .`) | **done**, exit 0 at 23:31:59 (details below) |
| Native custom kernels | **not built yet** |
| Isolation (base path, git exclude) | done: `.bench-home/` is in the clone's `.git/info/exclude`, and the base path was created by the smoke run |
| Model dir `~/Developer/mlsys/models/hf-bench/` | done (one symlink, see below) |
| Server smoke check on 8703 (task 4) | **done** with an empty model dir, no model loaded; the server is stopped and 8703 is free |
| Research questions | answered below from source. Items marked *verify* need a live check. |

### Install state at hand-off

- `uv pip install --python .venv/bin/python -e .` ran 23:21:39–23:31:59 and exited 0:
  "Resolved 110 packages in 7m 03s", "Prepared 29 packages in 3m 16s", "Installed 110
  packages" (log: `logs/omlx-install.log` in this repo, gitignored). All four git pins
  were fetched and built (mlx-lm, mlx-vlm, mlx-embeddings, mlx-audio).
- Installed versions: omlx 0.7.1rc1, mlx 0.32.4, mlx-metal 0.32.4,
  mlx-lm 0.31.4.dev132+g94cdcae13, mlx-vlm 0.7.8, mlx-embeddings 0.1.0, mlx-audio 0.5.7,
  transformers 5.17.0, tokenizers 0.23.3, huggingface-hub 1.33.0, numpy 2.3.5,
  fastapi 0.143.3, uvicorn 0.54.0.
- **Native kernels: not built.** There was no time before the 23:40 stop; a half-built
  in-place tree would be worse than none. `native_kernel_status()` right now reports
  `bonsai`, `decode_fast`, `glm_moe_dsa`, `minimax_m3` and `qwen35_prefill` all
  `available: False` (no `_ext` module). **Do not benchmark until resume step 2 passes.**
- Download size, approximate: about 166 MB of git packs for the four git pins
  (new `~/.cache/uv/git-v1/db` entries: 102.6 + 58.9 + 3.1 + 0.9 MB), plus 95.5 MiB of
  wheels that uv itemized (pyarrow 34.7, onnxruntime 19.9, magika 12.7, lxml 8.2,
  pdfminer-six 6.3, primp 5.7, pypdfium2 3.4, openai-harmony 2.5, cohere-melody 2.1),
  plus the wheels fetched during resolution that uv does not itemize (cmake 4.4.4,
  mlx-metal 0.32.4, nanobind 3.1.0, transformers 5.17.0 and small ones), estimated at
  about 100 MB. **Total: about 0.35–0.4 GB.** The `en0` counters cannot isolate this,
  because sibling sessions were downloading at the same time. pyarrow, onnxruntime and
  magika come in through the base `markitdown[pdf,docx,pptx]` dependency, which is not
  optional.
- Server smoke check (task 4), done 23:32:42–23:32:50 with an empty model dir
  (`.bench-home/empty-models`) and `OMLX_HF_CACHE_ENABLED=false`: it started in about 7 s
  on 127.0.0.1:8703 and **loaded no model**. `GET /v1/models` returned
  `{"object":"list","data":[]}`. `POST /v1/chat/completions` and `POST /v1/messages`
  returned 404 `not_found_error` "Model 'x' not found. Available models: (none)". The
  OpenAPI schema lists 121 routes, including `/v1/chat/completions`, `/v1/completions`,
  `/v1/messages`, `/v1/messages/count_tokens`, `/v1/responses`, `/v1/models`,
  `/v1/models/status`, `/v1/models/{model_id}/load|unload`, `/v1/tokenize` and
  `/v1/detokenize`. The server was stopped with SIGINT at 23:32:50 and nothing listens on
  8703 any more (log: `logs/omlx-smoke.log`).
- Isolation check after the smoke run: the server's open files under `~` were only the
  Python binary, the clone and its log; there was no `~/.omlx` path. No file newer than
  the start marker exists in `~/Library/Application Support/oMLX`,
  `~/Library/Application Support/Splash`, `~/.cache/huggingface` or
  `~/Developer/mlsys/models`. `git status` of the clone is clean. The base path now
  holds `settings.json`, `stats.json`, `usage.sqlite3`, `cache/` (`_boundary_snapshots`,
  `response-state`), `logs/` (`server.log`, `crash.log`), `cluster/identity.json` and
  `empty-models/`.
- **Finding: the first start wrote the full effective settings to
  `<base>/settings.json`, env-derived values included** (`"port": 8703`, host
  `127.0.0.1`), even though no persisted CLI flag was passed. Env vars still override the
  file on later starts (`omlx/settings.py:1098-1113`), so this is harmless inside
  `.bench-home`, but the file is not a pure record of what was explicitly configured.
- Startup warning: "Metal cap (107.5GB, Apple max_recommended_working_set_size) is below
  the oMLX static ceiling (120.0GB) … because iogpu.wired_limit_mb is unset". The effective
  GPU working set is therefore 107.5 GB. Do not change the sysctl for this benchmark;
  record it with M6.

### Resume steps (exact)

```bash
cd ~/Developer/mlsys/serving/omlx_0.7

# 1. Python deps: DONE 23:31:59 (exit 0). Rerun only if .venv is recreated (idempotent, uses the uv cache)
uv pip install --python .venv/bin/python -e . 2>&1 | tee -a \
  ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/omlx-install.log

# 2. NEXT: native custom kernels = the Makefile's `kernels` target, aimed at .venv
make clean-kernels
uv pip install --python .venv/bin/python 'setuptools>=61.0' 'cmake>=3.27' 'nanobind==3.1.0'
xcodebuild -showComponent MetalToolchain     # mounts the Metal toolchain (see Caveats)
xcrun -sdk macosx metal --version            # must print "Apple metal version 32023.921 ..."
PATH="$PWD/.venv/bin:$PATH" OMLX_WITH_CUSTOM_KERNEL=1 \
  .venv/bin/python setup.py build_ext --inplace --force 2>&1 | tee \
  ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/omlx-kernels.log

# 3. Verify (the Makefile's own check)
.venv/bin/python -c "from omlx.custom_kernels import native_kernel_status; print(native_kernel_status())"

# 4. Record versions for this file
.venv/bin/python -c "import omlx, mlx.core as mx, mlx_lm, mlx_vlm; print(omlx.__version__, mx.__version__, mlx_lm.__version__, mlx_vlm.__version__)"
uv pip list --python .venv/bin/python | grep -E '^(mlx|omlx|transformers|tokenizers|huggingface)'

# 5. Server smoke check with an EMPTY model dir: DONE 23:32 (results above). Repeat after the kernel build, then stop it (Ctrl-C)
mkdir -p "$PWD/.bench-home/empty-models"
OMLX_BASE_PATH="$PWD/.bench-home" OMLX_HOST=127.0.0.1 OMLX_PORT=8703 \
OMLX_MODEL_DIR="$PWD/.bench-home/empty-models" OMLX_HF_CACHE_ENABLED=false \
  .venv/bin/omlx serve --base-path "$PWD/.bench-home" --headless
#   in another shell:
curl -s http://127.0.0.1:8703/v1/models
curl -s -X POST http://127.0.0.1:8703/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"hi"}]}'   # expect a model-not-found error
curl -s -X POST http://127.0.0.1:8703/v1/messages -H 'Content-Type: application/json' \
  -d '{"model":"x","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}'
#   then confirm nothing outside .bench-home changed:
find ~/Developer/mlsys/serving/omlx_0.7/.bench-home -maxdepth 2
```

`make install PYTHON=.venv/bin/python` is the literal alternative, but it calls
`$(PYTHON) -m pip`, and a uv venv has no pip unless it was created with `uv venv --seed`.
The steps above are the same targets (`Makefile:13-15`, `Makefile:19-20`, `Makefile:32-37`)
with `uv pip` in place of `pip`, so they reuse the shared uv cache on the slow network.

Open questions (need a running server or the model):

1. Exact `native_kernel_status()` output on this machine (expect all five extensions
   available: `bonsai`, `decode_fast`, `glm_moe_dsa`, `minimax_m3`, `qwen35_prefill`).
2. Whether `sampling.max_context_window_policy` in `settings.json` and the per-model
   `max_context_window` both show up as `max_model_len` in `/v1/models` (*verify*).
3. G1–G4 live behaviour (below).
4. Whether Splash 1.3.1 accepts a uniform 8-bit checkpoint (docs only promise affine
   4-bit/g64 and mixed-bit).

## Versions

| Component | Version | Source |
| --- | --- | --- |
| oMLX | `0.7.1rc1`, commit `7a5a3d75` | `git describe --tags` |
| mlx | `==0.32.4` (pinned) | `pyproject.toml` dependencies, also `[build-system]` |
| mlx-lm | git `94cdcae13b266c337bcaca09b97b9c5a9c0e2cde` (reports `0.31.4.devN`, has the 0.32.0 features) | `pyproject.toml` |
| mlx-vlm | git `9790231827a890eade1a626643a6bc94a1317c72` (v0.7.8) | `pyproject.toml` |
| mlx-embeddings | git `32981fa4e8064ed664b52071789dd18271fe4206` | `pyproject.toml` |
| mlx-audio | git `94c7716212b2228f178d2f9c7619a591fd1b0b78` (v0.5.7), base install only | `pyproject.toml` |
| transformers | `>=5.14.0,<5.18` | `pyproject.toml` |
| nanobind (kernel build) | `==3.1.0`, must match MLX's ABI | `pyproject.toml` `[build-system]` |
| Python | CPython 3.12.14 (uv-managed) | `uv venv --python 3.12 .venv` |
| uv | 0.12.19 | |
| macOS | 27.2, build 26B5101f | `sw_vers` |
| Xcode | 27.1, build 27A9275 (default `xcode-select`, not changed) | `xcodebuild -version` |
| Metal toolchain | component build 27A266a, `Apple metal version 32023.921 (metalfe-32023.921.6)` | `xcodebuild -showComponent MetalToolchain` |
| macOS SDK | 27.0, which is >= 26.2, so `setup.py` also builds the NAX (M5 tensor-op) Qwen3.5 libraries | `setup.py:51-66` |

Fill in the installed (resolved) versions with resume step 4.

Optional extras were **not** installed: `[grammar]` (xgrammar, about 2 GB with torch),
`[audio]`, `[mcp]`, `[cluster]`, `[modelscope]`, `[paroquant]`, `[bundle]`, `[dev]`.
None is needed for this benchmark. Without `[grammar]`, `reasoning_parser`-based
constrained decoding is unavailable; nothing in G1–G5 or M1–M7 needs it.

## Isolation

Base path: `~/Developer/mlsys/serving/omlx_0.7/.bench-home` (git-excluded through
`.git/info/exclude`).

- **Mechanism.** `omlx serve --base-path` (`omlx/cli.py:1359-1362`) feeds
  `init_settings(base_path=args.base_path, ...)` (`omlx/cli.py:202`). Without the flag,
  `resolve_default_base_path()` uses `OMLX_BASE_PATH`, then the macOS app's bootstrap file
  `~/Library/Application Support/oMLX/base-path`, then `~/.omlx` (`omlx/settings.py:44-71`).
- **Set both the env var and the flag.** The cluster code ignores `--base-path` and
  reads only `OMLX_BASE_PATH`, falling back to `~/.omlx`
  (`omlx/cluster/registry.py:207-213`, `omlx/cluster/discovery.py:807`). Exporting
  `OMLX_BASE_PATH` keeps every code path inside `.bench-home`.
- **No reads, migrations or writes of `~/.omlx` with a custom base path** (source audit):
  - settings come only from `<base>/settings.json` (`omlx/settings.py:1098-1108`);
  - the only "migration" is `_migrate_saved_network_auth`, which reads
    `settings.base_path / "settings.json"` (`omlx/cli.py:87-97`); the settings-version
    "migrating..." message only logs (`omlx/settings.py:1132-1138`);
  - `ensure_directories()` creates only the base path, its SSD cache dir, its log dir and
    the model dirs (`omlx/settings.py:1605-1640`);
  - per-model settings, profiles and templates live in `<base>/model_settings.json`,
    `<base>/model_profiles.json`, `<base>/global_templates.json`
    (`omlx/model_settings.py:597-606`, created from `omlx/server.py:2397-2401`);
  - the remaining literal `~/.omlx` references are fallbacks used only when no base path
    is set (`omlx/server.py:571`, `omlx/server.py:2399`) and the experimental cluster
    feature's defaults (`omlx/cluster/*.py`), which this benchmark does not enable.
  - *verify* at runtime: `ls -la ~/.omlx` metadata (mtime only, read nothing) before and
    after a run. Not done yet, because no server was started.
- **Port.** `OMLX_HOST` / `OMLX_PORT` are applied in `_apply_env_overrides`
  (`omlx/settings.py:1201-1209`) and are never persisted: `save_cli_overrides` writes only
  explicit CLI flags, "without freezing env state" (`omlx/settings.py:1595-1602`).
- **`--port` does write back.** `port` (and also `host`, `model_dir`,
  `max_concurrent_requests`, `paged_ssd_cache_dir`, `paged_ssd_cache_max_size`,
  `hot_cache_max_size`, `--no-cache`, `--hf-cache` and others) is in `persisted_fields`
  (`omlx/cli.py:47-85`). Any of them triggers `settings.save_cli_overrides(args)` →
  `<base>/settings.json` (`omlx/cli.py:287-293`). Inside the isolated base path this is
  harmless but sticky, so this plan uses env vars or an explicit `settings.json` instead
  of those flags. `--base-path`, `--api-key` and `--headless` are not persisted.
- **HF cache auto-discovery is on by default.** `huggingface.hf_cache_enabled = True`
  (`omlx/settings.py:715`) adds `$HF_HUB_CACHE`, or `$HF_HOME/hub`, to the model dirs
  (`omlx/settings.py:1490-1497`, `omlx/settings.py:1518-1521`). That would list every
  cached repo. Set `OMLX_HF_CACHE_ENABLED=false` (`omlx/settings.py:1310`, not persisted)
  so that only `hf-bench` is scanned.

## Model directory

```
~/Developer/mlsys/models/hf-bench/
└── models--mlx-community--Qwen3.8-27B-8bit -> ~/Developer/ml_source/huggingface/hub/models--mlx-community--Qwen3.8-27B-8bit
```

This matches `~/Developer/mlsys/models/hf`: the link name is the cache dir name and the
target is the absolute cache-entry path. `models/hf` was only listed, never modified.

How oMLX resolves it: a subdir that is not itself a model dir is tried as an HF cache entry
(`omlx/model_discovery.py:1895-1905`). `models--Org--Name` is decoded to the model id
`mlx-community--Qwen3.8-27B-8bit` and the repo id `mlx-community/Qwen3.8-27B-8bit`
(`omlx/model_discovery.py:1453-1468`). The snapshot comes from `refs/main` →
`snapshots/<hash>`, falling back to the newest snapshot (`omlx/model_discovery.py:1471-1505`).
Here `refs/main` = `815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9`.

Checkpoint facts (read from `config.json` and `model.safetensors.index.json`, no shard I/O):
`Qwen3_5ForConditionalGeneration`, `model_type: qwen3_5`, 64 layers, full attention every
4th layer (16 layers), 4 KV heads × head_dim 256, `max_position_embeddings: 262144`,
affine 8-bit g64, 29.5 GB of weights, 333 `vision_tower.*` tensors, and **zero `mtp.*`
tensors** even though `text_config.mtp_num_hidden_layers: 1`.

KV arithmetic (bf16): 2 × 16 layers × 4 heads × 256 × 2 B = 64 KiB per token, so
262144 tokens = 16 GiB and 131072 = 8 GiB. The GDN recurrent state is
48 layers × 48 heads × 128 × 128 × 4 B (fp32) ≈ 151 MB per sequence, plus about 3 MB of
conv state, independent of length.

## Launch commands

Common environment (zsh or bash):

```bash
cd ~/Developer/mlsys/serving/omlx_0.7
export OMLX_BASE_PATH="$PWD/.bench-home"
export OMLX_HOST=127.0.0.1 OMLX_PORT=8703
export OMLX_MODEL_DIR="$HOME/Developer/mlsys/models/hf-bench"
export OMLX_HF_CACHE_ENABLED=false
```

Model id on the API: `mlx-community--Qwen3.8-27B-8bit`. Follow the GPU-lock protocol in
`METHODOLOGY.md` before every timed segment.

### 1. Context 131072 and cache settings (once, before the first launch)

The default context limit is the model's native length, **262144**: per-model override >
model-config native length (optionally clamped by `sampling.max_context_window_policy`) >
the `sampling.max_context_window` fallback of 32768 (`omlx/server.py:2164-2212`,
`omlx/settings.py:782-793`). The limit rejects prompts that are too long
(`omlx/model_settings.py:194`). The KV cache is paged and grows on demand
(`initial_cache_blocks: 256`, `omlx/settings.py:398`), so the 16 GiB figure is reached only
by a 256K-token prompt.

To pin 131072, use either of the following:

- **Per model (preferred).** `max_context_window: 131072` in `<base>/model_settings.json`.
  The file has the shape `{"version": 1, "models": {"<model_id>": {...}}}`
  (`omlx/model_settings.py:33`, `omlx/model_settings.py:627-650`). With the server
  running, use the admin API instead of editing the file:
  `PUT /admin/api/models/mlx-community--Qwen3.8-27B-8bit/settings` with
  `{"max_context_window": 131072}` (`docs/admin-api.md:55`).
- **Global cap.** `"sampling": {"max_context_window_policy": 131072}` in
  `<base>/settings.json` (`omlx/settings.py:793`, `omlx/settings.py:816-817`).

SSD cache: keep it inside the base path with a fixed size. The default dir is
`<base>/cache` (`ssd_cache_dir: None`, `omlx/settings.py:387`, `omlx/settings.py:452`), and
the default size `auto` is 50 % of free disk (`README.md:367`). Write
`"cache": {"ssd_cache_max_size": "40GB", "hot_cache_max_size": "0"}` into
`<base>/settings.json` (keys from `omlx/settings.py:385-389`), or pass
`--paged-ssd-cache-max-size 40GB` once (it is persisted to `<base>/settings.json`).
Hot-tier size `hot_cache_max_size`: default `"0"` = disabled (`omlx/settings.py:389`).

Admin API auth: the admin API takes the main API key as a Bearer token. With no key, it
needs `skip_api_key_verification` on a loopback-only bind (`docs/admin-api.md:5-18`).
`--api-key` is **not** persisted (`save_cli_overrides` passes `include_api_key=False`,
`omlx/settings.py:1601`). For a scripted setup, either export `OMLX_API_KEY=<local-only key>`
in the common environment block (`omlx/settings.py:1300`) and send it as the Bearer
token, or write `"auth": {"api_key": "..."}` into `<base>/settings.json` while the server
is stopped. Keep the key in `.bench-home` or `.env`, never in the experiment repo. Editing
the JSON files while the server is stopped also works for every setting.

### 2. Spec off (target only)

```bash
.venv/bin/omlx serve --base-path "$OMLX_BASE_PATH" --headless \
  2>&1 | tee ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/omlx-serve-specoff.log
```

`mtp_enabled` and `dflash_enabled` default to `false` (`omlx/model_settings.py:421`,
`omlx/model_settings.py:435`), and `external_engine` defaults to `None`, meaning in-process
(`omlx/model_settings.py:469`). Spec off is therefore the default.

### 3. Spec on

Not runnable now. Every oMLX method needs files that are not on disk (next section). Once
the files exist, switch per run through per-model settings, then unload and reload the
model (`POST /admin/api/models/<id>/unload`, then `.../load`, `docs/admin-api.md:53`):

| Variant | Per-model settings (`PUT /admin/api/models/<id>/settings`) |
| --- | --- |
| Lightning MTP | `{"mtp_enabled": true, "dflash_enabled": false}`; optional `mtp_adaptive_max_depth` / `mtp_fixed_depth` (`omlx/model_settings.py:431-444`) |
| DFlash (in-process) | `{"dflash_enabled": true, "mtp_enabled": false, "dflash_draft_model": "<local path to the Qwen3.8-27B DFlash draft>"}`; `dflash_verify_mode` defaults to `adaptive` (`omlx/model_settings.py:269-288`, `omlx/model_settings.py:421-429`) |
| Splash external engine | `{"external_engine": "splash"}` after the Splash setup in `docs/Splash.md:7-19` |
| Back to off | `{"mtp_enabled": false, "dflash_enabled": false, "external_engine": null}` |

MTP and DFlash are mutually exclusive (`omlx/model_settings.py:289-294`).

## Speculative decoding requirements

| Method | Needs | Available locally? |
| --- | --- | --- |
| **Lightning MTP** (`mtp_enabled`) | MTP head weights in the target checkpoint. oMLX attaches the MTP module only if `mtp.*` (or nextn) tensors exist; it reads the safetensors index and skips the module otherwise (`omlx/utils/model_loading.py:1318-1341`, `omlx/patches/mlx_vlm_mtp/qwen35_vlm_runtime.py:286-305`). Compatible types: `qwen3_5*`, `qwen3_6*`, `deepseek_v4*` (`omlx/model_settings.py:289-294`). | **No.** `mlx-community/Qwen3.8-27B-8bit` has 0 `mtp.*` tensors. Options: a checkpoint that keeps MTP (an oQ conversion from the BF16 source keeps it when the source has it, `omlx/oq.py:2031`, `omlx/oq.py:3475-3477`; the BF16 repo is not downloaded), or the admin `import-mtplx` route (`docs/admin-api.md:14`), which presumably fetches MTPLX weights; *verify* its source and size. |
| **DFlash** (`dflash_enabled`) | A DFlash draft checkpoint (`dflash_draft_model`; `None` means a draft bundled in the target's `dflash/` dir, which this checkpoint lacks, `omlx/model_settings.py:275-277`). Runs inside the batched engine on the Lightning MTP verify path (`omlx/model_settings.py:269-274`). | **No.** No `*DFlash*` repo in `$HF_HOME/hub`. Candidates: `z-lab/Qwen3.8-27B-DFlash2` / `incoai/Qwen3.8-27B-DFlash2` (named in `docs/Splash.md:15`). Size and whether the in-process path accepts the DFlash2 format: *verify*. |
| **Splash** (external engine) | The `splash` launcher, version >= 1.3.0 (`brew install incoai/tap/splash`), plus a DFlash2 draft in a model dir, plus an affine 4-bit/g64 checkpoint (1.3.0) or a mixed-bit one (1.3.1) (`docs/Splash.md:7-26`). It runs offline against a private cache under `<base>/splash/hub` (`docs/Splash.md:30`, `omlx/engine_pool.py:2070-2079`). On first start it hashes the model files once. Note that Splash also writes outside the base path, to `~/Library/Application Support/Splash/models/omlx/` (`docs/Splash.md:32`). | **No.** `splash` is not installed, and no DFlash2 draft is cached. The 8-bit row is probably unsupported; the 4-bit row (`mlx-community/Qwen3.8-27B-4bit`) would fit once it is downloaded. |

Before a spec-on run, check the server log for a line saying that MTP or DFlash is active;
a missing head degrades silently to target-only decoding.

## Research notes (other questions)

- **Concurrency / batching.** `--max-concurrent-requests`, default 8 (`omlx/cli.py:1233-1238`),
  env `OMLX_MAX_CONCURRENT_REQUESTS` or `OMLX_MAX_NUM_SEQS` (`omlx/settings.py:1242-1251`).
  Continuous batching runs through mlx-lm's `BatchGenerator` behind an FCFS scheduler
  (`README.md:189-191`, `README.md:390-391`). Lightning MTP batches only rows whose cache
  positions are aligned; unaligned rows fall back to normal decoding
  (`omlx/model_settings.py:289-294`). That matters for M5.
- **Prefix cache for hybrid GDN.** The paged KV cache with prefix sharing is used by
  default (`cache.enabled = True`, `omlx/settings.py:385`). GDN layers cannot be
  re-derived from KV blocks, so oMLX stores GDN state snapshots. The policy
  `gdn_ssd_split_enabled = None` ("auto") keeps them in an SSD sidecar when the SSD cache
  is on, otherwise embedded with the main cache (`omlx/settings.py:399-416`);
  `gdn_sidecar_state_dtype = "fp32"`, and `gdn_ssd_pending_max_size = "512MB"`
  (`omlx/settings.py:403-404`). The SSD budget counts the GDN sidecars (`README.md:367`).
  *verify* in M4 that a prefix ending mid-history is reused (snapshot granularity).
- **Cached tokens in `usage`.** Yes. `usage.prompt_tokens_details.cached_tokens` is
  filled (`omlx/server.py:4529-4531`, also `omlx/server.py:5190`, `omlx/server.py:5905`,
  `omlx/server.py:6845`; model in `omlx/api/openai_models.py:435-455`). Anthropic usage
  maps it to `cache_read_input_tokens` (`omlx/api/anthropic_utils.py:1058`,
  `omlx/api/anthropic_utils.py:1257`). Streaming usage needs
  `stream_options.include_usage` (`README.md:265`).
- **`chat_template_kwargs` / `reasoning_effort`.** Top-level `reasoning_effort` is merged
  with `merged.setdefault("reasoning_effort", ...)`, so an explicit
  `chat_template_kwargs.reasoning_effort` wins (`omlx/api/utils.py:92-100`, called at
  `omlx/server.py:4562-4570`). Per-model `chat_template_kwargs` and `forced_ct_kwargs` are
  merged on top (`omlx/model_settings.py:204-205`). If the template raises on a value,
  oMLX retries once with an alias (`none`/`off`/`minimal` → `low`, `medium` → `high`,
  `high` → `xhigh`, `xhigh` → `max`), then renders without `reasoning_effort` (the
  template's default) (`omlx/reasoning_effort.py:25-36`, `omlx/reasoning_effort.py:81-140`).
  So Hermes-style `"none"` + thinking on is remapped to `low`, and `medium` passes as is.
  With `enable_thinking=false`, whether the template validates the effort at all:
  *verify*.
- **Tool-call parser.** The Qwen3.5 family uses the XML `<function=…><parameter=…>` format
  (`README.md:287`), parsed by the `qwen3_coder` parser (`omlx/api/tool_calling.py:10`,
  `omlx/api/tool_calling.py:484`). **Streaming:** visible text streams incrementally and
  tool markup is suppressed, but the structured `tool_calls` are emitted **after the turn
  completes** (`README.md:296`). G1 therefore sees one late `tool_calls` delta. For a
  tool-only reply, the first-token time in the methodology's TTFT definition equals the
  end of generation, so the harness should log both.
- **Anthropic `/v1/messages`.** The `thinking.type` field accepts `enabled`, `disabled` and
  `adaptive` (`omlx/api/anthropic_models.py:213`). Image blocks accept base64 or URL
  sources (`omlx/api/anthropic_models.py:30-34`, `omlx/api/anthropic_models.py:125`).
  `tool_use` is supported, with Splash and in-process engines alike (`docs/Splash.md:34`).
  Streaming `tool_use` shape: *verify*.
- **VLM path.** mlx-vlm is a hard dependency (git pin in `pyproject.toml`), not an extra.
  A model is a VLM when its config has a non-empty `vision_config`
  (`omlx/model_discovery.py:650-668`). This checkpoint has one, plus `vision_tower`
  weights, and `README.md:176` lists Qwen3.8 as a VLM with images and video. Image
  limits: `--max-image-side-length`, default 2048, downscaled
  (`omlx/cli.py:1223-1229`); `--max-image-upload-size`, default 50MB.
- **Per-model settings that persist.** All persist in `<base>/model_settings.json`
  (`omlx/model_settings.py:604`), including profiles (`<base>/model_profiles.json`). Set
  them non-interactively with `PUT /admin/api/models/{id}/settings`
  (`docs/admin-api.md:55`), or by editing the file while the server is stopped. Global
  settings: `POST /admin/api/global-settings` with flat fields (`docs/admin-api.md:32`), or
  `<base>/settings.json`.

## Gate expectations (G1–G5)

| Gate | Expectation | Evidence / what to check |
| --- | --- | --- |
| G1 OpenAI streaming + Qwen3.5 XML tool calls | **expected pass** | `qwen3_coder` parser, markup suppressed (`README.md:287`, `README.md:296`). Calls arrive as a late, single delta. Check that argument types are JSON-parseable (`omlx/api/tool_calling.py:336`). |
| G2 image input | **expected pass** | VLM detection (`omlx/model_discovery.py:650-668`), vision tower present, mlx-vlm installed. The code-reading answer still has to be shown live. |
| G3 Anthropic `/v1/messages` | **expected pass** (unknown–verify: streaming `tool_use`) | `adaptive` thinking type (`omlx/api/anthropic_models.py:213`), image blocks (`omlx/api/anthropic_models.py:30-34`). |
| G4 thinking control | **expected pass** (unknown–verify: `none` with thinking off) | `enable_thinking` passes through `chat_template_kwargs`; `reasoning_effort` setdefault merge plus alias fallback (`omlx/api/utils.py:92-100`, `omlx/reasoning_effort.py:81-140`). Reasoning is split out by `ThinkingParser`, which separates `<think>…</think>` and also handles a missing opening tag (`omlx/api/thinking.py:3-28`, `omlx/api/thinking.py:235`). Whether it lands in `reasoning_content` or stays inline: *verify* in the first response. |
| G5 context >= 64K | **expected pass** | Native 262144, so the 131072 cap is set via per-model `max_context_window`. 29.5 GB of weights + 8 GiB of KV at 128K + about 0.15 GB of GDN state fits in 128 GB. Default memory limit is RAM − 8 GB (`README.md:205`). |

## Caveats

- The Metal toolchain is a cryptex that is mounted lazily. The first
  `xcrun -sdk macosx metal --version` in this session failed with "missing Metal
  Toolchain". After `xcodebuild -showComponent MetalToolchain` (status: installed,
  27A266a) it worked. Run that command before the kernel build. Do not download a new
  component.
- Sibling sessions were running `uv pip install` at the same time (`serving/mlx-lm`, a
  vLLM wheel) and shared the network (about 1.3 MB/s of background traffic measured on
  `en0`). Measured download sizes are therefore approximate.
- Without the kernels, Qwen3.5-family prefill silently uses slower generic paths
  (`README.md:85-99`). Record `native_kernel_status()` with every result.
- `qwen35_oq_a8_enabled` (INT8-activation prefill, M5-only) is an opt-in per-model setting
  that changes numerics (`omlx/model_settings.py:249-258`). Keep it off for comparability
  unless it is benchmarked as a separate row.
- `--port` and most other CLI flags are persisted into `<base>/settings.json`
  (`omlx/cli.py:47-85`, `omlx/cli.py:287-293`). Use the env vars from this file.
- The 8-bit checkpoint declares `mtp_num_hidden_layers: 1` but ships no MTP weights. A
  spec-on run with `mtp_enabled` on this checkpoint would measure target-only decoding.

## Smoke test, 2026-10-18 01:16 (4-bit, manual, not timed)

`scripts/omlx_configure.sh` set `max_context_window: 131072` for both models.
`scripts/serve.sh omlx spec-off 4bit` started the server, which lists both models (`mlx-community--Qwen3.8-27B-4bit` and `-8bit`, `max_model_len` 131072). It loads a model on the first request.

These are first-request timings, not benchmark numbers.

| Probe | Result |
| --- | --- |
| Streaming text | OK. The first request includes the model load (TTFT 17.4 s). |
| Streaming tool call | OK: `get_weather {"city": "Paris", "unit": "c"}`. The call arrives as one delta at the end (TTFT = end-to-end = 1.81 s). |
| Image 1280×1024, random code | OK. Answered `VERIFY: WK3-DEG`; 1308 prompt tokens; TTFT 2.69 s. |
| Thinking on | Reasoning returned. |
| `/v1/messages`, no thinking field | HTTP 200; the response starts with a `thinking` block. |

**To check in the formal run.** The agent-benchmark session reports that oMLX 0.7 applies sampling defaults from `generation_config` (e.g. `top_k 20`). Verify that request-level `temperature=0` is honoured.

## Determinism and thinking checks, 2026-10-18 02:02 (short check, not timed)

**Greedy decoding is honoured.** The same prompt was sent three times (`temperature: 0`,
`enable_thinking: false`, 96 tokens) and produced byte-identical outputs (sha256
`dc80a6df…`). The `generation_config` defaults that oMLX 0.7 applies (e.g. `top_k 20`) do not
override a request-level `temperature: 0`.

**Thinking cannot be disabled with `reasoning_effort` alone.** A top-level
`reasoning_effort: "none"` sent without `chat_template_kwargs.enable_thinking` does **not**
disable thinking (seen in the quick gate run). Hermes-style requests send both fields and
behave correctly.

## HOME isolation (2026-10-18 02:25)

On every server start, oMLX 0.7.1rc1 writes into the real home directory, whatever
`OMLX_BASE_PATH` is set to:
- **Cluster shim.** It writes `~/.omlx/bin/omlx-cluster-python`
  (`omlx/cluster/worker_shim.py`, called unconditionally from `server.py:520`).
- **Launch reaper.** It reaps orphaned distributed launches from `~/.omlx/cluster/runtime`
  (`cluster/launch.py:895`).

`~/.omlx` belongs to the agent-benchmark session, so `scripts/serve.sh` now starts our
oMLX with `HOME=<base>/home`. Every other path it passes is absolute, and `HF_HOME` is
explicit.

**Earlier starts wrote to the shared home.** Before this change, our smoke run (01:16)
and quick validation (02:02) each rewrote that shim to point at our venv. The other
session's oMLX restored its own version at 02:17, and the file has not been touched by us
since.

**Bonjour is off.** Bonjour and peer discovery only start when distributed inference is
enabled in settings. It is off in `.bench-home`.
