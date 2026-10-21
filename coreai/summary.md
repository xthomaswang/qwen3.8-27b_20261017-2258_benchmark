# coreai: results

## Read first

- **What this is.** Core AI is a reference row, not an agent-backend candidate.
  - apple/coreai-models `3b25d93` exported Qwen3.8-27B from the BF16 release with its
    `qwen3_5_cfg` 4-bit preset. That is uint4 per block of 32, 5.06 bits per weight, with
    `embed_tokens` and `lm_head` quantized too.
  - The bundle is text-only: the vision and MTP weights are dropped.
  - The export ran on 2026-10-18 (exit 0, peak footprint 37.7 GB, 16 GB bundle).
  - Two runs: the capability gate against `llm-server`, the OpenAI-compatible server, and a
    direct-call A/B of `llm-benchmark` against `mlx_lm.benchmark` (the table below).
  - No metric suite ran on `llm-server`: the campaign closed on 2026-10-21, after the gate.
- **`llm-server` gate: G1, G4 and G5 pass; G2, G2b and G3 fail** (`capabilities.md`).
  - G1 passes: an `fs_read_file` call with `finish_reason=tool_calls`. The call arrives as one
    delta, 17.6 s after the request, on a 13,233-token prompt (prefill 799 tok/s).
  - G2 and G2b fail, as `env.md` section 6 expected from the source: images are accepted
    (HTTP 200) and dropped without an error. The server counted 45 prompt tokens for G2
    against the harness's 1,319, and 586 against 1,920 for the `role=tool` image. The model
    then answers with a code that is not in the image.
  - G3 fails: there is no `/v1/messages` (HTTP 404).
  - G4 passes: `reasoning_effort=none` turns thinking off, alone or with
    `enable_thinking=false`. `chat_template_kwargs.enable_thinking=false` alone does not
    (86 characters of thinking). Thinking streams inline, as `<think>` text in `content`.
    - The chat template accepts only `xhigh` (the default), `medium` and `low`. With `high` or
      `minimal`, `applyChatTemplate` throws, and the server answers anyway from the bare text
      without the template (19 prompt tokens). The client sees no error.
  - G5 passes: the 64,004-token prompt completed with a TTFT of 123.6 s (519.5 tok/s), against
    102–119 s on the oMLX rows. Peak system GPU memory in use was 40.8 GB. The 12.0 GiB
    process footprint undercounts, because the weights are mapped.
- **Every `llm-server` request decodes `max_tokens` steps.** In the server's own timing, the
  requests with `max_tokens` 512 took 17.9–18.9 s whatever the answer's length (3 to 65
  tokens): 512 steps at about 28 tok/s. The same 51-token answer took 2.4 s with
  `max_tokens` 64, and the stream closes only at the end.
  - So an agent turn costs its whole token budget in time.
  - The cause was not traced in the source.
- **Other `llm-server` notes.**
  - No response carried token usage; the harness counted the tokens itself.
  - The source admits one request at a time and queues the rest (`RequestQueue.swift`). This
    was not measured.
  - The specialization cache is kept per executable. This was the first `llm-server` load of
    the bundle, so it wrote a second 16 GB entry under `~/Library/Caches/coreai-cache` (the
    first belongs to `llm-benchmark`). Launch to listening still took only 50 s, including a
    2.8 s warm-up.
  - On stop it ignored SIGINT for 30 s and exited on SIGTERM.
- **How the gate ran.** `scripts/serve.sh coreai server 4bit`: port 8706, `DEVELOPER_DIR` set to
  Xcode-beta for this process only, `--temperature 0 --max-tokens 4096`, harness profile
  `generic`.
  - 2026-10-20 23:31–23:36, on AC power, under macOS 27.2 (26B5101f) and Xcode 27.2 beta
    (27B5028f).
  - It passed the quiet pre-flight and the monitor (27 samples).
- **A/B protocol.** `llm-benchmark` runs against `mlx_lm.benchmark` on
  `mlx-community/Qwen3.8-27B-4bit` (mlx-lm `v0.32.2`, mlx 0.32.4).
  - Each run is a random-token prompt with no chat template, greedy decoding and batch 1.
    It does one warm-up, then 5 trials, each with a cold prefill.
  - Prompts are 512 and 16,384 tokens, with 1024 generated tokens.
  - For each prompt length the order was Core AI, mlx-lm, Core AI, mlx-lm, with 60 s idle
    between runs (`scripts/coreai_ab.py`).
  - Every run passed the quiet pre-flight and the monitor. One Core AI 16K run was disturbed
    by `mds` (Spotlight) and repeated.
- **When (A/B).** 2026-10-20 09:26–10:20, on AC power, under macOS 27.2 (26B5101f). Core AI
  builds against Xcode 27.2 beta (27B5028f), selected through `DEVELOPER_DIR`. The system
  default stays Xcode 27.1 (27A9275).

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

<!-- agentbench:begin summary 4bit -->
## Results, tag `4bit`

### Gate G1-G5

Source: `raw/gate-4bit-20261020-233148.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path":"docs\/setup.md"}; one delta; first call chunk at 17.63 s, e2e 26.48 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | image accepted but code not read (answer '482913', expected Y3N-9JT) |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer '482913', expected Y3N-9JT); prompt_tokens=None; control (user message): code not read (answer '482910', expected Y3N-9JT); prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: HTTP 404: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 115 chars in inline_think \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: accepted; reasoning 117 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 86 chars in inline_think |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=None, TTFT 123.6 s; configured context: unknown; peak server footprint 12.0 GiB |
<!-- agentbench:end summary 4bit -->
