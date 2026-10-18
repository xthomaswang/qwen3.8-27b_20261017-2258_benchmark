# Resume — current progress

Updated: 2026-10-18 18:30 (local). Rewrite this after every major phase, and read it first
when resuming.

## Current state (2026-10-18 18:30): battery re-run running

- **Finding: the night's timed runs ran on a nearly empty battery.**
  - The machine is on a 96 W USB-C adapter, which cannot supply it under sustained GPU load,
    so the battery drains even on AC.
  - Back-to-back timed runs drained it from 95 % (02:00) to 6 % (05:15): first the
    agent-benchmark session's harness smoke (02:17–04:15), then ours from 04:20. It stayed
    at 6–14 % until 08:40.
  - Near 6–7 % the system capped power:
    - llama.cpp 16K thinking decode fell from ~21.5 to 16.8 tok/s within a minute at
      05:16; 32K thinking ran at 15.7 tok/s;
    - vLLM-Metal's M2 64K took 187 s at 07:56–08:11, against 163 s (G5) at full charge.
  - `pmset -g therm` showed nothing. Thermal pressure (`notifyutil`) reached level 2 at
    night and in the afternoon alike, so it is not the cause.
  - **So "thinking decode is ~25 % slower" (open issue 2) was the power cap.**
- **Pre-registered check for the llama.cpp `mtp-off` M3 re-run.** The pre-cap trials
  (05:13–05:15) gave 21.5–22.0 tok/s at 16K with thinking on, against 23.1 with it off;
  a 5–7 % gap is expected from the longer context during generation.
  - Issue closed if 16K thinking ≥ 20.5 tok/s and 32K thinking ≥ 18.5 tok/s.
  - A real effect, to investigate server-side, if 16K ≤ 18 or 32K ≤ 17.
  - In between: look closer before deciding.
- **Quarantined** (moved to `raw/_unverified/`, with `README-battery.txt`). These ran with
  the battery below 30 %:
  - llama.cpp: m1, m2, m3 and m4 for `mtp-off`; m1, m3 and m4 for `mtp-on`; m5 for `conc`,
    with its monitor TSV.
  - oMLX: the night gate and m1–m5.
  - vLLM-Metal: the 07:46 gate, m1 and m2, with their monitor TSV.

  Kept: the M7 runs (correctness only, no timing), the afternoon runs (battery 91–100 %),
  and the night monitor TSVs that cover M7.
- **Tooling** (METHODOLOGY.md, "Battery"):
  - quietlib: a battery below 20 % marks a sample DISTURBED; the battery level and the
    thermal pressure level are logged in every row (TSV v3); new `battery --min --wait`
    subcommand; `check --min-battery`.
  - run_framework.sh waits up to 90 min, with the server idle and charging, until the
    battery is ≥ 40 %, both before the server starts and before each suite.
