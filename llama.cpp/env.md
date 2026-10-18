# llama.cpp (`llama-server`): environment and launch plan

This file was written 2026-10-17 from source reading and `llama-server --help` only. No model has been
loaded and no server has been started. Every claim cites `file:line` in `~/Developer/mlsys/serving/llama.cpp`.
Each is marked **verified (source)**, **expected**, or **verify** (needs a live run).

## 1. Build

| Item | Value |
| --- | --- |
| Source | `~/Developer/mlsys/serving/llama.cpp`, tag `b11717`, commit `848bbda9041decd87904f7eb5a2990863ecce03b` (2026-10-17) |
| `--version` | `0.7.0-dev (build 1, commit 848bbda)`, AppleClang 21.0.0.21000334, Darwin arm64. "build 1" is a shallow-clone artifact; the tag is the real version. |
| Backend | Metal (GPU), BLAS, CPU |
| Binaries | `build/bin/llama-server`, `llama-bench`, `llama-cli`, `llama-mtmd-cli`. `llama-quantize` and `llama-imatrix` are **not built**. |
| macOS | 27.2, build 26B5101f |
| Xcode | 27.1, build 27A9275 (`xcodebuild -version`) |

## 2. Files (none downloaded yet)

The paths are inside the shared HF cache, so nothing is copied into this repo.

```
SNAP=~/Developer/ml_source/huggingface/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4ca720788d1e01f1bff70c033e0d0028fd02e502
$SNAP/Qwen3.8-27B-UD-Q4_K_M.gguf      16,464,440,224 B  sha256 322e194f…   (blob .incomplete, 0 B)
$SNAP/MTP/mtp-Qwen3.8-27B-Q4_0.gguf    1,369,590,656 B  sha256 50d9ce5a…   (blob .incomplete, 0 B)
$SNAP/mmproj-F16.gguf                    927,607,488 B  sha256 cbb841a9…   (blob .incomplete, 536,546,384 B so far)
```

The cached unsloth README (`$SNAP/README.md`) has **no llama.cpp or MTP usage instructions**; it only links to
unsloth.ai docs. All MTP flags below therefore come from the llama.cpp source.

## 3. Launch commands (port 8702 only)

The shared settings are the same across all variants:

```bash
LS=~/Developer/mlsys/serving/llama.cpp/build/bin/llama-server
EXP=~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark
COMMON=(
  -m "$SNAP/Qwen3.8-27B-UD-Q4_K_M.gguf"
  --mmproj "$SNAP/mmproj-F16.gguf"
  --host 127.0.0.1 --port 8702 --alias qwen3.8-27b
  -c 131072 -ngl all -fa on -ctk f16 -ctv f16
  --jinja --reasoning-format deepseek
  --ctx-checkpoints 32 --checkpoint-min-step 8192
  --cache-ram 8192
  --metrics --slots --no-webui --offline
)
```

**A. MTP off.** This is the baseline used for the gate and for M1, M2, M4, M6 and M7.

```bash
$LS "${COMMON[@]}" -np 1 --spec-type none \
  --log-file "$EXP/logs/llama-server-8702-mtp-off.log"
```

**B. MTP on.** This is the "spec on" run for M3.

```bash
$LS "${COMMON[@]}" -np 1 \
  -md "$SNAP/MTP/mtp-Qwen3.8-27B-Q4_0.gguf" --spec-type draft-mtp --spec-draft-n-max 3 \
  --log-file "$EXP/logs/llama-server-8702-mtp-on.log"
```

**C. Concurrency (M5).** This uses three slots and a unified KV pool.

```bash
$LS "${COMMON[@]}" -np 3 -kvu --spec-type none \
  --log-file "$EXP/logs/llama-server-8702-np3.log"
```

Notes on the flags:

- **`--port 8702` must always be passed.** The default port is now 9931 (help text, `--port`).
- **`--jinja`** is the default (help: "default: enabled"). It is passed explicitly for provenance.
- **`-fa on`** works with this model on Metal:
  - `FLASH_ATTN_EXT` supports head dim 256 (`ggml/src/ggml-metal/ggml-metal-device.m:1739`).
  - K and V must use the **same** cache type (`:1753-1755`).
  - The allowed types are f32, f16, q8_0, q4_0, q4_1, q5_0, q5_1, and bf16 (`:1757-1770`).
  - The memory-saving variant is therefore `-ctk q8_0 -ctv q8_0`. Never mix f16 and q8_0. **Verified (source).**
