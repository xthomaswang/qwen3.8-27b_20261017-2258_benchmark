# Resume — current progress

Updated: 2026-10-19 09:20 (local). Rewrite this after every major phase, and read it first
when resuming.

## Current state (2026-10-19 09:20): Tier-2 block done; Q8_0 downloading; next block planned

- **The overnight block, 22:36–09:05** (`logs/tier2-20261018-223602.log`). All steps
  returned rc 0. The user moved lithos-metal to the front.
  - **Battery pauses:** 02:10:46 (43 %) to 02:49:19, and 05:11:06 (47 %) to 05:47:09. The
    script released and re-took the lock itself. The session was blocked on an
    AskUserQuestion from 23:47 to 06:45, so no notices went out; `localmelo_main` watched
    the lock file. Never block while a chain runs.
  - **Verified:**
    - lithos-metal `dspark`, `no-draft` and `nvfp4`: gate, M2, M3, M7 (`no-draft` has no
      gate);
    - M6 for llama.cpp `mtp-on`, oMLX and vLLM-Metal;
    - 8-bit gate, M1, M4 and M7 for oMLX and vLLM-Metal, and gate and M7 for mlx-lm;
    - mlx-lm 4-bit: gate, M2, M3, M7.
  - **Invalid, then quarantined:** the mlx-lm and lithos M1/M4. Each suite runs in its own
    process, so the gate's auto text-only switch never reached them, and they sent
    screenshots to servers that reject images. Fixed in `c9581b1`, which forces text-only in
    those profiles and sends lithos all-text content as strings; 96 tests pass.
- **8-bit findings,** sent to the agent-benchmark session:
  - stock oMLX 8-bit fails G2b, like 4-bit;
  - oMLX M4 step 1 re-prefills at 8-bit too;
  - vLLM-Metal passes everything; its peak footprint is 62 GiB;
  - both 8-bit MLX runs fail `m7-07-enum`, as llama.cpp Q4_K_M does, so the llama.cpp
    note is corrected: a borderline case, not GGUF.
