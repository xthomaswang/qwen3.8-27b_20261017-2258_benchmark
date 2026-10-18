# Resume — current progress

Updated: 2026-10-18 02:10 (local). Work resumed at 00:20 on a good network (HF ~30 MB/s),
and large downloads are allowed again. Rewrite this after every major phase, and read it
first when resuming.

## Current state (2026-10-18 02:10)

- **The harness is done.** Commit `6b6a2db`; 82 pytest pass.
  - Measured sizes: agent prefix 14,905 tokens; screenshot 1,282; M1 trial 16,590
    (1,641 new); M4 step-20 prompt 49,082.
  - Profiles: llamacpp, omlx, vllm, lithos, mlxlm, mlc (xgrammar structured output), generic.
- **Live quick validation passed** (unverified, in `raw/_unverified/`).
  - llama.cpp 4-bit with MTP:
    - G1–G4 pass.
    - M1: warm TTFT 4.5 s vs cold 33.3 s, 14,947 cached tokens.
    - M4: each step reuses all but ~1.7K new tokens, ~4.9 s per step.
    - M7: 6/6.
  - oMLX 4-bit:
    - G1–G4 pass.
    - M1: warm 3.35 s vs cold 24.0 s.
    - M7: 6/6.
    - `temperature 0` is honoured.
- **Runner.** `scripts/run_framework.sh <fw> <variant> <tier> <profile> <tag> <suites> [args]`
  runs serve → wait → warm-up → `run-all --preflight` → stop. The lock must already be held.
- **Quiet-machine rule** (user, 01:46): publish only quiet runs.
  - `scripts/quiet_check.sh` gates each suite.
  - Disturbed runs go to `<fw>/raw/_unverified/`, which is gitignored, and are repeated.
  - Tonight's direct-call numbers (Core AI vs MLX, 512 and 16K) are unverified, because of
    background fixture generation. They will be re-run A/B/A/B.
- **Core AI.**
  - The 27B bundle is exported to `~/Developer/mlsys/models/coreai/qwen3_8_27b_qwen3_5_cfg_dynamic`
    (16 GB; 296 s; 37.7 GB peak footprint).
  - `llm-server` exists, so Core AI gets a text-only server row.
- **MLC-LLM.**
  - The nightly wheels abort on import even after re-signing (user-approved).
  - The source build is in progress (agent). Tool calls go through xgrammar structured
    output.
- **GPU schedule.** The agent-benchmark session runs its 1.5–2 h harness smoke next. Our
  formal matrix starts after it releases the lock.

| # | Phase | Status |
| --- | --- | --- |
| 0 | Plan, repo scaffold, methodology | **done** |
| 1 | Framework installs + flag research | **done** for 5 servers + Core AI. MLC-LLM: source build in progress. |
| 1b | Manual smoke tests | **done** |
| 2 | Harness + fixtures | **done** (live quick validation on llama.cpp and oMLX) |
| 3–4 | Formal gate + metrics, one `bench/<fw>` PR each, self-merged | **next**, after the peer's slot |
| 5 | Summary PR + Chinese summary to the agent-benchmark session | pending |

## Formal run plan (quiet machine, `--preflight` on every run)

1. **Agent candidates, 4-bit, full suites:**
   - llama.cpp `mtp-off` and `mtp-on`; the `conc` variant is used only for M5.
   - oMLX `spec-off`.
   - vLLM-Metal `spec-off`. Spec-on is n/a for oMLX and vLLM, with the reasons recorded.
2. **References, 4-bit, `--text-only`:**
   - lithos-metal: `dspark`, `no-draft`, `nvfp4`, with `--server-log`.
   - mlx-lm.
   - Core AI: `--profile generic`; force `--text-only`, because images are dropped silently.
   - MLC-LLM: run G1 alone first with the log open.
3. **8-bit rows** for oMLX, vLLM-Metal and mlx-lm, on M1, M4 and M7.
4. **Direct-call A/B/A/B:** Core AI vs `mlx_lm.benchmark`, 512 and 16K, 60 s idle between runs.
5. **M6 stability:** 10–15 min for the three candidates; 30 min for the two finalists.
6. **Trials:** run M7 separately with `--trials 1`. For no-cache servers, budget about
   15 min for each M3 64K cell.

**Caveats to carry into the summaries:**
- vLLM reserves 0.55 × RAM of KV at startup.
- Text-only substitution skips the vision encoder.
- Spec on/off exists only for llama.cpp (MTP) and lithos-metal (DSpark).

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
