# vLLM-Metal v0.31.0 — environment and launch notes

Recorded 2026-10-17. No model was loaded and no server was started while preparing this
file. Every claim below cites the source (`file:line`) or `--help`; items marked
**verify** still need a live run.

- Machine: MacBook Pro M5 Max (40-core GPU, 128 GB). macOS 27.2, build 26B5101f.
  Xcode 27.1 (27A9275) is the default; `xcode-select` was not changed.
- Source: `~/Developer/mlsys/serving/vllm-metal`, tag `v0.31.0`, commit `e7a0c90b`.
  It is a reference checkout only. The venv runs the **release wheel**, not an editable install.
- Model: `mlx-community/Qwen3.8-27B-8bit`, HF cache snapshot
  `815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9`. `Qwen3_5ForConditionalGeneration`,
  `model_type=qwen3_5`, MLX affine 8-bit g64, 29.5 GB.
  - Tensors: 2180 in total, 333 of them under `vision_tower.*`.
  - **No MTP tensors**, although `text_config.mtp_num_hidden_layers=1`.
  - 64 layers: 48 GDN `linear_attention` + 16 `full_attention` (every 4th layer).
  - Full-attention layers: 4 KV heads, head_dim 256. `max_position_embeddings=262144`.

Source paths below are short forms:
- `vllm/...` is the vLLM 0.31.0 wheel, i.e. `.venv/lib/python3.12/site-packages/vllm/...`.
- `vllm_metal/...` and `docs/...` are in the source checkout.

## 1. Install (replicates `install.sh`'s release path; install.sh was not run)

`install.sh` (release path) does three things:
1. `uv venv ~/.venv-vllm-metal --python 3.12 --seed` (`scripts/lib.sh` `ensure_venv`).
2. `uv pip install` the vLLM CPU wheel for the tag in `.github/vllm-release-tag.commit`
   (`v0.31.0`; `install.sh` `install_vllm`).
3. `uv pip install` the vllm-metal wheel attached to the GitHub release
   (`download_and_install_wheel`).

The same steps, but into `serving/vllm-metal/.venv`:

```bash
cd ~/Developer/mlsys/serving/vllm-metal
uv venv --python 3.12 --seed .venv          # CPython 3.12.14 (already local, no download)
W=<scratch dir>                             # wheels fetched with curl, sha256 checked against the GitHub API digest
curl -fsSL -o "$W/vllm-0.31.0+cpu-cp312-cp312-macosx_11_0_arm64.whl" \
  "https://github.com/vllm-project/vllm/releases/download/v0.31.0/vllm-0.31.0%2Bcpu-cp312-cp312-macosx_11_0_arm64.whl"
curl -fsSL -o "$W/vllm_metal-0.31.0-cp312-cp312-macosx_15_0_arm64.whl" \
  "https://github.com/vllm-project/vllm-metal/releases/download/v0.31.0/vllm_metal-0.31.0-cp312-cp312-macosx_15_0_arm64.whl"
uv pip install --python .venv/bin/python "$W/vllm-0.31.0+cpu-cp312-cp312-macosx_11_0_arm64.whl"     # step 1: core
uv pip install --python .venv/bin/python "$W/vllm_metal-0.31.0-cp312-cp312-macosx_15_0_arm64.whl"   # step 2: plugin
```

| Artifact | Size | sha256 (matches the GitHub release digest) |
| --- | --- | --- |
| `vllm-0.31.0+cpu-cp312-cp312-macosx_11_0_arm64.whl` | 29.5 MB | `21378516a51ff15029f71168e827b94660e21b39484eb52277166f01ac7dd686` |
| `vllm_metal-0.31.0-cp312-cp312-macosx_15_0_arm64.whl` | 4.3 MB | `e2ab31296f8c42d8b65c8d5f5490f160087d1070178444870a5672e44aaacf6e` |

Pins:
- vLLM: `torch==2.13.0` on Darwin, `transformers>=5.10.4,<5.18.0`, `xgrammar==0.2.7`,
  `outlines_core==0.2.14`, `anthropic>=0.71.0` (wheel `METADATA`).
