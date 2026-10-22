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

## Conclusion (2026-10-21)

**Use oMLX 0.7.1rc1 with Lightning MTP on an oQ checkpoint, plus the G2b patch.** It is the
fastest on warm TTFT, cold prefill, decode and the 20-step trajectory; its oQ8 row stays the
fastest on M1 and M4 under every M8 load; and with the patch it passes every gate. The agent
benchmark already runs this setup, with oQ8.

| | oMLX oQ4 + MTP | oMLX oQ8 + MTP | llama.cpp 4-bit, MTP on | vLLM-Metal 4-bit |
| --- | --- | --- | --- | --- |
| M1 cached-prefix TTFT, warm | **2.59 s** | 2.86 s | 4.51 s | 4.10 s |
| M3 decode, structured output, 16K | **68.4 tok/s** | 47.2 tok/s | 41.5 tok/s | 26.2 tok/s |
| M4 20-step trajectory, total | **158 s** | 195 s | 201 s | 250 s |
| M6 requests in 30 min | **233** | 190 | 187 | 75 in 15 min |
| M8 slowdown of M4: all cores busy / GPU load | not run | +10 % / +44 % | +16 % / +52 % | +8 % / +42 % |
| Gate | G1–G5 pass; G2b only with the patch | same | all pass, G2b included | all pass, G2b included |

All numbers come from quiet, verified runs: the 4-bit columns from Tier-1 and Tier-2
(2026-10-18/19), the oQ columns from Tier-3 (2026-10-20), and M8 from the night of
2026-10-20. Each framework's `summary.md` has the details. M6 counts include steps that the
150-token cap cuts: oMLX reports them as `incomplete_tool_call`, llama.cpp as
`finish_reason=length`.

- **The patch.** Stock oMLX drops screenshots inside OpenAI `role=tool` messages: G2b, the
  Hermes computer-use path. The agent-benchmark session's local fix keeps them (branch
  `pab/openai-tool-message-images`, commit `57620a3f`, not upstream), and that session
  reported a G2b pass on 2026-10-20. This repo measured stock oMLX. The patch only touches
  request conversion, so the speed numbers should carry over, but the patched build did not
  go through this harness. Pin the commit, and test again after any oMLX upgrade.
- **MTP keeps the output.** oMLX verifies drafts with standard speculative sampling, so the
  output keeps the target model's distribution. It also keeps its speed at temperature 1.0.
- **Which oQ level** ([PRECISION.md](PRECISION.md), measured 2026-10-21/22).
  - **oQ4 + MTP** is the fastest: 16 GB of weights, a 26–33 GiB server. It is also the only
    level that loses on agent tasks:
    - it solves 27 of 36 Aider exercises, against 31–33 at oQ5, oQ6 and oQ8;
    - it drifts on prose, with token KL 0.216 against BF16.
  - **oQ5 and oQ6** match oQ8 on Aider and on screenshot reading.
    - oQ5 runs the 20-step trajectory as fast as oQ4 (171 s against 172 s on the same night),
      with a 32–36 GiB server.
    - oQ6 passes the token-level gate (KL 0.043) and takes about 9 % longer.
  - **oQ8 + MTP** runs 8-bit weights at the speed of the plain 4-bit row without MTP: 28 GB of
    weights, a 46–47 GiB server, a 72.5 GiB system peak.
  - The user has not picked a level yet; the agent benchmark keeps oQ8 until then.
- **Under interference** ([M8.md](M8.md), measured on oQ8 + MTP):
  - 32 GB of memory pressure and heavy disk I/O change nothing for any framework.
  - With half the cores busy, oMLX slows the most (warm TTFT +27 %, against +8–20 % for
    the others), but it stays the fastest on M1 and M4 in every scenario.
  - A competing GPU load costs every framework 42–56 % on M4.
- **Runner-up: llama.cpp with MTP**, when an unreleased patch is not acceptable. It is a
  stock release that passes every gate, G2b included, and its M6 throughput matches oQ8 +
  MTP. Its M4 is 201 s, against 158 s for oQ4 + MTP, and its MTP gain shrinks at
  temperature 1.0.
- **The rest.**
  - vLLM-Metal passes every gate, but it is slower and reserves about 62.5 GiB.
  - lithos-metal decodes fast with its draft model (58.8 tok/s at 16K in M8), but its
    trajectory is the slowest (310 s), and it has no images and no thinking control.
  - mlx-lm, MLC-LLM and Core AI fail the image or Anthropic gates and stay reference rows.
    MLC-LLM re-prefills every request.
