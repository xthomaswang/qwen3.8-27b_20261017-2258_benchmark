# Core AI (apple/coreai-models): environment, export, benchmark commands, gate notes

Recorded 2026-10-18, 00:53–01:20 local time. macOS 27.2 (build 26B5101f). Core AI uses
Xcode-beta 27.2 (build 27B5028f), selected only through `DEVELOPER_DIR`; the global default
stays Xcode 27.1 (build 27A9275) and `xcode-select` was never changed.

Only the tiny `Qwen/Qwen3.5-0.8B` was exported and loaded, as a toolchain check. Nothing
27B has been exported or loaded. Its numbers in section 3 are **not benchmark results**.

> **Update, 2026-10-20.** The 27B export ran after this file was written (2026-10-18
> 01:05–01:31, exit 0, peak footprint 37.7 GB). The direct-call A/B against
> `mlx_lm.benchmark` is in `summary.md`. The `llm-server` gate probes have not run yet.

> **Premise correction.** The README lists Core AI as "reference only — no HTTP server".
> That is out of date. `apple/coreai-models` has shipped `llm-server`, an OpenAI-compatible
> HTTP server, since #187. It builds and runs here (section 3.4). Section 6 has the
> gate expectations: G1 likely passes; G2 and G3 fail; G4 is partial. Whether to promote
> the Core AI row from "reference" to a gated backend is the user's call. This file does not
> edit README.md or METHODOLOGY.md.

## 1. Versions

| Item | Value |
| --- | --- |
| apple/coreai-models | `main` at `3b25d934ccaee2d05edc6e281c555a5a9a13a55c` (2026-10-16, "Qwen3.5/3.6/3.8 macOS export (#321)"), clean tree, cloned 2026-10-18 00:53 into `~/Developer/mlsys/serving/coreai-models` |
| Xcode (Core AI) | Xcode 27.2, build 27B5028f; `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` |
| Swift / SDK | Apple Swift 6.4 (swiftlang-6.4.0.34.1), target `arm64-apple-macosx27.2.0`, `xcrun --show-sdk-version` = 27.2 |
| macOS | 27.2, build 26B5101f |
| uv / Python | uv 0.12.19; CPython 3.11.16 (from `.python-version`) |
| Python packages (`uv.lock`) | coreai-core 1.0.0b3, coreai-torch 0.4.3, coreai-opt 0.3.0, torch 2.9.0, torchao 0.17.0, transformers 5.12.1, huggingface-hub 1.27.0, safetensors 0.7.0, tokenizers 0.22.2, numpy 2.3.5, accelerate 1.13.0, datasets 4.8.5, diffusers 0.37.1 (86 packages) |
| SwiftPM pins (`Package.resolved`) | swift-argument-parser 1.7.0, swift-transformers 1.2.0, swift-jinja 2.3.2, xgrammar 0.2.2, hummingbird 2.22.0, swift-nio 2.96.0 |
| Runtime frameworks | system `CoreAI.framework`, `FoundationModels.framework` (2.1.8), `MetalPerformanceShadersGraph` (from `otool -L llm-benchmark`) |

## 2. Install and build (reproducible)

```sh
cd ~/Developer/mlsys/serving
git clone https://github.com/apple/coreai-models.git coreai-models    # main @ 3b25d93
cd coreai-models
printf '%s\n' 'export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer' > .envrc
echo '.envrc' >> .git/info/exclude          # .envrc stays untracked; git status is clean
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # direnv does not load in agent shells
uv sync                                       # 1.2 s, everything from the uv cache; .venv at repo root
swift build -c release --product llm-benchmark   # 107 s wall incl. package resolution
swift build -c release --product llm-runner      # 6 s
swift build -c release --product llm-server      # 28 s (adds Hummingbird / swift-nio)
swift build -c release --show-bin-path           # .build/out/Products/Release
```

- **Checks.** These all exit 0:
  - `uv run coreai.llm.export --help` (and `--dry-run` for `qwen3.8-27b` and `qwen3.5-0.8b`).
  - `llm-benchmark --help`, `llm-runner --help` and `llm-server --help`.