- vllm-metal: `mlx==0.32.1` exact (ABI pin, `pyproject.toml:31`), `mlx-lm` at git SHA
  `9e6acca6`, `mlx-vlm>=0.6.8,<0.7.0`, `nanobind==2.10.2`, `fastapi[standard]<0.137`.
- No extras were installed (`gguf`, `stt` and `dev` were skipped).

Installed versions (`uv pip list`, verified 23:33):

| Package | Version |
| --- | --- |
| vllm | 0.31.0+cpu |
| vllm-metal | 0.31.0 |
| mlx / mlx-metal | 0.32.1 |
| mlx-lm | 0.32.0 (git `9e6acca6`) |
| mlx-vlm | 0.6.17 |
| torch | 2.13.0 |
| transformers | 5.17.0 |
| huggingface-hub | 1.33.0 |
| fastapi | 0.136.3 |
| xgrammar | 0.2.7 |

Checks:
- `vllm --version` prints `0.31.0+cpu`. The first cold run took 50 s.
- `current_platform` is `vllm_metal.platform.MetalPlatform`, so the plugin is detected.
  The plugin reports torch `device_type=cpu`; MLX does the GPU work.
- `vllm serve --help=all` is saved to `logs/vllm-metal-serve-help.txt`. It lists
  `qwen3_coder` and `qwen3_xml` among the `--tool-call-parser` choices.
  `--gpu-memory-utilization` defaults to 0.92.

Download size, about 0.3 GB in total:
- The two release wheels: 34 MB.
- Step 1 from PyPI: about 199 MiB. torch 2.13.0 was 106 MiB and llvmlite 35.5 MiB;
  transformers, pycountry, mistral-common and pillow made up most of the rest.
- Step 2: about 64 MiB (mlx-metal 59.4, mlx-vlm 2.5, mlx-audio 2.0).
- The full log is `logs/vllm-metal-install.log`.

Run the server from the venv: `source ~/Developer/mlsys/serving/vllm-metal/.venv/bin/activate`.

## 2. Launch commands (port 8705 only)

Spec off (the only runnable variant; see section 4):

```bash
source ~/Developer/mlsys/serving/vllm-metal/.venv/bin/activate
HF_HUB_OFFLINE=1 vllm serve mlx-community/Qwen3.8-27B-8bit \
  --host 127.0.0.1 --port 8705 \
  --served-model-name qwen3.8-27b-8bit \
  --max-model-len 131072 \
  --gpu-memory-utilization 0.55 --max-num-seqs 4 \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --enable-prefix-caching \
  --enable-prompt-tokens-details \
  2>&1 | tee ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/vllm-metal-serve-8bit.log
```

- **Repo id vs path.** A cached repo id should work with `HF_HUB_OFFLINE=1`.
  `get_model_download_path` returns local paths as-is and otherwise defers to
  mlx_lm/mlx_vlm's HF download, which reads the cache when offline
  (`vllm_metal/utils.py:98-150`). The multimodal checks resolve repo ids with
  `snapshot_download(..., local_files_only=True)` (`vllm_metal/v1/model_adapter.py:55-74`).
  The snapshot is complete: 6/6 shards, index, processor and tokenizer configs.
  **verify** on the first launch. Fallback: pass the snapshot dir
  `$HF_HOME/hub/models--mlx-community--Qwen3.8-27B-8bit/snapshots/815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9`
  and keep `--served-model-name`.
- `--enable-prefix-caching` resolves to `mamba_cache_mode=align` for hybrid models
  (`vllm_metal/platform.py:664-672`).
- `--tool-call-parser qwen3_coder` and `qwen3_xml` are aliases
  (`vllm/tool_parsers/__init__.py:185-191`).
- **Images per prompt.** The default limit is 999 per modality
  (`vllm/config/multimodal.py:127-133,525-526`), so the 20-image M4 history needs no flag.
  Optionally add `--limit-mm-per-prompt '{"image": 24, "video": 0}'` to bound
  startup profiling (**verify** its effect on startup time and memory).
