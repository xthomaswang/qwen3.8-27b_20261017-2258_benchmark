# MLC-LLM — verdict, environment and launch notes (Qwen3.8-27B)

Recorded 2026-10-18 01:30 EDT. No model was loaded on the GPU, no server was started, and
no weights were converted or compiled. Claims cite `file:line`, PR numbers or commits.
Items marked **executed** were run; items marked **verify** need a live run under the GPU
lock.

- Machine: MacBook Pro M5 Max (40-core GPU, 128 GB). macOS 27.2, build 26B5101f.
  Xcode 27.1 (27A9275) is the default; `xcode-select` was not changed.
- Upstream source: `~/Developer/mlsys/serving/mlc-llm_bench`, a fresh clone of
  `mlc-ai/mlc-llm` at `main` = `8978ea9a` (2026-10-06, "[Serve] Pass token ids to models
  that look them up at every layer (#3565)"). That is upstream main on 2026-10-18
  (`gh api repos/mlc-ai/mlc-llm/commits/main`). The pinned TVM submodule is
  `mlc-ai/relax@201fa000`; it was not checked out, and its files were read through `gh api`.
- Venv: `~/Developer/mlsys/serving/mlc-llm_bench/.venv` (uv, CPython 3.12.14) holds the
  newest macOS nightly wheels. **They do not load as shipped** (section 3.2).
- Model: `Qwen/Qwen3.8-27B` BF16, snapshot `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`. The
  download was still running at 01:15; config, tokenizer and index were present.
  - `Qwen3_5ForConditionalGeneration`, `model_type=qwen3_5`; the text part is `qwen3_5_text`.
  - 64 layers: 48 `linear_attention` (Gated DeltaNet, GDN) and 16 `full_attention`
    (`full_attention_interval=4`).
  - Hidden 5120; 24 Q / 4 KV heads, head_dim 256, `attn_output_gate=true`.
  - GDN: 16 key heads and 48 value heads, both of dim 128; conv kernel 4.
  - Interleaved mRoPE `[11,11,10]`, `partial_rotary_factor=0.25`, `rope_theta=1e7`,
    `max_position_embeddings=262144`.
  - `tie_word_embeddings=false`, `mtp_num_hidden_layers=1`; the vision tower has depth 27,
    patch 16, merge 2.
- Short forms used below:
  - `main:` is the clone at `8978ea9a` (paths relative to `python/mlc_llm/` or `cpp/` as written).
  - `nightly:` is `.venv/lib/python3.12/site-packages/` in that venv.
  - `tvm:` is `mlc-ai/relax@201fa000`.

## 1. Verdict

**Supported with caveats for text-only serving. Fails the agent gate (G1, G3, G4) at the
code level, so it is eligible only for METHODOLOGY's text-only reference row.**

- **The hybrid architecture is supported upstream end to end, including `mlc_llm serve`.**
  PR #3449 (merged 2026-03-26, `05f79e11`) added the Qwen3.5 GDN model. It also added a
  `kHybrid` KV-state kind that drives a PagedKVCache and an RNNState together. Qwen3.8-27B
  uses the same `qwen3_5` architecture (section 2.3). No PR or issue names Qwen3.6 or 3.8.
- **Vision is on `main` only.** Qwen3.5 vision (#3568, 2026-10-01) is not in any wheel. The
  newest macOS nightly was built on 2026-08-24 from `main@9fa644f5`; it has the text model
  only.
- **The nightly dylibs carry invalid ad-hoc signatures.** macOS SIGKILLs the process at
  `import tvm`. One `codesign` command fixes it (section 3.2). The agent was not permitted
  to run it, so that is the user's call.
- **Correct serving needs `--prefix-cache-mode disable` and one sequence at a time
  (`--mode interactive`).** Without both, the RNN (GDN) state is forked wrongly, rolled back
  past its history, or read with the wrong batch size (section 6). The consequences:
  - no prefix reuse, so M1 and M4 run a cold prefill every step;
  - no concurrency, so M5 is serialized;
  - no speculative decoding, so M3 spec-on is N/A.
- **The 27B is untested upstream.** #3449 tested 0.8B to 9B. Prefill also reuses the
  sequential recurrent decode kernel (#3480 is open), so expect slow prefill.

| Gate | Expectation | Short reason (details in section 7) |
| --- | --- | --- |
| G1 OpenAI streaming + Qwen XML tool calls | **fail** | No Qwen XML parser, and `tools` never reach the prompt. Streaming never emits `tool_calls`. History containing `tool_calls` or `tool` messages is rejected. Plain streaming text works. |
| G2 image input | **fail** on the nightly; **degraded, verify** on a `main` source build | The nightly has no vision model. On main, every image is stretched to 448×448 (196 tokens) and given 1-D positions. |
| G3 `/v1/messages` | **fail** | No route. |
| G4 thinking control | **fail** per request | No `chat_template_kwargs` or `reasoning_effort`. Thinking is fixed per `mlc-chat-config.json` (`qwen3_5` vs `qwen3_5_nothink`), and reasoning is not separated from `content`. |
| G5 context ≥ 64K | **memory: pass (estimate); time: verify** | About 24 GiB resident at 131072 tokens. The speed of a 64K cold prefill is unknown. |

## 2. Evidence

### 2.1 Upstream PRs and issues (`gh search prs/issues`, 2026-10-18)

Searches used: qwen3.5, qwen3_5, qwen35, Qwen3.6, Qwen3.8, gated delta, GatedDeltaNet,
hybrid, RNNState, kHybrid, tool calls, chat_template_kwargs, enable_thinking, anthropic,
prefix cache. The relevant results:

| PR / issue | State | Meaning here |
| --- | --- | --- |
| #3449 Add Qwen3.5 GatedDeltaNet hybrid model + kHybrid KVStateKind (@mitiskuma) | merged 2026-03-26, `05f79e11` | Model, loader and the `kHybrid` engine path. The PR body says it was tested with 0.8B/2B/4B/9B fp16 and 9B q4f16_1 on Metal via `MLCEngine`. |
| #3465 Migrate tir to tirx in qwen35_model | merged 2026-03-27, `f35b0fb5` | TVM API follow-up. |
| #3473 Add Qwen3.5 conversation templates | merged 2026-04-05, `d46f65fc` | Adds `qwen3_5` (thinking) and `qwen3_5_nothink`. |
| #3568 Add Qwen3.5 vision on the artifact manifest | merged 2026-10-01, `b84792ac` | Adds the `qwen3_5_vision` model type. On main only. |
| #3554, #3571 TVM submodule bumps | merged 2026-09-29 / 2026-10-04 | main needs a newer TVM than the nightly has. |
| #3480 Hybrid model upgrade (@babusid) | open since 2026-04-12 | Body: "we leverage the recurrent decode kernel for both prefill and decode". It ports a chunked GDN prefill, and notes that batch-size-1 methods "were previously disabled for hybrid models universally". |
| #3550 Strip reasoning in history for Qwen3.5 chat templates | open | Until it merges, history rendering differs from the HF template. |
| #3579 Add LFM2 support (@JCNTH) | open since 2026-10-17 | Independently confirms section 6: "prefix-cache forks ignore the fork position, PopN fails when `max_history` is 1, and speculative rollback is not supported". Also: "a 2-sequence `batch_prefill` fails … Qwen3.5 uses the same packed conv design without a cap". |
| #3489 Add qwen3 coder tool parser | closed unmerged 2026-04-25 (`9489dd7f`) | The closest prior art for G1 (section 8). |
| #3474 Qwen3.5 vision, first version | open | Superseded by #3568. |
| Issue #3448 Model Request: Qwen3.5 | closed | — |
| Issue #3492 POC for qwen3.5 / qwen3.6 on AGX Orin | open | An external fork, not upstream. |

### 2.2 Dual-state engine code (main@8978ea9a)

- `kHybrid = 3`, with the string form `"hybrid"`: `cpp/metadata/model.h:26-29`, `:39-40`,
  `:53-54`.
- `_infer_kv_state_kind` returns `"hybrid"` for any `model_type` containing `qwen3_5`
  (`python/mlc_llm/interface/compile.py:99-106`).
- The function table resolves both `create_tir_paged_kv_cache` and `create_rnn_state`
  (`cpp/serve/function_table.cc:243-247`).
- `CreateKVCache` creates both state objects (`cpp/serve/model.cc:908-930`):
  - RNN slots = `max_num_sequence + prefix_cache_max_num_recycling_seqs`;
  - RNN history = `max(max_history_size, 1)`.
- Fork, Remove and PopN are mirrored onto the RNN state (`model.cc:948-978`).
- Prefill packs every sequence into `(1, total_length, h)` and calls `BeginForward` on the
  RNN state with every sequence id (`model.cc:276-299`).

### 2.3 Qwen3.8-27B vs the upstream model code

| Item | Qwen3.8-27B | Upstream handling | Status |
| --- | --- | --- | --- |
| Layer pattern | `layer_types`: 48 linear / 16 full, interval 4 | Layer *i* is full attention iff (i+1) % 4 == 0 (`main:model/qwen35/qwen35_model.py:123-132`) | Matches; checked against the config. |
| Grouped value heads | 48 value / 16 key heads (ratio 3) | `kh = h_idx // heads_per_group` (`nightly:mlc_llm/model/qwen35/qwen35_model.py:282`; main `:241` plus use inside the blocks) | Generic, but ratio 3 is untested. The code comment says "1 for 0.8B, 2 for 4B". |
| Output head | Untied top-level `lm_head.weight` | The loader prefixes only `model.*` names (`nightly:…/qwen35_loader.py:129-131`) | Expected to work; untested upstream at 27B. |
| RoPE | Interleaved mRoPE `[11,11,10]` on 64 rotary dims | 1-D `RopeMode.NORMAL` with `rotary_dim = head_dim × 0.25` (`main:qwen35_model.py:769-795`) | Exact for text, where t = h = w. Not exact for images (M-RoPE TODO, `qwen35v_model.py:83-87`). |
| Context | `max_position_embeddings` 262144 | `context_window_size` defaults to that value (`qwen35_model.py:91-107`); `prefill_chunk_size` defaults to min(ctx, 2048) (`:108-111`) | Pass `--context-window-size 131072`. |
| Extra tensors | `mtp.*` (15) and `model.visual.*` (333) in the index | Not mapped by the text model. Qwen3.5-0.8B has the same tensor families. | The tiny run (4.1) exercises this. |
| Stop tokens | `<|im_end|>` = 248046, `<|endoftext|>` = 248044 | `stop_token_ids=[248046, 248044]` (`conversation_template/qwen3_5.py`) | Match; checked in `tokenizer.json`. |

### 2.4 The user's `feat/qwen3.5-support` branch

- **Not found anywhere.** None of these has it:
  - the refs, reflogs or stash of `serving/mlc-llm`, which `mlc-llm_2a` and `mlc-llm_2b`
    share as worktrees;
  - the 10 branches on `xthomaswang/mlc-llm`;
  - the `migration/*` branches from the 2026-09-29 move;
  - the backup manifests (`~/Archive/backup-2026-09-29.zip`, `3-manifest.jsonl.gz`).
- The old Mac's three checkouts held only upstream's `model/qwen35/` (from #3449). None had a
  `model/qwen3_5/` directory.
- **Upstream #3449 superseded it.** The memory note that describes the branch
  (`qwen35_integration.md`) is dated 2026-03-10. #3449, by another author, merged on
  2026-03-26 and implemented exactly that note's TODO list: `kHybrid` in `model.h`,
  `model.cc` and `function_table.cc`, plus `"hybrid"` in `_infer_kv_state_kind`.
- Current checkouts (read with read-only git commands; nothing changed):

  | Checkout | Commit | Branch |
  | --- | --- | --- |
  | `mlc-llm` | `c6f86e03` | `feature/embedding/decoder-first-class` |
  | `mlc-llm_2a` | `a4679d11` | `feature/embedding/single-task-serve` |
  | `mlc-llm_2b` | `354f6174` | `feature/embedding/cross-request-batching` |

  All three include #3449 through main, and none adds Qwen3.5 work.
- Dual-state engine support exists upstream only, since #3449.

## 3. Install

### 3.1 Done (executed 01:00–01:05)

```bash
git clone --filter=blob:none https://github.com/mlc-ai/mlc-llm.git ~/Developer/mlsys/serving/mlc-llm_bench   # main 8978ea9a, no submodules
cd ~/Developer/mlsys/serving/mlc-llm_bench
uv venv --python 3.12 .venv                       # CPython 3.12.14
mkdir -p .venv/wheels && cd .venv/wheels
B=https://github.com/mlc-ai/package/releases/download/v0.9.dev0
curl -fsSLO "$B/mlc_llm_nightly_cpu-0.26.dev6-py3-none-macosx_26_0_arm64.whl"
curl -fsSLO "$B/mlc_ai_nightly_cpu-0.26.dev246-py3-none-macosx_26_0_arm64.whl"
cd ../.. && uv pip install --python .venv/bin/python .venv/wheels/*.whl   # 74 packages
```

| Artifact | Built | sha256 (matches the GitHub release digest) |
| --- | --- | --- |
| `mlc_llm_nightly_cpu-0.26.dev6-py3-none-macosx_26_0_arm64.whl` (21.1 MB) | 2026-08-24 | `cab4ad761d60e71068c61d576a8a21308700d040d758562b6db5fffed2768b66` |
| `mlc_ai_nightly_cpu-0.26.dev246-py3-none-macosx_26_0_arm64.whl` (66.5 MB) | 2026-08-24 | `935d2a55238b0cb14738c913bb6d50580f6bdc418696ef0d85e4eb6c15fa26cc` |

- **These are the newest macOS arm64 wheels.** That is the pair https://mlc.ai/wheels lists,
  confirmed against the asset dates of the `v0.9.dev0` release on 2026-10-18. It is also the
  documented macOS install (`main:docs/install/mlc_llm.rst:95-101`).
- **The nightly is `main@9fa644f5` (2026-08-17).** The git blob hashes of the wheel's Python
  files match that commit; for example, all three files #3534 touched match it exactly.
  - So the nightly contains #3449, #3465, #3473 and #3505.
  - It lacks #3554, #3568 and #3571: no vision, older TVM.
- **The gate-relevant files are identical in the nightly and on main**
  (`git diff --stat 9fa644f5 8978ea9a`): `openai_api_protocol.py`, `engine_base.py`,
  `engine.py`, `cli/serve.py`, `conversation_template/qwen3_5.py` and `prefix_cache.cc`.
- Installed versions: `mlc-llm-nightly-cpu 0.26.dev6`, `mlc-ai-nightly-cpu 0.26.dev246`,
  `apache-tvm-ffi 0.1.14.post1`, `torch 2.14.1`, `transformers 5.20.1`, `numpy 2.5.4`. The
  log is `logs/mlc-llm-install.log`.
- **There is no `mlc_llm` executable.** The wheel ships no `entry_points.txt`. Use
  `python -m mlc_llm …`; the subcommands are listed at `nightly:mlc_llm/__main__.py:17-27`.

### 3.2 Blocker: invalid code signatures (the user must run one command)

**Executed:** `python -I -c "import tvm"` exits with 137.
- The crash report `~/Library/Logs/DiagnosticReports/python3.12-2026-10-18-010303.ips` reads
  `"signal":"SIGKILL (Code Signature Invalid)"`, with termination namespace `CODESIGNING` and
  indicator `Invalid Page`.
- `import tvm_ffi` alone works.

`codesign -v` reports "invalid signature (code or signature have been modified)" for every
TVM/MLC dylib in the wheels:
- `tvm/lib/libtvm_runtime.dylib`, `libtvm_compiler.dylib`, `libtvm_runtime_metal.dylib`,
  `libtvm_runtime_extra.dylib`;
- `mlc_llm/lib/libmlc_llm.dylib`, and the others.

`tvm_ffi/lib/libtvm_ffi.dylib`, which is linker-signed, is valid. The binaries were evidently
modified after linking without being re-signed, and arm64 macOS kills any process that maps
such pages.

This is the root cause behind the note in `~/Developer/dotfiles/3_新机状态与使用.md`
("mlc-main nightly 尚未可用：0.26.dev246 / 0.26.dev6 在本机导入时发生原生库 abort；重建 FFI
后仍复现"). The FFI was never the problem.

**Fix.** It re-signs the shipped bytes ad hoc, touches only files inside this venv, and
changes no system setting. The auto-mode classifier blocked the agent from running it, so
run it yourself if you accept it. Re-run it after any reinstall of the wheels.

```bash
S=~/Developer/mlsys/serving/mlc-llm_bench/.venv/lib/python3.12/site-packages
find "$S/tvm" "$S/mlc_llm" -type f \( -name '*.dylib' -o -name '*.so' \) -exec codesign --force --sign - {} +
find "$S/tvm" "$S/mlc_llm" -type f \( -name '*.dylib' -o -name '*.so' \) -exec codesign -v {} \;   # no output = OK
~/Developer/mlsys/serving/mlc-llm_bench/.venv/bin/python -c "import tvm, mlc_llm; print(tvm.__file__, mlc_llm.__file__)"
```

### 3.3 Alternative: build main from source (not run; only for vision/G2)

Not recommended for this benchmark: G1, G3 and G4 fail on main too. If G2 must be measured:

- **Prerequisites (all present):** cmake 4.4.3, ninja 1.13.2, Rust/cargo 1.98.1, Homebrew
  LLVM 23.1.2 (`/opt/homebrew/opt/llvm/bin/llvm-config`), Metal toolchain 27.1, git 2.56.
- **Sources for the steps:** `main:docs/install/tvm.rst:176-240` and
  `main:docs/install/mlc_llm.rst:175-245`, plus the flags in
  `~/Developer/dotfiles/2_单独环境.md` §C2 (TVM: RelWithDebInfo + LLVM + Metal; MLC: Release + Metal).
- **Steps:**
  1. `git submodule update --init --recursive`.
  2. Configure and build `3rdparty/tvm` with `USE_METAL=ON` and
     `USE_LLVM=/opt/homebrew/opt/llvm/bin/llvm-config`.
  3. Build MLC: `python cmake/gen_cmake_config.py` (choose Metal), then `cmake` and build.
  4. Install the TVM and MLC Python packages editable into a separate venv (for example
     `.venv-src`), next to a matching `apache-tvm-ffi`.
- **Cost:** roughly 20–45 min of CPU (estimate) and about 0.5–1 GB of submodule clones.
  Linker-signed outputs need no re-sign.
- This path was not validated.

## 4. Pipeline (not run)

All commands run inside the venv and use `python -m mlc_llm` (section 3.1). Run section 3.2
first.

```bash
cd ~/Developer/mlsys/serving/mlc-llm_bench && source .venv/bin/activate
export HF_HOME=~/Developer/ml_source/huggingface
mkdir -p ~/Developer/mlsys/models/mlc/libs
```

### 4.1 Tiny validation: Qwen3.5-0.8B (CPU only; no GPU lock needed)

`Qwen/Qwen3.5-0.8B` was added to the HF cache for this check (1.77 GB, snapshot
`2fc06364715b967f1860aea9cf38778875588b17`).
- **What it checks:** it has the same tensor families as the 27B (`model.language_model.*`,
  `model.visual.*`, `mtp.*`). So it validates the loader, the conversion and the Metal
  codegen.
- **What it doesn't check:** its embeddings are tied and its grouped-value ratio is 1, so it
  says nothing about the 27B's untied head or its ratio-3 heads.

```bash
SRC=$HF_HOME/hub/models--Qwen--Qwen3.5-0.8B/snapshots/2fc06364715b967f1860aea9cf38778875588b17
DST=~/Developer/mlsys/models/mlc/Qwen3.5-0.8B-q4f16_1-MLC
python -m mlc_llm convert_weight "$SRC" --quantization q4f16_1 --model-type qwen3_5 --device cpu --output "$DST"
python -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 --conv-template qwen3_5_nothink \
  --context-window-size 131072 --prefill-chunk-size 2048 --max-batch-size 4 --output "$DST"
python -m mlc_llm compile "$DST/mlc-chat-config.json" --device metal \
  --output ~/Developer/mlsys/models/mlc/libs/Qwen3.5-0.8B-q4f16_1-ctx131072-metal.so
```

- **Expected outputs:**
  - `$DST/` holds `mlc-chat-config.json`, `tensor-cache.json`, `params_shard_*.bin` and the
    tokenizer files, about 0.4–0.5 GB in total. The user's March run gave 0.395 GB at 3.88
    bits/param.
  - The `.so` in `libs/`.
  - A few minutes in total (estimate).
- **Time the convert step.** The 27B has about 34× the parameters, so this calibrates the
  27B CPU estimate.
- **No kernels run on the GPU.** `--device cpu` keeps quantization on the CPU.
  `compile --device metal` creates a Metal device only to read its limits
  (`nightly:mlc_llm/support/auto_target.py:86-103`).
- The `metal:generic` preset avoids even that query, but it sets `thread_warp_size=1` and
  256 threads per block (`auto_target.py:531-538`). That gives slower kernels, so don't use it
  for benchmark artifacts.

### 4.2 Qwen3.8-27B, q4f16_1

- **Format:** `q4f16_1` stores 4-bit weights in groups of 32 with fp16 scales, i.e. 4.5 bits
  per weight. It is the closest MLC format to MLX affine 4-bit g64, which is also 4.5 bits
  per weight (scale and bias per 64). It is not bit-identical to the other 4-bit rows.
- **Check the BF16 snapshot first:**

  ```bash
  /usr/bin/python3 -I ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/scripts/hf_snapshot.py Qwen/Qwen3.8-27B --safetensors   # exit 0 = complete
  ```

Then run:

```bash
SRC=$HF_HOME/hub/models--Qwen--Qwen3.8-27B/snapshots/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0
DST=~/Developer/mlsys/models/mlc/Qwen3.8-27B-q4f16_1-MLC
LIB=~/Developer/mlsys/models/mlc/libs/Qwen3.8-27B-q4f16_1-ctx131072-metal.so

# 1. Weights. GPU variant (fast; run it under the GPU lock): --device metal
#    CPU variant (no lock; slower): replace with --device cpu
python -m mlc_llm convert_weight "$SRC" --quantization q4f16_1 --model-type qwen3_5 --device metal --output "$DST"

# 2. Chat config: thinking off, 131072 context
python -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 --conv-template qwen3_5_nothink \
  --context-window-size 131072 --prefill-chunk-size 2048 --max-batch-size 4 --output "$DST"

# 3. Model library (CPU work; Metal device query only)
python -m mlc_llm compile "$DST/mlc-chat-config.json" --device metal --output "$LIB"

# 4. Thinking-on chat config for G4 (same weights and the same library)
python -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 --conv-template qwen3_5 \
  --context-window-size 131072 --prefill-chunk-size 2048 --max-batch-size 4 --output "$DST-think"
ln -s "$DST"/params_shard_*.bin "$DST/tensor-cache.json" "$DST-think"/
```

- **The weight index is `tensor-cache.json`.** `convert_weight` writes it through
  `tvmjs.dump_tensor_cache` (`nightly:mlc_llm/interface/convert_weight.py:190`;
  `nightly:tvm/contrib/tvmjs.py:259`), so the `ln -s` in step 4 links the right file. Confirm
  with `ls "$DST"` after the tiny run.
- **Pass `--model-type qwen3_5` explicitly.** On a `main` build, `auto` would resolve this
  config to `qwen3_5_vision`, because it has a `vision_config`
  (`main:python/mlc_llm/support/auto_config.py:117`). For a vision artifact on main, pass
  `--model-type qwen3_5_vision`.
- **Estimates:**
  - Output: about 15.1 GB (14.1 GiB), from 26.9 B text parameters at 4.5 bits.
  - Convert: 10–20 min on Metal, or 20–60 min on CPU; peak RAM 10–20 GB.
  - Compile: 5–15 min of CPU.
  - Disk: 1.2 TiB free.

## 5. Serve (port 8700)

The repo's `scripts/serve.sh` and `scripts/lib.sh` know neither mlc-llm nor port 8700
(`OUR_PORTS="8701 8702 8703 8704 8705"` in `lib.sh`), so launch manually. Use port 8700 only.

```bash
cd ~/Developer/mlsys/serving/mlc-llm_bench && source .venv/bin/activate
python -m mlc_llm serve ~/Developer/mlsys/models/mlc/Qwen3.8-27B-q4f16_1-MLC \
  --model-lib ~/Developer/mlsys/models/mlc/libs/Qwen3.8-27B-q4f16_1-ctx131072-metal.so \
  --device metal --mode interactive \
  --prefix-cache-mode disable \
  --overrides "context_window_size=131072;max_total_seq_length=131072;prefill_chunk_size=2048" \
  --enable-debug \
  --host 127.0.0.1 --port 8700 \
  2>&1 | tee ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/mlc-llm-serve-4bit.log
```

Why each flag:
- **`--mode interactive`** sets `max_num_sequence=1` (`nightly:mlc_llm/interface/help.py:177-194`).
  This is required while packed multi-sequence prefill breaks the GDN state (section 6.2).
- **`--prefix-cache-mode disable`**: the default, `radix`, is unsafe for hybrid models
  (section 6.1).
- **`--enable-debug`** makes `usage.extra` carry `prompt_tokens`, `prefill_tokens`, `ttft_s`
  and more (`main:cpp/serve/metrics.cc:77-91`).
  - Cached tokens = `prompt_tokens − prefill_tokens`, which is always 0 with the prefix cache
    off.
  - There is no `usage.prompt_tokens_details` (`main:python/mlc_llm/protocol/openai_api_protocol.py:56-60`).
- **Thinking-on runs (G4):** serve `…-MLC-think` instead, with the same `--model-lib`.
- **Startup (estimate):** about 1–2 min, for 15 GB of weights plus Metal shaders compiled from
  source at load.

Harness notes for this server. Together they mean a separate MLC request path in the
harness (no `tools` field, schemas inlined as text, flattened tool history). That is a code
change rather than a flag, so budget for it before scheduling MLC runs.
- **`model` may be omitted or set to anything.** With one model served, `get_engine` returns
  it (`main:python/mlc_llm/serve/server/server_context.py:50-55`).
- **Don't send `tools`, `tool`-role messages or assistant `tool_calls`** (G1).
  - For the text-only rows, render the tool schemas into the system message as plain text.
    That keeps prompt lengths comparable with the other frameworks.
- **Always send a system message.** MLC inserts "You are a helpful assistant." when there is
  none (`conversation_template/qwen3_5.py`); the HF template inserts nothing.
- **Unknown fields should be ignored, not rejected** — **verify**. This covers
  `chat_template_kwargs` and `reasoning_effort`. `openai_api_protocol.py` sets no pydantic
  `extra=` option, so the default is to ignore them.
- **Don't use `response_format`.** Grammar jump-forward rolls tokens back through `PopN`
  (`cpp/serve/engine_actions/batch_jumpforward.cc:85`, `batch_decode.cc:285-289`), which fails
  on the RNN state (section 6.1).
- **Stop this server yourself before releasing the lock.** `gpu_lock.sh release` checks only
  ports 8701–8705.

## 6. Hybrid-state limits (why the flags in section 5 are mandatory)

### 6.1 The prefix cache (radix, the default) is unsafe

- **Forks copy the wrong state.** `RNNState::ForkSequence` ignores `fork_pos` and copies the
  parent's current state (`tvm:src/runtime/vm/rnn_state.cc:338-357`; `Sequence::Fork` copies
  the parent's length, `:61-65`). The paged KV cache, by contrast, forks at `fork_pos`.
  - A child forked from a longer sequence therefore gets a GDN state that already includes
    the parent's later tokens.
  - The output is silently wrong.
- **Rollback is impossible.** `PopN` ICHECKs `n <= available_history_num`
  (`rnn_state.cc:361-374`).
  - Any prefill resets that count to 0 (`EndForward`, `:237-252`, reset at `:245-247`).
  - On the hybrid path the history length is 1 anyway, through this chain:
    1. `ModelsUseKVCache` treats every non-`rwkv` model as a KV-cache model
       (`cpp/serve/config.cc:1065-1068`).
    2. So `InferForKVCache` runs, and it sets `max_history_size = 0` (`config.cc:899`).
    3. `CreateKVCache` turns that into `max(0, 1) = 1` (`model.cc:926-927`).
    4. As a result, `available_history_num` stays 0.
- **The radix cache takes both broken paths** (`cpp/serve/prefix_cache.cc`):
  - when `matched_offset > 0.9 × length`, it reuses a recycled sequence and rolls back its
    tail (`:102-111`);
  - otherwise it forks (`:114-135`).
  - The engine applies both (`cpp/serve/engine_actions/new_request_prefill.cc:317-341`).
- **M1 hits the rollback branch.** Its shape (a 15K shared prefix of a ~16.6K previous
  request) leads to `PopN(~1.6K)`, which fails the ICHECK.
  - `RunBackgroundLoop` has no try/catch (`cpp/serve/threaded_engine.cc:136`), so expect the
    engine loop to die — **verify**.
- The default mode is radix (`cpp/serve/config.h:287`; the `--prefix-cache-mode` default at
  `cli/serve.py:161-166`).

### 6.2 Packed multi-sequence prefill breaks

- **The batch sizes don't match.**
  - `batch_prefill` takes `input_embeds [1, seq_len, H]` with every sequence packed into one
    row (`main:qwen35_model.py:807-808`; `model.cc:276-299`).
  - The GDN layer reads and writes the RNN state with batch `b = 1`
    (`qwen35_model.py:406-475`; `state.get` at `:423` and `:454`).
  - The RNN get/set kernels bind `batch_size` from the sequence-id buffer (N) and require
    the output buffer to match (`main:python/mlc_llm/nn/rnn_state.py:178-208`).
  - So with N > 1 the call fails. Even if it didn't, the conv and the recurrence would run
    across sequence boundaries.
- **Any concurrency can trigger it:**
  - `prefill_mode=hybrid`, the default (`cli/serve.py:168-173`), merges running decodes into a
    new request's prefill;
  - the new-request action packs several pending requests into one prefill.
- #3579 reports the same failure on LFM2 ("a 2-sequence `batch_prefill` fails") and says
  Qwen3.5 shares the design.
- **Decode batching itself is fine**, since `batch_decode` has a real batch dimension. But
  there is no safe way to get two sequences into it.
- Hence `--mode interactive`, which makes M5 measure queueing. **Verify** with a
  two-request probe at `max_num_sequence=2`.

### 6.3 Speculative decoding: N/A

- MLC's modes are `small_draft`, `eagle` and `medusa` (`cli/serve.py`). None works here:
  - the qwen35 model has no MTP support (its `mtp.*` tensors aren't mapped);
  - no EAGLE or Medusa heads exist for Qwen3.8;
  - rejected draft tokens are rolled back with `PopN` on the target, which fails (6.1).
- #3579 says the same: "speculative rollback is not supported".
- Record M3 spec-on as N/A.

### 6.4 Prefill speed

- **The GDN prefill runs sequentially.** The kernel loops `for t in range(seq_len)` per
  thread (`main:qwen35_model.py:222-345`, loop at `:278`).
  - There is one threadgroup per (sequence, value head): 48 × 128 threads at batch 1
    (`:268-270`).
- #3480 (open) exists because prefill reuses this decode kernel.
- Expect M2 to come in below the MLX stacks and llama.cpp. Give the G5 64K probe a generous
  timeout (≥ 15 min).

## 7. Gate expectations (G1–G5)

| Gate | Expectation | Evidence |
| --- | --- | --- |
| G1 | **fail** | See "G1 evidence" below the table. |
| G2 | **fail** on the nightly; **degraded, verify** on main | See "G2 evidence" below the table. |
| G3 | **fail** | See "G3 evidence" below the table. |
| G4 | **fail** per request | See "G4 evidence" below the table. |
| G5 | **memory: pass (estimate); time: verify** | See "G5 evidence" below the table. |

**G1 evidence.**
1. **Tools never reach the prompt.** The `qwen3_5` template has no `{function_string}`
   placeholder (`conversation_protocol.py:218-224`; template file).
2. **Every answer to a request with `tools` is treated as a tool call.**
   - The finish reason is always reported as `tool_calls` (`serve/engine_base.py:849-850`).
   - The non-streaming path parses the output as a Python call with `ast.parse`
     (`engine_base.py:1154-1213`).
   - So a Qwen XML call, or a plain answer, comes back as `finish_reason="error"` with
     "Got an invalid function call output from model".
3. **Streaming never builds `tool_calls` deltas.** The stream path only forwards text
   (`engine_base.py:781-889`; `serve/entrypoints/openai_entrypoints.py:262-286`), and parsing
   happens only in the non-streaming branch (`:327`). Markup therefore leaks into `content`.
4. **History is rejected:**
   - an assistant message with `tool_calls` → 400 "not supported yet"
     (`openai_api_protocol.py:361-364`);
   - a `tool` message → `ValueError`, because the role is not in the template
     (`conversation_protocol.py:157-158`).

**G2 evidence.**
- The nightly has no `qwen35v_*` files.
- On main, `qwen3_5_vision` (#3568) stretches every image to 448×448
  (`cpp/support/vlm_utils.cc:31-33,53-55`; manifest at `qwen35v_model.py:338`).
  - That gives (448/16/2)² = 196 image tokens (`serve/data.py:155-159`); the other frameworks
    use 1280.
  - Image tokens get 1-D positions (M-RoPE TODO, `qwen35v_model.py:83-87`).
- A 1280×1024 screenshot shrinks by 2.9× horizontally and 2.3× vertically, with a distorted
  aspect ratio, so reading a small rendered code may fail.

**G3 evidence.**
- The only routes are `/v1/embeddings`, `/v1/models`, `/v1/completions` and
  `/v1/chat/completions` (`openai_entrypoints.py:45,120,132,236`), plus the debug, metrics
  and microserving routes.
- Neither "anthropic" nor `/v1/messages` appears anywhere in `python/` or `cpp/`.
- A translating proxy would hit G1 anyway.

**G4 evidence.**
- **No control fields.** `ChatCompletionRequest` has no `chat_template_kwargs`,
  `enable_thinking` or `reasoning_effort` (`openai_api_protocol.py:258-284`), and none of
  these names appears in `serve/` or `protocol/`.
- **Thinking is fixed per chat config:**
  - `qwen3_5` opens `<think>`; `qwen3_5_nothink` pre-fills an empty block (#3473).
  - The nothink generation prompt equals HF's `enable_thinking=false` output
    (`<think>\n\n</think>\n\n`).
  - The thinking template lacks the reasoning-effort system line that HF adds.
  - So the only toggle is the template, through two chat configs (section 4.2 step 4).
- **No reasoning separation.** There is no `reasoning_content` (`ChatCompletionMessage`,
  `:250-255`); thinking text arrives in `content`.

**G5 evidence.**
- KV is 64 KiB per token (16 layers × 2 × 4 heads × 256 × 2 B), i.e. 8.0 GiB at 131072
  tokens.
- RNN state is 147 MiB per slot, with 2 slots.
- Weights are 14.1 GiB, so the total is about 24 GiB plus temporary buffers.
- 262144 is the model's limit, so 131072 is allowed.
- Prefill speed: see 6.4.

## 8. What passing the gate would take (rough effort; nothing implemented)

| Item | Change | Files | Effort |
| --- | --- | --- | --- |
| G1 | Render Qwen tool schemas (FUNCTION placeholder); parse the XML `<tool_call><function=…><parameter=…>` format with streaming deltas; support the `tool` role; accept assistant `tool_calls` in history; stop forcing `finish_reason` | `conversation_template/qwen3_5.py`, `protocol/conversation_protocol.py`, `protocol/openai_api_protocol.py`, `serve/engine_base.py`, `serve/engine.py`, `serve/entrypoints/openai_entrypoints.py` | 2–4 days of Python. #3489 (closed unmerged, `9489dd7f`) is a partial start: a parser interface, streaming parse, and tool-role rendering. |
| G4 | Per-request `chat_template_kwargs.enable_thinking` and `reasoning_effort` that choose the assistant prefix; optionally a reasoning parser feeding `reasoning_content` | protocol, `engine_base.py`, template | about 1 day |
| G3 | A `/v1/messages` router that translates to the chat path (text, `tool_use`, images, streaming events) | new entrypoint module | 1–2 days, after G1 |
| Hybrid prefix cache | RNN-state snapshots at fork points, or checkpoints every N tokens; fork-at-position; a history length on the hybrid config path | `3rdparty/tvm/src/runtime/vm/rnn_state.cc`, `cpp/serve/config.cc`, `cpp/serve/prefix_cache.cc` | 1–2 weeks of C++ |
| Concurrency | Per-sequence offsets in the GDN and conv kernels, or one prefill per sequence | `model/qwen35/qwen35_model.py`, maybe `cpp/serve/model.cc` | 2–4 days |
| Prefill speed | A chunked GDN kernel | #3480 (open) | already written, not merged |

No existing branch, upstream or the user's, covers G1, G3, G4 or the hybrid prefix cache.

## 9. Status / remaining work (2026-10-18 01:30)

**State**
- **Checkout and venv.** `~/Developer/mlsys/serving/mlc-llm_bench` is a clone of
  `main@8978ea9a` (no submodules) with a `.venv` holding the two nightly wheels.
  - The wheels are sha256-verified, and copies are kept in `.venv/wheels/`.
  - **The venv is not importable until section 3.2 is run.**
- **Tiny checkpoint.** `Qwen/Qwen3.5-0.8B` was added to the HF cache (add-only).
- **Nothing else has run.** `~/Developer/mlsys/models/mlc/` is still empty. No GPU was used,
  no lock was taken, and no server was started.
- **Not touched:** the user's MLC checkouts, the conda envs, and the other sessions' files.
- **Docs.** MLC (port 8700) is not yet in `README.md`'s status table or in `resume.md`.

**Steps for the user or coordinator, in order**

| # | Step | GPU | Time (estimate) | Memory (estimate) |
| --- | --- | --- | --- | --- |
| 1 | Section 3.2: re-sign the dylibs, then check the import | no | < 1 min | — |
| 2 | Section 4.1: tiny convert, gen_config and compile | no (device query only) | 3–5 min | < 4 GB |
| 3 | Section 4.2: 27B `convert_weight`, either `--device metal` under the lock or `--device cpu` | Metal variant only | 10–20 min (Metal) / 20–60 min (CPU) | 10–20 GB RAM peak |
| 4 | Section 4.2: `gen_config` ×2 and `compile` | no (device query only) | 5–15 min | < 8 GB |
| 5 | Section 5: serve and the gate probes on port 8700, under the lock | yes | 1–2 min startup, plus probes | about 24–26 GiB resident at 131072 |

**Open questions for the first live run**
1. Does the server come up with `--mode interactive --prefix-cache-mode disable`? Record the
   KV and temporary memory it logs.
2. Is 27B output coherent? Ratio-3 grouped value heads and the untied head are untested
   upstream; a short greedy answer must make sense.
3. Does G1 behave as predicted? Record the `finish_reason` with `tools`, and the HTTP codes
   for `tool` and `tool_calls` history.
4. Are unknown fields ignored, rather than rejected with 422?
5. G5 and M6: 64K prompt prefill time and peak memory.
6. Optional crash probes, never during timed runs: the radix prefix cache with an M1-shaped
   request pair, and two concurrent requests at `max_num_sequence=2`.

## 3.2a Result after re-signing (2026-10-18 01:30, run with the user's approval)

- **Re-signing.** The ad-hoc re-sign from §3.2 ran over the 10 TVM/MLC dylibs in
  `serving/mlc-llm_bench/.venv`. `codesign -v` is clean, and the `SIGKILL (Code Signature
  Invalid)` is gone.
- **`import tvm` now aborts instead** (exit 134, `SIGABRT`).
  - faulthandler stack: `tvm/__init__.py:126` → `_autoload_backends` →
    `_load_builtin_backends` → ctypes load of `tvm_runtime_extra`.
  - Crash report: `abort() called` from
    `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED`, inside a static
    initializer of `libtvm_runtime_extra.dylib`, run by dyld.
- **The two wheels ship different TVM runtimes.**
  - `tvm/lib/libtvm_runtime.dylib` is 2,696,064 B; `mlc_llm/lib/libtvm_runtime.dylib` is
    2,300,000 B.
  - `libtvm_runtime_extra.dylib` is the same size in both.
- **Disabling backend autoload doesn't help.**
  - With `TVM_DEVICE_BACKEND_AUTOLOAD=0`, `import tvm` succeeds, but `import mlc_llm` then
    fails: `Library not loaded: @rpath/libtvm_runtime_extra.dylib` from
    `mlc_llm/libmlc_llm_module.dylib`.
  - This matches the dotfiles note (`3_新机状态与使用.md`, "nightly … 导入时发生原生库 abort").
- **Verdict.** The nightly wheels can't run on this machine (macOS 27.2 beta 26B5101f).
  MLC-LLM needs a source build of TVM + MLC-LLM against the local toolchain (§3.3). Estimate:
  1–2 h of build and debugging, no GPU needed. That is not "simple support", and the
  framework would still fail the agent gate (G1, G3, G4). **MLC-LLM is parked as blocked**
  unless the user asks for the source build.