- **Next block** (the user's order: A1-relevant first). The steps are in `run_tier2.sh`:
  1. `omlx-8bit-m3`, then `llama-q8-off` and `llama-q8-on`. The Q8_0 GGUF (29.05 GB) is
     downloading now; the user approved it at 09:10.
  2. `mlxlm-8bit-fix`, `mlxlm-4bit-fix`, then `lithos-dspark-fix`, `lithos-nodraft-fix` and
     `lithos-nvfp4-fix`. Each re-runs M1 and M4; lithos's M4 runs once, because it has no
     prefix cache.

  Give `localmelo_main` the 10 min notice first. suggestd (43674) and mediaanalysisd
  (93568) have been paused since 22:35:45; the user resumes them after the block.
- **Then:** the PRs for lithos-metal, mlx-lm, the 8-bit rows and M6. After that, Core AI,
  MLC-LLM and the A/B comparison (daytime, someone present), the summary PR and the final
  Chinese summary.
- **Last: disk cleanup** (the user's request). List the candidates with their sizes, and
  confirm the shared or big ones with the user before deleting.

## Overnight block (planned 2026-10-18 23:00, the user's choice)

- **Chain:** `scripts/run_tier2.sh`, run in this order:
  1. M6: llama.cpp `mtp-on` and oMLX for 30 min each, vLLM-Metal for 15 min;
  2. the 8-bit rows (oMLX, vLLM-Metal, mlx-lm), each with the gate plus M1, M4 and M7;
  3. the text-only references: mlx-lm 4-bit, then lithos-metal `dspark`, `no-draft` and
     `nvfp4`.

  Lock ETA 540 min. The log is named in `logs/tier1.current`.
- **Before it starts:** the user pauses suggestd (43674) and mediaanalysisd (93568) with
  `kill -STOP`. spotlightknowledged was not running at 22:23; it starts on demand. The
  chain starts at 23:00 only once suggestd is paused or idle.
- **In the morning:** the user resumes them with `kill -CONT 43674 93568`. Tell
  `localmelo_main` and the agent-benchmark session when the lock is released.
- **Deferred to a daytime block,** because these need someone at the machine:
  - Core AI, which is not in `serve.sh` (`coreai/env.md`);
  - MLC-LLM, whose G1 runs first with the log open;
  - the direct-call A/B/A/B;
  - a possible llama.cpp Q8_0 row: the GGUF is 29.05 GB, MTP works through the separate
    `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` draft, and the agent-benchmark session asked. The
    user decides.

## Current state (2026-10-18 22:15): Tier-1 published (PRs #1–#3)

- **Tier-1 is done.** PRs #1 (llama.cpp), #2 (oMLX) and #3 (vLLM-Metal) are merged. Each
  framework directory holds:
  - the verified raw files, redacted with `scripts/redact.py`;
  - the monitor TSVs;
  - `summary.md`, opening with a hand-written "Read first" block outside the generated
    markers;
  - `capabilities.md`;
  - an `env.md` section on the measurement environment;
  - `raw/superseded/`, for the gates that ran before the G3 fix.

  README.md has the status table and a Tier-1 overview.
- **Battery re-run, 18:27–21:58.** All suites verified; the battery never fell below 63 %.
  - Repeats, all automatic and quarantined: systemstats, ANECompilerService, and
    power-adapter dropouts at 19:09:44, 19:10:17 (about 5 s each) and 19:57:19–20:01:01.
  - oMLX m2 needed a third run (`run_tier1.sh omlx-m2`).
  - **The thinking-decode issue is closed**, against the pre-registered band. llama.cpp
    thinking-on decode equals thinking-off: 23.7 against 24.0 tok/s at 16K, and 22.0 against
    22.0 at 32K. The night's gap was the power cap.
- **The daemons were resumed at 22:02:05**, by the user in the agent-benchmark session
  (`kill -CONT`, plus `launchctl enable` for suggestd).
  - mediaanalysisd exited on resume; launchd started PID 93568.
  - spotlightknowledged exited cleanly and is started on demand.
  - suggestd went back to its queue at ~96 %.
  - Pause them again, with their new PIDs, before the next timed segment if they are busy.
- **Quarantined absolute numbers stay private.** Public text gives the power cap's effect
  only in relative terms (METHODOLOGY.md, "Battery"). Older commits still hold some
  night-time figures; do not rewrite history without the user's approval.
- **Privacy.** quietlib shows non-Apple app bundles as `<app>` (by `CFBundleIdentifier`).
  Before committing older files, run `scripts/redact.py --check` on them.

## State at 18:00 (superseded: the night suites were quarantined at 18:20 and re-run by 21:58)

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
- **Anchor: passed** (acceptance fixed before the run; see METHODOLOGY.md §3). The 17:37
  M1 (battery 96 %) matched the 04:35 run (battery 29 %) within 1 %, warm and cold. The
  04:35 run was quarantined later anyway, under the battery rule.
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
     compare it with the 04:35 run. This checks for thermal or
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

1. **Interim Chinese summary to the agent-benchmark session** (Tier-1: gates and M1–M7 for
   the three candidates, with a recommendation). Sent at 22:20, with a follow-up on oMLX's
   thinking-on TTFT.
2. **References**, `--text-only`, one at a time with the lock. First give the 10 min notice
   to `localmelo_main`, check the battery (≥ 40 %), and pause busy daemons with the user's
   consent. Then run lithos-metal (`dspark`, `no-draft`, `nvfp4`, with `--server-log`),
   mlx-lm, Core AI (`--profile generic`) and MLC-LLM. For MLC-LLM, run G1 first with the
   log open.
3. **The rest:** 8-bit rows (oMLX, vLLM-Metal, mlx-lm; M1/M4/M7), the direct-call
   A/B/A/B, and M6 (10–15 min for the candidates, 30 min for the finalists).
4. **Summary.** Open the summary PR, and send the final Chinese summary to the
   agent-benchmark session.

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