- Text-only A/B (if images break startup or memory): add
  `VLLM_METAL_MULTIMODAL_MODE=text-only` (`docs/configuration.md:14`, `vllm_metal/envs.py:137-145`).
- The 4-bit row uses the same command with `mlx-community/Qwen3.8-27B-4bit`, once it is downloaded.

Spec on: **not available for this model in v0.31.0** (section 4). Record vLLM-Metal's
M3 spec-on cells as "unsupported", not as measured.

## 3. Gate expectations (G1–G5)

| Gate | Expectation | Evidence |
| --- | --- | --- |
| G1 OpenAI streaming + Qwen XML tool calls | **Expected pass (verify)** | See notes below the table. |
| G2 image_url input | **Unknown – verify (likely pass)** | See notes below the table. |
| G3 Anthropic `/v1/messages` | **Expected pass for text + tool_use streaming; image: likely pass (verify); thinking caveat** | See notes below the table. |
| G4 thinking control | **Expected pass for `enable_thinking`; `reasoning_effort` is passed to the template unmapped** | See notes below the table. |
| G5 context ≥ 64K | **Expected pass (verify memory)** | See notes below the table. |

**G1 evidence.**
- Both parser names map to `Qwen3EngineToolParser` (`vllm/tool_parsers/__init__.py:185-191`).
- The engine parses `<tool_call>` / `<function=NAME>` / `<parameter=KEY>VALUE</parameter>`
  (`vllm/parser/qwen3.py:7-13,43-48`) and streams argument deltas
  (`stream_arg_deltas=True`, `qwen3.py:199`).
- It accepts `<function=` without `<tool_call>` (`qwen3.py:150`).
- `<tool_call>` implicitly ends reasoning (`qwen3.py:205-209`). Check for markup leaks
  when thinking is on.

**G2 evidence.**
- `Qwen3_5ForConditionalGeneration` / `qwen3_5` belong to the native-adapter family
  (`vllm_metal/v1/model_adapter.py:402-408`).
- In `VLLM_METAL_MULTIMODAL_MODE=auto`, a non-FP8 MLX-affine wrapper with an adapter is
  not forced onto the text backbone (`model_adapter.py:423-462`).
- The checkpoint has `vision_tower.*`, `processor_config.json` and `preprocessor_config.json`.
- The docs list only Qwen3.5 dense as 🔵 native multimodal (`docs/supported_models.md:49`);
  Qwen3.8 appears in the text table only (`:128`). It is the same code path, but
  untested at 27B.
- Spec decoding would interact with multimodal (`vllm_metal/v1/model_lifecycle.py:297`).

**G3 evidence.**
- The routes exist: `/v1/messages` and `/count_tokens` (`vllm/entrypoints/anthropic/api_router.py:52,90`).
- `vllm serve` mounts them unconditionally, next to chat/completions/responses
  (`vllm/entrypoints/generate/api_router.py:40-44`).
- `stream`, `tool_use`, `thinking` and `image` blocks are part of the protocol
  (`vllm/entrypoints/anthropic/protocol.py:36-61,161-173,248-262`).
- base64 images are converted to data-URI `image_url` (`anthropic/serving.py:261-279,446-448`).
  Images inside `tool_result` are handled too (`:500-536`).
- **Thinking caveat.** `thinking: {type: "adaptive"}` pins nothing (`serving.py:587-610`).
  No `thinking` field also pins nothing. The Qwen3.8 template then defaults to thinking
  ON at `xhigh` (`chat_template.jinja:46-47`), so Claude Code-style requests will think.
- An `output_config.effort` of `high` or `max` would hit the template's
  `raise_exception` (`chat_template.jinja:48-49`). **verify**

**G4 evidence.**
- `reasoning_effort` accepts `none|minimal|low|medium|high|xhigh|max`
  (`vllm/entrypoints/openai/chat_completion/protocol.py:245-246`).
- It is forwarded to the template as-is (`:577`).
- It sets `enable_thinking = (effort != "none")` only when the client did not send
  `enable_thinking` (`:585-586`).
