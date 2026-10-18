# Resume — current progress

Updated: 2026-10-18 01:25 (local). Work resumed at 00:20 on a good network (HF ~30 MB/s),
and large downloads are allowed again. Rewrite this after every major phase, and read it
first when resuming.

## Current state (2026-10-18 01:25)

- **Checkpoints.** All are downloaded (`done: core gguf extra` at 01:10): 8-bit, 4-bit,
  DSpark head, GGUF + MTP + mmproj, NVFP4, BF16.
- **Manual smoke tests (not timed) on all five servers are done.** Results are in each
  `env.md` under "Smoke test":
  - **llama.cpp** (4-bit, MTP off/on): text, streamed tool calls, image read-back,
    thinking and `/v1/messages` all OK. MTP draft acceptance 0.5–0.9; mmproj and MTP
    coexist.
  - **oMLX** (4-bit): text, tool calls (one final delta), image, thinking and
    `/v1/messages` all OK. The model loads on first request (17 s).
  - **vLLM-Metal** (8-bit): OK, through the procfix view.
  - **lithos-metal** (4-bit and NVFP4, DSpark): text, tool calls and `/v1/messages`
    text OK. Images → 400; thinking is hard-wired off. 4-bit needs the local patch, now
    applied on branch `bench/mlx-head-rename` (73b8cb6).
  - **mlx-lm** (8-bit): text and tool calls OK. Images and `/v1/messages` → 404.
- **Incident, fixed.** At 00:28 the procfix view's `README.md` symlink caused a write
  through into the shared HF blob (the 8-bit model card). Restored at 01:15 with a
  hash-verified original. The peer verified all 19 files against HF. Views now use
  regular files for anything we write.
- **Scripts done** (`scripts/README.md`): `serve.sh`, `gpu_lock.sh` (atomic),
  `wait_ready.sh`, `stop_server.sh`, `omlx_configure.sh`, `make_procfix.sh`,
  `hf_snapshot.py`.
- **Still running:**
  - the harness agent (fixtures, suites, `run-all`, `summarize`);
  - the MLC-LLM feasibility agent;
  - the Core AI setup agent (a tiny-model toolchain check done under our lock,
    01:04–01:09).
- **Lock and servers.** No lock held; no servers running.
- **Peer scheduling.** The agent-benchmark session wants a 1–2 h GPU slot for its harness
  smoke test. It was offered the GPU now (01:22), with our formal runs after.

| # | Phase | Status |
| --- | --- | --- |
| 0 | Plan, repo scaffold, methodology | **done** |
| 1 | Framework installs + flag research | **done**. MLC-LLM and Core AI were added 2026-10-18; their agents are running. |
| 1b | Manual smoke tests | **done** for llama.cpp, oMLX, vLLM-Metal, lithos-metal, mlx-lm |
| 2 | Harness + fixtures | **in progress** (agent) |
| 3 | Gate G1–G5 per framework (live, via harness) | pending |
| 4 | Metrics M1–M7 per framework; one `bench/<framework>` PR each, self-merged | pending |
| 5 | Summary PR + Chinese summary to the agent-benchmark session | pending |

## Frameworks: installs and expected gate results (from source; verify live)