- **Commands below call the binaries directly**, as `$B/<tool>` with
  `B=~/Developer/mlsys/serving/coreai-models/.build/out/Products/Release`. That avoids
  `swift run`'s rebuild check during timed runs. The README's
  `swift run -c release llm-benchmark …` is equivalent.
- **`uv run coreai.llm.export …` and `.venv/bin/coreai.llm.export …` are the same entry
  point** (`coreai_models.llm.export:main`). The measured commands use the venv script, so
  that `/usr/bin/time -l` reports the Python process's own peak footprint, not uv's.
- **No local patches.**
  - The June fix (`mpsGraphScalarOutputBufferBytes = 64`, `experiments/coreai/coreai-local.patch`)
    is upstream now: `CoreAIPipelinedEngine.swift` sizes the decode output buffer with
    `max(minimumMPSNDArrayBufferSize, MemoryLayout<Int32>.size)`.
  - `llm-benchmark` has no engine-variant flag. `EngineFactory` auto-selects `coreai-pipelined`
    for dynamic (macOS) bundles, which matches what the June patch forced.
- **Harmless warnings.**
  - torchao prints `Skipping import of cpp extensions … torch >= 2.11.0 (found 2.9.0)`.
  - The Swift build warns `unrecognized platform name 'FoundationModels'`. It also warns
    that the switch at `CoreAILanguageModel.swift:617` is not exhaustive: the 27.2 SDK
    added a transcript entry case `.data(_)`.
    - This only matters on the FoundationModels path, if a transcript ever carries a
      `.data` entry. Text multi-turn does not.

## 3. Tiny-model toolchain check (Qwen3.5-0.8B): not benchmark results

Checkpoint: `Qwen/Qwen3.5-0.8B`, snapshot `2fc06364715b967f1860aea9cf38778875588b17`
(1.77 GB, downloaded 01:02 into `$HF_HOME`).
- Text decoder: 752.4 M params, tied embeddings.
- The checkpoint also holds 100.6 M vision and 20.5 M MTP params. The export drops both.

Run under the shared GPU lock (`local_ai-benchmark session`, 01:04:05–01:09:36). Logs and JSON
are in `logs/coreai/` (gitignored).

### 3.1 Export

```sh
cd ~/Developer/mlsys/serving/coreai-models
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer HF_HUB_OFFLINE=1
/usr/bin/time -l .venv/bin/coreai.llm.export qwen3.5-0.8b --output-dir ~/Developer/mlsys/models/coreai
```

| Measure | Value |
| --- | --- |
| Resolved config | macOS, `--compression-config models/qwen3_5/qwen3_5_cfg.yaml` (uint4 asymmetric, per-block 32 along the input axis, `minval` formulation, eager mode; Linear **and** Embedding quantized), bfloat16 compute, max context 262144, plus a second `prefill` entrypoint |
| Wall time | 74.8 s (74.4 s user: essentially single-threaded) |
| Peak memory footprint | 5.51 GB (`/usr/bin/time -l`). Max RSS 7.13 GB, which includes mmap'd scratch pages. |
| Phase profile (1 s RSS samples; phase labels inferred from log order) | load 0–6 s; ≈7.0 GB plateau 6–17 s (quantize/finalize); ≈4.8 GB 30–75 s (trace, convert, save) |
| Peak scratch disk | 2.35 GB in `$TMPDIR/coreai_export_*/{layers,quantized}` (4.9× the bundle), deleted at exit |
| Output | `~/Developer/mlsys/models/coreai/qwen3_5_0_8b_qwen3_5_cfg_dynamic/` = 496 MB: `…dynamic.aimodel/main.mlirb` 475.8 MB, `tokenizer/` 20.0 MB, `metadata.json` |
| Bytes per parameter | 475.8 MB / 752.4 M = **0.632 B/param (5.06 bits)**. That is uint4 codes plus a bf16 scale and a bf16 min per 32 weights. |

### 3.2 `llm-benchmark` (512 / 1024 / 5 and 16K / 1024 / 5)

```sh
B=.build/out/Products/Release; M=~/Developer/mlsys/models/coreai/qwen3_5_0_8b_qwen3_5_cfg_dynamic
/usr/bin/time -l $B/llm-benchmark --model $M -p 512 -g 1024 -n 5 --clear-coreai-cache --output-json …   # cold
/usr/bin/time -l $B/llm-benchmark --model $M -p 512 -g 1024 -n 5 --output-json …                        # warm
/usr/bin/time -l $B/llm-benchmark --model $M -p 16384 -g 1024 -n 5 --output-json …
```