- The Qwen3.8 template checks the effort only when thinking is on, and raises on
  anything other than `xhigh` / `medium` / `low` (`chat_template.jinja:46-49`). So:
  - Hermes `medium` + `true`: fine.
  - `none` + `false`: fine.
  - `high` / `minimal` / `max` with thinking on: request error, with no mapping. **verify** the HTTP code.
- Reasoning is returned in the field **`reasoning`** (`protocol.py:72`), not
  `reasoning_content`; the harness must accept both.

**G5 evidence.**
- `max_position_embeddings=262144`.
- KV for the 16 full-attention layers is 2 × 16 × 4 × 256 × 2 B = 64 KiB/token, so
  131072 tokens ≈ 8 GiB per sequence.
- GDN state ≈ 144 MiB per sequence (48 layers × 48 × 128 × 128 × fp32).
- Weights are 29.5 GB, which fits in 128 GB.
- Budget: `--gpu-memory-utilization` (`docs/configuration.md:61-63`); a KV commit
  probe runs at startup (release notes, `VLLM_METAL_KV_COMMIT_PROBE`).

## 4. Speculative decoding

- **Methods on Metal**
  - `mtp`: Gemma4 targets only.
  - `draft_model` and `ngram`: non-hybrid paged-attention targets only.
  - DFlash and DSpark: experimental, single-device Qwen3 text target, plus trained drafter weights.
  - Sources: `docs/speculative_decoding.md:7-22`, `docs/dflash.md:26`.
- **Hybrid targets are excluded.** "Hybrid GDN targets and heterogeneous draft
  vocabularies are not supported." (`docs/speculative_decoding.md:32`). Qwen3.8 is a
  hybrid GDN target.
- **It would cost prefix caching.** Any `--speculative-config` on a hybrid model
  disables prefix caching (`vllm_metal/platform.py:691-700`), which would cost M1/M4.
- **MTP.** The mlx-community checkpoint has no `mtp.*` tensors. MTP would need a
  checkpoint that keeps them, e.g. the 55.6 GB BF16 `Qwen/Qwen3.8-27B`. The Metal MTP
  path is Gemma4-only anyway.
- **Bottom line.** Nothing runs with local files only. Spec-on for vLLM-Metal is
  N/A in v0.31.0.

## 5. Memory, scheduler and Metal knobs

- **KV budget.** `--gpu-memory-utilization` sets the fraction; `VLLM_METAL_MEMORY_FRACTION`
  was removed (`docs/configuration.md:61-63`).
- **KV pool commit.** The pool is committed lazily, except for Mamba/GDN state, which
  keeps its zero fill (`docs/configuration.md:70-78`).
  - The release notes say the same: lazy commit applies "except for hybrid, MLA, and
    draft-model setups".
  - **Qwen3.8 is hybrid, so expect the whole KV budget to be resident from startup.**
    Set `--gpu-memory-utilization` explicitly; do not rely on the default.
  - A sensible start is about 0.55, roughly 70 GB: 29.5 GB of weights plus about 35 GB
    of cache. Record the KV capacity from the log and the RSS for M6.
  - `VLLM_METAL_KV_COMMIT_PROBE=1` is the default; it shrinks the pool or fails startup
    if macOS would swap.
- **Scheduler.** `--max-num-seqs` and `--max-num-batched-tokens` are standard vLLM flags.
  Record the resolved values from the startup log. M5 needs at most 3 concurrent
  requests, so `--max-num-seqs 4` is enough.
- **M5 NAX prefill** is automatic. `VLLM_METAL_DISABLE_NAX=1` forces the fallback
  (`docs/configuration.md:10`). Whether NAX covers head_dim 256 here: **verify** in the
  startup log.
- **Other knobs, all at their defaults.**
  - `VLLM_METAL_GDN_LAZY_KERNELS=1` (`docs/configuration.md:18`)
  - `VLLM_METAL_DECODE_PIPELINE=1` (greedy, `:19`)
  - `VLLM_METAL_DISABLE_GQA_DECODE=0` (`:11`)
  - `VLLM_METAL_COMPILED_MLP=0` (opt-in, `:20`)