| Framework | Install (`~/Developer/mlsys/serving/…`) | G1 tools | G2 images | G3 `/v1/messages` | G4 thinking | G5 ≥64K | Concurrency | Spec decoding |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| llama.cpp | `llama.cpp`, b11717 (848bbda), Metal build in `build/bin` | pass (Qwen3-Coder XML parser) | pass (`--mmproj`) | pass; `thinking: adaptive` is ignored | pass | pass (~22 GiB at 64K, est.) | `-np 3 -kvu` | MTP: `-md mtp.gguf --spec-type draft-mtp` |
| oMLX | `omlx_0.7`, v0.7.1rc1 (7a5a3d75); isolated `.bench-home`; **kernels not built** | pass; the call arrives as one delta at the end of the turn | pass (VLM path) | pass; streaming `tool_use` still to check | pass; `reasoning_effort` merged into template kwargs | pass (8 GiB KV at 131072) | continuous batching | none from local files: no MTP weights in 8-bit; no DFlash draft or Splash |
| vLLM-Metal | `vllm-metal`, v0.31.0 (e7a0c90b); wheels kept in `.venv/wheels` | pass (verify) | likely pass (verify native multimodal path) | pass for text + tool_use; thinking defaults on (xhigh) | `enable_thinking` pass; `reasoning_effort` unmapped | pass (verify memory) | `--max-num-seqs` | **unsupported**: vllm-metal excludes hybrid GDN targets from spec decoding, and any spec config disables the prefix cache; record M3 spec-on as n/a |
| lithos-metal | `lithos-metal`, v0.1.2 (46b2bc4c); note: the DSpark repo ships a `lithos-metal-runtime.patch` (unread) | pass, only if no thinking fields are sent | **fail** (HTTP 400) | partial: text + tool_use; images and `adaptive` → 400 | **fail**: thinking hard-wired off | unknown (upstream tested ≤33K) | **429** on concurrent requests | DSpark; needs the 1.1 GB head |
| mlx-lm | `mlx-lm`, v0.32.2 (93e6d4a6) | pass (`qwen3_coder` auto; whole call in one delta) | **fail** (HTTP 404 "Only 'text'") | **fail** (no route) | partial: `enable_thinking` works, `reasoning_effort` ignored | unknown (~4 GiB KV at 64K, est.) | — | none |
| Core AI | not set up; reference only (no HTTP server) | — | — | — | — | — | — | — |

Notes:
- **lithos-metal checkpoint loading.** lithos-metal rejects MLX checkpoints that name the
  head `language_model.lm_head.*`; the 8-bit uses that name. One local rename or patch
  makes all 498 tensors load (see `lithos-metal/env.md`).
- **lithos-metal with the official 4-bit.** Whether the official mlx-community 4-bit
  shares that naming is unverified. Check its `model.safetensors.index.json`; the fetch
  timed out on the bad network.

## Checkpoints and downloads

- **On disk.**
  - `mlx-community/Qwen3.8-27B-8bit` (28 GB): has a vision tower, no MTP tensors.
  - `LithosAI/Qwen3.8-27B-DSpark-NVFP4` (1.1 GB): complete since 2026-10-18 00:24.
- **Downloading.** With the user's go-ahead, `scripts/download_models.sh core gguf extra`
  resumed at 2026-10-18 00:23 on a ~30 MB/s network and runs the groups in order:
  1. MLX 4-bit
  2. GGUF (UD-Q4_K_M + MTP + mmproj-F16)
  3. NVFP4
  4. BF16

  Pause these downloads during timed segments.
- **Derived views.** Metadata-only views live in `~/Developer/mlsys/models/derived/`. They
  are needed because the mlx-community `processor_config.json` names a class that
  transformers doesn't have; see `vllm-metal/env.md` §8.
  - The 8-bit view exists.
  - The 4-bit view comes from `scripts/make_procfix.sh` once that checkpoint is complete.
- **Local fallbacks.** No longer needed now that downloads are allowed. Both are
  documented in the env.md files: lithos-metal 4-bit via re-quantization, and llama.cpp
  via conversion.

## Decisions (user)

- I may merge the per-framework PRs myself.
- Large downloads wait until the user is back on a good network.
- Framework sources live in `serving/`. This repo holds only the experiment.
- All repo files are in English.
- `resume.md` is updated after each phase.
- Independent work goes to parallel subagents.
- The 8-bit rows run first: oMLX → vLLM-Metal → mlx-lm.

## Harness requirements found during framework research (implement before the first run)

- **mlx_lm.server**
  - Omit `model` (or send `"default_model"`). Any other value reloads the model and drops the prompt cache.
  - Never send `seed`.
  - Reasoning comes back as `reasoning`.
  - The M1 warm-up must end with a user message, or the prefix is not cached.
- **lithos-metal**
  - Strip `chat_template_kwargs`, any `reasoning_effort` other than `none`, and any Anthropic `thinking` other than `disabled`.
  - Expect 429 under concurrency.
  - Cached tokens appear only in the server log.
