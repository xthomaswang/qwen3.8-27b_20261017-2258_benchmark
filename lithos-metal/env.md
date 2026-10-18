# lithos-metal v0.1.2: environment, launch plan, gate expectations

Recorded 2026-10-17, 23:20–23:40. No model was loaded onto the GPU and no weights were
downloaded. `lithos-metal serve` was never run with a model; only `--help` was run.

- macOS 27.2, build 26B5101f. Xcode 27.1, build 27A9275 (default `xcode-select`, not changed). uv 0.12.19.
- Source: `~/Developer/mlsys/serving/lithos-metal`, tag `v0.1.2`, commit `46b2bc4`.
- Evidence is cited as `file:line` relative to that checkout. "Measured upstream" means the
  project's own [M]-tagged notes, which used a 48 GB M5 Max 40c and the NVFP4 target.

## 0. Doc map

The docs named in the brief (`docs/design/serving.md`, `models.md`,
`speculative-decoding.md`, `extensions.md`) do not exist at v0.1.2. Their equivalents
are `docs/serving.md` (serving and CLI), `docs/research/dspark.md` (speculation),
`docs/porting.md` (models, formats and drafters, i.e. extension points),
`docs/qwen-hybrid-moe.md`, `docs/installation.md`, and `docs/design/design.md`. The CLI
source is `monolith/cli.py`, `monolith/serve.py`, and `monolith/serving/*.py`.

## 1. Install (done, verified)

```bash
cd ~/Developer/mlsys/serving/lithos-metal
uv venv --python 3.12 .venv
UV_NO_PROGRESS=1 uv pip install --python .venv/bin/python '.[serve]'   # builds the Metal runtime via CMake
# log: ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/lithos-install.log
.venv/bin/lithos-metal --version        # -> lithos-metal 0.1.2
.venv/bin/lithos-metal serve --help     # exit 0 (full flag list below)
.venv/bin/lithos-metal models
```

- The result is a regular, non-editable install into `.venv/lib/python3.12/site-packages/monolith`.
  The native runtime is `monolith/runtime/_native.cpython-312-darwin.so`. **Source edits
  (for example the lm_head patch in §4) need a reinstall**, or reinstall as editable:
  `uv pip install --python .venv/bin/python -e '.[serve]'`.
- Python 3.12.14. Packages: lithos-metal 0.1.2, fastapi 0.143.3, pydantic 2.14.1
  (core 2.50.1), uvicorn 0.54.0, transformers 5.20.1, tokenizers 0.23.3, safetensors 0.8.0,
  huggingface-hub 2.2.0, jinja2 3.1.6, numpy 2.5.4. No torch.
- Size: `.venv` is 131 MB. **Network download: not measured** (progress output was off).
  Dependency resolution was served entirely from the uv cache ("Resolved 38 packages in 3ms").
  uv reported "Prepared 2 packages in 2m 03s"; one is the lithos-metal source build.
  The build-isolation wheels (`cmake`, `nanobind`, `setuptools`, `wheel`) are not among the 38.
  Their uv-cache entries, plus `transformers`, were touched during the install, so some were
  probably fetched. The PyPI `cmake` wheel alone is tens of MB. Other sessions were installing
  into the same uv cache at the same time.
- The build took about 2 min (the CMake/clang build of `runtime/`) using the default Xcode 27.1 toolchain.
- `lithos-metal models` prints (`monolith/cli.py:31-35`, `monolith/models/catalog.py:16-21`):
  ```
  nvidia/Qwen3.8-27B-NVFP4
    DSpark: LithosAI/Qwen3.8-27B-DSpark-NVFP4 (7 proposals + anchor)
  nvidia/Qwen3.6-35B-A3B-NVFP4
    DSpark: LithosAI/Qwen3.6-35B-A3B-DSpark-NVFP4 (7 proposals + anchor)
  ```
  **`mlx-community/Qwen3.8-27B-4bit` is not a catalogued target.** It gets no automatic
  DSpark head and needs an explicit `--draft`.

## 2. Serve flags (`monolith/serve.py:372-409`)

