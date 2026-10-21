# MLC-LLM — verdict, environment and launch notes (Qwen3.8-27B)

First recorded 2026-10-18 01:30 EDT (code study, nightly wheels). **Updated 2026-10-18
02:30 EDT.** The update covers:
- a source build of TVM + MLC-LLM;
- the CPU-only artifact pipeline for Qwen3.5-0.8B and Qwen3.8-27B;
- the structured-output, tools, usage and thinking research for the harness (5.3–5.7).

Still nothing has run on the GPU: no server was started, no model was loaded, and the GPU
lock was never taken. Claims cite `file:line`, PR numbers or commits. Items marked
**executed** were run; items marked **verify** need a live run under the GPU lock.

- Machine: MacBook Pro M5 Max (18-core CPU, 40-core GPU, 128 GB). macOS 27.2, build 26B5101f
  (`sw_vers`). Xcode 27.1, build 27A9275 (`xcodebuild -version`), is the default; SDK
  MacOSX 27.0. `xcode-select` was not changed.
- Upstream source: `~/Developer/mlsys/serving/mlc-llm_bench`, a fresh clone of
  `mlc-ai/mlc-llm` at `main` = `8978ea9a` (2026-10-06, "[Serve] Pass token ids to models
  that look them up at every layer (#3565)"). That is upstream main on 2026-10-18
  (`gh api repos/mlc-ai/mlc-llm/commits/main`).
  - Submodules are now checked out recursively (section 3.1).
  - The pinned TVM is `mlc-ai/relax@201fa000`.
- Venv: `~/Developer/mlsys/serving/mlc-llm_bench/.venv` (uv, CPython 3.12.14). It now holds
  **source-built, editable** TVM and MLC-LLM (section 3).
  - The nightly wheels were uninstalled; section 3.3 says why.
  - Copies of the wheels stay in `.venv/wheels/`.
- **Deleted 2026-10-21.** The campaign closed and this build tree was removed to free disk.
  - Its four driver scripts are kept in this repo as [`bench-tools/`](bench-tools/),
    unchanged, so they still name their original paths.
  - The build and pipeline logs are kept only in the local, gitignored `logs/mlc-build/`,
    because they contain absolute local paths.
- Model: `Qwen/Qwen3.8-27B` BF16, snapshot `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`. It is
  complete: 18 shards, 55.56 GB (`scripts/hf_snapshot.py --safetensors`, exit 0, 02:00).
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
  - `main:` is the clone at `8978ea9a` (paths relative to `python/mlc_llm/` or `cpp/` as
    written). This is also what is installed now.
  - `nightly:` was `.venv/lib/python3.12/site-packages/` while the nightly wheels
    (`main@9fa644f5`) were installed. They are now removed.
    - The gate-relevant files are identical on main (`git diff --stat 9fa644f5 8978ea9a`):
      `openai_api_protocol.py`, `engine_base.py`, `engine.py`, `cli/serve.py`,
      `conversation_template/qwen3_5.py`, `prefix_cache.cc`.
    - Other `nightly:` line numbers may be a few lines off on main.
  - `tvm:` is `mlc-ai/relax@201fa000`, now checked out at `3rdparty/tvm`.

## 1. Verdict

**Supported with caveats for text-only serving. Fails the agent gate (G1, G3, G4) at the
code level, so it is eligible only for METHODOLOGY's text-only reference row.**

- **The hybrid architecture is supported upstream end to end, including `mlc_llm serve`.**
  PR #3449 (merged 2026-03-26, `05f79e11`) added the Qwen3.5 GDN model. It also added a
  `kHybrid` KV-state kind that drives a PagedKVCache and an RNNState together. Qwen3.8-27B
  uses the same `qwen3_5` architecture (section 2.3). No PR or issue names Qwen3.6 or 3.8.
- **The nightly wheels cannot run on this machine; a source build replaces them (executed).**
  - TVM `201fa000`, its tvm-ffi and tvm-ffi-orcjit, and MLC-LLM `8978ea9a` are built from one
    tree with Metal and Homebrew LLVM 23.1.2, in about 6 min of CPU (section 3).
  - `python -I -c "import tvm, mlc_llm"` works, and every dylib is mapped once.
  - The Qwen3.5-0.8B and Qwen3.8-27B q4f16_1 artifacts are built on CPU (section 4).
- **Vision is in the source build, but not in these artifacts.** Qwen3.5 vision (#3568) is on
  main, but the artifacts here are text-only (`--model-type qwen3_5`). A `qwen3_5_vision`
  build is listed in section 9.
- **Correct serving needs `--prefix-cache-mode disable` and one sequence at a time
  (`--mode interactive`).** Without both, the RNN (GDN) state is forked wrongly, rolled back
  past its history, or read with the wrong batch size (section 6). The consequences:
  - no prefix reuse, so M1 and M4 run a cold prefill every step;
  - no concurrency, so M5 is serialized;
  - no speculative decoding, so M3 spec-on is N/A.
- **131072 context needs an explicit `max_total_seq_length`.** On Metal the engine caps the KV
  cache at 32768 tokens unless `max_total_seq_length` is overridden
  (`cpp/serve/config.cc:752-757`, `:769-771`). See section 5.2.
- **Structured output (xgrammar) needs constraint mode.** It works through MLC's own
  `response_format` shape, but only with `debug_config.grammar_execution_mode = "constraint"`
  and `--enable-debug`. The default jump-forward mode rolls tokens back through `PopN`, which
  the GDN state cannot do (sections 5.3–5.4).
- **Thinking is fixed per chat config.** No request can turn it on or off. The default
  artifact is thinking-off; a `-think` twin shares weights and library (section 5.7).
- **The 27B is untested upstream.** #3449 tested 0.8B to 9B. Prefill also reuses the
  sequential recurrent decode kernel (#3480 is open), so expect slow prefill.

| Gate | Expectation | Short reason (details in section 7) |
| --- | --- | --- |
| G1 OpenAI streaming + Qwen XML tool calls | **fail** | No Qwen XML parser, and `tools` never reach the prompt. Streaming never emits `tool_calls`. History containing `tool_calls` or `tool` messages is rejected. Plain streaming text works. |
| G2 image input | **degraded, verify**; needs a `qwen3_5_vision` artifact, which was not built | The source build is main, so the vision model exists. Every image is stretched to 448×448 (196 tokens) and given 1-D positions. The text-only artifacts in section 4 have no vision encoder. |
| G3 `/v1/messages` | **fail** | No route. |
| G4 thinking control | **fail** per request | No `chat_template_kwargs` or `reasoning_effort`. Thinking is fixed per `mlc-chat-config.json` (`qwen3_5` vs `qwen3_5_nothink`), and reasoning is not separated from `content`. |
| G5 context ≥ 64K | **memory: pass (estimate); time: verify** | About 24–26 GiB resident at 131072 tokens, but only with `--overrides "max_total_seq_length=131072"`: Metal otherwise caps the cache at 32768. The speed of a 64K cold prefill is unknown. |

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

## 3. Install: source build (executed 01:34–02:12)

The build follows MLC's "Build from Source" (`main:docs/install/mlc_llm.rst:160-245`) and the
TVM page it points to (`3rdparty/tvm/docs/install/from_source.rst`, steps 2–4).
- **CPU courtesy.** Every compile ran through [`bench-tools/heavy.py`](bench-tools/heavy.py),
  a wrapper that never compiles while `local_ai-benchmark` holds the GPU lock.
  - It SIGSTOPs the process group if that lock appears mid-run.
  - It runs at `nice 19` with at most 8 jobs under another session's lock, and at full speed
    with no lock.
  - The drivers are `bench-tools/build_all.sh` and `bench-tools/pipeline.sh <tiny|27b>`.
  - Timeline: it waited 01:59–02:01 and 02:02–02:05. Every compile then ran with no lock
    held, at 18 jobs, and none had to be paused.
  - Only setup work ran while the lock was held: cloning the submodules, writing the
    configs, and one 5-second CMake configure at `nice 19`.
- **Nothing outside the bench checkout.** No `brew install`, no conda, no global pip, no
  `xcode-select`.

### 3.1 Toolchain, sources and steps

| Item | Version |
| --- | --- |
| Compiler | Apple clang 21.0.0 (clang-2100.3.34.2), Xcode 27.1 (27A9275), SDK MacOSX 27.0 |
| LLVM | Homebrew `llvm` **23.1.2** (`/opt/homebrew/opt/llvm@23`), linked statically (`llvm-config --ignore-libllvm --link-static`). Its static libraries target the system `/usr/lib/libc++.1.dylib`, so they are ABI-safe with Apple clang. |
| Build tools | CMake 4.4.3, Ninja 1.13.2, ccache 4.14.1 (Homebrew); cargo/rustc 1.98.1 (rustup) |
| Python | uv 0.12.19, CPython 3.12.14 |
| Build backends in the venv | scikit-build-core 1.1.1, setuptools-scm 10.3.4, cython 3.3.0, mlc-z3-static 4.16.0 |
| Z3 | Homebrew z3 5.1.0, linked dynamically. Homebrew LLVM's static libraries need it, and TVM's `USE_Z3=AUTO` binds all 117 of its Z3 imports to it. The installed mlc-z3-static ends up unused. |

| Component | Commit | Installed as |
| --- | --- | --- |
| MLC-LLM | `mlc-ai/mlc-llm@8978ea9a` (2026-10-06) | `mlc-llm 0.20.0.dev0`, editable (`python/mlc_llm`, libs in `build/`) |
| TVM | `mlc-ai/relax@201fa000` (2026-10-03, "[HotFix] Skip sw pipeline for dlight gemm for low SM") | `apache-tvm 0.26.dev529`, editable (`3rdparty/tvm/python`, libs in `3rdparty/tvm/build/lib`) |
| tvm-ffi | `apache/tvm-ffi@df463f9b` (v0.1.14-52; TVM's submodule) | `apache-tvm-ffi 0.1.14.post2.dev22+gdf463f9bd`, built from source |
| tvm-ffi-orcjit | the same tree, `addons/tvm_ffi_orcjit` | `apache-tvm-ffi-orcjit 0.1.2`, built from source |
| xgrammar | `mlc-ai/xgrammar@d4f57c44` (2024-11-11) | compiled into `libmlc_llm_module.dylib` (C++ only) |
| tokenizers-cpp | `mlc-ai/tokenizers-cpp@34885cfd` (Rust `tokenizers` 0.21.4) | compiled into `libmlc_llm_module.dylib` |

```bash
B=~/Developer/mlsys/serving/mlc-llm_bench; cd "$B"
git submodule update --init --recursive --filter=blob:none --jobs 6        # 28 s, 483 MB
uv pip uninstall --python .venv/bin/python mlc-llm-nightly-cpu mlc-ai-nightly-cpu apache-tvm-ffi
uv pip install --python .venv/bin/python --only-binary :all: \
  "scikit-build-core>=0.11" "setuptools-scm>=8" "cython>=3.2.8" "mlc-z3-static>=4.16.0" psutil
UVI="uv pip install --python $B/.venv/bin/python --no-build-isolation --no-deps -v"
export CCACHE_DIR="$B/.ccache"

# 1. tvm-ffi from TVM's submodule (TVM docs: "cd 3rdparty/tvm-ffi; pip install .")            23 s
$UVI ./3rdparty/tvm/3rdparty/tvm-ffi
# 2. tvm-ffi-orcjit: in-process LLVM JIT, which `convert_weight --device cpu` needs                 4 s
LLVM_PREFIX=/opt/homebrew/opt/llvm@23 $UVI \
  -C cmake.define.ZLIB_STATIC="$(xcrun --show-sdk-path)/usr/lib/libz.tbd" \
  -C cmake.define.ZSTD_STATIC=/opt/homebrew/opt/zstd/lib/libzstd.a \
  ./3rdparty/tvm/3rdparty/tvm-ffi/addons/tvm_ffi_orcjit
# 3. TVM: build/config.cmake = cmake/config.cmake + the overrides below; configure; build         227 s, 628 steps
cmake -S 3rdparty/tvm -B 3rdparty/tvm/build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DTVM_BUILD_PYTHON_MODULE=ON -DUSE_CUDA=OFF -DUSE_Z3=AUTO -DBUILD_TESTING=OFF \
  -DPython3_EXECUTABLE="$B/.venv/bin/python" -DPython_EXECUTABLE="$B/.venv/bin/python"
cmake --build 3rdparty/tvm/build
# 4. TVM Python package, editable (reuses 3rdparty/tvm/build)                                       64 s
$UVI -C cmake.build-type=RelWithDebInfo -e ./3rdparty/tvm
# 5. MLC-LLM: build/config.cmake from `cd build && python ../cmake/gen_cmake_config.py`
#    (answers: default TVM_SOURCE_DIR, Metal y, everything else n); scikit-build-core builds build/   28 s, 176 steps
$UVI -e .
```

`3rdparty/tvm/build/config.cmake` is `cmake/config.cmake` plus the overrides from the docs'
step 3:

```cmake
set(CMAKE_BUILD_TYPE RelWithDebInfo)
set(USE_LLVM "/opt/homebrew/opt/llvm@23/bin/llvm-config --ignore-libllvm --link-static")
set(HIDE_PRIVATE_SYMBOLS ON)
set(USE_METAL ON)
# OFF: USE_CUDA USE_ROCM USE_VULKAN USE_OPENCL USE_CUBLAS USE_CUDNN USE_CUTLASS (USE_RPC stays ON)
```

MLC's `build/config.cmake` sets `TVM_SOURCE_DIR 3rdparty/tvm`,
`CMAKE_BUILD_TYPE RelWithDebInfo` and `USE_METAL ON`, with every other backend OFF.

Notes:
- **Why tvm-ffi is built from source.** TVM pins tvm-ffi `v0.1.14-52`, and its headers are
  compiled into every `libtvm_*`.
  - Both TVM and MLC are installed with `--no-deps`. The source tvm-ffi carries a dev version
    (`0.1.14.post2.dev22`), and uv would otherwise replace it with a PyPI release.
  - All other runtime dependencies were already in the venv, except **`psutil`**.
    `mlc_llm/serve/server/popen_server.py:10` imports it, but `pyproject.toml` does not list it
    (a packaging gap on main). It was installed separately.
- **Why orcjit is needed.**
  - In this TVM, running an LLVM-compiled module in process goes through the separate
    `apache-tvm-ffi-orcjit` package (`tvm:src/target/llvm/llvm_module.cc:107`, `:317-327`).
  - `convert_weight --device cpu` runs its quantize kernels exactly that way
    (`main:python/mlc_llm/quantization/utils.py:75-82`).
  - orcjit requires LLVM ≥ 23.1.1 (`addons/tvm_ffi_orcjit/CMakeLists.txt`). So TVM uses LLVM
    23.1.2 too; TVM has `TVM_LLVM_VERSION >= 230` code paths.
  - The user's older `serving/mlc-llm` build used `llvm@22` 22.1.8, dynamically linked.
  - Homebrew LLVM ships no `libz.a`, hence the `ZLIB_STATIC` override: system zlib, linked
    dynamically.
- **A benign configure "Failed".** The `TVM_LLVM_DIBUILDER_USES_ITERATOR` probe compiles but
  fails to link, because the probe links without LLVM. TVM therefore uses the
  `Instruction*` overloads. LLVM 23 still has them (deprecated,
  `llvm/IR/Instruction.h:57-59`), with the same insertion point.
- **Steps 3 and 4 overlap.** Step 4 reconfigures the same build directory and recompiled all
  619 objects. 604 of them were ccache hits in preprocessed mode, so the objects are
  identical. Step 4 alone, after writing `config.cmake`, is enough to reproduce the build.
- **Warnings only, no errors.** 139 warnings, mostly `-Woverloaded-virtual`.
- **Logs.** In `serving/mlc-llm_bench/logs/`: `submodules.log`, `tvm-configure.log`, and
  `build-{ffi,orcjit,tvm,tvm_py,mlc}.log`.
- **Disk:** `3rdparty/` 483 MB, `3rdparty/tvm/build` 3.3 GB, `build/` 768 MB,
  `.ccache` 741 MB.

| Library | Size |
| --- | --- |
| `3rdparty/tvm/build/lib/libtvm_compiler.dylib` (static LLVM 23 inside, RelWithDebInfo) | 294.5 MB |
| `3rdparty/tvm/build/lib/libtvm_runtime.dylib` / `libtvm_runtime_metal.dylib` / `libtvm_runtime_extra.dylib` | 3.7 / 0.4 / 1.3 MB |
| `.venv/lib/python3.12/site-packages/tvm_ffi/lib/libtvm_ffi.dylib` | 1.9 MB |
| `.venv/lib/python3.12/site-packages/tvm_ffi_orcjit/lib/libtvm_ffi_orcjit.dylib` (static LLVM 23) | 52.7 MB |
| `build/libmlc_llm_module.dylib` (MLC + xgrammar + tokenizers) | 13.8 MB |

### 3.2 Verification (executed 02:12, CPU only)

Script: [`bench-tools/verify.py`](bench-tools/verify.py). Log:
`serving/mlc-llm_bench/logs/verify.log`. Every check ran under `.venv/bin/python -I` from a
neutral directory, with `HF_HUB_OFFLINE=1`.
- **`import tvm, mlc_llm` works**, with no abort.
  - `tvm.__file__` = `~/Developer/mlsys/serving/mlc-llm_bench/3rdparty/tvm/python/tvm/__init__.py`
    (0.26.dev529).
  - `mlc_llm.base._LIB_PATH` = `~/Developer/mlsys/serving/mlc-llm_bench/build/libmlc_llm_module.dylib`.
  - TVM loads `libtvm_runtime`, `libtvm_compiler`, `libtvm_runtime_metal` and
    `libtvm_runtime_extra`, all from `3rdparty/tvm/build/lib`.
- **Every dylib is mapped exactly once** (dyld image list).
  - `libtvm_ffi` comes only from the `tvm_ffi` package.
  - MLC's own copies in `build/lib/` (`libtvm_runtime`, `libtvm_runtime_extra`, `libtvm_ffi`)
    are not loaded: dyld reuses the already-loaded images, matched by install name
    (`@rpath/…`).
- **The CPU LLVM JIT works** (`relax.build(target="llvm")` → VM on `cpu`, through orcjit).
- **xgrammar is compiled into `libmlc_llm_module.dylib`.** It has 475 `xgrammar::` symbols,
  such as `GrammarMatcher::AcceptToken`.
  - MLC never imports a Python `xgrammar` package (no `import xgrammar` under
    `python/mlc_llm`), and none is installed.
  - It is used from `cpp/serve/engine.cc`, `request_state.{h,cc}`.
- **`python -m mlc_llm serve --help` works** (`logs/serve-help.txt`).
  - There is no `mlc_llm` console script, because `pyproject.toml` defines none. Always use
    `python -m mlc_llm`.
- **`tvm.support.libinfo()` is not informative in this TVM.** It returns 15 generic entries
  (for example `USE_CUDA: ON`, `USE_METAL: OFF`) that do not describe this build. The real
  flags are in `3rdparty/tvm/build/CMakeCache.txt` and `logs/tvm-configure.log`: Metal ON,
  LLVM 23.1 static, hidden symbols, Z3, RPC.
- **Code signatures.** All built dylibs are linker-signed (ad hoc) and load without a
  re-sign.
  - `codesign -v` reports "valid" for the installed copies.
  - For the in-tree paths it prints "No such process"; a byte-for-byte copy verifies as
    valid, so this is a quirk of the tool.
- **Not run, by rule:** `tvm.metal().exist` and any Metal runtime test.

### 3.3 Why the nightly wheels were dropped (history, 01:00–01:30)

- **What was tried.** `mlc_llm_nightly_cpu-0.26.dev6` and `mlc_ai_nightly_cpu-0.26.dev246` from
  `mlc-ai/package` `v0.9.dev0`, built 2026-08-24 from `main@9fa644f5`.
  - These are the newest macOS arm64 wheels; their sha256 matched the release digests.
  - Copies stay in `.venv/wheels/`, not installed.
- **As shipped:** `import tvm` was SIGKILLed with "Code Signature Invalid". Every TVM/MLC dylib
  had been modified after linking without being re-signed.
- **After an ad-hoc re-sign (user-approved):** `import tvm` aborted with SIGABRT
  ("pointer being freed was not allocated").
  - The abort came from a static initializer of `libtvm_runtime_extra.dylib` during backend
    autoload.
  - The two wheels ship different `libtvm_runtime.dylib` builds (2,696,064 B vs 2,300,000 B).
  - With `TVM_DEVICE_BACKEND_AUTOLOAD=0`, `import mlc_llm` instead failed on
    `@rpath/libtvm_runtime_extra.dylib`.
- **Not root-caused.** The source build avoids the problem: it builds tvm-ffi, TVM and MLC from
  one pinned tree with one toolchain. It also brings main's newer code (#3554, #3568, #3571).
- **Removed ~01:45** with `uv pip uninstall`. No `tvm*` or `mlc*` files were left. The package
  list from before is in `serving/mlc-llm_bench/logs/venv-before-source-build.txt` (76 lines).

## 4. Pipeline (executed 02:13–02:16, CPU only)

```bash
cd ~/Developer/mlsys/serving/mlc-llm_bench && source .venv/bin/activate
export HF_HOME=~/Developer/ml_source/huggingface HF_HUB_OFFLINE=1   # offline: the HF cache is only read
SRC=$HF_HOME/hub/models--Qwen--Qwen3.8-27B/snapshots/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0
DST=~/Developer/mlsys/models/mlc/Qwen3.8-27B-q4f16_1-MLC
LIB=$DST/Qwen3.8-27B-q4f16_1-ctx131072-bs1-metal.dylib

python -m mlc_llm convert_weight "$SRC" --quantization q4f16_1 --model-type qwen3_5 --device cpu --output "$DST"
python -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 --conv-template qwen3_5_nothink \
  --context-window-size 131072 --prefill-chunk-size 2048 --max-batch-size 1 --output "$DST"
python -m mlc_llm compile "$DST/mlc-chat-config.json" --device metal --output "$LIB"

# Thinking-on twin: the same weights and library, a different chat config (section 5.7)
mkdir -p "$DST-think"
python -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 --conv-template qwen3_5 \
  --context-window-size 131072 --prefill-chunk-size 2048 --max-batch-size 1 --output "$DST-think"
ln -sf "$DST"/params_shard_*.bin "$DST"/tensor-cache*.json "$DST-think"/
```

The tiny model ran first with the same commands (`SRC` = the `Qwen/Qwen3.5-0.8B` snapshot
`2fc06364…`, `DST` = `…/Qwen3.5-0.8B-q4f16_1-MLC`).
- **Snapshots.** Both were complete before the run (`scripts/hf_snapshot.py --safetensors`):
  - 27B: 18 shards, 55.56 GB;
  - 0.8B: 1.75 GB.
- **Commands.** The driver is [`bench-tools/pipeline.sh`](bench-tools/pipeline.sh) `<tiny|27b>`. The
  exact command lines and outputs are in `serving/mlc-llm_bench/logs/pipeline-{tiny,27b}-*.log`.

| | Qwen3.5-0.8B | Qwen3.8-27B |
| --- | --- | --- |
| `convert_weight --device cpu` (wall) | 8 s | **96 s**: HF load 0.6 s, pre-quantization mapping 27.4 s, quantization 39.9 s. 51.75 GB read; peak RAM 5.7 GB as reported (13.3 GB RSS observed). |
| Parameters / bits per parameter | 873,438,784 / 3.883 | 27,781,427,952 / 4.358 |
| Weights after quantization | 0.395 GB (11 shards) | **14.094 GB** (309 shards) |
| `gen_config` | 3 s | 3 s |
| `compile --device metal` (wall) | 17 s | **29 s** |
| Model library | `Qwen3.5-0.8B-q4f16_1-ctx131072-bs1-metal.dylib`, 4.1 MB | `Qwen3.8-27B-q4f16_1-ctx131072-bs1-metal.dylib`, **7.7 MB** |
| Compile-time memory estimate | params 404 MB + temp 2,065 MB | params 14,432 MB + temp 2,340 MB |
| Directory size | 430 MB | **14 GB** (`-think`: 22 MB of its own plus symlinks) |

- **Output paths:**
  - `~/Developer/mlsys/models/mlc/Qwen3.8-27B-q4f16_1-MLC/` holds `mlc-chat-config.json`,
    `tensor-cache.json` (plus `tensor-cache-b16.json`), `params_shard_{0..308}.bin`, the
    tokenizer files and the `.dylib`;
  - `…/Qwen3.8-27B-q4f16_1-MLC-think/`;
  - the 0.8B pair in `…/Qwen3.5-0.8B-q4f16_1-MLC{,-think}/`.
- **Chat config.** `qwen3_5`, `q4f16_1`, `context_window_size` 131072, `prefill_chunk_size`
  2048, `model_config.max_batch_size` 1. Stop tokens: `[248046, 248044]`.
  - The default sampling comes from HF's `generation_config.json`: temperature 1.0, top_p 0.95.
    **The harness must send `temperature: 0`.**
- **The Metal target was detected, with no kernels run:** `max_threads_per_block` 1024,
  `thread_warp_size` 32, `max_shared_memory_per_block` 32768, `max_num_threads` 256; host
  `arm64-apple-darwin27.2.0`, `-mcpu=apple-m5`.
- **What the convert dropped.** The text model maps `model.language_model.*` and `lm_head`.
  - The convert warns "Unused extern parameters: model.visual.*" (and `mtp.*`), as expected.
  - The 0.8B result (0.395 GB, 3.883 bits) matches the user's March run exactly.
- **The temporary-buffer maximum is `batch_verify`.** That is the speculative-decoding verify
  function; prefill needs 401 MB and decode 7 MB.
  - The engine reserves 2 × that maximum (`cpp/serve/config.cc:854-855`).
  - It is not allocated unless the function runs.
- **Ignore the compile log's KV line** ("Total memory usage with a 4K KV cache:
  17795.77 MB").
  - It uses the generic `num_hidden_layers` = 64 (`main:cli/model_metadata.py:115-123`).
  - The real paged KV cache covers only the 16 full-attention layers
    (`qwen35_model.py:786`, `num_hidden_layers=self.num_attention_layers`), and the engine's
    own estimate uses the library's KV metadata (`cpp/serve/config.cc:702-708`).
  - So KV is 64 KiB per token: **8.0 GiB at 131072**. The RNN state is about 154 MB per slot:
    a 48 × 128 × 128 fp32 recurrent state and a 3 × 10240 fp16 conv state, in each of the 48
    GDN layers (`qwen35_model.py:745-767`).
- **The format.** `q4f16_1` stores 4-bit weights in groups of 32 with fp16 scales (NK layout),
  and the activations are fp16.
  - It is the closest MLC format to MLX affine 4-bit g64 (4.5 bits per weight), but not
    bit-identical to the other 4-bit rows.
  - The embedding and `lm_head` are quantized too. The 4.358 bits per parameter includes the
    unquantized norms and biases.

## 5. Serve (port 8700) and the harness contract

### 5.1 Launch (GPU; run it under the lock)

```bash
cd ~/Developer/mlsys/serving/mlc-llm_bench && source .venv/bin/activate
M=~/Developer/mlsys/models/mlc/Qwen3.8-27B-q4f16_1-MLC
python -m mlc_llm serve "$M" \
  --model-lib "$M/Qwen3.8-27B-q4f16_1-ctx131072-bs1-metal.dylib" \
  --device metal --mode interactive \
  --prefix-cache-mode disable \
  --overrides "context_window_size=131072;max_total_seq_length=131072;prefill_chunk_size=2048" \
  --enable-debug \
  --host 127.0.0.1 --port 8700 \
  2>&1 | tee ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs/mlc-llm-serve-4bit.log
```

- **Thinking-on bucket:** serve `"$M-think"` with the same `--model-lib`, after restarting the
  server (section 5.7).
- **Readiness:** `curl -s http://127.0.0.1:8700/v1/models`.
- **Memory (estimate):** about 24–26 GiB resident at 131072.
  - Weights take 14.1 GiB and the KV cache 8.0 GiB. The KV cache is preallocated at startup
    for `max_total_seq_length`.
  - The RNN state adds about 0.15–0.3 GiB, and temporary buffers up to 2.3 GB.
  - The log line "Estimated total single GPU memory usage …" gives the real split; record it.
- **Startup (estimate):** 1–2 min. That covers loading 14 GB of weights and compiling the
  Metal shaders from source at load.
- **Stop the server yourself before releasing the lock.** `gpu_lock.sh release` checks only
  ports 8701–8705. The repo's `scripts/serve.sh` and `scripts/lib.sh` do not know MLC or
  port 8700, so launch manually.

### 5.2 Why each flag

- **`--mode interactive`** sets `max_num_sequence=1`
  (`main:mlc_llm/interface/help.py:177-194`; `cpp/serve/config.cc`, `EstimateMemoryUsageOnMode`).
  This is required while packed multi-sequence prefill breaks the GDN state (section 6.2).
- **`--prefix-cache-mode disable`.** The default, `radix`, is unsafe for hybrid models
  (section 6.1).
- **`max_total_seq_length=131072` is mandatory for G5.**
  - On Metal the engine clamps the inferred KV capacity to 32768 tokens ("Metal runtime has
    severe performance issues with large buffers", `cpp/serve/config.cc:752-757`).
  - Interactive mode takes that clamped value (`:769-771`), unless `max_total_seq_length` is
    given; a user value is used as is (`:781-783`).
  - So `context_window_size=131072` alone leaves a 32768-token cache, and a 64K prompt fails.
  - **Verify** that the server log reports "max KV cache token capacity 131072". Watch for the
    large-buffer slowdown that the code comment warns about.
- **`prefill_chunk_size=2048` is redundant but harmless.** Interactive mode already picks
  min(compile-time 2048, KV capacity, context) (`cpp/serve/config.cc:606-612`, `:785-791`).
  The help text's "set to the context window size" is bounded by that.
- **`--enable-debug`** is needed for two things:
  - `debug_config.grammar_execution_mode` (section 5.4);
  - `usage.extra` (section 5.6).
- **Leave `--speculative-mode` at `disable`** (the default). See section 6.3.

### 5.3 Structured output (xgrammar): the request shape

These findings were read from source (main@8978ea9a, the xgrammar submodule `d4f57c44`). The
pydantic checks are **executed** (`logs/verify.log`); nothing ran on the GPU.

MLC does **not** accept OpenAI's `{"type": "json_schema", "json_schema": {...}}`.
`RequestResponseFormat` (`main:protocol/openai_api_protocol.py:135-141`) has only
`type: Literal["text", "json_object"]` and `json_schema: Optional[str]`, aliased to `schema`.
The working request:

```json
POST http://127.0.0.1:8700/v1/chat/completions
{
  "messages": [{"role": "system", "content": "..."}, {"role": "user", "content": "..."}],
  "stream": true,
  "stream_options": {"include_usage": true},
  "temperature": 0,
  "max_tokens": 300,
  "response_format": {"type": "json_object",
                      "schema": "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}"},
  "debug_config": {"grammar_execution_mode": "constraint"}
}
```

- **`schema` must be a string.** Send `json.dumps(schema)`. Executed checks:
  - a dict → 422;
  - `"type": "json_schema"` → 422;
  - a key named `json_schema` is silently ignored, so the request falls back to plain JSON
    mode.
- **No `schema` = generic JSON.** `{"type": "json_object"}` alone uses xgrammar's built-in JSON
  grammar (`cpp/serve/engine.cc:981-991`).
- **The engine path.** `engine_utils.openai_api_get_generation_config` copies `response_format`
  and `debug_config` into the `GenerationConfig` (`serve/engine_utils.py:31-46`). Executed:
  the serialized config carries both. C++ re-parses them (`cpp/serve/config.cc:44-59`).
- **The grammar is compiled when the request is added.**
  `GetCompiledGrammarForJSONSchema(schema)` runs on the engine thread (`engine.cc:702`) and is
  cached per schema string. The first request with a new schema pays the compile against the
  248K-token vocabulary, so **warm each schema once** before timing.
- **The output format is fixed.** Without an indent, xgrammar forces single-line JSON with
  `", "` and `": "` separators (`3rdparty/xgrammar/cpp/json_schema_converter.cc:32`, `:347`).
  `strict_mode=true` (`include/xgrammar/xgrammar.h:334-339`), so a missing
  `additionalProperties` means `false` (`json_schema_converter.cc:766`, `:990`).
- **Supported keywords** (xgrammar from 2024-11):
  - supported: `type`, `properties`, `required`, `additionalProperties`, `items`,
    `prefixItems`, `enum`, `const`, `anyOf`, and `$ref` into `#/$defs/…` only (`:580-588`);
  - warned and **ignored**: `allOf`, `oneOf`, `not`, `if`; `minimum`, `maximum`,
    `multipleOf` and the exclusive bounds; `minLength`, `maxLength`, `pattern`, `format`;
    `uniqueItems`, `contains`; `patternProperties`, `minProperties`, `maxProperties` and
    `propertyNames` (`:513`, `:659`, `:677`, `:695`, `:728`, `:943`).
  - Keep the harness schemas inside the supported set, or the constraint is weaker than the
    schema says.
- **Use the thinking-off chat config.** `qwen3_5_nothink` already ends the prompt with
  `<think>\n\n</think>\n\n`, so the first constrained token is JSON. Under `qwen3_5`, the
  grammar would forbid the thinking text.

### 5.4 Why `grammar_execution_mode: "constraint"` is mandatory here

- **Jump-forward is the default.** `grammar_execution_mode` defaults to `jump_forward`
  (`cpp/serve/config.h:67-73`, `:104`; `protocol/debug_protocol.py:40`).
- **Jump-forward rolls tokens back:**
  1. `BatchJumpForward` runs before every decode in the normal action list
     (`engine_actions/action_commons.cc:114-124`).
  2. It retokenizes the forced string and calls `PopNFromKVCache` once the rollback reaches
     tokens that are already in the cache (`batch_jumpforward.cc:75-78`; PopN at `:211`).
  3. It also sets `require_retokenization_in_next_decode` (`:85`). The next decode then calls
     `PopNFromKVCache(rollback_cnt)` too (`batch_decode.cc:178-186`, `:286-289`).
- **On this model, any PopN kills the engine.**
  - The hybrid PopN is mirrored onto the RNN state (`cpp/serve/model.cc:970-978`).
  - There, `available_history_num` is always 0, because `max_history = 1`
    (`rnn_state.cc:245-250`; section 6.1).
  - So the ICHECK at `rnn_state.cc:366` fires inside the engine loop.
- **`constraint` mode never rolls back.**
  - `CanJumpForward` returns false (`batch_jumpforward.cc:112-124`), and the retokenize flag
    is never set.
  - The grammar only masks logits, so nothing is popped.
- **`debug_config` needs `--enable-debug`.** Without it, the server drops `debug_config`, and
  the default `jump_forward` applies (`serve/entrypoints/openai_entrypoints.py:243-247`).
- **Fallback without `--enable-debug`.** `"logprobs": true` also disables jump-forward
  (`batch_jumpforward.cc:117-119`). The cost: logprobs are computed for every token and sent
  in every chunk.
- **Verify** on the first live run: one constraint-mode request must return schema-valid JSON.
  The jump-forward crash is predicted from the code; probe it only outside timed runs, and
  expect to restart the server after it.

### 5.5 `tools` / `tool_choice`, streaming, and errors

- **`tools` and `tool_choice` are accepted, but they do nothing useful.**
  - The fields exist (`openai_api_protocol.py:278-279`). `tool_choice` may be `"none"`,
    `"auto"` or `{"type": "function", "function": {"name": …}}`.
  - Any other string, an unknown name, or a non-function type → HTTP 400 (`:366-404`;
    `BadRequestError`, mapped at `interface/serve.py:128`).
  - The tool JSON lands in `function_string`, but the `qwen3_5` templates have no
    `{function_string}` placeholder (`conversation_template/qwen3_5.py`). So **tools never
    reach the prompt.**
  - Unless `tool_choice` is `"none"`, `use_function_calling` is set:
    - **streaming:** the final `finish_reason` is always rewritten to `"tool_calls"`
      (`serve/engine_base.py:847-851`), and the deltas carry only text;
    - **non-streaming:** the text is parsed as a Python call with `ast.parse`
      (`engine_base.py:1154-1213`). JSON or Qwen XML gives `finish_reason: "error"`.
  - The history rules from section 7, G1 evidence, still apply: assistant `tool_calls` →
    400, and a `tool` role → error.
  - So **never send `tools`.** A substitute that keeps prompts comparable: put the tool schemas
    in the system text, and constrain the answer with `response_format` to a
    `{"name": {"enum": [...]}, "arguments": {...}}` schema. That is not the G1 protocol.
- **Streaming works with `response_format`.** The grammar is applied in the engine in both
  modes. Nothing in the stream path checks `response_format` (`openai_entrypoints.py:262-286`;
  `engine_base.py:781-889`), and the deltas are plain `content` text.
- **Errors.** A body that fails pydantic validation gets FastAPI's default 422, with a
  `detail` list; only `BadRequestError` maps to 400. Two executed checks:
  - `stream_options` without `stream: true` → 422 (`openai_api_protocol.py:323-329`);
  - unknown top-level fields are dropped, not rejected.
- **`model` may be omitted or set to anything.** With one model served, `get_engine` returns it
  (`serve/server/server_context.py:50-55`).
- **Always send a system message.** MLC inserts "You are a helpful assistant." when there is
  none (`conversation_template/qwen3_5.py`); the HF template inserts nothing.

### 5.6 `usage`

- **Non-streaming:** `usage` is always present: `prompt_tokens`, `completion_tokens`,
  `total_tokens` (`openai_api_protocol.py:56-61`; `cpp/serve/metrics.cc:95-104`).
- **Streaming:** usage arrives only with `stream_options.include_usage: true`. It is one last
  chunk with `choices: []` and a `usage` object, before `data: [DONE]`
  (`engine_base.py:820-841`).
- **`usage.extra` needs `--enable-debug`** (`openai_entrypoints.py:243`, `:314-316`). It carries
  per-request engine metrics (`metrics.cc:74-93`):
  - `prompt_tokens`, `completion_tokens`;
  - `prefill_tokens`, `decode_tokens`, `jump_forward_tokens`;
  - `prefill_tokens_per_s`, `decode_tokens_per_s`;
  - `end_to_end_latency_s`, `ttft_s`, `inter_token_latency_s`.
- **There is no `prompt_tokens_details`.** Cached tokens = `extra.prompt_tokens −
  extra.prefill_tokens`, which is always 0 with `--prefix-cache-mode disable`.
- **Engine-wide metrics:** `GET /metrics` (`serve/entrypoints/metrics_entrypoints.py:13`).

### 5.7 Thinking: off by default; there is no per-request switch

- **Qwen3.8's own template turns thinking on by default, at `reasoning_effort` `xhigh`**
  (`chat_template.jinja:46-55`, `:163-169` in the snapshot).
  - xhigh adds a system line, "Reasoning effort is set to xhigh. Please think carefully …",
    before the system text.
  - `low` adds a shorter line; `medium` adds nothing.
  - `enable_thinking=false` pre-fills `<think>\n\n</think>\n\n`.
  - The template has no `/no_think` soft switch.
- **MLC has no per-request control.** `ChatCompletionRequest` has no `chat_template_kwargs`,
  `enable_thinking` or `reasoning_effort` (`openai_api_protocol.py:258-284`).
  - Executed: all three, which is also what the OpenAI SDK's `extra_body` sends, are accepted
    and silently dropped.
  - A `/no_think` in the system prompt does nothing to the template. Under `qwen3_5` the
    generation prompt has already opened `<think>`.
- **Thinking is fixed per chat config.** `gen_config --conv-template` is required and has no
  default (`cli/gen_config.py:44-49`). The choice made here:
  - **Default artifact `Qwen3.8-27B-q4f16_1-MLC` = `qwen3_5_nothink` (thinking OFF).** Use it
    for M1, M2, M3 (short), M4, M5, M7 and structured output.
  - **`Qwen3.8-27B-q4f16_1-MLC-think` = `qwen3_5` (thinking ON).** Use it only for the M3
    long/thinking bucket and for G4 probes.
  - Both share the weights (symlinks) and the same `.dylib`. Switching means restarting the
    server.
- **Byte-identical renderings (executed with transformers 5.20.1 and the snapshot's
  template):**
  - MLC `qwen3_5_nothink` = HF `enable_thinking=false`.
  - MLC `qwen3_5` = HF thinking on with `reasoning_effort="medium"`, **not** the default
    xhigh.
  - To reproduce xhigh with the `-think` config, the harness puts the exact xhigh sentence
    (the template's `reasoning_instructions`) plus `\n\n` before the system text. With no
    system message, send the sentence alone as the system message.
- **No reasoning separation.** The thinking text and `</think>` arrive inside `content`; there
  is no `reasoning_content`. The harness must split it itself.

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

### 6.5 Grammar jump-forward rolls back the state

- The default grammar mode, `jump_forward`, calls `PopNFromKVCache`. That fails on the RNN
  state for the same reason as 6.1.
- So structured output must use `debug_config.grammar_execution_mode = "constraint"`
  (section 5.4).
- `constraint` mode only masks logits and never rolls back.

## 7. Gate expectations (G1–G5)

| Gate | Expectation | Evidence |
| --- | --- | --- |
| G1 | **fail** | See "G1 evidence" below the table. |
| G2 | **degraded, verify**; needs a `qwen3_5_vision` artifact (not built) | See "G2 evidence" below the table. |
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
- The removed nightly had no `qwen35v_*` files. The source build (main) has them, but the
  artifacts in section 4 are text-only.
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
  - The thinking template lacks the reasoning-effort system line that HF adds. It equals HF's
    `reasoning_effort="medium"` rendering (**executed**, section 5.7).
  - So the only toggle is the template, through two chat configs (section 4, `-think`).
  - **Executed:** the unknown fields are silently dropped, not rejected.
- **No reasoning separation.** There is no `reasoning_content` (`ChatCompletionMessage`,
  `:250-255`); thinking text arrives in `content`.

**G5 evidence.**
- KV is 64 KiB per token (16 layers × 2 × 4 heads × 256 × 2 B), i.e. 8.0 GiB at 131072
  tokens.
- RNN state is about 147 MiB (154 MB) per slot, with 1–2 slots.
- Weights are 14.1 GiB (**executed**: 14.094 GB), so the total is about 24 GiB plus temporary
  buffers.
- 262144 is the model's limit, so 131072 is allowed.
- **It needs `--overrides "max_total_seq_length=131072"`.** Otherwise Metal caps the cache at
  32768 tokens (section 5.2).
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

## 9. Status / remaining work (2026-10-18 02:30)

**State**
- **The build works.** The TVM + MLC-LLM source build is installed editable in
  `~/Developer/mlsys/serving/mlc-llm_bench/.venv` (section 3).
  - `import tvm, mlc_llm`, `python -m mlc_llm serve --help` and the CPU JIT are verified.
  - The nightly wheels were uninstalled.
- **Artifacts** (built on CPU, section 4):

  | Path (`~/Developer/mlsys/models/mlc/…`) | Contents | Size |
  | --- | --- | --- |
  | `Qwen3.8-27B-q4f16_1-MLC/` | q4f16_1 weights (309 shards); `mlc-chat-config.json` (`qwen3_5_nothink`, ctx 131072, prefill 2048, max batch 1); `Qwen3.8-27B-q4f16_1-ctx131072-bs1-metal.dylib` | 14 GB (weights 14.094 GB, library 7.7 MB) |
  | `Qwen3.8-27B-q4f16_1-MLC-think/` | `mlc-chat-config.json` (`qwen3_5`), tokenizer files, symlinks to the weights | 22 MB of its own |
  | `Qwen3.5-0.8B-q4f16_1-MLC{,-think}/` | the tiny validation pair, with its own library | 430 MB |

- **Pipeline cost.** The whole 27B pipeline took about 2.2 min of wall time on CPU: convert
  96 s, gen_config 3 s, compile 29 s. It is far below the 90-min stop rule.
- **Nothing ran on the GPU.** The lock was never taken, and no server was started.
  `compile --device metal` only read the device limits.
- **Not touched:**
  - the user's MLC checkouts (`serving/mlc-llm`, `mlc-llm_2a`, `mlc-llm_2b`), which were read
    only;
  - the conda envs and other sessions' files;
  - the HF cache, which was read offline and never written.
- **Docs.** MLC (port 8700) is not yet in `README.md`'s status table or in `resume.md`.

**GPU steps for the coordinator, under the lock, in order** (all times and memory are estimates)

| # | Step | How | Time | Memory |
| --- | --- | --- | --- | --- |
| 1 | Tiny smoke (optional, fast fail) | Section 5.1, with `M=~/Developer/mlsys/models/mlc/Qwen3.5-0.8B-q4f16_1-MLC` and its `Qwen3.5-0.8B-q4f16_1-ctx131072-bs1-metal.dylib`; then requests (a)–(c) below | 2–3 min | ~3–4 GB (KV 12 KiB/token: 6 attention layers × 2 KV heads, so 1.5 GiB at 131072) |
| 2 | Serve the 27B | Section 5.1 | 1–2 min startup | 24–26 GiB resident |
| 3 | Smoke requests | (a)–(c) below; record the serve log's memory line | < 2 min | — |
| 4 | Text-only reference row (M1–M7, G5) | Harness with the MLC request path (below) | per METHODOLOGY | — |
| 5 | Thinking bucket (M3 long, G4) | Restart with `…-MLC-think`, same `--model-lib` | 1–2 min startup | same |
| 6 | Crash probes (optional; never during timed runs) | a `jump_forward` grammar request (no `debug_config`); the radix cache with an M1-shaped pair; 2 concurrent requests at `max_num_sequence=2` | minutes | — |

```bash
U=http://127.0.0.1:8700/v1/chat/completions; H='Content-Type: application/json'
# (a) greedy sanity: the answer must be 391
curl -s $U -H "$H" -d '{"messages":[{"role":"system","content":"You are concise."},{"role":"user","content":"What is 17*23? Reply with the number only."}],"temperature":0,"max_tokens":16}'
# (b) streaming, with usage.extra in the last chunk
curl -sN $U -H "$H" -d '{"messages":[{"role":"system","content":"You are concise."},{"role":"user","content":"Name three primary colors."}],"temperature":0,"max_tokens":64,"stream":true,"stream_options":{"include_usage":true}}'
# (c) structured output, constraint mode: expect {"city": "Paris"}
curl -sN $U -H "$H" -d '{"messages":[{"role":"system","content":"Answer in JSON."},{"role":"user","content":"What is the capital of France?"}],"temperature":0,"max_tokens":64,"stream":true,"stream_options":{"include_usage":true},"response_format":{"type":"json_object","schema":"{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}"},"debug_config":{"grammar_execution_mode":"constraint"}}'
```

**Open questions for the first live run**
1. Does the server start with section 5.1's flags? Does the log report "max KV cache token
   capacity 131072", and what memory split does it give?
2. Is the 27B output coherent? Ratio-3 grouped value heads and the untied head are untested
   upstream; request (a) must answer 391.
3. Does constraint-mode output validate against its schema? How much TTFT does the first
   request with a new schema add, compared with the second?
4. G5 and M6: what are the 64K cold-prefill time and the peak memory? Is there a Metal
   large-buffer slowdown (`cpp/serve/config.cc:753-754`)?
5. Does G1 behave as predicted? Record the `finish_reason` with `tools`, and the HTTP codes
   for `tool` and `tool_calls` history.

**Remaining work (not done here)**
- **Harness: an MLC request path.**
  - Send no `tools`; render the tool schemas into the system text.
  - Send `response_format` in MLC's shape, plus `debug_config.grammar_execution_mode="constraint"`.
  - Send `temperature: 0` explicitly, and always a system message.
  - For `-think` runs, add the xhigh sentence (section 5.7).
  - Split `<think>…</think>` out of `content`, and read cached tokens from `usage.extra`.
- **G2:** a `qwen3_5_vision` artifact (`--model-type qwen3_5_vision`, the same CPU pipeline).
- **`README.md` and `resume.md` entries** for MLC on port 8700.
- **Upstream nits found while building (none blocks):**
  - `psutil` is missing from `pyproject.toml`;
  - `tvm.support.libinfo()` does not describe the build;
  - the `TVM_LLVM_DIBUILDER_USES_ITERATOR` probe reports a false negative;
  - the compile-time KV estimate counts all 64 layers.
