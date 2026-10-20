# coreai: results

## Read first

- **What this is.** Core AI is a direct-call reference row, not an agent-backend candidate.
  - apple/coreai-models `3b25d93` exported Qwen3.8-27B from the BF16 release with its
    `qwen3_5_cfg` 4-bit preset. That is uint4 per block of 32, 5.06 bits per weight, with
    `embed_tokens` and `lm_head` quantized too.
  - The bundle is text-only: the vision and MTP weights are dropped.
  - The export ran on 2026-10-18 (exit 0, peak footprint 37.7 GB, 16 GB bundle).
  - The `llm-server` gate probes have not run yet. `env.md` section 6 has the expectations
    from the source: G2 drops images silently, and there is no `/v1/messages`.
- **Protocol.** `llm-benchmark` runs against `mlx_lm.benchmark` on
  `mlx-community/Qwen3.8-27B-4bit` (mlx-lm `v0.32.2`, mlx 0.32.4).
  - Each run is a random-token prompt with no chat template, greedy decoding and batch 1.
    It does one warm-up, then 5 trials, each with a cold prefill.
  - Prompts are 512 and 16,384 tokens, with 1024 generated tokens.
  - For each prompt length the order was Core AI, mlx-lm, Core AI, mlx-lm, with 60 s idle
    between runs (`scripts/coreai_ab.py`).
  - Every run passed the quiet pre-flight and the monitor. One Core AI 16K run was disturbed
    by `mds` (Spotlight) and repeated.
- **When.** 2026-10-20 09:26–10:20, on AC power, under macOS 27.2 (26B5101f). Core AI builds
  against Xcode 27.2 beta (27B5028f), selected through `DEVELOPER_DIR`. The system default
  stays Xcode 27.1 (27A9275).

| prompt | engine | trials | generation tok/s | prompt tok/s | GPU memory in use, peak |
| --- | --- | --- | --- | --- | --- |
| 512 | Core AI | 10 | 28.46 (28.37–28.71) | 670 (629–695) | 34.5 GB |
| 512 | mlx-lm | 10 | 32.91 (32.19–33.42) | 601 (514–682) | 16.7 GB |
| 16,384 | Core AI | 10 | 25.41 (24.60–25.72) | 689 (655–707) | 41.0 GB |
| 16,384 | mlx-lm | 10 | 29.58 (29.27–29.76) | 749 (721–761) | 20.8 GB |

Medians, with min–max over the 10 trials of two runs.

GPU memory is the system-wide AGX "In use system memory" from the monitor, the same measure
the README uses. The process footprint is not comparable here, because Core AI maps its
weights: its footprint is 3.5 / 9.5 GB, but its max RSS is 33.8 GB.

- **Decode: Core AI is 13–14 % slower.** It also streams about 12 % more bytes per token
  (17.0 GB against 15.2 GB of text weights; `env.md` section 5). Per byte, the two are
  within about 4 %.
- **Prefill.** Core AI is faster at 512 tokens (670 against 601 tok/s) and 8 % slower at
  16K (689 against 749).
  - `llm-benchmark` divides by the time to the first generated token, which includes the
    first decode step. That makes its number slightly low; at 16K the step is negligible.
- **Memory: Core AI holds about twice the GPU memory.** That is 34 GB at 512 and 41 GB at
  16K, against 17 and 21 GB. Its max RSS (33.8 GB) is also about twice the 17 GB bundle.
- **Load.** The specialization cache from the export night was in place (`cache_hit: true`).
  So the one-time specialization of the 27B was not measured.
  - Prepare took 3.9–5.1 s.
  - The warm-up took 38 s at 512 and 63–66 s at 16K.
- **Raw files.** There is one JSONL per run in `raw/` (`ab-<engine>-p<prompt>-…`). Each has
  the provenance and the pre-flight in its header, then the per-trial results. The block's
  monitor is `raw/monitor-ab-20261020-092613.tsv`. The two 2026-10-18 runs ran at load 4.0
  under the export lock; they stay local in `raw/_unverified/`.
