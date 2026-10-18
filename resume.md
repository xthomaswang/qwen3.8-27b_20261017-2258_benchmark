# Resume — current progress

Updated: 2026-10-18 10:15 (local). Rewrite this after every major phase, and read it first
when resuming.

## Current state (2026-10-18 10:15): Tier-1 paused again by the user

- **Two pauses so far, both on the user's request.**
  - The first was at 08:39.
  - The run resumed at 09:44 (vLLM-Metal m3,m4,m5,m7, then the llama.cpp gate, then the
    anchor).
  - The second pause came at 10:13:55. The user asked to let the nearly finished suite end
    and then stop, so vLLM-Metal's m3 was allowed to finish. A trigger then stopped the
    runner before the m3 retry could start; its harness was killed within a second and
    wrote no file.

  The runner, harness, server, monitor and heartbeats are all stopped, and ports 8700–8705
  are free. The lock was released at 10:14:15, and the agent-benchmark session was told.
  Before resuming, message them, then acquire the lock.
- **Tier-1 status.** Every "verified" suite passed the pre-flight and the monitor check.

  | Variant (tag) | Verified suites | Still to run |
  | --- | --- | --- |
  | llama.cpp `mtp-off` (`4bit-mtp-off`) | m1 m2 m3 m4 m7 | **gate**: disturbed twice (startup burst, then suggestd) |
  | llama.cpp `mtp-on` (`4bit-mtp-on`) | m1 m3 m4 m7 | — |
  | llama.cpp `conc` (`4bit-conc`) | m5 | — |
  | oMLX `spec-off` (`4bit-spec-off`) | gate m1 m2 m3 m4 m5 m7 | — |
  | vLLM-Metal `spec-off` (`4bit-spec-off`) | gate m1 m2 | **m3 m4 m5 m7**: three m3 attempts, none clean (below) |

- **Working tree.** Nothing from the formal runs is committed or pushed yet. The results
  are untracked in `<fw>/raw/`, `<fw>/summary.md` and `<fw>/capabilities.md`.
  - `llama.cpp/capabilities.md` holds the gate fragment of a *disturbed* attempt. The gate
    re-run overwrites it; do not commit it before then.
  - `vllm-metal/summary.md` holds only the M2 section, because each per-suite run-all
    upserts its own suite. Regenerate it after the remaining suites (`agentbench summarize
    --framework vllm-metal --tag 4bit-spec-off --write`).
  - Quarantined in `raw/_unverified/` (gitignored, never publish):
    - llama.cpp: gate ×2 and the first m2 attempt;
    - vLLM-Metal:
      - the first m1 attempt (airportd);
      - m3 at 08:11 (sysmond, plus another session's 50 s grep);
      - the partial m3 at 08:36, cut by the first pause;
      - m3 at 09:49, which finished but is disturbed: one com.apple.WebKit.WebContent
        process at 86 % for two samples at 09:52;
      - that run's monitor TSV (`monitor-4bit-spec-off-20261018-094709.tsv`).

      The 09:49 m3 stays unpublished, however consistent its trials look.
- **Daytime use of the Mac adds disturbances.** Since about 09:50, WebKit content (Mail,
  Safari, widgets), Activity Monitor (through sysmond) and app activity have tripped the
  persistence rule more often than the night did. The user was asked to close Mail, the
  browser and Activity Monitor during timed runs; otherwise expect more automatic repeats.
- **Numbers stay local until the PRs.** The preliminary tables are in the untracked
  `<fw>/summary.md` files. They are not copied here, because this file is public, and one
  of them is known to be off: oMLX's M4 per-run totals may skip the error-flagged steps (issue 1
  below).
