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

## The tests, and the agent situation each one stands for

The IDs below appear in every table and file name. METHODOLOGY.md has the exact shapes and
pass criteria.

### Gate: can the server act as an agent backend at all?

A framework that fails a gate item is not an agent-backend candidate; it may still be
measured text-only as a reference row.

| ID | What it tests | Real-world situation |
| --- | --- | --- |
| G1 | OpenAI-compatible chat API with streaming, and Qwen3.8 tool calls returned as structured `tool_calls` | Every step of an OpenAI-API agent (Hermes, localmelo): the model has to call a tool (read a file, run a command, click) in a form the harness can execute |
| G2 | An image in a user message, read back correctly | The user pastes a screenshot, an error dialog or a design mock and asks about it |
| G2b | An image inside a tool result (`role=tool`) | Computer use: the agent calls a screenshot tool and the screen comes back as the tool's result. A server that drops it leaves the agent blind, without any error |
| G3 | The Anthropic Messages API (`/v1/messages`): text, `tool_use`, images, and images inside `tool_result` | Pointing Claude Code, or another Anthropic-API client, straight at the local model, MCP screenshot tools included, without a translating proxy |
| G4 | Turning thinking on or off per request | Quick tool-calling steps without thinking, and planning or debugging steps with it, in one session |
| G5 | A 64K-token prompt completes within memory (128K preferred) | Long sessions, where a large repo, many tool results or a long screenshot history fill the context |

### Metrics: how fast and how reliable is it in an agent loop?

| ID | What it measures | Real-world situation |
| --- | --- | --- |
| M1 | Time to first token (TTFT) when a ~15K-token prefix (system prompt and tool schemas) is already cached and ~1.5K new tokens arrive: a tool result plus a screenshot | The pause before the agent reacts, on every ordinary step. This is the main per-step cost |
| M2 | Prefill speed with nothing cached, at 16K, 32K and 64K tokens | Starting a new session, switching projects, or any request after the cache was evicted |
| M3 | Decode speed for short outputs (50–300 tokens) at 16K–64K context, with and without speculative decoding; a second bucket generates 1000–2000 tokens with thinking on | Writing a tool call or a short JSON answer. The thinking bucket is a planning step |
| M4 | A canned 20-step trajectory: each step adds a screenshot and a tool result, and the output is capped at 150 tokens. Per-step and total time | A whole task end to end (look, act, look again), with history growing every step. It shows whether the server reuses the cached history |
| M5 | A main step's TTFT while 1–2 helper requests run at the same time | A main agent with sub-agents or background helpers (summaries, titles, a second session) sharing one server |
| M6 | Memory at 64K context, then 15–30 minutes of M4 trajectories in a loop: latency drift, errors, memory growth | Leaving an agent on a long task for an hour |
| M7 | 24 tool-call prompts: the right tool, valid JSON arguments, no call when none is needed, no markup leaking into the text | Whether the agent's calls execute. A wrong name or broken JSON makes the step fail or retry |
| M8 | M1, M3 and M4 again under a background load, against clean baselines on the same server launch | The laptop is used for other things while the agent runs (the scenarios below) |

M8's scenarios (METHODOLOGY.md, section 4):

| Scenario | Load | Real-world situation |
| --- | --- | --- |
| `cpu1` | 1 busy thread | A background daemon, such as Spotlight or suggestd, on one core |
| `cpuhalf` | 8 busy threads | Another agent running tests or type checks |
| `cpuall` | 18 busy threads, one per logical CPU | A full compile |
| `gpu` | An MLX matmul loop, busy half of the time | Video, a browser or another model on the GPU |
| `mem` | 40 GB held resident | Another large program in memory |
| `disk` | 200 MB/s of writes and 1 GB/s of reads, uncached | A large download, or Spotlight indexing |
| `power` | Low Power Mode | Working on battery in Low Power Mode |

### Tiers and tags

- **Tier-1:** the three agent-backend candidates (llama.cpp, oMLX, vLLM-Metal) at 4-bit, with
  the gate, M1–M5 and M7.
- **Tier-2:** M6, the 8-bit rows, and the text-only reference rows.
- **Tier-3:** oMLX with Lightning MTP on oQ checkpoints, llama.cpp's Q8_0 with MTP, and runs at
  temperature 1.0.