- **GDN ops on Metal:** `GATED_DELTA_NET` (head dim a multiple of 32), `SSM_CONV` and `SOLVE_TRI` are all
  supported (`ggml-metal-device.m:1839-1846`), so no CPU fallback is expected. The arch is `qwen35`
  (`src/llama-arch.cpp:41`, `src/models/qwen35.cpp`). **Verified (source).**
- **`-ub`:** the default 512 is fine for screenshots.
  - The server caps `image_max_tokens` to `n_ubatch` only for non-causal or mixed-batch models
    (`tools/server/server-context.cpp:1286-1300`).
  - The `qwen3vl_merger` projector is neither (`tools/mtmd/mtmd.cpp:2351-2370`; `server-context.cpp:4192-4194`).
  - A larger `-ub` (1024–2048) may speed up prefill, but it also moves the near-end checkpoint offset
    (`4 + n_ubatch`, `server-context.cpp:4103-4121`).
  - Record whichever value is used.
- **`--cache-reuse` is a no-op here, so it is not passed.** The server disables it when an mmproj is loaded
  (`server-context.cpp:1316-1319`) and again when the memory cannot shift, which is the case for recurrent/hybrid
  memory (`:1322-1331`). Context shift is disabled by the same two blocks.
- **`-fit` stays on by default.** It only adjusts unset arguments. After launch, confirm that the log line
  `initializing, n_slots = …, n_ctx_slot = …, kv_unified = …` (`server-context.cpp:1393-1394`) shows
  `n_ctx_slot = 131072`. **Verify.**
- **Thinking default:**
  - `-rea auto` detects support from the template.
  - `--reasoning-effort default` keeps the template default, which is **`xhigh`** for Qwen3.8 (MLX snapshot
    `chat_template.jinja`: `reasoning_effort|default('xhigh')`).
  - The latency metrics turn thinking off per request (§4 G4).
  - The `/v1/messages` runs need a server-side default; see G3.

**MTP evidence** (all **verified (source)**):

- `--spec-type` accepts `draft-mtp` (help; `common/speculative.cpp:76`).
- The draft file is given with `-md` / `--model-draft` / `--spec-draft-model` (help).
- `--draft-max` and `--draft-min` are **removed**; use `--spec-draft-n-max` (default 3) and `--spec-draft-n-min`
  (help lines "the argument has been removed").
- With no `--spec-type`, the type is auto-detected from the draft GGUF. A draft file with
  `blk.{N-1}.nextn.eh_proj.weight` resolves to `draft-mtp` (`common/arg.cpp:563-575`,
  `common/speculative.cpp:2396-2421`).
- `draft-mtp` sets `load_mtp` (`common/common.cpp:1706`). The server loads the draft or MTP context
  (`server-context.cpp:1127-1131`, `:1245-1271`).
- The MTP context type is `LLAMA_CONTEXT_TYPE_MTP` (`common/common.cpp:1252-1256`).
- The unsloth sidecar was produced with `convert_hf_to_gguf.py --mtp`, which writes an `mtp-` file
  (`convert_hf_to_gguf.py:120-123`). That file carries its own `token_embd`, `output_norm` and `output`
  (`conversion/qwen.py:341-347`), which explains its 1.37 GB size.
- **Sidecar auto-discovery happens only for `-hf` plans** (`arg.cpp:545-575`, `:640-648`). With local `-m`, MTP
  stays off unless `-md` is given. To turn MTP off, omit `-md` and pass `--spec-type none`.
- **MTP together with mmproj.** I found no guard that disables spec decoding when an mmproj is loaded: slot init
  assigns both `slot.spec` and `slot.mctx` (`server-context.cpp:1400-1441`). Command B keeps `--mmproj`. If the
  startup log reports speculative decoding disabled, drop `--mmproj` from B; M3 is text-only. **Verify.**
- **Thinking-off server default.** For the thinking-off latency runs, you may add
  `--chat-template-kwargs '{"enable_thinking":false}'` as a server default. Per-request kwargs still override it
  (`server-common.cpp:1404-1418`). Run the gate itself without this flag so the default behavior is recorded honestly.