- **New gate item G2b** (requested by the agent-benchmark session; do it before the PRs).
  - **Why.** Real agents send screenshots *inside tool results*: Claude Code's MCP
    screenshot is an image block in `tool_result`, and Hermes keeps the image in the
    `role=tool` message. oMLX 0.3.9 used to drop such images. A framework that drops them
    leaves computer use blind, which matters more than TTFT.
  - **G2b, OpenAI path.**
    1. The user asks "take a screenshot and tell me the code".
    2. The assistant replies with `tool_calls` for `computer_screenshot`.
    3. The `role=tool` message carries `[text, image_url data URI]`, using the same
       1280×1024 `g2-verify` image as G2.

    Control: the same image in a following user message. Pass: the code is read back.
    Record `prompt_tokens` for both; a drop shows as roughly 1.3K fewer tokens than the
    control.
  - **New G3 sub-probe, Anthropic path.** `tool_use(computer_screenshot)` →
    `tool_result` with `[image block, text]`, plus a control. Same pass rule.
  - **Then.** Run pytest. Re-run the gate on llama.cpp (it needs one anyway), oMLX and
    vLLM-Metal, about 15 min. If a framework fails G2b, flag it in the summary. M1 and M4
    use `--screenshot-placement user` by default; `tool` exists in the harness if needed.
  - **First data point** (agent-benchmark session, 10:15, on its own oMLX 0.7.1rc1 8-bit
    instance, with our `g2-verify.png`; untimed). To be confirmed on our 4-bit runs.
    - OpenAI: the image in the `role=tool` message is **dropped**. prompt_tokens was 313
      against 1603 for the user-message control, and the model invented a code.
    - Anthropic: the image in `tool_result` works. prompt_tokens was 1600 against 1601,
      and the code was read correctly.
    - So on oMLX, Claude Code sees screenshots, but Hermes-style OpenAI tool images do not.
    - Their stdlib probe is at `experiments/personal-agent-bench/scripts/probe_tool_images.py`.
      Read it as a reference; do not copy their run data into this repo.
    - **Local patch.** With the user's consent, the agent-benchmark session patched its *own*
      oMLX worktree to keep OpenAI tool-message images, following oMLX's Anthropic path:
      branch `pab/openai-tool-message-images`, commit `57620a3f`, not pushed upstream. It was
      re-testing that at 10:21. Our `serving/omlx_0.7` stays stock 0.7.1rc1, so our G2b
      should show the drop. In the summary, report the patch as a known, unreleased fix.
- **Open issues to fix before the PRs.**
  1. **oMLX M4 errors.**
     - What happens: 22 of 63 requests ended with an `incomplete_tool_call` stream error,
       raised when the 150-token cap cut a multi-call step. llama.cpp returns
       `finish_reason=length` for the same thing.
     - Effect: the harness counts these as errors, so some steps show n=0. Their TTFT and
       e2e are valid; cached tokens are missing because no usage chunk arrives.
     - Fix: in `summarize`, count cap-truncated streams as latency samples and flag them.
       Then run pytest and regenerate the summaries. Note it in capabilities, since it is
       safer agent behaviour.
  2. **llama.cpp thinking-mode decode is ~25 % slower** than non-thinking, with MTP off and
     on. Check the M3 thinking request shape (sampling fields?) and the server-side
     `timings`.
  3. **Drift anchor.** Re-run llama.cpp `mtp-off` M1 under tag `4bit-mtp-off-anchor` and
     compare it with 04:35 (warm 4.361 s, cold 31.205 s). This checks for thermal or
     long-run drift across the block.
  4. **Privacy check before committing.** The monitor TSVs and pre-flight blocks list
     foreign process basenames: Apple apps such as Maps, Music and Mail, and possibly
     third-party apps. Redact third-party app names before pushing.