- **llama-server**
  - Always pass `--port`; the default is now 9931.
  - Cached tokens are in `timings.cache_n` / `cached_tokens`, and need `include_usage`.
- **oMLX**
  - Export `OMLX_BASE_PATH`. Some code reads only the env var, not `--base-path`.
  - Set the 131072 context per model through the admin API or `model_settings.json`.
  - Build the kernels first: `xcodebuild -showComponent MetalToolchain`, then step 2 of `omlx/env.md`.
- **vLLM-Metal**
  - Pass `--gpu-memory-utilization 0.55`. With hybrid models the KV budget is committed at startup, and the default 0.92 means about 118 GB resident.
  - Reasoning arrives as `reasoning`, so the TTFT check must accept both `reasoning` and `reasoning_content`.
  - Launch command: `vllm-metal/env.md`.
- **Qwen chat template.** The template puts the tools block before the system prompt, so the cold-run cache-busting nonce goes into the first tool's description.
- **Sizes.** 64K means 64,000 tokens. A 1280×1024 screenshot is 1280 image tokens (1282 with the vision markers).

## Next steps (in order)

1. **Finish the harness:** fixtures, suites, `summarize`. Resume from `harness/STATUS.md`. A subagent can do this, with no GPU needed.
2. **Build the oMLX native kernels** (`omlx/env.md`, step 2).
3. **Run the 8-bit gate and metrics.**
   - Message the agent-benchmark session first, then take the GPU lock.
   - Order: oMLX → vLLM-Metal → mlx-lm.
   - Each framework gets a `bench/<framework>` PR, self-merged.
4. **4-bit rows, lithos-metal, llama.cpp.** These need downloads (user's call), or the fallbacks above.
5. **Core AI reference row.** Needs the BF16 download.
6. **Summary.** Open the summary PR, and send the summary to the agent-benchmark session.

## Shared with the other session

Two Claude Code sessions work in ~/Developer/mlsys and share one GPU:
- **agent-benchmark session** ("Meta Muse 本地替代方案"; resume: `~/Developer/mlsys/resume.md`) owns:
  - `experiments/personal-agent-bench`
  - `agent/`
  - `serving/omlx` (oMLX 0.3.9) and `~/.omlx`
  - `serving/omlx-v0.7.1rc1` (a git worktree of `serving/omlx`) and `~/.omlx-0.7`
  - `models/hf`
  - ports 8500 and 8600-8699
- **local_ai-benchmark session** (resume: `~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/resume.md`) owns:
  - that repo
  - `serving/{llama.cpp,omlx_0.7,lithos-metal,vllm-metal,mlx-lm,mlc-llm_bench,coreai-models}`
  - `models/{hf-bench,derived,mlc,coreai}`
  - ports 8700-8705
- **Untouched by both** (the user's own work): `serving/mlc-llm`, `serving/mlc-llm_2a`, `serving/mlc-llm_2b`, `experiments/coreai`. Read-only access is fine.

Rules for both sessions:
- Neither session edits the other's files or stops the other's processes.
- The HF cache (`~/Developer/ml_source/huggingface`) is add-only: no deletes, no moves. Both sessions use the same `mlx-community/Qwen3.8-27B-8bit` checkpoint read-only.
- GPU lock (`~/Developer/mlsys/experiments/.gpu-lock`, containing holder, purpose, start time and ETA):
  1. The side that is about to time creates the lock.
  2. It checks `lsof -nP -iTCP:8500 -sTCP:LISTEN`. If oMLX is up on 8500, it asks the agent-benchmark session to stop it.
  3. It deletes the lock when done.
  - Nobody starts a model server or loads a model while the other side holds the lock.
- Agent traces from the agent benchmark stay on this machine. They are never committed to the public serving-benchmark repo.

State at the 2026-10-17 23:50 pause:
- No lock is held, and nothing listens on 8500 or 8700-8705.
- After resuming, local_ai-benchmark messages the agent-benchmark session before its first lock.
- Whether the agent benchmark switches from 8-bit to 4-bit is the user's call, made after the serving results come in.
