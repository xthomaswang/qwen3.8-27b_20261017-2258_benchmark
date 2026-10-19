# Qwen3.8-27B local serving benchmark — M5 Max, 2026-10-17

Question: **which local serving framework is the fastest and most suitable backend for
agent workloads** (Claude Code / Hermes-style harnesses, computer use with screenshots)
on a MacBook Pro M5 Max with 128 GB unified memory?

Every framework serves the same model, Qwen3.8-27B, at a 4-bit tier. The MLX-based
stacks also get an 8-bit row (`mlx-community/Qwen3.8-27B-8bit`), which is the checkpoint
the agent benchmark currently uses. Each one first goes
through a capability gate (OpenAI-compatible streaming + tool calls, image input,
Anthropic Messages, thinking control, context length). Then it is measured on
agent-shaped latency: cached-prefix TTFT, short structured decodes with and without
speculative decoding, a 20-step trajectory, and concurrency. See
[METHODOLOGY.md](METHODOLOGY.md).

## Status

| Framework | Version under test | Gate | Results PR |
| --- | --- | --- | --- |
| [llama.cpp](llama.cpp/) (`llama-server`) | b11717 | **pass**: G1–G5 and G2b ([capabilities](llama.cpp/capabilities.md)) | [#1](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/1), Tier-1 at 4-bit |
| [oMLX](omlx/) | v0.7.1rc1 | **G2b fails**: screenshots inside `role=tool` messages are dropped (the Hermes path); G1–G5 pass, including images in Anthropic `tool_result` ([capabilities](omlx/capabilities.md)) | [#2](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/2), Tier-1 at 4-bit |
| [lithos-metal](lithos-metal/) | v0.1.2 | pending | — |
| [vLLM-Metal](vllm-metal/) | v0.31.0 | **pass**: G1–G5 and G2b ([capabilities](vllm-metal/capabilities.md)) | [#3](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/3), Tier-1 at 4-bit |
| [mlx-lm](mlx-lm/) (`mlx_lm.server` + direct) | 0.32.2 | pending | — |
| [MLC-LLM](mlc-llm/) (`mlc_llm serve`, added 2026-10-18) | source build: mlc-llm `8978ea9a` + TVM `201fa000` (the nightly wheels abort on import here) | expected fail: no Qwen XML tool parser (tool calls go through xgrammar structured output), no `/v1/messages`, no per-request thinking switch; prefix cache must be off for the hybrid model. Text-only reference row | — |
| [Core AI](coreai/) (`llm-server` + `llm-benchmark`) | apple/coreai-models `3b25d93` | expected fail (images dropped, no `/v1/messages`). Text-only reference row | — |

Tier-1 at 4-bit (the agent-backend candidates; details in each framework's `summary.md`):

| Metric | llama.cpp, MTP off / on | oMLX | vLLM-Metal |
| --- | --- | --- | --- |
| M1 cached-prefix TTFT, warm | 4.45 / 4.51 s | **2.73 s** | 4.10 s |
| M2 cold prefill, 16K / 64K | 568 / 433 tok/s (MTP off) | **765 / 650 tok/s** | 614 / 391 tok/s |
| M3 decode, structured output, 16K | 24.0 / **41.5** tok/s | 27.4 tok/s | 26.2 tok/s |
| M4 20-step trajectory, total | 250 / **201 s** | 206 s | 250 s |
| M5 main step with 2 helpers (vs solo) | 2.49× (`conc`, MTP off) | 2.56× | **2.44×** |
| M7 tool-call correctness | 23/24 | 24/24 | 24/24 |
| G5 peak footprint at 64K | **18.0 GiB** | 23.0 GiB | 62.3 GiB |

All timed numbers come from quiet runs with the battery rule (METHODOLOGY.md, "Battery").

## Layout

```
METHODOLOGY.md     gate + metric definitions, measurement protocol
ENVIRONMENT.md     machine, OS/Xcode builds, power state, checkpoints
harness/           benchmark client (uv project), used unchanged against every server
fixtures/          synthetic inputs: fake-UI screenshots, tool-call suite, agent prefix
scripts/           download + per-framework setup helpers
<framework>/       env.md (exact versions/flags), capabilities.md (gate), raw/*.jsonl, summary.md
logs/              (gitignored) raw server logs
```

This repo holds only the experiment itself: protocol, inputs, scripts, results.
Framework sources and their venvs live outside it, in `~/Developer/mlsys/serving/<framework>`.
oMLX 0.7 is a separate checkout at `serving/omlx_0.7` with an isolated base path. The
older `serving/omlx` (0.3.9) is a different, untouched install.

## Workflow

- `main` holds the methodology and the harness.
- Each framework's results arrive through a `bench/<framework>` pull request. That PR is
  pushed again after every completed sub-run.
- A final `summary` pull request adds the cross-framework comparison and the
  recommendation.

Every result file records the harness commit it was produced with, plus the
`sw_vers` build and the `xcodebuild -version` output.
