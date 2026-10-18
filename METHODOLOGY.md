# Methodology

The goal is to pick the serving backend for local agents (Claude Code, Hermes,
localmelo-style harnesses, including computer use). Plain decode tok/s is a secondary
concern. The things that matter are the per-step latency an agent actually feels, and
whether the server speaks the agent's protocol correctly.

## 1. Capability gate

A framework that fails a hard requirement is not suitable as an agent backend. It may
still be measured on text-only metrics for reference.

| ID | Requirement | Pass criterion |
| --- | --- | --- |
| G1 | OpenAI-compatible `POST /v1/chat/completions`, SSE streaming, Qwen3.8 tool calls (Qwen3.5-family XML `<function=…><parameter=…>` format, a.k.a. `qwen3_coder`) | Streamed `tool_calls` deltas assemble into a valid call (correct name, JSON-parseable arguments). No tool markup leaks into `content`. |
| G2 | Image input (`image_url` content part, base64 PNG). A 1280×1024 screenshot is ≈1.3K tokens. | The request is accepted **and** the answer reads a code rendered inside the image. This proves the image reached the model and was not silently dropped. |
| G3 | Anthropic-compatible `POST /v1/messages` (bonus; a translating proxy is the fallback) | Streaming text, `tool_use` blocks, and an image block all work. |
| G4 | Thinking control through `chat_template_kwargs` (`enable_thinking`) and/or `reasoning_effort` | `enable_thinking=false` yields no reasoning. `true` yields reasoning, either separated into `reasoning_content` or inside `<think>`. |
| G5 | Context ≥ 64K (128K preferred) that fits in memory | The server is configured for 131072 tokens (or its maximum), and a 64K-token prompt completes. Memory is recorded. |

G3 and G4 requests are shaped like the real harnesses, not idealized calls:

- **Hermes-style (OpenAI API).** Every request carries a top-level `reasoning_effort`
  (`"none"` when thinking is off, `"medium"` by default) **and**
  `chat_template_kwargs.enable_thinking`. Qwen3.8's template accepts only
  `xhigh` / `medium` / `low` when thinking is on, so we check whether the server maps or
  rejects other values.
- **Claude Code-style (`/v1/messages`).** Requests send either `thinking: {type: "adaptive"}`
  or no `thinking` field. They never send `"disabled"`.

## 2. Metrics