- **Full env-var list:** `vllm_metal/envs.py:113-160`.

## 6. Caveats

- Hybrid GDN prefix caching is 🔵 experimental. Cache-on vs cache-off parity still
  diverges on some divergent-suffix prompts (v0.31.0 release notes, "Known Boundaries").
  Check M4 outputs as well as timings.
- Whether `usage.prompt_tokens_details.cached_tokens` is populated with
  `--enable-prompt-tokens-details` (`vllm/entrypoints/launchers/cli_args.py:145`) for
  hybrid align-mode hits: **verify**. Hits are block-aligned.
- vLLM cannot start without loading the model, so nothing here was exercised live.
- On import, objc warns that `AVFFrameReceiver` and `AVFAudioReceiver` are defined twice:
  in Homebrew ffmpeg 9.0.2's `libavdevice` and in the copy bundled with `cv2`
  (opencv-python-headless). It is harmless for image-only serving so far. If video or
  audio code paths crash, this is the first suspect.
- `torch` warns "Triton not available". This is expected on macOS.
- The Homebrew formula in this tag still pins v0.30.0 (`Formula/vllm-metal.rb:7-10`).
  The release wheel was used instead.
- Provenance for each raw record: `vllm --version`, `pip show vllm-metal mlx`, `sw_vers`
  build, `xcodebuild -version`.

## 7. Status / remaining work (as of 2026-10-17 23:30)

**Install state**
- Venv `~/Developer/mlsys/serving/vllm-metal/.venv` exists (CPython 3.12.14, arm64, `--seed`).
- Both wheels are sha256-verified. Durable copies are in
  `~/Developer/mlsys/serving/vllm-metal/.venv/wheels/`; `.venv` is gitignored.
- Install log: `logs/vllm-metal-install.log` in this repo.
- **The install is complete** (exit 0, 23:32):
  - Step 1: vLLM core, 149 packages.
  - Step 2: plugin, 81 resolved and 12 new.
  - `vllm --version` and Metal platform detection were verified at 23:33.
- `~/.venv-vllm-metal` was **not** created. Nothing outside `serving/vllm-metal/.venv`
  was installed or modified, apart from the shared uv cache.

**Resume steps.** Both commands are idempotent and safe to rerun:

```bash
cd ~/Developer/mlsys/serving/vllm-metal
uv pip install --python .venv/bin/python .venv/wheels/vllm-0.31.0+cpu-cp312-cp312-macosx_11_0_arm64.whl
uv pip install --python .venv/bin/python .venv/wheels/vllm_metal-0.31.0-cp312-cp312-macosx_15_0_arm64.whl
source .venv/bin/activate
vllm --version
python -c "from vllm.platforms import current_platform; print(type(current_platform))"   # expect MetalPlatform
uv pip list --python .venv/bin/python | grep -iE '^(vllm|mlx|torch|transformers)'
vllm serve --help=all | grep -nE 'tool-call-parser|reasoning-parser|prompt-tokens-details|limit-mm-per-prompt|mamba-cache-mode|speculative-config|gpu-memory-utilization|max-num-seqs|max-num-batched-tokens'
```

**Verified (static, no model loaded).** All of section 3's file:line evidence:
- parser aliases
- the Anthropic routes, mounted by default
- the reasoning_effort pass-through and the template's effort check
- the multimodal adapter decision for `Qwen3_5ForConditionalGeneration`
- hybrid spec-decoding exclusion and the prefix-cache disable under spec
- checkpoint contents: no MTP tensors, vision_tower present

**Open questions (first live run, under the GPU lock, port 8705)**
1. Repo id resolves offline (else use the snapshot path).
2. Native multimodal path engaged: the startup log should not say text-only.
   Then G2's image-code readback.
3. Streamed `tool_calls` deltas and no markup leak (G1, M7).
4. `cached_tokens` populated, and its value on the M1/M4 prefix.
5. NAX engaged for head_dim 256.
6. HTTP status for `reasoning_effort` values the template rejects (`high`, `minimal`, `max`).
7. `/v1/messages` with `thinking: adaptive` / no thinking field: thinking is ON at
   `xhigh`, so record the latency impact.