| Run | Prepare | Warm-up | Prompt tok/s, median (min–max) | Generation tok/s, median (min–max) | Wall | Peak footprint |
| --- | --- | --- | --- | --- | --- | --- |
| 512/1024/5, cache cleared | 5.105 s (specialization) | 5.25 s | 15,881 (15,841–20,065) | 378.3 (363.9–384.2) | 24.4 s | 1.01 GB |
| 512/1024/5, cached | 0.129 s (cache hit) | 2.91 s | 15,763 (15,713–21,716) | 375.2 (347.7–376.5) | 17.5 s | 0.98 GB |
| 16384/1024/5, cached | 0.140 s | 4.65 s | 15,510 (15,080–16,272) | 281.9 (263.9–321.5) | 28.1 s | 4.53 GB |

Trial 2's prompt rate is high in both 512-token runs. At a time to first token of about
25–32 ms, that is timing noise. It is not prefix reuse, because each trial calls
`engine.reset()` → `reset(to: 0)`, which clears the history. For hybrid models any prefix
overlap falls back to a full replay anyway (section 7).

### 3.3 `llm-runner`

```sh
$B/llm-runner --model $M --prompt "List three prime numbers greater than 10, comma-separated." --max-tokens 96 --temperature 0
```

The output was `11, 13, 17`.
- Model load 5.2 s: each executable has its own specialization cache (section 7).
- Prompt: 25 tokens in 430 ms.
- Generation: 11 tokens at 172.5 tok/s.
- Peak footprint 0.75 GB.

### 3.4 `llm-server` smoke (port 8700, 127.0.0.1, manual, not timed)

```sh
$B/llm-server --model $M --port 8700 --temperature 0 --max-tokens 512 --verbose
```

Port 8700 sits in this repo's 8700–8705 range and is unassigned in METHODOLOGY. If the row is
promoted, give Core AI a port in that table.

The server was ready about 6 s after start.
- `/ready` reports `max_context_length` 262144 and `tool_calling: true`.
- The engine log shows `coreai-pipelined`.
- `keyCache` and `valueCache` are GROWING (6 × 1 × 2 × ? × 256). `convStates` (18 × 1 × 4 × 6144)
  and `recurrentStates` (18 × 1 × 16 × 128 × 128) are FIXED.

| Probe | Result on 0.8B |
| --- | --- |
| Streaming text, `reasoning_effort: "none"` | HTTP 200, `Paris`, TTFT 0.046 s, no reasoning |
| Streaming tool call (`get_weather`, `qwen3_coder` XML) | HTTP 200. `get_weather {"city": "Paris", "unit": "c"}`; valid JSON; **one complete `tool_calls` delta**; `finish_reason=tool_calls`; no markup in `content` |
| Thinking on, `reasoning_effort: "medium"` | HTTP 200, but the reasoning ("Thinking Process: …") arrived in **`content`**, and `reasoning_content` was empty. It hit `max_tokens` before `</think>`. |
| `chat_template_kwargs: {enable_thinking: false}` only | Accepted but ignored: the field is not decoded. Got the template's default behaviour. |
| Image part (base64 PNG showing `K7Q2`) | **HTTP 200, answer `0`**: the image was silently dropped |
| `POST /v1/messages` | HTTP 404 |
| Non-streaming `usage` | `prompt_tokens`, `completion_tokens` and `total_tokens` only. No `prompt_tokens_details.cached_tokens`. `stream_options.include_usage` produced no usage chunk. |
| Prefix reuse | `/v1/stats` showed `prefix_hits` 0 for all 9 requests. Request B (A + assistant turn + user) and request C (same 1.5K-token system prompt, new user turn) were both re-prefilled in full (section 7). |

## 4. Qwen3.8-27B commands (not run, waiting for a GPU slot)

### 4.1 Preconditions (both verified 01:15)