- **Harness fixes** (88 tests pass):
  - G3's drop check sums `input_tokens + cache_creation_input_tokens +
    cache_read_input_tokens`. All three frameworks split Anthropic usage, not only oMLX.
    With the sums, nothing is dropped: the tool_result image and the control differ by
    10–15 tokens.
  - M4 reports the slope with and without step 1. For oMLX it goes from −0.136 to
    +0.068 s/step once step 1 is left out.
- **Chain**, started at about 18:28 under a lock with a 300 min ETA:
  `scripts/run_tier1.sh vllm-rerun omlx-rerun llama-off-rerun llama-on-rerun llama-conc-rerun`
  (the log is named in `logs/tier1.current`). The gates are re-run too, so their fragments
  carry the G3 fix.
- **Daemons still paused:** suggestd (43674) since 16:19; mediaanalysisd (1221) and
  spotlightknowledged (50910) since 17:29:33. **Restore after the chain**, the user running
  `kill -CONT 43674 1221 50910`, then `launchctl enable gui/501/com.apple.suggestd`. Tell
  both other sessions.
- **Peers:** `localmelo_main` stopped its work at 18:18 and is waiting for our release
  message. The agent-benchmark session knows about the re-run, and it adopts the battery
  rule for its own timed runs.
- **Stay idle during timed suites:** only Monitor re-arms, and no `log show` or greps.

## State at 18:00 (superseded at 18:20: the night suites were quarantined; see above)

- **Tier-1 is fully measured.** Every suite below passed the pre-flight and the monitor
  check. The lock was released at 17:53:11, and both other sessions were told.

  | Variant (tag) | Verified suites |
  | --- | --- |
  | llama.cpp `mtp-off` (`4bit-mtp-off`) | gate (17:30, with G2b) m1 m2 m3 m4 m7 |
  | llama.cpp `mtp-on` (`4bit-mtp-on`) | m1 m3 m4 m7 |
  | llama.cpp `conc` (`4bit-conc`) | m5 |
  | llama.cpp anchor (`4bit-mtp-off-anchor`) | m1 (17:37) |
  | oMLX `spec-off` (`4bit-spec-off`) | gate (17:43, with G2b) m1 m2 m3 m4 m5 m7 |
  | vLLM-Metal `spec-off` (`4bit-spec-off`) | gate (16:32, with G2b) m1 m2 m3 m4 m5 m7 |

  Spec-on is n/a for oMLX and vLLM-Metal (formal run plan below).
- **This afternoon's segment, 16:31–17:53.**
  - Chain 1, `scripts/run_tier1.sh vllm-rest llama-gate llama-anchor omlx-gate`
    (`logs/tier1-rest2-20261018-163113.log`):
    - vLLM-Metal: the gate, m3 and m4 verified.
    - m5 was disturbed at 17:13:49: mediaanalysisd went to ~115 %. It was moved to
      `raw/_unverified/`. The retry never started, because the machine was not quiet within
      600 s, so the run stopped before m7.
    - The llama.cpp gate, the anchor and the oMLX gate then verified.
  - Chain 2, `scripts/run_tier1.sh vllm-m5m7` (`logs/tier1-rest3-20261018-174648.log`):
    vLLM-Metal m5 and m7 verified.
- **Background daemons paused for the timed runs** (METHODOLOGY.md §3 has the details):
  - **suggestd**, PID 43674. The user killed it at 16:13, but launchd relaunched it on
    demand and it went back to its harvesting queue at ~99 %; `caffeinate -u` had no effect.
    - `launchctl disable gui/501/com.apple.suggestd` is in force, but it does not unload
      the loaded job: after a `killall`, launchd started it again on an xpc event.
    - `launchctl bootout` is refused under SIP (error 150).
    - `kill -STOP 43674` at 16:19 (the user).
  - **spotlightknowledged** (PID 50910) and **mediaanalysisd** (PID 1221). From 17:13,
    spotlightknowledged generated Spotlight document embeddings, about 3 per second, as
    "foreground" text-processing tasks for mediaanalysisd. That kept mediaanalysisd at
    ~115 %, and the heartbeat had no effect.
    - `kill -STOP 50910 1221` at 17:29:33 (on the user's request).
    - The PID 27281 spotlightknowledged belongs to an iOS simulator runtime; it was idle
      and left alone.
  - **Restore** (the user; we asked at 17:55): `kill -CONT 43674 1221 50910`, then
    `launchctl enable gui/501/com.apple.suggestd`. Then fill the resume time into
    METHODOLOGY.md §3. The agent-benchmark session wants to know when this is done; it may
    want the daemons paused for its own timed runs.
  - **Our own session counts too.** This session's `claude` process runs at 20–35 % CPU
    while it is working, and it is outside the run's process tree. Stay idle during timed
    suites: no `log show`, no greps, and no summarize.
- **Anchor: passed** (acceptance fixed before the run; see METHODOLOGY.md §3).

  | Phase | 04:35 run | Anchor, 17:37 | Band |
  | --- | --- | --- | --- |
  | warm | 4.361 s (4.066–4.432) | 4.402 s (4.070–4.486) | 4.066–4.432 s |
  | cold | 31.205 s (31.127–31.362) | 31.390 s (30.941–32.175) | 30.58–31.83 s |

  The night-time llama.cpp and oMLX runs are therefore comparable with today's vLLM-Metal
  runs.
- **G2b, formal and verified.** The verdicts match the afternoon's mechanics runs.

  | Framework | G2b: image in `role=tool` (Hermes path) | G3: image in `tool_result` (Claude Code path) | G5 at 64K: TTFT, peak footprint |
  | --- | --- | --- | --- |
  | llama.cpp b11717 | PASS (prompt_tokens 1920 vs control 1935) | PASS | 151.0 s, 18.0 GiB |
  | vLLM-Metal 0.31.0 | PASS (1920 vs 1935) | PASS | 163.1 s, 62.4 GiB |
  | oMLX 0.7.1rc1, stock | **FAIL**: image dropped (639 vs 1936; it answered "a blank white display") | PASS | 101.7 s, 23.0 GiB |

  More from the oMLX gate:
  - `reasoning_effort=none` alone does not disable thinking; `enable_thinking=false` is
    needed too.
  - Its Anthropic `usage.input_tokens` is 0, by design. When a request carries
    `cache_control` (Claude Code's requests do), oMLX splits the prompt the Anthropic way:
    `input_tokens` 0, plus `cache_creation_input_tokens` and `cache_read_input_tokens`
    (`omlx/api/anthropic_utils.py` 1059–1066, found by the agent-benchmark session). The
    prompt length is the sum of the three. Our G3 drop check reads `input_tokens` only, so
    for oMLX it could not compare token counts; the verdict rests on the code read back.
- **Decisions for the PRs:**
  - **Superseded gates.** vLLM-Metal (07:50) and oMLX (night) also have earlier verified
    gates without G2b, while summarize reports the latest. Commit both and say in
    `summary.md` which one the table uses.
  - **The anchor** has its own section in `llama.cpp/summary.md`. Publish it as a
    validation row, with the 04:35 comparison.
  - **Scripts.** Commit the `run_tier1.sh` steps (`vllm-rest`, `llama-gate`,
    `llama-anchor`, `omlx-gate`, `vllm-m5m7`) with the results.

## State at 14:55: blocked on suggestd; G2b answered (unverified)

- **14:22–14:52 session.**
  - The user said continue, so we took the lock at 14:22.
  - **The vLLM-Metal m3–m7 run never started.** suggestd was back at ~100 % of a core
    (188 CPU-min by 14:52), and this time the 60 s `caffeinate -u` heartbeat did not stop
    it; the lid had just been opened at 14:19. The pre-serve check gave up after 300 s with
    "nothing started".
  - The user was asked to run `! killall suggestd`; the classifier still blocks us from
    doing it.
  - While blocked, we landed the harness changes (below) and ran the three gates in
    mechanics mode to answer G2b.
  - The lock was released at 14:52:33. Both other sessions were told: the agent-benchmark
    session, and `localmelo_main` (socket `uds:/tmp/cc-socks/96257.sock`).
  - **Protocol addition:** message `localmelo_main` at least 10 min before taking the lock.
    It watches the lock file and stops its CPU work within ~15 s.
- **G2b answered** (unverified: mechanics mode, with suggestd busy). The functional
  verdicts stand; timing parts such as G5 TTFT are not publishable from these runs.

  | Framework | G2b: image in `role=tool` (Hermes path) | G3: image in `tool_result` (Claude Code path) |
  | --- | --- | --- |
  | llama.cpp b11717 | PASS (prompt_tokens 1920 vs control 1935) | PASS |
  | vLLM-Metal 0.31.0 | PASS (1920 vs 1935) | PASS |
  | oMLX 0.7.1rc1, stock | **FAIL**: image dropped (639 vs 1936); model cannot see it | PASS |

  Other notes from these gates:
  - G5 peak footprint at 64K: llama.cpp 18.0 GiB, oMLX 23.0 GiB, vLLM-Metal 62.5 GiB (it
    reserves 0.55 × RAM of KV at startup).
  - vLLM-Metal rejects `reasoning_effort=high` with 400.
  - oMLX's SSD prefix cache survives restarts: G1 cold TTFT was 1.3 s. Our cold
    measurements carry nonces, so they are not affected.
- **Harness changes** (85 tests pass):
  - `ef9bb1e`: G2b, and the G3 tool_result-image probe.
  - `ef9bb1e` also: summarize counts `incomplete_tool_call` cap-truncated streams as latency
    samples, and recomputes the M4 slope from the request lines.
  - `511f72b`: `capabilities.md` shows only verified gate runs.
- **Correction to issue 1.** oMLX's M4 run totals were never wrong: they include every
  step's e2e. Only the per-step n and the slope were affected, and both are fixed. The
  regenerated table shows a real effect: oMLX step 1 TTFT is about 17.9 s, close to a full
  re-prefill, against about 3.7 s from step 2 on. Its hybrid prefix cache does not reuse
  the step-0 prompt at step 1. For comparison, llama.cpp is 5.7 s at step 1. Report the
  slope with and without step 1.

## State before 14:22 (second pause, 10:14)

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
      should show the drop. In the summary, report the patch as a known, unreleased fix. The patched build passed G2b (10:26): it read the code from the `role=tool`
      image, with 1600 prompt tokens.
    - **Client-side caveats for the summary** (from the agent-benchmark session; these are
      not framework issues):
      - **Hermes.** By default Hermes sends no image at all. It cannot find our custom
        provider's Qwen3.8 in models.dev, so it treats the model as non-vision and replaces
        MCP images with a `MEDIA:<path>` text reference. Only with
        `model.supports_vision: true` in its config do images reach the `role=tool`
        message. G2b models that configured case.
      - **Claude Code.** With the MCP filesystem server's `read_media_file`, Claude Code
        sends the image block *and* `structuredContent`, a second base64 copy as about
        82 KB of text. One 1280×1024 screenshot step then costs about 64K prompt tokens.
        Worth noting for long screenshot trajectories.
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
| 3–4 | Formal gate + metrics, one `bench/<fw>` PR each, self-merged | **in progress**: Tier-1 measured (17:53); PRs next; references, 8-bit rows and M6 pending |
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

1. **Restore the paused daemons** (the user; asked at 17:55): `kill -CONT 43674 1221 50910`,
   then `launchctl enable gui/501/com.apple.suggestd`. Fill the time into METHODOLOGY.md §3
   and tell the agent-benchmark session. Pause them again only for a later timed segment,
   and only if they are busy then.
2. **Fix the open issues** (no GPU; run pytest afterwards):
   1. G3 drop check, Anthropic path: compare the sum `input_tokens +
      cache_creation_input_tokens + cache_read_input_tokens`. Check whether the raw jsonl
      keeps the full usage; if it does, recompute instead of re-running.
   2. Thinking-mode decode: llama.cpp is ~25 % slower with thinking on, but vLLM-Metal is
      not (M3 at 16K: 25.5 tok/s against 26.3). Check llama.cpp's request shape and
      server-side `timings`.
   3. M4: report the slope with and without step 1 (oMLX step 1 is a near-full re-prefill).
   4. Redaction: show `/Applications/` paths as `<app>` in quietlib, and redact third-party
      app names in the monitor TSVs and pre-flight blocks before committing.
3. **Per-framework PRs** (`bench/llama.cpp`, `bench/omlx`, `bench/vllm-metal`):
   1. Commit `raw/*.jsonl`, `raw/*.md`, the monitor TSVs, `summary.md`, `capabilities.md`,
      the `env.md` updates and `scripts/run_tier1.sh`.
   2. Open the PR and self-merge it.
   3. Update the README status table and this file.
4. **Interim Chinese summary to the agent-benchmark session**: the Tier-1 comparison (gate
   pass/fail and M1–M7 for the three candidates), since the user is choosing a serving
   stack now. The final summary follows step 7.
5. **References**, `--text-only`, one at a time with the lock (and the 10 min notice to
   `localmelo_main`): lithos-metal (`dspark`, `no-draft`, `nvfp4`, with `--server-log`),
   mlx-lm, Core AI (`--profile generic`) and MLC-LLM. For MLC-LLM, run G1 first with the
   log open.
6. **The rest:** 8-bit rows (oMLX, vLLM-Metal, mlx-lm; M1/M4/M7), the direct-call
   A/B/A/B, and M6 (10–15 min for the candidates, 30 min for the finalists).
7. **Summary.** Open the summary PR, and send the Chinese summary to the agent-benchmark
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
- The agent-benchmark session ran untimed G2b probes on 8500: stock oMLX from 10:14:38 to
  10:15:19, then its patched build from 10:21:10 to 10:26:56. No lock is held. Nothing of ours runs: no server on 8700–8705, no
  heartbeat, no monitor.
- After resuming, local_ai-benchmark messages the agent-benchmark session before its next
  lock.
- Whether the agent benchmark switches from 8-bit to 4-bit is the user's call, made after the
  serving results come in.