- **Tooling learned tonight** (all in METHODOLOGY.md, "Quiet machine"; commits up to
  `0ebf4d0`).
  - **Heartbeat.** macOS discretionary daemons (suggestd, mediaanalysisd) start on an idle
    machine on AC power. A `caffeinate -u -t 1` heartbeat every 60 s stops them within 5 s;
    a single held assertion lasts only ~7 min. `killall suggestd` was denied by the
    auto-mode classifier, so it was not used.
  - **Persistence rule.** verify counts CPU only when the same process, or the total, stays
    over the limit in consecutive samples. One-sample blips (Watch sync, Spotlight, WebKit,
    Maps, Apple Intelligence) come about every minute.
  - **Other sessions.** Other Claude sessions on the machine can disturb runs: at 08:27
    `localmelo_main` ran a 50 s grep. The agent-benchmark session relays requests to them.

| # | Phase | Status |
| --- | --- | --- |
| 0 | Plan, repo scaffold, methodology | **done** |
| 1 | Framework installs + flag research | **done** (all seven) |
| 1b | Manual smoke tests | **done** |
| 2 | Harness + fixtures + quiet-machine tooling | **done**; live mechanics check passed 04:16–04:23 |
| 3–4 | Formal gate + metrics, one `bench/<fw>` PR each, self-merged | **in progress**: Tier-1 ~80 % done, paused; no PR yet |
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

1. **Resume Tier-1.** Message the agent-benchmark session first, then run
   `scripts/gpu_lock.sh acquire "Tier-1 remainder: vLLM-Metal m3-m7, gates with G2b, anchor" 120`.
   Start the vLLM part in the background (`nohup … > logs/tier1-rest-<ts>.log 2>&1 &`) and
   watch it with a Monitor:
   ```
   scripts/run_framework.sh vllm-metal spec-off 4bit vllm 4bit-spec-off m3,m4,m5,m7 --spec-label off
   ```
   Expect about 60 min, more if daytime use triggers repeats.
2. **Implement G2b and the G3 tool_result-image sub-probe** (above). Do this while no timed
   segment runs, then run pytest. The agent-benchmark session ran a G2b probe on its own
   oMLX 0.7.1rc1 at 10:14 and will send the results; use them as a reference.
3. **Re-run the gates with G2b**, plus the anchor:
   ```
   scripts/run_framework.sh llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off gate
   scripts/run_framework.sh llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off-anchor m1
   scripts/run_framework.sh omlx spec-off 4bit omlx 4bit-spec-off gate
   scripts/run_framework.sh vllm-metal spec-off 4bit vllm 4bit-spec-off gate
   ```
   Then release the lock and tell the peer.
4. **Fix the open issues** above: summarize, the thinking-decode check, the anchor
   comparison and the redaction. Run pytest outside any timed segment.
5. **Per-framework PRs** (`bench/llama.cpp`, `bench/omlx`, `bench/vllm-metal`):
   1. Commit `raw/*.jsonl`, `raw/*.md`, the monitor TSVs, `summary.md`, `capabilities.md`
      and the `env.md` updates.
   2. Open the PR and self-merge it.
   3. Update the README status table and this file.
6. **References**, `--text-only`, one at a time with the lock: lithos-metal (`dspark`,
   `no-draft`, `nvfp4`, with `--server-log`), mlx-lm, Core AI (`--profile generic`) and
   MLC-LLM. For MLC-LLM, run G1 first with the log open.
7. **The rest:** 8-bit rows (oMLX, vLLM-Metal, mlx-lm; M1/M4/M7), the direct-call
   A/B/A/B, and M6 (10–15 min for the candidates, 30 min for the finalists).
8. **Summary.** Open the summary PR, and send the Chinese summary to the agent-benchmark
   session: gate pass/fail per framework, the metrics, the recommendation and the reasons.

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

State at the 2026-10-18 10:14 pause:
- The agent-benchmark session ran its untimed G2b probe on 8500 from 10:14:38 and released
  the lock at 10:15:19. No lock is held. Nothing of ours runs: no server on 8700–8705, no
  heartbeat, no monitor.
- After resuming, local_ai-benchmark messages the agent-benchmark session before its next
  lock.
- Whether the agent benchmark switches from 8-bit to 4-bit is the user's call, made after the
  serving results come in.