- **BF16 download complete.**
  - `scripts/download_models.sh` logged `done: core gguf extra` at 01:10:51.
  - Snapshot `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`: 18/18 shards, `model.safetensors.index.json`
    present, 0 `.incomplete` blobs. 55.56 GB on disk = index `total_size`.
  - Breakdown: text decoder 51.25 GB + `lm_head` 2.54 GB, which is what the export reads.
    The vision tower (0.92 GB) and MTP (0.85 GB) are dropped.

```sh
S27=$HF_HOME/hub/models--Qwen--Qwen3.8-27B/snapshots/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0
ls "$S27"/model-*-of-00018.safetensors | wc -l                       # 18
ls "$HF_HOME/hub/models--Qwen--Qwen3.8-27B/blobs" | grep -c incomplete # 0
```

- **Weight-free preflight passed** (CPU only, 2 s, 0.38 GB):
  `.venv/bin/python -I ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/scripts/coreai_preflight.py qwen3.8-27b`.
  - It resolves the preset offline to the cached snapshot.
  - It builds `Qwen3_5ForCausalLM` on the meta device: **26.896 B params**, 16 KV layers,
    48 delta layers.
  - The loader's key index finds 18 shards, 64 layers, 848 per-layer keys, plus `lm_head.weight`,
    `embed_tokens.weight` and `norm.weight`.

### 4.2 Export (CPU and memory heavy; run it under the lock as planned)

```sh
cd ~/Developer/mlsys/serving/coreai-models
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer HF_HUB_OFFLINE=1
LOGS=~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/coreai
caffeinate -i /usr/bin/time -l .venv/bin/coreai.llm.export qwen3.8-27b \
  --output-dir ~/Developer/mlsys/models/coreai 2>&1 | tee "$LOGS/export_qwen3.8-27b.log"
# = uv run coreai.llm.export qwen3.8-27b --output-dir ~/Developer/mlsys/models/coreai
# output: ~/Developer/mlsys/models/coreai/qwen3_8_27b_qwen3_5_cfg_dynamic/{qwen3_8_27b_qwen3_5_cfg_dynamic.aimodel,tokenizer,metadata.json}
```

- **Why the short-name and not a path.** `coreai.llm.export` takes a registry short-name or
  a Hub id, not a directory.
  - `_is_hf_id()` treats anything containing `/` as a Hub id.
  - A path would then need `--experimental` and would lose the `qwen3_5_cfg` preset.
  - `from_hf_memory_efficient` calls `snapshot_download(<id>)`, which rejects paths.
  - The short-name plus `HF_HUB_OFFLINE=1` resolves to exactly the local snapshot above
    (checked by the preflight), with no network access.
- **Defaults kept.**
  - `qwen3_5_cfg.yaml` 4-bit, bfloat16 compute.
  - Max context 262144: the KV cache grows on demand, so a large cap costs nothing up front.
  - `--num-layers` and `--quantization-mode graph` are rejected for this hybrid family.
  - No activation calibration, so no C4 download.

| Resource | Expected (extrapolated from the 0.8B run and from source; not measured) |
| --- | --- |
| Peak RAM (footprint) | **≈ 40–45 GB, range 30–60 GB.** The peak should come at conversion and save, not at load. See the breakdown after this table. |
| RSS / page cache | RSS will read higher than the footprint. It includes about 54 GB of BF16 safetensors read through mmap and about 84 GB of mmap'd scratch. That memory is clean and reclaimable, but don't export while a 27B server is resident. |
| Disk | **≈ 84 GB transient scratch** in `$TMPDIR/coreai_export_*`: 4.9× the bundle, as on the 0.8B. It is deleted at normal exit and stays if the process is killed. The **bundle is ≈ 17.0 GB** (0.632 B/param × 26.9 B), so the **peak is ≈ 101 GB**. The first load by each tool adds about 17 GB more (section 7). The volume has 1.3 TiB free. To watch or relocate the scratch, set `TMPDIR`. |
| Time | **≈ 20–45 min.** The 0.8B took 75 s, nearly single-threaded. Weight-proportional work scales about 36×; graph work scales about 2.7× (64 vs 24 layers). |

How the peak breaks down:

1. Conversion copies every packed weight into in-memory MLIR `DenseElementsAttr`s
   (`coreai_torch/converter.py:_constant_from_tensor`). That is about 17 GB.