8. Resolved `max_num_batched_tokens`, `max_num_seqs` and KV capacity from the startup log.
9. Memory at a 64K prompt.

## 8. Smoke test, 2026-10-18 00:28 (8-bit, manual, not timed)

**Startup failure with the checkpoint as shipped.** `vllm serve mlx-community/Qwen3.8-27B-8bit`
aborts during multimodal budget setup with `ValueError: Unrecognized image processor`. The
cause is in the checkpoint: its `processor_config.json` names
`image_processor_type: Qwen3VLImageProcessor`, and transformers 5.17 (the version vllm-metal
pins, `<5.18`) has no such class. 5.20.1 doesn't have it either. Its
`preprocessor_config.json` names the equivalent `Qwen2VLImageProcessorFast`.

**Workaround.** Serve a metadata-only view at
`~/Developer/mlsys/models/derived/Qwen3.8-27B-8bit-procfix`:
- every file is a symlink into the HF snapshot;
- `processor_config.json` is a patched copy, with `image_processor_type` set to
  `Qwen2VLImageProcessor`;
- weights and preprocessing parameters are unchanged.

Launch with `--served-model-name qwen3.8-27b-8bit`. Startup log: MLX-VLM model loaded in 2.97 s,
NAX prefill attention kernels loaded (M5 tensor units), CPU KV cache 351,031 tokens,
maximum concurrency 2.68× at 131,072 tokens per request, engine init 13.9 s.

**Manual probes.** `temperature=0`, `enable_thinking=false` unless noted; first-request
timings, not benchmark numbers.

| Probe | Result |
| --- | --- |
| Streaming text | OK, TTFT 1.15 s |
| Streaming tool call | OK: `get_weather {"city": "Paris", "unit": "c"}`, `finish_reason=tool_calls`, TTFT 0.94 s |
| Image (1280×1024, random code) | OK: read `WK3-DEG` correctly; prompt 1308 tokens, 1280 of them image (`usage.prompt_tokens_details.multimodal_tokens.image`); TTFT 2.29 s |
| Thinking on (`enable_thinking=true`, `reasoning_effort=medium`) | Reasoning returned in the `reasoning` field |
| `/v1/messages`, no `thinking` field | HTTP 200, but the response starts with a `thinking` block (template default) |

`usage.prompt_tokens_details` reports `cached_tokens` and `created_cache_tokens`.

## Measurement environment (Tier-1 results, 2026-10-18)

- **Machine.** MacBook Pro `Mac17,7`, Apple M5 Max, 128 GB. macOS 27.2 (build 26B5101f).
  Xcode 27.1 (build 27A9275) is the default `xcode-select`, and it was never changed.
- **Power.** AC through a 96 W USB-C adapter, in High Power mode (`powermode 2`). The adapter
  cannot supply this machine under sustained GPU load, so the battery drains during runs.
  The battery rule keeps it at 40 % or more at each suite start and above 20 % throughout
  (METHODOLOGY.md, "Battery"). Suites measured on a low battery were re-run.
- **Quiet machine.** As in METHODOLOGY.md. The monitor TSVs next to the results hold every
  10 s sample; v3 rows also record the battery level and the thermal pressure level.
- **Paused system daemons.** suggestd was stopped with SIGSTOP from 16:19, and
  mediaanalysisd and spotlightknowledged from 17:29:33. All three were resumed at 22:02.
  They were busy with backlogs that the user-activity heartbeat could not defer
  (METHODOLOGY.md, "Quiet machine").
- **Provenance.** Each raw file's header records the server flags, the framework version, the
  harness commit and the pre-flight output.
- **Launch** (`scripts/serve.sh vllm-metal spec-off 4bit`): `vllm serve models/derived/Qwen3.8-27B-4bit-procfix --max-model-len 131072 --gpu-memory-utilization 0.55 --max-num-seqs 4 --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 --enable-prefix-caching --enable-prompt-tokens-details`.
