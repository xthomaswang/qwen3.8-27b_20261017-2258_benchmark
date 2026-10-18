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
| G2b | Image inside a **tool result**: the `role=tool` message carries `[text, image_url]`. This is what Hermes sends once `model.supports_vision` is set; computer-use screenshots arrive this way. | The code in the screenshot is read back. A control sends the same image in a following user message. If the tool-message request has about 1.3K fewer `prompt_tokens` than the control, the image was dropped. |
| G3 | Anthropic-compatible `POST /v1/messages` (bonus; a translating proxy is the fallback) | All of these work: streaming text, `tool_use` blocks, an image block, and an image block inside `tool_result` (the Claude Code MCP screenshot path, checked against a control the same way as G2b). |
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
| M4 | 20-step agent trajectory | Each step appends a screenshot plus a tool result. Output is capped at 150 tokens. Some canned steps issue 2–3 parallel calls, so the cap can cut a call: llama.cpp reports `finish_reason=length`, and oMLX ends the stream with an `incomplete_tool_call` error. Both count as latency samples; the oMLX case reports no cached tokens. Reports, per step: TTFT, end-to-end latency, and the server-reported cached prompt tokens (`usage.prompt_tokens_details.cached_tokens` or the framework's equivalent), plus the total. The per-step data shows whether screenshot-bearing history is reused from the prefix cache; if it is not, latency grows linearly with the step index. The history is canned, so every framework sees byte-identical prompts. Real recorded agent traffic can be replayed later, but only locally (never committed). |
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
- **Quiet machine.** Published numbers come only from suites during which the machine was
  quiet. `scripts/run_framework.sh` runs one `agentbench run-all` per suite and enforces the
  rule with `scripts/quietlib.py`. "Foreign" below means any process outside the run's own
  process tree (server, engine workers, harness); WindowServer and kernel_task are ignored.
  - **User activity is declared every 60 s for the whole run,** with `caffeinate -u -t 1`,
    the same signal as touching the keyboard. On an idle machine on AC power, macOS starts
    discretionary background work. On the night of 2026-10-18 that was suggestd harvesting
    at ~100 % of a core for over two hours, and mediaanalysisd at ~220 %. Both dropped to 0 %
    within 5 s of a declaration.
    - A single declaration does not last: holding one assertion let them resume after about
      7 min. Hence the repeat.
    - The first declaration triggers a short "user returned" burst of about 30 s (Spotlight,
      widgets). The runner waits 45 s before its first check to absorb it.
    - Every framework runs under the same heartbeat.
  - **Before the server starts.** The GPU is idle, and no other model is resident: at most
    6 GB of GPU memory is in use.
  - **Before each suite,** with the server idle, `scripts/quiet_check.sh` must pass. The
    runner waits up to 10 min for it. Criteria:
    - our GPU lock is held, port 8500 is down, and the machine is on AC power in High Power
      mode;
    - 1-min load average ≤ 2.5, and GPU utilization ≤ 10 %;
    - no foreign process above 25 % CPU, and foreign CPU in total ≤ 150 %;
    - no build, convert or download tools running, and no thermal warning.

    The check's output is stored in every raw file's header. The limits were calibrated on
    2026-10-18 04:24 on the idle machine, with the user-activity assertion held and the
    three Claude sessions resident:

    | Reading | Idle baseline | Limit |
    | --- | --- | --- |
    | Load average | 1.3–1.8 | 2.5 |
    | Foreign CPU, total | 12–50 % | 150 % |
    | GPU utilization | 0–2 % | 10 % |
    | GPU memory in use | 0.9–1.1 GB | 6 GB |
  - **During each suite,** a monitor samples every 10 s into
    `<framework>/raw/monitor-<tag>-<ts>.tsv`, which is committed with the results. The suite
    counts as disturbed on any of these, in a sample taken after the suite started (up to
    one interval past its end):
    - a lock, port, power, thermal or build-tool event;
    - the same foreign process above 25 % CPU in two consecutive samples;
    - foreign CPU in total above 150 % in two consecutive samples.

    A one-sample blip is logged as `SPIKE` and does not count; on this machine one comes
    roughly every minute (Watch sync, Spotlight, a WebKit page). `verify` re-judges every
    suite from the logged reasons, so all suites get the same rule. Load average is logged
    but not judged, because the server under test adds to it.
  - A disturbed suite is moved to `<framework>/raw/_unverified/` and repeated once
    automatically. That directory is gitignored and never published. The same applies to any
    run with a configuration doubt or a broken trial. Nothing from such a run is reported
    until it has been repeated cleanly.
  - No subagent work runs while a timed segment is in progress: no compiles, conversions,
    fixture generation, test suites or downloads.
- **Ordering.** When two frameworks are compared directly (e.g. Core AI vs MLX on the same
  protocol), their runs alternate A/B/A/B after an idle cool-down, so drift such as
  thermal throttling cannot favour either side.
- **Ports.**

  | Framework | Port |
  | --- | --- |
  | MLC-LLM | 8700 |
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