2. `AIProgram.save_asset` writes `main.mlirb`, then calls `read_bytes()` on the whole file
   for the SHA-256 (`coreai/authoring/asset.py`). That is about another 17 GB, while the
   program is still alive.
3. Add 5–10 GB of graph overhead for 64 layers and 2 entrypoints.
4. The quantize phase is lower, about 20–25 GB. Its float32 temporaries of the 1.27 B-element
   `embed_tokens` / `lm_head` (5.1 GB per copy) scale as on the 0.8B run (≈4.4× that size).

**Streaming or full load? It streams from disk.**
- The macOS path loads one decoder layer at a time from the mmap'd safetensors
  (`from_hf_memory_efficient`), writes it to `$TMPDIR/…/layers/layer_<i>.safetensors`, and
  re-mmaps it.
- coreai-opt's eager `finalize(mmap_dir=…)` also writes the quantized weights per layer and
  re-mmaps them, "so large models can be finalized without holding full weights in RAM".
- So the 53.8 GB BF16 decoder is never held in anonymous memory.
- What does sit in RAM is the **4-bit program**, about 1–2× its 17 GB size, during
  conversion and save.

### 4.3 `llm-benchmark`, 512 / 1024 / 5 (reference protocol; same as `mlx_lm.benchmark` defaults)

```sh
cd ~/Developer/mlsys/serving/coreai-models
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
B=.build/out/Products/Release; M27=~/Developer/mlsys/models/coreai/qwen3_8_27b_qwen3_5_cfg_dynamic
REPO=~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark; mkdir -p "$REPO/coreai/raw" "$REPO/logs/coreai"
/usr/bin/time -l $B/llm-benchmark --model "$M27" -p 512 -g 1024 -n 5 \
  --output-json "$REPO/coreai/raw/llm-benchmark_p512_g1024_n5.json" 2>&1 | tee "$REPO/logs/coreai/llmbench_27b_p512_g1024_n5.log"
```

- **Peak memory: ≈ 18–19 GB.** That is 17.0 GB of weights plus 1–2 GB. On the 0.8B it was
  1.0 GB with 0.48 GB of weights.
- **Time: ≈ 5–8 min.** That is 1 warm-up plus 5 trials of about 1 s prefill and about 35–50 s
  of decode each.
  - Decode should be bandwidth-bound at 17.0 GB/token, so the expectation is about
    20–30 tok/s.
  - The **first** load also pays the one-time specialization. On the 0.8B that was 5.1 s
    cold vs 0.13 s cached; for 27B, guess 1–3 min.
  - It writes about 17 GB to `~/Library/Caches/coreai-cache/26B5101f/llm-benchmark/`.
- **Record from the run.**
  - The per-trial lines, as median, min and max (the tool prints only means).
  - `Prepare`, and whether the cache was hit.
  - "peak memory footprint" from `/usr/bin/time -l`. `llm-benchmark` itself reports no
    memory.

MLX counterpart, the same protocol from `mlx-lm/env.md` §4 (4-bit row):

```sh
cd ~/Developer/mlsys/serving/mlx-lm; export HF_HUB_OFFLINE=1
M4=$HF_HOME/hub/models--mlx-community--Qwen3.8-27B-4bit/snapshots/10c35caafbb80f7dc6a7a432cdd11af10a6d4818
.venv/bin/mlx_lm.benchmark --model "$M4" -p 512 -g 1024 -n 5
```

### 4.4 Long context: 16K prompt (supported; validated on the 0.8B)

```sh
/usr/bin/time -l $B/llm-benchmark --model "$M27" -p 16384 -g 1024 -n 5 \
  --output-json "$REPO/coreai/raw/llm-benchmark_p16384_g1024_n5.json" 2>&1 | tee "$REPO/logs/coreai/llmbench_27b_p16384_g1024_n5.log"
# MLX: .venv/bin/mlx_lm.benchmark --model "$M4" -p 16384 -g 1024 -n 5
```

- **Peak memory: ≈ 22–30 GB.**
  - The KV cache costs 64 KiB/token, about 1.1 GiB at 17.4K tokens.
  - The growing cache doubles to a 32K capacity, about 2 GiB.
  - On the 0.8B, footprint rose 3.5 GB from the 512-token run to the 16K run, mostly
    chunk-attention transients. Those scale with 24 vs 8 query heads.