- Spec decoding on recurrent memory works by taking per-step checkpoints (`server-context.cpp:1387-1389`,
  `:3519-3556`). It also reserves `n_max` extra recurrent cells per sequence (`common/common.h:401-407`). The
  overhead is part of what M3 measures.

## 4. Gate expectations

| Gate | Expectation | Evidence |
| --- | --- | --- |
| G1 tool calls (OpenAI, streaming) | **Expected pass.** Verify the deltas and that no markup leaks. | A specialized Qwen3-Coder XML parser is selected when the template contains `<tool_call>`, `<function=` and `<parameter=` (`common/chat.cpp:1245-1253`; the comment names Qwen3.5). The diff struct carries `tool_call_delta` (`common/chat.h` ~l.150). Qwen3.5 fixtures exist in `tests/test-chat.cpp` and `tests/test-chat-auto-parser.cpp`. The unsloth GGUF embeds its own "unsloth_fixed" template, so the template-dependent results must be verified live. |
| G2 image input | **Expected pass.** Verify the code is read. | `image_url` parts are parsed. With no mmproj the request is rejected with an error, not dropped silently (`tools/server/server-common.cpp:1203-1204`). Projector is `qwen3vl_merger` (`tools/mtmd/clip-impl.h:476`, `clip.cpp:1000-1002`). Image budget is 8–4096 tokens (`clip.cpp:1746-1755`). A 1280×1024 PNG is 40×32 = 1280 tokens, with no resize. `data:` base64 is certain; `http(s)` fetching was not checked. |
| G3 `/v1/messages` | **Expected pass** for streaming, `tool_use` and images. **Expected partial** for thinking control. | Route: `server.cpp:280`; `count_tokens`: `:298`. Converter: `server-chat.cpp:348`. The request then shares the chat path, the parser and mmproj. Images are mapped from base64 and url sources (`server-chat.cpp:418-441`), and `tool_result` content with images is supported (`:478-516`). `tool_choice` `any` maps to `required` (`:568-575`). The stream emits `message_start` (with `cache_read_input_tokens`), `thinking_delta` and `signature_delta`, `input_json_delta` and `message_delta` (`server-task.cpp:1324-1443`, `:878-956`). **However:** only `thinking.type == "enabled"` is mapped, to a budget defaulting to 10000 (`server-chat.cpp:600-605`). **`adaptive` is silently ignored**, so Claude Code-style requests get the template default (thinking ON). For no-think `/v1/messages` latency runs, start the server with `--chat-template-kwargs '{"enable_thinking":false}'`; per-request kwargs override it (`server-common.cpp:1404-1418`). **Verify.** Whether a `ping` event is sent was not checked. |
| G4 thinking control | **Expected pass** for `enable_thinking` and for `reasoning_effort` = `none`, `medium`, `low` or `xhigh`. **Expected fail (HTTP error)** for other effort values. | Per-request `chat_template_kwargs` are merged over the CLI kwargs (`server-common.cpp:1404-1408`). `enable_thinking` must be a JSON boolean; a string is rejected (`:1410-1418`). Top-level `reasoning_effort: "none"` sets thinking off and removes the kwarg (`:1421-1426`). Any other value is passed **verbatim** to the template (`:1427-1428`; `common/chat.cpp:916-918`; `common/jinja/caps.cpp:29-33`), with no mapping. The Qwen3.8 template raises for values outside `xhigh`/`medium`/`low`. Reasoning arrives in `delta.reasoning_content` with `--reasoning-format deepseek` (`server-chat.cpp:623-624`). |
| G5 context ≥ 64K | **Expected pass** at `-c 131072`, `-np 1` (and at `-np 3 -kvu`; verify `n_ctx_slot`). | `n_ctx_slot()` = `llama_n_ctx_seq`, capped by `--kv-unified-per-slot` and `n_ctx_train` = 262144 (`server-context.cpp:4652-4660`). Memory estimate is in §6. |

## 5. Prefix cache on this hybrid architecture (critical for M1 and M4)

The 48 Gated DeltaNet layers keep a recurrent state that **cannot be rewound**. Only the 16 full-attention layers have a
positional KV cache. llama-server copes with this through **context checkpoints**: snapshots of the non-rewindable
state taken with `LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY`. All points below are **verified (source)** unless marked.

1. **Exact extension needs no checkpoint.** When the new prompt is the cached sequence plus new tokens, the recurrent
   state's `pos_min` is below the threshold, so the server simply continues from that state (`server-context.cpp:3791-3794`,
   `:3843`). This happens when the re-rendered history is byte-identical, generated tokens included.
