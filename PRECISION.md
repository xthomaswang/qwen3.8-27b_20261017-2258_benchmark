# oQ precision study: oQ4, oQ5, oQ6 and oQ8 with Lightning MTP, 2026-10-21/22

The question: how much speed and answer quality change across oMLX's oQ levels, and which
level gives the best balance for agent use. Everything runs on oMLX 0.7.1rc1 with Lightning MTP,
the recommended setup ([README](README.md#conclusion-2026-10-21)).

## Summary

What an agent user would notice:

| | oQ4 | oQ5 | oQ6 | oQ8 |
| --- | --- | --- | --- | --- |
| Weights on disk | 16 GB | 19 GB | 22 GB | 28 GB |
| Server footprint in M6, start / peak | 26 / 33 GiB ² | 32 / 36 GiB | 39 / 40 GiB | 46 / 47 GiB ² |
| Aider, solved of 36 (3 harnesses × 12) | 27 | 32 | 31 | 33 |
| Screenshot reading, correct of 60 | 54 | 54 | 56 | 54 |
| M7 tool calls × 5 at temperature 1.0, of 120 | 111 ¹ | 107 | 103 | 98 ¹ |
| Token KL / top-1 against BF16, all positions | 0.216 / 91.7 % | 0.093 / 95.4 % | 0.043 / 97.3 % | 0.013 / 98.5 % |
| M3 decode at 16K, cap 300, thinking off | 75.7 tok/s | 61.9 tok/s | 51.8 tok/s | 45.3 tok/s ² |
| M4 20-step trajectory, median total | 172 s | 171 s | 187 s | 195 s ² |
| M6 requests in 30 min | 233 ² | 212 | 199 | 190 ² |

¹ Measured by the agent-benchmark session on the afternoon of 2026-10-21 with
`--thinking-fields kwargs`, not in this study's night run. oQ5 and oQ6 are from the night run.
² From Tier-3, 2026-10-20. All other speed numbers are from the night of 2026-10-21/22.

- **oQ4 is the only level that loses on agent tasks.**
  - It solves 27 of 36 Aider exercises, against 31–33 for the others.
  - It drifts on prose. On the Hermes README, KL is 0.18 and cross-entropy rises 18 % for
    English and 27 % for Chinese.
  - Code and the agent's own turns stay close to BF16, at KL 0.016–0.020.
- **oQ5, oQ6 and oQ8 cannot be told apart on tasks.**
  - Aider: 32, 31 and 33 of 36. oQ5 and oQ6 ran in the same session; paired, only oQ5 failed 3
    times and only oQ6 failed 4 times (p = 1.0).
  - Screenshots: 54–56 of 60, with the same misses at every level: O against 0 in 16 px Menlo,
    and the case of f/F at low contrast.
  - M7 × 5 does not follow precision either.
    - oQ4 and oQ8 scored 111 and 98, from the agent-benchmark session's run on 2026-10-21.
    - oQ5 and oQ6 scored 107 and 103, from this night.
    - The misses are a few borderline cases, not a quality signal. With the harness defaults,
      the one miss at oQ5, oQ6 and oQ8 is the same case, `m7-07-enum`.
- **The token level orders the levels as expected.**
  - KL falls 2–3× with each step up: 0.216, 0.093, 0.043, 0.013.
  - Against the reference gate used for the oQ4 decision (KL ≤ 0.05, top-1 ≥ 94 %):
    - oQ6 and oQ8 pass;
    - oQ5 fails on KL only. The excess comes from tool-output segments, where BF16's own
      logits are least stable; its code (0.006) and agent turns (0.005) are well inside the gate;
    - oQ4 fails on both.
- **oQ5 keeps oQ4's speed where an agent spends its time.**
  - On the same night, its 20-step trajectory took as long as oQ4's with the harness
    defaults: 171 s against 172 s. M4 is dominated by prefill and short tool-call outputs.
  - With the model's sampling it took 182 s. That compares with 189 s for oQ6 on the same
    night, and 164 s for oQ4 on 2026-10-20.
  - Its decode is 11–18 % slower than oQ4's from 16K to 64K, and 19 % faster than oQ6's at 16K.
  - In the agent-benchmark session's Aider runs, oQ5 needed a median 0.81 of oQ6's time per
    exercise: 28 pairs, with about the same number of calls (223 against 227).
- **oQ8 is the slowest.** It decodes at 45 tok/s at 16K and 34 at 64K. Its trajectory took
  23 % longer than oQ4's on the same night (2026-10-20), and 14 % longer than oQ5's across
  nights.
- **Memory.** Each step up adds 3–7 GiB to the server footprint. Every level fits in 128 GB
  with room to spare.

**Reading.**
- **oQ5** is the balance point for agent use. It shows no task-level loss against oQ6 or oQ8,
  runs the default trajectory at oQ4's speed, and its server uses 11–14 GiB less than oQ8's.
- **oQ6** is the choice if token-level fidelity on long prose matters, since it passes the KL
  gate with margin. Its trajectories take 4–9 % longer than oQ5's.
- **oQ4** is only worth it if memory or raw decode speed comes first. It is the only level
  that loses Aider exercises.

The agent benchmark keeps oQ8 until the user picks a level.

## Setup

- **Machine.** MacBook Pro, Apple M5 Max, 128 GB; macOS 27.2 (26B5101f); Xcode 27.1 (27A9275).
  On the power adapter all night.
- **Server.** oMLX `v0.7.1rc1 (7a5a3d75)`, stock, on port 8703, with Lightning MTP. G2b fails on
  stock oMLX at every level, as it did on 2026-10-18 to 10-20. That is the missing patch, not
  precision.
- **Checkpoints.** All four levels were converted from BF16 `Qwen/Qwen3.8-27B` with
  `scripts/oq_convert.py`: oMLX's streaming oQ quantizer, group size 64, with the MTP head kept.
  - oQ5 and oQ6 took about 100 s each on 2026-10-21; oQ4 and oQ8 were converted on 2026-10-19/20.
  - The agent-benchmark session converted its own oQ5 and oQ6. Their sha256 match ours for
    every shard, `config.json` and the index.
- **Speed.** This repo's harness ran the Tier-3 suites with MTP on:
  - the gate;
  - M1, M3, M4 and M7, with the harness defaults;
  - `t1`: the model's own sampling (temperature 1.0, top_p 0.95, top_k 20) for M3 and M4,
    and M7 with 5 trials;
  - M6, a 30-minute loop.

  Every suite passed the quiet monitor (`scripts/quiet_check.sh`). The tags end in `-prec`.

  | Level | Night of 2026-10-21/22 | From Tier-3, 2026-10-20 |
  | --- | --- | --- |
  | oQ4 | M1, M3, M4, M7 | gate, t1 (M3, M4), M6 |
  | oQ5 | gate, M1, M3, M4, M7, t1, M6 | — |
  | oQ6 | gate, M1, M3, M4, M7, t1, M6 | — |
  | oQ8 | — | gate, M1, M3, M4, M7, t1 (M3, M4), M6 |

  - The user dropped the same-night re-runs of oQ4 and oQ8.
  - The cross-night spread, measured on oQ4, is −7 % to +24 % per M3 cell and +8–20 % on M1
    TTFT. Treat differences under about 10 % across nights as noise.
  - One suite ran the next morning (2026-10-22 05:29): oQ5's `t1` M4. Both night attempts
    were disturbed by macOS daemons.
- **Answer quality.** Measured by the agent-benchmark session, the peer session that drives
  Claude Code, Hermes and localmelo against this setup.
  - It ran its own oMLX 0.7.1rc1 with the G2b patch and MTP: thinking off, temperature 1.0,
    levels alternating ABBA.
  - oQ4 and oQ8 were measured on 2026-10-21, oQ5 and oQ6 on 2026-10-22.
  - Token level: KL and top-1 agreement against BF16 logits over about 40K tokens of code,
    agent turns, tool output and two READMEs. Positions where BF16 itself is unstable are
    excluded.
  - Screenshot code reading: 12 images × 5.
  - Aider: 12 exercises in each of 3 harnesses.

## Speed details

**M1, cached-prefix TTFT** (s, median):

| | oQ4 | oQ5 | oQ6 | oQ8 ² | oQ4 ² |
| --- | --- | --- | --- | --- | --- |
| warm, 16.6K prompt | 3.10 | 3.16 | 3.22 | 2.86 | 2.59 |
| cold, 16.6K prompt | 23.9 | 25.0 | 26.8 | 26.4 | 22.2 |

**M3, decode with the harness defaults** (tok/s, median of 3):

| Thinking | Context | Cap | oQ4 | oQ5 | oQ6 | oQ8 ² | oQ4 ² |
| --- | --- | --- | --- | --- | --- | --- | --- |
| off | 16K | 300 | 75.7 | 61.9 | 51.8 | 45.3 | 67.0 |
| off | 32K | 300 | 53.3 | 45.2 | 44.7 | 41.3 | 56.4 |
| off | 64K | 300 | 46.4 | 41.5 | 39.4 | 34.2 | 50.1 |
| on | 16K | 2000 | 44.8 | 42.3 | 37.8 | 28.8 | 48.6 |
| on | 32K | 2000 | 42.2 | 39.2 | 34.0 | 26.6 | 46.0 |

**M3 and M4 with the model's sampling** (`t1`; tok/s, and M4 total in s):

| | oQ4 ² | oQ5 | oQ6 | oQ8 ² |
| --- | --- | --- | --- | --- |
| M3 16K, cap 150, thinking off | 75.1 | 58.5 | 54.8 | 53.5 |
| M3 32K, cap 150, thinking off | 55.6 | 50.8 | 44.7 | 42.0 |
| M3 16K, cap 1000, thinking on | 45.6 | 37.5 | 38.6 | 35.0 |
| M3 32K, cap 1000, thinking on | 47.4 | 37.7 | 35.8 | 34.8 |
| M4 20 steps, median total | 164 s | 182 s ³ | 189 s | 200 s |

³ Re-run on 2026-10-22 at 05:29: macOS daemons disturbed both night attempts.

**M4, 20-step trajectory with the harness defaults** (total per run, s):

| | oQ4 | oQ5 | oQ6 | oQ8 ² | oQ4 ² |
| --- | --- | --- | --- | --- | --- |
| median | 172.2 | 170.8 | 186.6 | 194.8 | 158.3 |
| three runs | 159.5, 172.2, 174.0 | 164.1, 173.9, 170.8 | 176.5, 187.7, 186.6 | 187.4, 194.8, 198.0 | 155.8, 158.3, 159.9 |

**M6, a 30-minute loop of the 20-step trajectory:**

| | oQ4 ² | oQ5 | oQ6 | oQ8 ² |
| --- | --- | --- | --- | --- |
| requests (runs) | 233 (12) | 212 (11) | 199 (10) | 190 (10) |
| steps cut by the 150-token cap | 89 | 80 | 76 | 67 |
| server footprint, start / peak / end (GiB) | 26 / 33 / 22 | 32 / 36 / 28 | 39 / 40 / 34 | 46 / 47 / 42 |
| e2e, last run against the first | 1.02 | 1.03 | 1.02 | 1.01 |

oMLX reports the capped steps as `incomplete_tool_call`, as in the README's M6 row.

**Gate and M7.**
- oQ5 and oQ6 pass G1–G5 with MTP on, like oQ4 and oQ8. G2b fails on stock oMLX at every level.
- The peak footprint for the 64K prompt in G5 is 24, 29, 33 and 40 GiB for oQ4, oQ5, oQ6 and
  oQ8.
- M7 with the harness defaults: 24/24 for oQ4, and 23/24 for each of the others. The one miss
  is `m7-07-enum` every time.

## Answer quality details (agent-benchmark session)

**Aider, solved per harness** (12 exercises each):

| Harness | oQ4 | oQ5 | oQ6 | oQ8 |
| --- | --- | --- | --- | --- |
| Claude Code | 7 | 9 | 9 | 10 |
| Hermes | 11 | 12 | 11 | 11 |
| localmelo | 9 | 11 | 11 | 12 |
| total of 36 | 27 | 32 | 31 | 33 |

- oQ4 against oQ8, 2026-10-21: discordant pairs 8 against 2 (p = 0.11).
- oQ5 against oQ6, 2026-10-22: 3 against 4 (p = 1.0).

**Token level against BF16** (KL / top-1, stable positions):

| Positions | oQ4 | oQ5 | oQ6 | oQ8 |
| --- | --- | --- | --- | --- |
| all | 0.216 / 91.7 % | 0.093 / 95.4 % | 0.043 / 97.3 % | 0.013 / 98.5 % |
| code | 0.020 / 96.6 % | 0.006 / 97.7 % | 0.002 / 98.9 % | 0.001 / 99.4 % |
| the agent's assistant turns | 0.016 / 96.2 % | 0.005 / 97.9 % | 0.002 / 98.4 % | 0.001 / 99.2 % |

**Prose against BF16** (KL / top-1 / cross-entropy change):

| Text | oQ4 | oQ5 | oQ6 | oQ8 |
| --- | --- | --- | --- | --- |
| Hermes README (repetitive markdown and HTML) | 0.18 / 91–92 % / +18 % EN, +27 % ZH | 0.048 / 96 % / +2.9 % EN, +7.3 % ZH | 0.013 / 98 % / +0.8–1.6 % | ~0.002 / 99 % / ~0 |
| oMLX README | 0.027–0.030 / 92–93 % / +2 % | 0.008 / 96–97 % / +0.5 % | 0.002–0.003 / 98 % / ~0 | 0.001 / 99 % |

The errors surface where the model's top-1 margin is small, which is in prose and README-style
text. Code and the agent's turns have wide margins, and they stay close to BF16 even at oQ4.

## Heat

- The monitor logs macOS thermal pressure (`notifyutil -g
  com.apple.system.thermalpressurelevel`: 0 nominal, 1 moderate, 2 heavy). It does not judge it,
  because the run itself produces it.
- Across the night's suites, 75 % of the samples were at 2 (heavy) and 91 % at 1 or 2. The
  30-minute M6 loops spent 88–90 % of their samples at 2. These are numbers from a hot machine.
- In a long Hermes session the user saw oQ8 fall from 40–50 to 30–40 tok/s once the laptop was
  hot. Context growth alone gives a drop of that size: oQ8's M3 runs at 45, 41 and 34 tok/s at
  16K, 32K and 64K.
- In M6, the last run against the first is 1.01–1.03 at every level, so speed does not keep
  falling once the machine is hot.

## Runs and re-runs

Raw files are in `omlx/raw/`; the tags are `oqNmtp-mtp-on-prec` and `oqNmtp-mtp-on-t1-prec`.
Three suites were disturbed. Their files stay local in `omlx/raw/_unverified/`, and each was
re-run:

- **oQ5 gate.** A foreign python process ran at 100 % CPU at 23:08; the second attempt was quiet.
- **oQ6 M6.** biomesyncd ran at 42–62 % CPU in two attempts; the third was quiet.
- **oQ5 `t1` M4.** biomesyncd at 01:20 and airportd at 01:29 hit both night attempts; it was
  re-run the next morning.