- **Time: ≈ 7–10 min.** Prefill is chunked at 4096 tokens, since this Mac has ≥ 64 GB.
  - Estimate 16K prefill at roughly 400–800 tok/s, so 20–40 s per trial.
  - Decode adds about 45–55 s per trial.
- Longer variants are possible: the bundle allows 262144 tokens. At 64K the KV cache is
  4 GiB plus transients. Each step up multiplies the run time, so treat 64K as a separate
  slot.

### 4.5 Optional: in-process multi-turn via FoundationModels

`CoreAILanguageModel` adapts a bundle to FoundationModels' `LanguageModel`:

```swift
import FoundationModels; import CoreAILanguageModels
let model = try await CoreAILanguageModel(resourcesAt: url, mode: .eager)
let session = LanguageModelSession(model: model)   // the transcript carries the turns
let r1 = try await session.respond(to: "…"); let r2 = try await session.respond(to: "…")
```

It advertises the `.toolCalling`, `.reasoning` and `.guidedGeneration` capabilities when the
tokenizer supports them.

A ready probe lives in `scripts/coreai_fm_probe/`. It is a SwiftPM package that depends on the
local clone, adapted from the June `experiments/coreai/bench_foundation_models.swift`.
- It runs one `LanguageModelSession` over three greedy turns. Turn 3 asks for a name given
  only in turn 1.
- It prints load time, plus TTFT and total time for each turn.
- **Built (44 s, no warnings) but not run.** Running it needs the GPU, and this session no
  longer takes the lock.

```sh
cd ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/scripts/coreai_fm_probe
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift build -c release --package-path . --scratch-path ~/Developer/mlsys/serving/coreai-models/.build/fm-probe
P=~/Developer/mlsys/serving/coreai-models/.build/fm-probe/out/Products/Release/coreai-fm-probe
$P ~/Developer/mlsys/models/coreai/qwen3_5_0_8b_qwen3_5_cfg_dynamic 64     # validate first on 0.8B (< 1 min)
/usr/bin/time -l $P ~/Developer/mlsys/models/coreai/qwen3_8_27b_qwen3_5_cfg_dynamic 128   # 27B: ≈ 3–5 min, ≈ 18–19 GB
```

- The probe is a fourth executable, so its first load pays a fresh specialization: about
  17 GB more under `~/Library/Caches/coreai-cache/26B5101f/coreai-fm-probe/`.
- FoundationModels gives text snapshots, not token counts. Report times, not tok/s.

### 4.6 Cleanup after the 27B runs (optional)

- Specialization caches: `$B/llm-benchmark --model "$M27" --clear-coreai-cache …`, or delete
  `~/Library/Caches/coreai-cache/26B5101f/<tool>/<hash>`. There is about 17 GB per tool
  that loaded the 27B.
- Leftover export scratch after a crash: `ls -d "$TMPDIR"coreai_export_*`.

## 5. Comparing `llm-benchmark` with `mlx_lm.benchmark`

`llm-benchmark` says it is "based on mlx-lm benchmark". What is the same:

- Defaults: `-p 512 -g 1024 -n 5`, plus 1 untimed warm-up.
- The prompt is uniform random token ids with no chat template. `llm-benchmark` uses
  SplitMix64 `% vocab` with seed 0.
- Greedy sampling (temperature 0). Batch 1.
- A full cold prefill every trial.

What differs:

- **Prompt tok/s.** `llm-benchmark` computes prompt tokens / time to the first generated
  token, which includes the first decode step and sampling.
- **Generation tok/s.** Computed as (n − 1) / (t_last − t_first).
- **Memory.** `llm-benchmark` reports none; take it from `/usr/bin/time -l`. mlx reports
  `peak_memory` itself.
- **Quantization.** The formats are not bit-identical.
  - Core AI is uint4 per-block 32, `minval`, with bf16 scale and min: 5.06 bits/weight
    measured. It quantizes `embed_tokens` and `lm_head` too.
  - The mlx-community 4-bit is affine g64 with bf16 scale and bias: about 4.5 bits/weight.
  - So Core AI streams **about 12% more bytes per decoded token**: ≈17.0 GB vs ≈15.2 GB of
    text weights. State this next to any decode comparison.