2. **Divergence inside the cached sequence needs a checkpoint.** The server searches for the **newest** checkpoint with
   `pos_max <= pos_next` and `pos_min` below the threshold (`:3845-3858`). It loads that checkpoint for the target, and
   for the draft when MTP is on (`:3862-3866`), then restarts from it (`:3878-3880`). Invalidated checkpoints are erased
   (`:3893+`). **With no usable checkpoint, the whole prompt is reprocessed from token 0** (`:3884-3889`).
3. **When checkpoints are created during prompt processing:**
   - Only for completion tasks with recurrent, SWA or seq_rm-limited memory (`:3983-3996`).
   - Prompt batches are split at the start of the **last user message**, and at earlier user starts when they are more
     than `--checkpoint-min-step` past the previous checkpoint (`:4094-4101`).
   - They are also split at `4 + n_ubatch` and at 4 tokens before the end (`:4103-4121`).
   - The checkpoint is taken **before** decoding the batch that starts at that point (`:4166-4180`).
   - Mid-prompt batches are skipped unless they start a user message or are near the end (`:4146-4155`).
   - The min-step gate is bypassed for the last user message and near the end (`:4170-4173`). The default
     `-cms 8192` therefore does **not** block the checkpoints M1 and M4 rely on.
   - **No checkpoint is taken after an image chunk in the same step** (`:4166-4167`).
4. **What counts as a "user" turn.** User starts come from message spans keyed on the template's rendered user
   delimiter (`common/chat.cpp:1417-1425`, `common/chat.h:175-200`, `server-common.cpp:795-800`). Qwen renders
   tool results as `<|im_start|>user\n<tool_response>…`, so a tool-result turn should count as a user start.
   **Verify** with `-lv 4` trace lines ("created context checkpoint …", `server-context.cpp:2604`).
5. **Eviction.** Up to `--ctx-checkpoints` (default 32) per slot. When the list is full, entries within min-step of
   each other are dropped first, then the oldest goes first (FIFO) (`:2544-2607`).
6. **Images in prefix matching.** Image chunks are matched by chunk id and token count
   (`server-common.cpp:745`, `:770-776`), so a byte-identical screenshot in the history counts toward the
   common prefix. How the chunk id is derived (image-bytes hash) was not checked.
7. **Reporting.**
   - `usage.prompt_tokens_details.cached_tokens` (`server-task.cpp:357-363`) and `timings.cache_n` both come from
     `n_prompt_cached = n_past`, set **after** the checkpoint logic (`server-context.cpp:3914`). They report the
     tokens actually skipped, which land on checkpoint boundaries.
   - `timings.prompt_n` is the count actually reprocessed.
   - Streaming usage needs `stream_options.include_usage: true` (`server-task.cpp:494-506`).
   - `timings`, with `cache_n`, `prompt_n`, `prompt_ms`, `predicted_*`, and `draft_n` / `draft_n_accepted` when
     drafting, is always sent on the last chunk (`server-task.cpp:508-510`, `server-common.cpp:84-101`).
   - Anthropic usage reports `cache_read_input_tokens` (`server-task.cpp:779-782`).

**Expected M1 behavior.**
- The warm-up request creates a checkpoint at the start of the last user turn, which is the end of the ≈15K prefix.
- Each trial whose suffix differs should restore that checkpoint and reprocess only the ≈1.5K suffix. In that case
  `cached_tokens` is about 15K.
- If `cached_tokens` is 0, the checkpoint was missing or was taken after an image, and the whole prompt was reprocessed.
- **TTFT may also include RAM prompt-cache traffic.** With `--cache-ram` on, a partially matching task may trigger
  `prompt_save` / `prompt_load` of the slot's full state (`server-context.cpp:308-335`; cache created at `:1500-1508`)
  before prefill, which is a host copy inside TTFT. Check `-lv 4` logs for per-trial save and load lines, and run one
  M1 control with `--cache-ram 0` to separate checkpoint-restore cost from prompt-cache churn. **Verify.**

**Expected M4 behavior.**
- If the template re-renders earlier assistant turns identically, each step is an exact extension and reprocesses only
  the new turn.
