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
| [llama.cpp](llama.cpp/) (`llama-server`) | b11717 | pending | — |
| [oMLX](omlx/) | v0.7.1rc1 | pending | — |
| [lithos-metal](lithos-metal/) | v0.1.2 | pending | — |
| [vLLM-Metal](vllm-metal/) | v0.31.0 | pending | — |
| [mlx-lm](mlx-lm/) (`mlx_lm.server` + direct) | 0.32.2 | pending | — |
| [MLC-LLM](mlc-llm/) (`mlc_llm serve`, added 2026-10-18) | nightly 0.26.dev | **blocked**: the nightly wheels abort on import on macOS 27.2 (native init bug, even after re-signing). A source build is needed. It would also fail the agent gate (no Qwen XML tool parser, no `/v1/messages`). | — |
| [Core AI](coreai/) (`llm-server` + `llm-benchmark`) | apple/coreai-models `3b25d93` | expected fail (images dropped, no `/v1/messages`). Text-only reference row | — |

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