- **Provenance.** The JSON from `--output-json` records neither `sw_vers` nor
  `xcodebuild -version` nor the coreai-models commit. Add them alongside, per README
  "Provenance".
  - Use `DEVELOPER_DIR=… xcodebuild -version`, which gives Xcode 27.2 / 27B5028f.

## 6. Gate notes (G1–G5): from source at 3b25d93, plus the 0.8B smoke in §3.4

All of these are expectations for the 27B. None has been verified on it.

| Gate | Expectation | Evidence |
| --- | --- | --- |
| G1 Chat Completions + SSE + Qwen tool calls | **Likely pass.** | `llm-server` serves `POST /v1/chat/completions` with `stream` (`text/event-stream`), `tools` and `response_format` (xgrammar guided JSON). `tool_choice` and `parallel_tool_calls` are decoded, but I did not check whether they are honoured. `ToolCallParser` detects the `<tool_call>` markers, tries JSON first, then falls back to the Qwen3-Coder `<function=…><parameter=…>` form. Values are coerced from the XML. Tool calls are emitted **as one complete delta per call**, after the closing marker, like mlx-lm. So for a tool-only reply, TTFT ≈ end-to-end time. `finish_reason=tool_calls`. Markup is stripped from `content`. Assistant `tool_calls` and `tool` messages are passed back to the template. Verified on 0.8B (§3.4). |
| G2 Image input | **Fail, silently.** | The Qwen3.8 bundle is text-only. The export loads only `model.language_model.*` and `lm_head`; vision and MTP weights are dropped. The VLM export (`coreai.vlm.export`) covers only Qwen3-VL-2B and Muse-Glimmer-30B. `llm-server` decodes `image_url` parts, but builds the prompt from `content.textContent` only (`ChatHandler.swift` `tokenizeMessages`). The result is HTTP 200 and the image never reaches the model, which is exactly the failure G2 is designed to catch. Observed on 0.8B: `K7Q2` was not read. |
| G3 Anthropic `/v1/messages` | **Fail.** | There is no route. Only `/v1/chat/completions`, `/v1` (lm-eval auto-route), `/v1/completions`, `/v1/models`, `/v1/stats`, `/health` and `/ready` exist. 404 on 0.8B. A translating proxy is the only route. |
| G4 Thinking control | **Partial.** | (a) `reasoning_effort` is honoured. `"none"` sets the template variable `enable_thinking=false` **and appends `\n/no_think` to the system message**, or inserts a `/no_think` system message if there is none. So prompts are not byte-identical to the other servers. Any other value sets `reasoning_effort=<value>` and `enable_thinking=true`. `--default-reasoning-effort` and `--no-thinking` set the server default. (b) **`chat_template_kwargs` is ignored**: it is not decoded. (c) **Reasoning is not separated for Qwen.** The tag-pair `ThinkTagParser` starts outside a think block, but the Qwen3.8 template (`chat_template.jinja:163-169`) ends the generation prompt with `<think>\n` unless `enable_thinking` is false. So the reasoning streams as `content`, and `reasoning_content` stays empty (observed on 0.8B). From source, the closing `</think>` and the answer also end up in `content`. (d) If the template raises, the server logs `applyChatTemplate failed` and **falls back to a plain `role: content` prompt instead of returning 400**. Qwen3.8 accepts only `xhigh`/`medium`/`low` with thinking on, so `high` is a likely trigger. |
| G5 Context ≥ 64K | **Expected to pass on memory; unverified.** | The bundle allows 262144 tokens. KV cache (`auto` → `growing`) costs 64 KiB/token for 16 full-attention layers × 4 KV heads × 256 × K/V × bf16: 4 GiB at 64K, 8 GiB at 128K. The fixed GDN state is about 80 MB (bf16 estimate). Weights are about 17.0 GB. Prefill runs in 4096-token chunks; the attention transient at 64K is not measured. |

## 7. Runtime notes that matter if the row is promoted

- **Prefix cache on hybrid models.** The pipelined engine keeps a single token history.
  - Only a pure extension of the processed tokens is reused.
  - Any divergence, or a shorter input, makes a hybrid model (`hasNonTruncatableStates`) do
    a full reset and replay the whole prompt, because recurrent state cannot be rewound.
  - On the 0.8B even an append-only follow-up got 0 reuse. A likely cause is the template
    re-rendering the assistant turn differently from the generated tokens (not inspected).
  - Expect M1 (fixed prefix, new suffix) and M4 (trajectory) to re-prefill everything on
    every step.