- If it does not (for example, empty `<think>` blocks are stripped or tool calls are re-serialized), each step restores
  the previous step's user-start checkpoint and reprocesses about two turns.
- Either way, latency should stay flat rather than grow linearly with the step index. The per-step `cached_tokens`
  will show which case applies.

## 6. Memory estimate (no measurements yet)

- **Full-attention KV cache:** 16 layers × 2 (K, V) × 4 KV heads × 256 dim × 2 B = **64 KiB/token** at f16.
- **Recurrent state** (f32, `src/llama-model.cpp:2909-2910`; formulas at `src/llama-hparams.cpp:229`, `:257`):
  48 GDN layers × (3 MiB SSM + 120 KiB conv) ≈ **150 MiB per sequence**.
  - MTP on reserves `n_max` extra recurrent cells. That is unverified, but probably about 600 MiB per slot at
    n_max = 3.
  - Each context checkpoint is about the same size, ~150 MiB, held in host RAM. 32 checkpoints come to up to
    ~4.7 GiB per slot.

| Component | 64K, `-np 1` | 128K, `-np 1` |
| --- | --- | --- |
| UD-Q4_K_M weights | 15.3 GiB | 15.3 GiB |
| mmproj F16 | 0.9 GiB | 0.9 GiB |
| KV f16 (q8_0 ≈ 0.53×) | 4.0 GiB | 8.0 GiB |
| Recurrent state, 1 slot | 0.15 GiB | 0.15 GiB |
| Compute buffers, including 248K-vocab logits (estimate) | ~1–2 GiB | ~1–2 GiB |
| **Subtotal, MTP off** | **~21–22 GiB** | **~25–26 GiB** |
| MTP on: sidecar 1.3 GiB + its 1-layer KV (4 KiB/token) + extra recurrent cells | +~1.8 GiB | +~2.3 GiB |
| Checkpoints (up to 32 × ~0.15 GiB) + `--cache-ram` prompt cache (≤ 8 GiB) | host RAM, up to ~13 GiB | same |

With `-np 3 -kvu` the KV pool is shared at 8 GiB, plus about 0.15 GiB recurrent state per slot and per-slot
checkpoints. Everything fits within 128 GB. Record the real footprint for M6.

## 7. Concurrency (M5)

- `-np N` creates N slots (`server-context.cpp:1397-1399`), and continuous batching is on by default (help `-cb`).
- `-kvu` gives one shared KV pool. Each slot can use up to `llama_n_ctx_seq`, optionally capped by
  `--kv-unified-per-slot` (`:4652-4660`, `:1352-1373`).