| ID | Metric | Shape |
| --- | --- | --- |
| M1 | **Cached-prefix TTFT** (the main per-step cost) | A fixed ≈15K-token prefix (system prompt + tool schemas, the size Claude Code / Hermes send) is warmed first. Each trial then appends ≈1.5K new tokens: one tool result plus one screenshot. The suffix is unique per trial. |
| M2 | Cold prefill throughput | 16K / 32K / 64K prompts with `max_tokens=1`. A unique nonce at the very start busts every prefix cache. Throughput = `prompt_tokens / TTFT`. |
| M3 | Short structured decode | Outputs of 50 / 150 / 300 tokens (JSON / tool-call shaped) at 16K / 32K / 64K context, with speculative decoding **on and off**. A long bucket adds 1000 / 2000-token outputs with thinking enabled at 16K / 32K, again spec on and off. It represents a thinking step: Qwen3.8's published computer-use scores use high thinking effort. |
| M4 | 20-step agent trajectory | Each step appends a screenshot plus a tool result. Output is ≈150 tokens. Reports, per step: TTFT, end-to-end latency, and the server-reported cached prompt tokens (`usage.prompt_tokens_details.cached_tokens` or the framework's equivalent), plus the total. The per-step data shows whether screenshot-bearing history is reused from the prefix cache; if it is not, latency grows linearly with the step index. The history is canned, so every framework sees byte-identical prompts. Real recorded agent traffic can be replayed later, but only locally (never committed). |
| M5 | Concurrency | TTFT of a main agent step while 1–2 auxiliary helper requests run at the same time, compared with the solo baseline. |
| M6 | Memory and stability | Footprint at 64K context. A sustained trajectory loop runs 10–15 min per framework, and 30 min for finalists. Tracks latency drift, errors, and memory growth. |
| M7 | Tool-call correctness | A suite of about 20 tool-call prompts, run with streaming. Success = expected call present, right name, schema-valid JSON arguments, no spurious call when none is needed, no markup leak. |

## 3. Protocol

- **Isolation.** One server runs at a time. The machine is on AC power in High Power mode,
  and no other model is resident. Every timed segment follows this sequence:
  1. Create the shared GPU lock (`~/Developer/mlsys/experiments/.gpu-lock`) with the
     session name, purpose, start time, and ETA.
  2. Check that no other server is resident (`lsof -nP -iTCP:8500 -sTCP:LISTEN` for the
     agent benchmark's oMLX). If one is, ask its owner to stop it; never kill another
     session's process.
  3. Run the segment.
  4. Delete the lock as soon as the segment ends.
- **Quiet machine.** Published numbers come only from timed segments in which the machine was
  quiet:
  - `scripts/quiet_check.sh --allow-pid <server pid>` passes before the segment starts.
    Its output (lock, port 8500, load average, busy foreign processes, build/convert/download
    tools, thermal warnings, power) is stored with the raw data.
  - No subagent work (compiles, conversions, fixture generation, test suites) and no
    downloads run while a timed segment is in progress.
  - A run that may have been disturbed (background load, a thermal warning, a configuration
    doubt, a broken trial) is moved to `<framework>/raw/_unverified/`. That directory is
    gitignored and never published. The run is repeated before any number is reported.
- **Ordering.** When two frameworks are compared directly (e.g. Core AI vs MLX on the same
  protocol), their runs alternate A/B/A/B after an idle cool-down, so drift such as
  thermal throttling cannot favour either side.
- **Ports.**

  | Framework | Port |
  | --- | --- |
  | mlx-lm | 8701 |
  | llama-server | 8702 |
  | oMLX | 8703 |
  | lithos-metal | 8704 |
  | vLLM-Metal | 8705 |

  8500 and 8600–8699 belong to the agent benchmark and are never used here.
- **Model.** Qwen3.8-27B. The formats below are not bit-identical; each row says which one
  it uses.

  | Row | Checkpoint | Used by |
  | --- | --- | --- |
  | 4-bit (primary) | MLX affine 4-bit g64 | MLX stacks, lithos-metal |
  | 4-bit (primary) | `UD-Q4_K_M` GGUF | llama.cpp |
  | NVFP4 (separate row) | NVFP4 | lithos-metal native path, if bandwidth allows the 22 GB download |
  | 8-bit (secondary) | MLX affine 8-bit g64 | MLX stacks, on M1 / M4 / M7 at minimum |

  The 8-bit row matches the checkpoint the agent benchmark uses today. Picking 8-bit or
  4-bit for agents is left to the user.
- **Sampling.** `temperature=0` for all timed runs. Thinking is disabled
  (`enable_thinking=false`) for every latency metric, because agent steps emit tool calls.
- **TTFT.** Measured from request send to the first SSE chunk that carries a generated
  token (`content`, `reasoning_content`, or a `tool_calls` delta). Role-only chunks,
  keep-alives and progress events are ignored.
- **Decode rate.** `(completion_tokens − 1) / (t_last − t_first)`, using server `usage`
  when it is reported and the Qwen3.8 tokenizer otherwise. Inter-chunk gaps are reported
  as p50/p99 together with tokens per chunk, because speculative decoding emits several
  tokens per chunk.
- **Trials.** At least 3 per cell, plus one warm-up. Report the median with min and max.
- **Speculative decoding.**
  - "off" means target-only.
  - "on" means the framework's own method with default settings: MTP for llama.cpp,
    Lightning MTP / DFlash for oMLX, DSpark for lithos-metal, and whatever vLLM-Metal
    supports for this model. mlx-lm has none.
- **Inputs.** Screenshots are synthetic fake-UI images rendered with Pillow
  (`fixtures/`), so no real screen content enters the repo. Prompt sizes are measured
  with the Qwen3.8 tokenizer.
- **Provenance.** Every raw record carries the framework version/commit, the server
  flags, the harness commit, the `sw_vers` build, and `xcodebuild -version`.