| Flag | Default | Notes / evidence |
| --- | --- | --- |
| `--model` | required | A Hub repo id or a local path (`:374`). See §4. |
| `--host` / `--port` | `127.0.0.1` / `8000` | `:394-395`. One uvicorn worker (`:427`). |
| `--max-context` | `32768` | `:391`. No upper clamp in code. Internal capacity = `max_context + (gamma-1)`, i.e. +6 with DSpark (`monolith/serving/setup.py:85`; `docs/serving.md:189-192`). The prompt + `max_tokens` check is against `--max-context` (`serve.py:106-110`). |
| `--no-draft` | off | Target-only (`:377`). Skips automatic draft selection (`:397-399`, `setup.py:70-74`). See §6. |
| `--draft` / `--drafter` | auto | Hub id or local path; mutually exclusive with `--no-draft` (`:375-377`). |
| `--draft-kind` | `dspark` | The only choice (`:378`). |
| `--draft-block-size` | `min(7, head.block_size)` | **Number of DSpark proposals**, 1..7 (`:379`, `setup.py:82-84`). Verification rows = proposals + 1 anchor. |
| verification policy | fixed | No CLI flag. Serve always uses `verify='fixed'`, `verify_length=gamma` (`setup.py:39-41`; also `monolith/generate.py:497-499`). The cost-aware rule exists only in the library and the research tools. |
| `--draft-quantization` | `auto` | auto = NVFP4 only when chip recipes match, otherwise source precision (`setup.py:96-102`). |
| `--pack`, `--draft-pack` | XDG cache | §5. |
| `--revision`, `--draft-revision`, `--download-dir`, `--local-files-only` | — | Passed to `snapshot_download` (`monolith/serving/cache.py:30-34`). |
| `--kernel-config`, `--kernel-config-key` | chip recipes | Override or pin the recipe map (`setup.py:103-110`). |
| `--served-model-name` | Hub id or dir name | Requests must send exactly this id, otherwise 404 (`serve.py:234-236`, `:421`). |
| `--prefill-chunk-size` | `128` | `:392`. Upstream measured 512 as the best for the NVFP4 27B recipe on the 40c chip (`docs/serving.md:244-245`). |
| `--no-warmup` | off | Otherwise startup compiles every recipe context ≤ max-context plus 2 short generations (`serve.py:44-62`). |

All draft options (`--draft-pack`, `--draft-revision`, `--draft-block-size`, `--kernel-config*`,
`--draft-quantization`≠auto) error out when no draft is active (`serve.py:406-408`).
API key: `LITHOS_METAL_API_KEY` (aliases `LMK_API_KEY`, `MONOLITH_API_KEY`) (`serve.py:419`).

## 3. Startup order (why `serve` downloads)

`prepare()` (`monolith/serving/setup.py:58-133`) runs these steps in order:

1. Opens the Metal device and selects the chip backend (`:59-67`).
2. Resolves the target with `snapshot_download`, which downloads if missing (`:69`).
3. Auto-selects the DSpark head by name (`:70-73`).
4. Resolves the head, which also downloads if missing (`:74`).
5. Reads `architectures[0]` and builds the draft (`:75-81`).
6. Builds the target and binds its formats (`:86`).
7. Checks draft/target compatibility (`:91-95`).
8. Builds or validates the packs (`:120-129`).
9. Runs the warmup (`serve.py:422-423`).

Downloads therefore happen before any format error can surface. Use
`HF_HUB_OFFLINE=1` plus `--local-files-only` on every launch.

## 4. Model resolution, identity, and the local 4-bit question

**Resolution** (`cache.py:19-38`):

- If the path exists, it is local. A directory, `config.json`, or a `*.safetensors` file
  are all accepted. A path that is absolute or starts with `.` or `~` but does not exist
  is a `FileNotFoundError`.
- Anything else is a Hub id, passed to `snapshot_download(..., allow_patterns=[*.json,
  *.safetensors, *.model, *.txt, *.jinja, *.tiktoken])`. It uses `$HF_HOME/hub` unless
  `--download-dir` is given.
- With `HF_HUB_OFFLINE=1` or `--local-files-only`, the local snapshot is returned
  without completeness checks. lithos then stats every shard listed in the index
  (`checkpoint_identity`, `cache.py:37,41-60`), so a partial snapshot fails fast with
  `FileNotFoundError`, which the CLI catches (`cli.py:13-18`). One example: the paused
  `LithosAI/Qwen3.8-27B-DSpark-NVFP4` snapshot in the HF cache has metadata files but
  three 0-byte `.incomplete` shards.
- The tokenizer loads with `local_files_only=True, trust_remote_code=False` and must
  ship a chat template (`serve.py:34-36`).

**Identity validation: none against a repo.**

- lithos never reads `validation.json`, `SHA256SUMS`, or `conversion.json` (grep over `monolith/`).
- No hashes are checked against Hugging Face. The model is accepted by
  `config.json:architectures[0]` through the registry (`setup.py:75-78`). Each tensor
  group's format is detected from safetensors dtypes (`monolith/formats/checkpoint.py:39-53`).
- `checkpoint_identity` (path, config/index SHA-256, shard sizes and mtimes) only keys the
  pack cache (`cache.py:111-131`).