- **Parts of a tag** such as `oq8mtp-mtp-on-t1`:
  - `4bit` and `8bit` are the mlx-community checkpoints, or the GGUF of that size.
  - `oq4mtp` and `oq8mtp` are oMLX oQ checkpoints that keep the MTP head.
  - `nvfp4` is NVIDIA's NVFP4 checkpoint, on lithos-metal.
  - `mtp-on` and `dspark` mean speculative decoding is on; `mtp-off`, `spec-off` and
    `no-draft` mean it is off.
  - `t1` means temperature 1.0 (the model's own sampling). Every other run uses
    temperature 0.
  - llama.cpp only: `conc` is a launch with three parallel slots, used for M5; `anchor` is
    an M1 run at full battery, kept to calibrate the battery rule.
  - Core AI's files are named `ab-<engine>-p<prompt>-g<generated>-n<trials>`, from the
    direct-call A/B.

## Status

| Framework | Version under test | Gate | Results PRs |
| --- | --- | --- | --- |
| [llama.cpp](llama.cpp/) (`llama-server`) | b11717 | **pass**: G1–G5 and G2b ([capabilities](llama.cpp/capabilities.md)) | [#1](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/1) (Tier-1, 4-bit), [#4](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/4) (Tier-2), [#7](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/7) (Tier-3: Q8_0 with MTP, temperature 1.0) |
| [oMLX](omlx/) | v0.7.1rc1 | **G2b fails**: screenshots inside `role=tool` messages are dropped (the Hermes path); G1–G5 pass, including images in Anthropic `tool_result` ([capabilities](omlx/capabilities.md)) | [#2](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/2) (Tier-1, 4-bit), [#4](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/4) (Tier-2), [#7](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/7) (Tier-3: Lightning MTP on oQ checkpoints, 8-bit M3, temperature 1.0) |
| [lithos-metal](lithos-metal/) | v0.1.2 plus a local `lm_head` fix | **fails** G2, G2b, the G3 images and G4: string content only, thinking always off ([capabilities](lithos-metal/capabilities.md)). Text-only reference row | [#6](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/6) |
| [vLLM-Metal](vllm-metal/) | v0.31.0 | **pass**: G1–G5 and G2b ([capabilities](vllm-metal/capabilities.md)) | [#3](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/3) (Tier-1, 4-bit), [#4](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/4) (Tier-2) |
| [mlx-lm](mlx-lm/) (`mlx_lm.server` + direct) | 0.32.2 | **fails** G2 and G2b (text content only) and G3 (no `/v1/messages`); G1, G4 and G5 pass ([capabilities](mlx-lm/capabilities.md)). Text-only reference row | [#5](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/5) |
| [MLC-LLM](mlc-llm/) (`mlc_llm serve`, added 2026-10-18) | source build: mlc-llm `8978ea9a` + TVM `201fa000` (the nightly wheels abort on import here) | **fails** G2–G4; G1 passes only through structured output; G5 passes, but a 64K prompt takes 815 s, because every request is a cold prefill. Text-only reference row | [#9](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/9) (open: the gate; the text-only suites follow) |
| [Core AI](coreai/) (`llm-server` + `llm-benchmark`) | apple/coreai-models `3b25d93` | `llm-server` gate pending; expected to fail (images dropped, no `/v1/messages`). Direct-call reference row | [#8](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/8) (direct-call A/B against mlx-lm: decode 13–14 % slower) |

Tier-1 at 4-bit (the agent-backend candidates; details in each framework's `summary.md`):

| Metric | llama.cpp, MTP off / on | oMLX | vLLM-Metal |
| --- | --- | --- | --- |
| M1 cached-prefix TTFT, warm | 4.45 / 4.51 s | **2.73 s** | 4.10 s |
| M2 cold prefill, 16K / 64K | 568 / 433 tok/s (MTP off) | **765 / 650 tok/s** | 614 / 391 tok/s |
| M3 decode, structured output, 16K | 24.0 / **41.5** tok/s | 27.4 tok/s | 26.2 tok/s |
| M4 20-step trajectory, total | 250 / **201 s** | 206 s | 250 s |
| M5 main step with 2 helpers (vs solo) | 2.49× (`conc`, MTP off) | 2.56× | **2.44×** |
| M7 tool-call correctness | 23/24 | 24/24 | 24/24 |
| GPU memory in use, peak during the run (4-bit) | 28.4 / 30.6 GB | 28.4 GB | 64.8 GB |

Tier-3 moved the front: oMLX with Lightning MTP on its oQ4 checkpoint, a different 4-bit
quantization that keeps the MTP head, runs M4 in 158 s and the M3 structured decode at 16K
at 68.4 tok/s. On oQ8 the same numbers are 195 s and 47.2 tok/s
([omlx/summary.md](omlx/summary.md)).

GPU memory is the system-wide AGX "In use system memory" from the monitor, which is comparable across frameworks; llama.cpp's process footprint leaves out its mmap'd weights. All timed numbers come from quiet runs that satisfy the battery rule (METHODOLOGY.md, "Battery"). M1, M4 and M5 run with thinking off; with thinking on, oMLX re-prefills ~1.5K tokens per step (`omlx/summary.md`).

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