- Without `-kvu` and with an explicit `-np 3`, the help says unified is **not** the default ("enabled if number of
  slots is auto"). Each sequence is then expected, but not confirmed from source, to get about `n_ctx / n_parallel` ≈
  43K. **Always pass `-kvu`** for M5 and confirm `n_ctx_slot` from the startup log line.
- `--cache-idle-slots` is on by default: idle slots are saved to the RAM prompt cache when a new task arrives, and
  cleared under unified KV (help).
- An idle slot's state may therefore be evicted and later restored. That can add a restore cost to the main agent's
  next step. **Verify** in the M5 logs (`-lv 4`).
- `--slot-prompt-similarity` (default 0.10) routes a request to the slot with the most similar cached prompt.

## 8. Local conversion assessment (not executed)

**Converter support.** At b11717 `convert_hf_to_gguf.py` supports `Qwen3_5ForConditionalGeneration`:

- Text model: `Qwen3_5TextModel`, which writes arch `QWEN35` (`conversion/qwen.py:665-668`, router
  `conversion/__init__.py:262`).
- mmproj: the Qwen3-VL vision class (`conversion/qwen3vl.py:16`, router `__init__.py:378`).
- MTP flags: `--mtp` writes an MTP-only sidecar; `--no-mtp` / `--no-nextn` drops the head
  (`convert_hf_to_gguf.py:120-127`, `:265-283`). By default the MTP head becomes `blk.64.nextn.*` in the main file
  (`qwen.py:300-306`).

**No MLX dequant path.** `dequant_model` (`conversion/base.py:326-563`) handles only bitnet, fp8, gptq and
compressed-tensors. A custom dequant step is required.

**MLX checkpoint layout** (headers only, 2180 keys):

- Quantization is affine `bits 8`, `group_size 64`, with no per-module overrides. This includes `embed_tokens` and
  `lm_head`: U32 weights with BF16 scales and biases.
- Stored in BF16, not quantized: the whole vision tower, all norms, `A_log`, `dt_bias` and `conv1d`.
- There are no `mtp.*` keys.
- Projections are already split (`in_proj_qkv`, `in_proj_z`, `in_proj_a`, `in_proj_b`), same as HF.

**HF index** (`Qwen/Qwen3.8-27B`, 1199 keys): `model.language_model.*`, `model.visual.*`, `lm_head.weight`,
and 15 `mtp.*` keys.

**Work needed to get HF layout:**

- Key renames:
  - `language_model.model.` → `model.language_model.`
  - `language_model.lm_head.` → `lm_head.`
  - `vision_tower.` → `model.visual.`
- Dequantize: `w = q·scale + bias` per group of 64, with four uint8 values packed little-endian per U32.
- Undo the MLX channels-last layout:
  - `conv1d` [10240,4,1] → [10240,1,4]
  - `patch_embed` [1152,2,16,16,3] → [1152,3,2,16,16]
- Drop the `quantization` block from `config.json`.
- **Unresolved:** whether MLX `sanitize()` shifted the RMSNorm weights by +1. Check a few `input_layernorm` values.
- The MLX config still says `mtp_num_hidden_layers: 1`, so pass `--no-mtp`.

**Pipeline (not run):**

1. A numpy dequant script, custom, about 2–4 h to write and validate. It writes BF16 HF-layout safetensors and copies
   the tokenizer and the **official** chat template, not unsloth's fixed one.
2. Create `uv venv ~/Developer/mlsys/serving/llama.cpp/.venv` and install
   `requirements/requirements-convert_hf_to_gguf.txt`. This is **not light**: `torch==2.11.0` (CPU) is pinned, and
   `convert_hf_to_gguf.py:12` imports torch unconditionally. Installing it is a decision point.
3. `python convert_hf_to_gguf.py <bf16dir> --no-mtp --outtype bf16 --outfile Qwen3.8-27B-BF16.gguf`
4. `python convert_hf_to_gguf.py <bf16dir> --mmproj --outtype f16 --outfile mmproj-F16.gguf`
5. `cmake --build build --target llama-quantize` (`tools/quantize/CMakeLists.txt:15`), then
   `build/bin/llama-quantize Qwen3.8-27B-BF16.gguf Qwen3.8-27B-Q4_K_M.gguf Q4_K_M`.

**Cost.** Disk peaks at about 126 GB: 54 GB safetensors, 54 GB BF16 GGUF, 16.5 GB Q4_K_M and 0.9 GB mmproj. 1.4 TiB
is free. Wall time is about 30–60 min plus the scripting.

**What is lost:**

- No MTP head, so no `draft-mtp`. The fix is to download only the 1.37 GB sidecar (about 46 min at 0.5 MB/s). It
  carries its own embedding and output tensors, so pairing it with a local target looks plausible, but runtime
  compatibility is unverified.
- No imatrix and no unsloth dynamic per-tensor types.
- The weights are quantized twice (8-bit, then 4-bit).

The result is therefore a **different row** from UD-Q4_K_M.

**Verdict: conditional GO, as a fallback only.** It unblocks G1–G5 and the text and vision metrics without the
16.5 GB download. It cannot stand in for the primary `UD-Q4_K_M` row, and it cannot measure MTP until the sidecar is
fetched. Resolve the norm-offset question before investing time in it.

## 9. Caveats

- Everything above comes from source reading. The flags are verified as existing in `--help`. Runtime behavior is
  "expected" until a live run.
- The unsloth GGUF embeds an `unsloth_fixed` template that differs from the official one. Gates G1 and G4 depend on
  the template, so record which template was used from the startup log.
- Checkpoint size and the restore cost per step are estimates. Read them from the `-lv 4` trace logs.
- `--reasoning-budget` exists only at CLI level, defaulting to -1. Per-request use was not checked; it is irrelevant
  to the latency metrics, which run with thinking off.
- The `--cache-ram` default (8192 MiB) may be smaller than one 128K-context state plus its checkpoints. M4 and M5
  could see evictions; watch the logs.

## 10. Status / remaining work (paused 2026-10-17 ~23:40)

**Verified from source:** every flag in §3 exists in b11717 `--help`. The MTP flag set is `-md` + `--spec-type
draft-mtp` + `--spec-draft-n-max`, and MTP is turned off by omitting `-md` and passing `--spec-type none`.
`--cache-reuse` is a no-op here. Flash attention at head dim 256 and the GDN ops are supported on Metal. The paths for
`reasoning_effort`, `chat_template_kwargs` and `/v1/messages` are as cited above.

**Resume steps:**

1. Finish the GGUF downloads. The `mmproj-F16` download is at about 537 of 928 MB; resume it with
   `scripts/download_models.sh gguf`. Do not touch the existing `.incomplete` blobs by hand.
2. Take the GPU lock and check that port 8500 is free (METHODOLOGY §3). Launch **A** with `-lv 4` once, and confirm
   these log lines:
   - `n_ctx_slot = 131072`
   - flash attention enabled
   - the template detected as Qwen3-Coder
   - mmproj loaded
   - checkpoint creation lines
   - startup memory
3. Run G1–G5. In particular, check that `reasoning_effort: "high"` errors, and that `/v1/messages` with
   `thinking: {type: "adaptive"}` thinks by default.
4. Run M1 with one warm-up and check that `cached_tokens` is about 15K. If it is 0, inspect the checkpoint trace (§5).
5. Launch **B** (MTP on) for M3. Check `timings.draft_n` / `draft_n_accepted` and the per-step speculative checkpoint
   cost.
6. Launch **C** (`-np 3 -kvu`) for M5. Watch for idle-slot cache eviction.
7. The conversion fallback (§8) is optional. First decide whether installing torch is acceptable, and check the RMSNorm
   +1 question.

**Not checked:**

- Whether `/v1/messages` sends a `ping` event, and how `thinking_budget_tokens` is consumed.
- `http(s)` image URLs.
- The exact `n_rs_seq` per slot with MTP.
- The MTP KV sizing.
- What `-fa auto` resolves to.
- The `/v1/messages` section of `tools/server/README.md`.

## Smoke test, 2026-10-18 01:13 (4-bit UD-Q4_K_M, manual, not timed)

`scripts/serve.sh llama.cpp mtp-off|mtp-on 4bit` (b11717). The server was ready in 6 s
(mtp-off) and 2 s (mtp-on, files already in page cache). These are first-request timings,
not benchmark numbers.

| Probe | mtp-off | mtp-on |
| --- | --- | --- |
| Streaming text | OK, TTFT 1.03 s | OK, TTFT 0.21 s |
| Streaming tool call | OK, `get_weather {"city":"Paris","unit":"c"}`, streamed (TTFT 1.66 s, end-to-end 2.67 s) | OK (TTFT 0.89 s, end-to-end 1.35 s) |
| Image 1280×1024, random code | OK, read `WK3-DEG`, 1308 prompt tokens, TTFT 2.82 s | OK, TTFT 2.57 s |
| Thinking on | reasoning returned | — |
| `/v1/messages`, no thinking field | HTTP 200, response starts with a `thinking` block | — |

- **MTP drafting.** The draft model `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` loads alongside the mmproj; the two coexist. Per-request draft acceptance in the log was 0.50–0.90, with a mean accepted length of 2.5–3.7 tokens per step. The tool call reached 27/30, mean length 3.70.

## Prefix reuse check, 2026-10-18 01:59 (quick harness validation, unverified run)

With the default launch flags (`--ctx-checkpoints 32 --checkpoint-min-step 8192 --cache-ram 8192`), the M4 trajectory reuses everything except each step's new ≈1.7K tokens:

| Step | Prompt tokens | `cache_n` | Newly processed | TTFT |
| --- | --- | --- | --- | --- |
| 0 (cold) | 15,030 | 0 | 15,030 | 29.0 s |
| 1 | 16,733 | 15,026 | 1,707 | 4.9 s |
| 2 | 18,439 | 16,729 | 1,710 | 4.9 s |
| 3 | 20,140 | 18,435 | 1,705 | 5.0 s |

- The checkpoint taken near the end of the previous prompt is the one reused, so `--checkpoint-min-step 8192` does not inflate per-step TTFT for 1.7K-token steps. We keep the flags unchanged.
- The ≈4.9 s per step covers the vision encode of one 1280×1024 screenshot plus ≈1.7K new tokens, an effective ≈350 tok/s.
- MTP accepted 62–106 of 87–128 drafts per step.