- DSpark auto-pairing is by name: the repo id, the dir name, `_name_or_path`, or
  `models--…` parents, then architecture/hidden/layers (`catalog.py:24-47`). An explicit
  `--draft` skips the name match. It still checks taps, hidden size, and vocab (`setup.py:91-95`).

**Answer: would a locally re-quantized MLX affine 4-bit g64 checkpoint be accepted?**

**No. As shipped, v0.1.2 rejects it, and it equally rejects the official
`mlx-community/Qwen3.8-27B-4bit`.** Downloading the 16 GB official repo would not get
lithos running either.

- The MLX layout stores the untied head as `language_model.lm_head.{weight,scales,biases}`.
  The 4-bit index was fetched as metadata only. It has the same 2180-tensor layout as the
  local 8-bit and is uniform 4-bit g64 with no per-layer overrides.
- The qwen3_5 package renames only `language_model.model.*` → `model.language_model.*`
  (`monolith/models/qwen3_5/weights.py:35-41`). It then asks for `lm_head.weight`
  (`monolith/models/qwen3_5/model.py:57-60`), and `bind_formats` raises KeyError
  (`monolith/nn/pack_plan.py:53-55`). Upstream validated the MLX path only on the
  tied-embedding Qwen3.5-0.8B, which has no separate head (`weights.py:6-10`,
  `docs/research/m5max-qwen-llama-audit.md:19`).
- **Measured (no GPU):** a header-only bind of the real 8-bit checkpoint's tensor names
  gives `KeyError "checkpoint has no tensor group for 'lm_head.weight'"`. KeyError is
  not caught by `cli.py:16`, so the user sees a traceback.
- With a one-line rename (`language_model.lm_head.*` → `lm_head.*`), all 498 slab tensors
  bind. The script is in §12.
- **With that fix, a local 4-bit g64 checkpoint should pass format binding.**
  Bind-OK is not the same as pack-OK. `bind_formats` checks only names and dtypes. Packing
  additionally enforces `weight == [N, K/8]`, group 64, and `K % 256 == 0`
  (`int4_affine.py:37-41,76-77,140-141`). The 27B's K values (5120, 6144, 17408) are all
  multiples of 256, so packing should pass, but this is not yet run. The
  `int4_affine` plugin wants a U32 `weight [N, K/8]` plus BF16/F16 `scales`/`biases`, and
  it hard-requires group 64 (`monolith/formats/int4_affine.py:73-83,140-141`).
- lithos does not care whether the checkpoint came from mlx-community or was made locally.
  That holds as long as the local checkpoint keeps MLX's norm convention: the unquantized
  norm, `A_log`, `dt_bias`, and conv tensors are copied byte-for-byte from the 8-bit (MLX
  folds `1 +` into the norms and lithos subtracts it back, `weights.py:53-66`).
- **Two ways to apply the fix** (choose one; neither is applied yet):
  1. Write the local checkpoint's head as `lm_head.{weight,scales,biases}`. lithos will then
     work, but mlx-lm/mlx-vlm will not load that copy.
  2. Make a local, uncommitted one-line patch in `monolith/models/qwen3_5/weights.py:mlx_rename`
     that maps `language_model.lm_head.` → `lm_head.`, then reinstall. This is cleaner and
     keeps one checkpoint for all MLX stacks. Record it as a deviation in provenance.
- **The 8-bit (`mlx-community/Qwen3.8-27B-8bit`) cannot be served at all.** `detect_format`
  labels any U32 weight with scales and biases as `int4_affine`, with no `bits` check
  (`checkpoint.py:45-46`). The test above bound all 498 tensors of the 8-bit as int4_affine.
  Packing would then fail the shape check `weight == [N, K/8]` (`int4_affine.py:76-77`).
  There is no affine-8-bit plugin; `int8` is symmetric `weight_scale` only (`int8.py:1-3,37-43`).
- **Performance caveat for any int4 target.** The tuned M5 Max 40c serving recipes
  require an NVFP4 + FP8 target and a DSpark draft (`monolith/backends/metal/m5_max_40c/serving.py:7-9,34-36`).
  An int4 target runs on generic profile defaults: no decoder or prefill recipe, and no
  `accelerator='on'` override (`setup.py:42-55`). The draft stays in its native NVFP4
  (`--draft-quantization auto` → None). DSpark acceptance against an int4 target is unmeasured.

## 5. Weight packs and compiled kernels

- **Default root:** `${XDG_CACHE_HOME:-~/.cache}/lithos-metal/packs`. If an old
  `lmk/packs` or `monolith/packs` exists, it is reused (`cache.py:63-72`).
  `~/.cache/lithos-metal` does not exist yet.