- **A known oMLX limit.** When an output crosses a 2048-token block, the next turn
  re-prefills up to 2K tokens (about 3 s). This matters with thinking on
  ([omlx/summary.md](omlx/summary.md)).

**Not run.** The user closed the campaign on 2026-10-21 at 09:39, so these never ran:

- the M8 power scenario (it needs sudo) and M8 for oQ4 + MTP;
- MLC-LLM's M7 (the first attempt was disturbed, the second was stopped), its full text-only
  set and its image suites;
- Core AI beyond the `llm-server` gate;
- the G2b patch through this harness;
- oMLX's `cache_reasoning_output: false` check.

Machine: MacBook Pro M5 Max, 128 GB. macOS 27.2 (26B5101f), Xcode 27.1 (27A9275). Core AI
ran with Xcode-beta 27.2 (27B5028f) through `DEVELOPER_DIR`.

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
| [llama.cpp](llama.cpp/) (`llama-server`) | b11717 | **pass**: G1–G5 and G2b ([capabilities](llama.cpp/capabilities.md)) | [#1](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/1) (Tier-1, 4-bit), [#4](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/4) (Tier-2), [#7](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/7) (Tier-3: Q8_0 with MTP, temperature 1.0), [#11](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/11) (M8) |
| [oMLX](omlx/) | v0.7.1rc1 | **G2b fails**: screenshots inside `role=tool` messages are dropped (the Hermes path); an unreleased local patch (`57620a3f`) fixes it. G1–G5 pass, including images in Anthropic `tool_result` ([capabilities](omlx/capabilities.md)) | [#2](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/2) (Tier-1, 4-bit), [#4](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/4) (Tier-2), [#7](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/7) (Tier-3: Lightning MTP on oQ checkpoints, 8-bit M3, temperature 1.0), [#11](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/11) (M8, oQ8 + MTP) |
| [lithos-metal](lithos-metal/) | v0.1.2 plus a local `lm_head` fix | **fails** G2, G2b, the G3 images and G4: string content only, thinking always off ([capabilities](lithos-metal/capabilities.md)). Text-only reference row | [#6](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/6), [#11](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/11) (M8, `dspark`) |
| [vLLM-Metal](vllm-metal/) | v0.31.0 | **pass**: G1–G5 and G2b ([capabilities](vllm-metal/capabilities.md)) | [#3](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/3) (Tier-1, 4-bit), [#4](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/4) (Tier-2), [#11](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/11) (M8) |
| [mlx-lm](mlx-lm/) (`mlx_lm.server` + direct) | 0.32.2 | **fails** G2 and G2b (text content only) and G3 (no `/v1/messages`); G1, G4 and G5 pass ([capabilities](mlx-lm/capabilities.md)). Text-only reference row | [#5](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/5) |
| [MLC-LLM](mlc-llm/) (`mlc_llm serve`, added 2026-10-18) | source build: mlc-llm `8978ea9a` + TVM `201fa000` (the nightly wheels abort on import here) | **fails** G2–G4; G1 passes only through structured output; G5 passes, but a 64K prompt takes 815 s, because every request is a cold prefill. Text-only reference row | [#9](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/9) (the gate and the text-only M1–M3: no prefix reuse, 151 tok/s prefill and 9.1 tok/s decode at 16K; M7 did not complete) |
| [Core AI](coreai/) (`llm-server` + `llm-benchmark`) | apple/coreai-models `3b25d93` | `llm-server` **fails** G2 and G2b (images accepted, then dropped) and G3 (no `/v1/messages`); G1, G4 and G5 pass. Every request decodes all of `max_tokens` ([capabilities](coreai/capabilities.md)). Reference row | [#8](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/8) (direct-call A/B against mlx-lm: decode 13–14 % slower), [#10](https://github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark/pull/10) (`llm-server` gate) |

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

M8, the interference study, covers llama.cpp with MTP, oMLX oQ8 + MTP, lithos-metal and
vLLM-Metal: [M8.md](M8.md).

GPU memory is the system-wide AGX "In use system memory" from the monitor, which is comparable across frameworks; llama.cpp's process footprint leaves out its mmap'd weights. All timed numbers come from quiet runs that satisfy the battery rule (METHODOLOGY.md, "Battery"). M1, M4 and M5 run with thinking off; with thinking on, oMLX re-prefills ~1.5K tokens per step (`omlx/summary.md`).

## Layout

```
METHODOLOGY.md     gate + metric definitions, measurement protocol
ENVIRONMENT.md     machine, OS/Xcode builds, power state, checkpoints
M8.md              the interference study across the four agent-backend rows
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