- **Concurrency (M5).** One engine, one sequence. `RequestQueue` serves one request at a time
  in FIFO order and returns 429 beyond `--max-queue-depth` (default 16). There is no
  batching. Interleaved sessions also destroy each other's cached prefix.
- **Specialization cache.**
  - Location: `~/Library/Caches/coreai-cache/<OS build>/<executable>/<hash>/`.
  - It is kept **per executable**: `llm-benchmark`, `llm-runner` and `llm-server` each built
    their own copy, 477 MB each, 1.00× the bundle (1.4 GB total for the 0.8B).
  - For 27B that is about 17 GB and a cold specialization for each tool. An OS-build change
    invalidates them.
- **KV strategy.** `auto` → `growing`, starting at 256 tokens and doubling. `llm-server` and
  `llm-runner` accept `--kv-cache-strategy fixed_size`, which preallocates `maxContextLength`.
  At 262144 that is 16 GiB, so don't use it at 262144.
- **Other server details.**
  - Default `--temperature` is 0.7; pass `--temperature 0` for timed runs.
  - Default `--max-tokens` is 512.
  - `--variant coreai-sequential` is required for `/v1/completions` logprobs.
  - The server binds `127.0.0.1` and has no context-length flag: the cap comes from
    `metadata.json`.
- **No ANE path.** The Qwen3.5/3.6/3.8 family is macOS-only and GPU-only (README table:
  iOS "No").

## 8. Status / remaining work

Done (2026-10-18, by 01:20):

1. Toolchain: clone at `3b25d93` with `.envrc` and exclude; uv env; `llm-benchmark`,
   `llm-runner` and `llm-server` built against Xcode-beta 27.2; `--help` passes for all.
2. Tiny-model export and `llm-benchmark` / `llm-runner` / `llm-server` smoke on Qwen3.5-0.8B
   (§3). The bundle is kept at `~/Developer/mlsys/models/coreai/qwen3_5_0_8b_qwen3_5_cfg_dynamic`
   for re-checks.
3. BF16 27B download verified complete, and the weight-free export preflight passed (§4.1,
   `scripts/coreai_preflight.py`).
4. Commands and resource estimates for the 27B (§4), and gate expectations (§6).
5. FoundationModels multi-turn probe built against the 27.2 SDK (`scripts/coreai_fm_probe/`,
   §4.5); not run.

Files added to this repo: `coreai/env.md`, `scripts/coreai_preflight.py` and
`scripts/coreai_fm_probe/` (`Package.swift`, `Package.resolved`, `Sources/`). Nothing is
committed. The tiny-run logs and JSON are in `logs/coreai/`, which is gitignored.

Remaining. Each step needs a slot scheduled by the main agent; this session takes no further
GPU lock.

| Step | Needs | Duration (est.) | Peak memory (est.) |
| --- | --- | --- | --- |
| 1. 27B export (§4.2) | lock: no other model resident; ≈101 GB free disk | 20–45 min | ≈40–45 GB (30–60) |
| 2. `llm-benchmark` 512/1024/5 (§4.3), first run includes specialization | lock | 5–8 min | ≈18–19 GB |
| 3. `llm-benchmark` 16384/1024/5 (§4.4) | lock | 7–10 min | 22–30 GB |
| 4. Matching `mlx_lm.benchmark` 4-bit rows, if not already run in the mlx-lm sub-run | lock | ≈12 min | per mlx-lm |
| 5. Optional: `llm-server` gate probes on 27B (G1 tool stream, G2 image, G4 thinking split, G5 64K prompt) | lock; port 8700 | ≈10–15 min | ≈19–27 GB |
| 6. Optional: FoundationModels multi-turn probe (§4.5) | lock | ≈5 min | ≈18–19 GB |

Afterwards:

- Write `coreai/raw/*.json` with provenance (§5) and `coreai/summary.md`.
- Decide whether README's "reference only — no HTTP server" row becomes a gated backend.
- Clear the specialization caches if disk matters (§4.6).