- **Entries:** `target-<sha24>/` and `draft-<sha24>/`, each holding `weights.pack` and
  `manifest.json`. The draft goes in the same root unless `--draft-pack` is given
  (`setup.py:120-129`).
- **Cache key:** checkpoint path, config/index hashes, shard sizes and mtimes, **capacity**,
  layout, backend, role, and quantization (`cache.py:122-132`). Builds use a lock plus an
  atomic rename. A truncated or mismatched entry is an error, not a silent rebuild
  (`cache.py:75-98,133-157`; `docs/serving.md:75-87`).
- **Sizes:**

  | Pack | Size | Source |
  | --- | --- | --- |
  | int4 27B target | ≈ the text-weight bytes, about 15 GB | estimate: padding-free `block` layout ≈ 1.01× the checkpoint (CLAUDE.md, #101) |
  | NVFP4 decode pack | 22.93 GiB | `docs/serving.md:256-261` |
  | NVFP4 prefill-derived layouts | 20.02 GiB | same; "content-addressed local caches", `docs/serving.md:234-235`; on-disk location not traced (open question) |
  | DSpark draft pack | 1.16 GiB | `validation.json` `reference_pack_bytes` 1245380608 |

- **Configurable:** yes. `--pack DIR`, `--draft-pack DIR`, or `XDG_CACHE_HOME`. Any directory works,
  so both `~/Developer/mlsys/serving/lithos-metal/.cache/packs` and a folder under
  `$HF_HOME` are possible. **Recommended:** `--pack ~/Developer/mlsys/serving/lithos-metal/.cache/packs`.
  Packs are derived artifacts, not HF-format, so they do not belong in `$HF_HOME`.
- **Capacity is in the key.** DSpark-on with `--max-context 131072` gives capacity 131078;
  `--no-draft` with `--max-context 131072` gives capacity 131072, which builds a second
  ~15–23 GB target pack. To share one entry, launch `--no-draft` with `--max-context 131078`
  (as in §10). Alternatively, pass the existing `target-*` dir to `--pack`; explicit packs
  only need capacity ≥ requested (`cache.py:82-83,114-120`).
- **Compiled kernels:** MSL is compiled at runtime and kept in memory only ("Compiled
  pipelines … survive engine replacement", `docs/serving.md:135`; `serve.py:72-93`). No
  on-disk kernel cache was found. Pass the `autotune` path only in tools; serve sets
  `autotune=False` (`serve.py:87`). Startup pays compilation on every launch.

## 6. `--no-draft`

Yes, it runs target-only without downloading the DSpark head. `parse_args` leaves `args.draft`
unset (`serve.py:397-399`), and `prepare` skips `default_draft` and the draft resolve
(`setup.py:70-74`), so `gamma = 0` and capacity = max-context.

**Caveat:** with no drafter, the tuned recipes are skipped even for the NVFP4 target
(`m5_max_40c/serving.py:8-9`). "Spec off" therefore also means "generic kernels" on lithos.
`--kernel-config` cannot be combined with `--no-draft` (`serve.py:406-408`). Record this in M3.

## 7. Protocols, tool calls, thinking

- **Endpoints:** `POST /v1/chat/completions`, `/v1/responses` (stateless), `/v1/messages`,
  `/v1/messages/count_tokens`, plus `GET /v1/models` and `/health` (`serve.py:225-367`).
  **There is no Ollama API.**
- **Strict validation.** `ChatRequest` is `extra='forbid', strict=True` (`monolith/serving/protocol.py:71-72`).
  **Any unknown top-level field, including `chat_template_kwargs`, returns 400.**
  `response_format` other than text, `strict` tools, and `n>1` are rejected (`:100-117`).
- **Tool calls (Qwen3.8 XML).**
  - The template's `<tool_call>` blocks are parsed in both JSON and
    `<function=…><parameter=…>` XML form. Parameters are typed by the tool's JSON schema,
    and required parameters are enforced (`protocol.py:184-186,215-245`).
  - Invalid or incomplete calls return a 502 `invalid_tool_call` instead of executable output
    (`:262-271`). With streaming, this arrives as an SSE error event.
  - Text deltas hide `<tool_call>` payloads and hold partial markers (`:189-212`).
- **Streaming `tool_calls` (Chat).**
  - Incremental: id and name first, then argument fragments from XML or JSON
    (`monolith/serving/tool_stream.py:20-121`, `monolith/serving/events.py:79-94`).
  - **The closing `}` is withheld** until the full response validates (`events.py:146-148`).
  - Messages and Responses emit each validated call once, at the end
    (`events.py:156-161,171-177`; `docs/serving.md:162-169`).
  - Upstream measured streaming XML tool calls, Responses continuation, and Anthropic
    streaming tool use on the NVFP4 pair (`docs/serving.md:371-377`).
- **Thinking: always off. Chat Completions:**
  - The chat template is applied with `enable_thinking=False`, hard-coded
    (`serve.py:102-103,147-149,360-361`).
  - `reasoning_effort` must be absent or `"none"`, otherwise 400 (`protocol.py:91,102-103`).
  - `chat_template_kwargs` is rejected as an extra field.
  - `reasoning_content` is accepted only in input history (`protocol.py:44`) and is never produced.
- **Thinking: always off. Responses and Anthropic:**
  - Responses maps `reasoning.effort` to the same check (`:384`). Replayed `reasoning`
    items are skipped (`:359-361`).
  - Anthropic: any `thinking.type` other than `disabled` returns 400 (`:319-320`). That
    includes Claude Code's `{type: "adaptive"}`, while omitting the field is fine.
    `output_config.effort` returns a capability-specific 400 (`:321-327`).

## 8. Image input

**Images are rejected (HTTP 400), not dropped.**

- Chat: content must be a string or a list of `TextPart` with `type: Literal['text']` and
  `extra='forbid'` (`protocol.py:17-21,40`), so an `image_url` part fails validation.
- Messages: an `image` block returns 400 "Unsupported Messages content block: image"
  (`protocol.py:302`). A `tool_result` that contains an image returns 400 "Only text
  content is supported; image, audio and document inputs are unavailable" (`:167-179`).
  Responses `input_image` hits the same message.
- The qwen3_5 package is text-only and ignores the vision tower. Weights come from
  `model.language_model.*`, and MLX `vision_tower.*` is never read
  (`monolith/models/qwen3_5/__init__.py:1-3`, `weights.py:27-32`; `docs/serving.md:185`).

## 9. Concurrency and timeouts

- **One generation at a time, and the rest are rejected, not queued.** Requests take a
  `threading.Lock` with `acquire(blocking=False)`; if it is held they get **HTTP 429**
  `model_busy` "The model is busy; retry after the current request finishes"
  (`serve.py:201,245-246`; `docs/serving.md:184`).
- A streaming worker holds the lock until generation ends, even if the client stops reading
  (`serve.py:286-288`). `/health`, `/v1/models`, and `count_tokens` do not take the lock
  (`:225-232,355-362`).
- **Timeouts:** there is no server-side request or generation timeout in code. SSE sends a
  `: keep-alive` comment every 5 s during compile and prefill (`serve.py:299-302`).
- **Client disconnect** sets a cancel flag. Work stops at the next prefill-chunk or
  decode-round boundary, after the active Metal dispatch finishes (`serve.py:336-337`;
  `docs/serving.md:170-172`). Client timeouts must cover long cold prefills (see §11).

## 10. Prefix caching (hybrid GDN)

- Checkpoints are exact-token CPU copies of the full sequence state: the occupied target
  and draft KV rows, both GDN recurrent slots, and StepState.
  - `PrefixCache.save/restore` (`monolith/runtime/prefix_cache.py:28-61`).
  - The KV-row sizing is at `:39-41`.
  - Lookup uses the longest exact token prefix and always leaves ≥ 1 token to prefill (`:22-26`).
- GDN state is recurrent, so a checkpoint is only valid at the exact boundary where it was
  saved. Hits therefore require an identical token prefix (`docs/serving.md:203-206`).
- **Checkpoint boundaries** are computed per request (`serve.py:134-161`):
  - the end of the last-but-one message ("message" mode);
  - the earlier text blocks of the last message (Claude Code project context).
  - Short prompts below `prefill_chunk_size` tokens are not saved (`serve.py:87-88`, `prefix_cache.py:30`).
- **Scope:** at most **2** checkpoints in the process (`prefix_cache.py:47-52`). Eviction
  keeps the shared system/tool prefix and replaces the latest conversation checkpoint.
  - The pool survives sampling-session rebuilds (`serve.py:77,89-90`).
  - It is lost on restart (`docs/serving.md:207-208`).
  - **Budget:** `min(4 GiB, recommendedWorkingSet/8)`, which is 4 GiB on this 128 GB
    machine (`monolith/generate.py:144-151`). One checkpoint costs about
    N × (64 KiB target KV + 20 KiB draft KV) + about 0.3 GiB of GDN state.
  - **The longest cacheable prefix is therefore about 46K tokens with DSpark (about 60K
    with `--no-draft`).** A 15K M1 prefix fits; 64K prompts are never cached.
- **Cached tokens are not reported to clients.**
  - Chat `usage` has only prompt/completion/total (`events.py:100-103`).
  - Messages has only input/output tokens (`:110`).
  - Responses hard-codes `input_tokens_details.cached_tokens: 0` (`:121-123`).
  - The real value is logged at INFO in the server log line
    `Generation: {..., 'cached_prompt_tokens': N, 'prefill_gpu_ms': …}` (`serve.py:164-177`).
    **M4 must parse the server log**, which is tee'd to `logs/`.
  - Non-streaming responses add `X-Lithos-Metal-Decode-*` headers only (`serve.py:260-262`).

## 11. Memory at 32K / 64K / 128K (estimates, planned GPU buffers)

**Per-token state:**

- Target KV is BF16 (`monolith/nn/attention.py:89`). 16 full-attention layers × K,V × 4 kv-heads × 256 × 2 B = **64 KiB/token**.
- DSpark KV is BF16 `(capacity, 8, 128)` per layer, ×5 layers (`monolith/spec/dspark/model.py:74-76`) = **20 KiB/token**.
- GDN state is FP32: 48 layers × 48 heads × 128 × 128 = 144 MiB per slot, ×2 slots ≈ 0.28 GiB.

| Context (capacity) | Target KV | Draft KV | int4 + DSpark total* | NVFP4 + DSpark total* |
| --- | ---: | ---: | ---: | ---: |
| 32K (32774) | 2.0 GiB | 0.63 GiB | ≈ 20 GB | ≈ 28 GB (≈ 48 GB if the 20 GiB prefill layout is resident too) |
| 64K (65542) | 4.0 GiB | 1.25 GiB | ≈ 22 GB | ≈ 31 GB (≈ 51 GB) |
| 128K (131078) | 8.0 GiB | 2.5 GiB | ≈ 28 GB | ≈ 36 GB (≈ 56 GB) |

\* The totals add, besides the KV columns:

- weights: int4 target pack ≈ 15 GB; NVFP4 decode pack 22.9 GiB; draft 1.16 GiB;
- GDN state;
- about 0.3–1 GiB of prefill scratch (`docs/serving.md:256-258`).

On top of that come up to 4 GiB of prefix-cache host copies, plus Python/tokenizer RSS.
`--no-draft` removes the draft column and the 1.16 GiB draft pack. **131072 fits
comfortably in 128 GB in every configuration.** These are estimates; measure them (M6).

Upstream ran only up to 33024 positions, and the recipes top out at the 32K key, which
is reused above 32K (`docs/serving.md:117-120,189-192,421-437`). Behavior and speed above
32K are unverified.

**Cold prefill is slow.** Upstream, on NVFP4 with 128-token chunks, saw 22K tokens take
110 s uncached and 7.5K tokens take 31.9 s (`docs/serving.md:48-53,399`). Tuned 512-chunk
GPU throughput is about 740–1000 tok/s at ≤ 16K (`:280-284`). A 64K cold prompt may take
several minutes, so set the client timeout to ≥ 20 min.

## 12. Launch commands (port 8704 only; GPU-lock protocol from METHODOLOGY §3 first)

All launches use `HF_HUB_OFFLINE=1 --local-files-only` so `serve` can never download.

```bash
cd ~/Developer/mlsys/serving/lithos-metal
EXP=~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark
PACKS=~/Developer/mlsys/serving/lithos-metal/.cache/packs

# A. NVFP4 native row: needs nvidia/Qwen3.8-27B-NVFP4 (22.0 GB) + the DSpark head (1.1 GB) fully cached.
# A1. DSpark on (default: auto head, 7 proposals + anchor, fixed verification)
HF_HUB_OFFLINE=1 .venv/bin/lithos-metal serve --model nvidia/Qwen3.8-27B-NVFP4 --local-files-only \
  --host 127.0.0.1 --port 8704 --max-context 131072 --pack "$PACKS" 2>&1 | tee "$EXP/logs/lithos-nvfp4-dspark.log"
# A2. Target only (131078 so the capacity, and therefore the target pack, matches A1)
HF_HUB_OFFLINE=1 .venv/bin/lithos-metal serve --model nvidia/Qwen3.8-27B-NVFP4 --local-files-only --no-draft \
  --host 127.0.0.1 --port 8704 --max-context 131078 --pack "$PACKS" 2>&1 | tee "$EXP/logs/lithos-nvfp4-nodraft.log"

# B. MLX affine 4-bit g64 row: needs the lm_head fix (§4) and a local checkpoint (no download);
#    B1 also needs the DSpark head (1.1 GB).
M4B=~/Developer/mlsys/models/Qwen3.8-27B-4bit-g64-from8bit   # converted artifacts go under mlsys/models
# B1. DSpark on: the head is NOT auto-paired for this target, so pass it explicitly
HF_HUB_OFFLINE=1 .venv/bin/lithos-metal serve --model "$M4B" --draft LithosAI/Qwen3.8-27B-DSpark-NVFP4 \
  --local-files-only --served-model-name Qwen3.8-27B-4bit --host 127.0.0.1 --port 8704 \
  --max-context 131072 --pack "$PACKS" 2>&1 | tee "$EXP/logs/lithos-4bit-dspark.log"
# B2. Target only: no download at all
HF_HUB_OFFLINE=1 .venv/bin/lithos-metal serve --model "$M4B" --no-draft --local-files-only \
  --served-model-name Qwen3.8-27B-4bit --host 127.0.0.1 --port 8704 \
  --max-context 131078 --pack "$PACKS" 2>&1 | tee "$EXP/logs/lithos-4bit-nodraft.log"
```

- If 131072 misbehaves, fall back to `--max-context 65536` (G5 minimum) and record why.
- `--prefill-chunk-size 512` is the upstream-tuned value for the NVFP4 recipe. It is not
  a speculation setting. Run defaults first, then optionally a 512 variant for M2, and
  record the flag.
- The first launch per capacity builds the pack (reads the whole checkpoint) and then
  compiles. Expect several minutes before `lithos-metal ready` (`serve.py:425-426`).

Header-only bind check before any serve (no GPU; it reads safetensors headers only). Save the
script outside the checkout, then run `.venv/bin/python -I bind_check.py "$M4B"`. The first line
should print `OK` after fix option 1 (or after option 2 plus reinstall), and the second line always `OK`.

```python
import collections, sys
import monolith.models
from monolith.models.qwen3_5 import Qwen3_5Model, weights as W
def run(label):
    try:
        m = Qwen3_5Model.from_checkpoint(sys.argv[1], max_context=4096)
        print(label, 'OK', dict(collections.Counter(s.format for _, mod in m.named_modules()
              for s in mod.weight_map().values() if not s.aux)))
    except Exception as e:
        print(label, 'FAILED:', type(e).__name__, e)
run('[as installed]')
orig = W.mlx_rename
W.mlx_rename = lambda n: n[len('language_model.'):] if n.startswith('language_model.lm_head.') else orig(n)
run('[with lm_head rename]')
```

Result on the real 8-bit snapshot's headers (2026-10-17):

- `[as installed] FAILED: KeyError "checkpoint has no tensor group for 'lm_head.weight'"`
- `[with lm_head rename] OK {'int4_affine': 498}`. These tensors are 8-bit, mislabeled; packing them would fail.

## 13. Gate expectations

| Gate | Expectation | Evidence / conditions |
| --- | --- | --- |
| G1 OpenAI chat + SSE + Qwen XML tool calls | **Expected pass for plain OpenAI requests. Expected fail (400) if the request carries `chat_template_kwargs` or `reasoning_effort` other than `none`.** | XML parse and incremental streaming: §7 (`protocol.py:184-245`, `tool_stream.py:20-121`, `events.py:79-94,146-148`). Markup is hidden from `content` (`protocol.py:189-212`). Measured upstream on NVFP4 (`docs/serving.md:371-377`). The harness's Hermes-shaped requests will be rejected by `extra='forbid'` (`protocol.py:72`) and `:102-103`, so run G1 with a plain request and report the Hermes-shaped result separately. Verify on the int4 path, which was never validated upstream. |
| G2 image input | **Expected fail: rejected with 400, not dropped** | §8 (`protocol.py:17-21,40,167-179,302`; text-only model package). |
| G3 Anthropic `/v1/messages` | **Expected fail overall.** Streaming text and `tool_use` are expected to pass; the image block fails. | Endpoint and stream events (`serve.py:351-353`, `events.py:50-66,153-163`, `protocol.py:280-333`), measured upstream (`docs/serving.md:371-377`). The image block returns 400 (`protocol.py:302`). `thinking: {type:"adaptive"}` returns 400 (`:319-320`). `tool_use` input arrives as a single `input_json_delta` at the end. Usage has no cache fields. |
| G4 thinking control | **Expected fail** | Thinking is hard-wired off (`serve.py:102-103`). `enable_thinking` cannot be set (`chat_template_kwargs` → 400), `reasoning_effort` must be `none` (`protocol.py:102-103`), and Anthropic thinking must be `disabled` (`:319-320`). "false ⇒ no reasoning" holds trivially; "true ⇒ reasoning" is impossible. M3's thinking bucket cannot run. |
| G5 ≥64K (128K preferred), fits in memory | **Unknown, verify.** Memory is expected to fit (§11). | `--max-context 131072` is accepted (`serve.py:391,400-401`). It was never exercised upstream above 33K, and the recipes cap at the 32K key (`docs/serving.md:117-120`). A 64K cold prefill may take minutes (§11). Record memory and wall time. |

## 14. Metric notes

**Hard prerequisite for every metric (M1–M7) and gate:** the lithos request shape must omit
`chat_template_kwargs` and send `reasoning_effort` only as `"none"` or not at all. Anthropic
requests must omit `thinking` or set it to `disabled`. Otherwise every request is rejected with
400 (`protocol.py:72,102-103,319-320`), so the harness cannot be used unchanged against
lithos. Thinking is already off server-side, so the stripped requests are still
"thinking disabled" as METHODOLOGY §3 requires.


- **M1:** prefix reuse works for a 15K prefix (§10). Read `cached_prompt_tokens` from the server log. The screenshot suffix is impossible (images → 400), so run text-only.
- **M3:** "spec off" uses `--no-draft`, which also drops the tuned recipes (§6). Thinking runs are impossible.
- **M4:** the screenshot trajectory cannot run. Cached tokens are available only from the log.
- **M5:** concurrent helpers get an immediate 429 (§9). Record the rejection rate; anything else, such as client retries, serializes.
- **M7:** run tool calls without `chat_template_kwargs`.

## 15. Caveats

- `serve` downloads the target and the head unless offline (§3). Always set `HF_HUB_OFFLINE=1` and `--local-files-only`.
- The DSpark head in the HF cache is a paused partial download: metadata only, 3 shards at 0 bytes. Resume with `hf download LithosAI/Qwen3.8-27B-DSpark-NVFP4` when the user allows.
- The MLX int4 path is untuned and its numerics are unvalidated on the 27B. The head's acceptance was trained and measured against NVFP4/BF16 target features. Expect lower acceptance on int4.
- Tested upstream on a 48 GB M5 Max 40c running macOS 26.x, not macOS 27.2 or 128 GB. The chip backend is chosen by core count and family (`setup.py:64-67`).
- Usage is not cached-aware. Tool-call failures surface as 502 or SSE error events.
- The default bind is localhost (`serve.py:394`). Keep it.

## 16. Status / remaining work

**Done:** the venv install builds and runs (`--version`, `serve --help`, `models`). The
source research above is complete. The local-checkpoint question is answered and
confirmed with a header-only bind test.

**Not done:** no GPU run, no pack built, no downloads, and no lm_head fix applied.

**Resume steps:**

1. Re-verify the install: `cd ~/Developer/mlsys/serving/lithos-metal && .venv/bin/lithos-metal --version`.
   If the venv is missing, rerun the §1 commands (about 2 min, served from the uv cache).
2. Choose an lm_head fix (§4, option 1 or 2). For option 2, edit `mlx_rename`, then
   `uv pip install --python .venv/bin/python -e '.[serve]'`. Do not commit.
3. Produce the local 4-bit g64 checkpoint into `~/Developer/mlsys/models/...`: dequantize the
   8-bit, re-quantize with mlx (group 64, bits 4), and copy non-quantized tensors byte-for-byte.
   Then run the §12 bind check against it.
4. **Minimum downloads by row:**

   | Row | Downloads needed |
   | --- | --- |
   | B2 (int4, `--no-draft`) | none |
   | B1 (int4 + DSpark) | the DSpark head, 1.1 GB, resumable |
   | A (NVFP4) | + `nvidia/Qwen3.8-27B-NVFP4`, 22.0 GB |

   Downloading `mlx-community/Qwen3.8-27B-4bit` (16 GB) does not help: it needs the same fix.
5. The first GPU step is a short B2 launch at `--max-context 32768`, under the GPU lock,
   with a 64-token request. This checks pack build, tokens, and memory before going to
   131072, then running G1/G3–G5.

**Open questions:**

- Correctness and speed of the 27B int4 path.
- Behavior and memory above 32K.
- Where the NVFP4 prefill-derived caches are written, and their size (`docs/serving.md:234-235`).
- DSpark acceptance on int4.

**Validated without a server or GPU** (installed pydantic models, `ChatRequest.model_validate_json` /
`anthropic_request`; FastAPI maps these errors to HTTP 400 via `serve.py:204-217`):

| Accepted | Rejected |
| --- | --- |
| `temperature: 0` (integer), `reasoning_effort: "none"`, Anthropic with no `thinking` | `chat_template_kwargs`, `reasoning_effort: "medium"`, a Chat `image_url` part, Anthropic `thinking: {type: "adaptive"}`, an Anthropic `image` block |
