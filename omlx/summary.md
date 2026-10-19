# omlx: results

## Read first

- **Build and checkpoint.** Stock oMLX `v0.7.1rc1` (`7a5a3d75`) serves
  `mlx-community/Qwen3.8-27B-4bit` (MLX affine 4-bit g64). Its base path is
  `serving/omlx_0.7/.bench-home`, never the user's `~/.omlx`.
  - Speculative decoding is off.
  - Lightning MTP needs `mtp.*` tensors, which this checkpoint lacks. DFlash needs a separate
    draft model. (`env.md`)
- **When.** Every timed suite ran on 2026-10-18 between 18:51 and 21:58, under the battery
  rule. M7 checks correctness only and is kept from the night run (07:41). M2 took three
  attempts: systemstats (19:01) disturbed the first, and a power-adapter dropout (19:09) the
  second.
- **G2b FAILS.** A screenshot inside a `role=tool` message is dropped: 639 prompt tokens
  against 1936 for the control, and the model answers without seeing it.
  - This is the Hermes computer-use path.
  - Images inside Anthropic `tool_result` blocks work: G3, the Claude Code path.
  - A local patch in another session's worktree fixes the drop. It is unreleased and was not
    tested here.
- **Thinking switch.** `reasoning_effort=none` alone does not disable thinking; also send
  `chat_template_kwargs.enable_thinking=false`.
- **Anthropic usage.** When a request carries `cache_control`, `input_tokens` is 0 and the
  prompt is split across `cache_creation_input_tokens` and `cache_read_input_tokens`
  (Anthropic's semantics).
- **M4 step 1.** TTFT is 15.2 s, close to a full re-prefill, because the hybrid prefix cache
  does not reuse the step-0 prompt. From step 2 on it is 3.1–4.2 s.
  - The slope is -0.107 s/step over steps 1-20, and +0.068 s/step over steps 2-20.
  - Steps whose tool calls hit the 150-token cap end with an `incomplete_tool_call` stream
    error and report no cached tokens (`-`). They still count as latency samples.
- **Thinking on costs ~2.5 s of TTFT per step.** With thinking on, the cached prefix is reused
  only up to a block boundary: 14,336 of 16,000 tokens at 16K, and 30,720 of 32,000 at 32K.
  Each request therefore re-prefills 1.3–1.7K tokens.
  - M3 TTFT is 2.7–2.8 s with thinking on, against 0.27–0.41 s with it off.
  - llama.cpp and vLLM-Metal show no such gap.
  - M1 and M4 run with thinking off, so an agent step with thinking on pays this on top.
- **Streaming granularity.** About 3.9 tokens per SSE chunk, with a chunk-gap p50 of
  ~150 ms. The decode rate is unaffected.
- **The SSD prefix cache persists across restarts,** which is why G1 shows a 1.3 s first call.
  The cold measurements (M1 cold, M2, G5, M4 step 0) carry nonces, so they are not affected.
- **Superseded gate.** The 17:43 gate is in `raw/superseded/`.

<!-- agentbench:begin summary 4bit-spec-off -->
## Results, tag `4bit-spec-off`

### Gate G1-G5

Source: `raw/gate-4bit-spec-off-20261018-185130.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 1.26 s, e2e 1.26 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer 'The screen shows a dialog with a verific', expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 111 chars in thinking_block / text ok ('ready'); reasoning 104 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 108 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 105.6 s; configured context: 131072; peak server footprint 23.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-4bit-spec-off-20261018-185405.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 2.729 (2.178-2.887) | 6.673 (5.522-7.952) | 14996 | 16644 | content | 0 |
| cold | 3 | 21.991 (21.720-22.509) | 25.313 (24.675-25.835) | 0 | 16659 | content | 0 |

Cold / warm TTFT (medians): 8.06x.

### M2 cold prefill

Source: `raw/m2-4bit-spec-off-20261018-214950.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 20.915 (20.501-21.206) | 765 (754-780) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 43.974 (43.655-44.180) | 728 (724-733) | 32000 | 0 | ttft | 0 |
| 64,000 | 3 | 98.508 (98.317-99.550) | 650 (643-651) | 64000 | 0 | ttft | 0 |

### M3 short structured decode

Source: `raw/m3-4bit-spec-off-20261018-191408.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 27.5 (27.3-27.5) | 0.267 (0.266-0.268) | 2.052 (2.051-2.063) | 50 | 3/3 | 145.9 | 147.9 | 3.57 |
| off | off | 16,000 | 150 | 3 | 27.4 (27.3-27.5) | 0.268 (0.268-0.272) | 5.708 (5.692-5.735) | 150 | 3/3 | 146.2 | 152.0 | 3.85 |
| off | off | 16,000 | 300 | 3 | 27.6 (27.5-27.6) | 0.265 (0.264-0.271) | 11.102 (11.094-11.132) | 300 | 3/3 | 144.7 | 151.8 | 3.95 |
| off | off | 32,000 | 50 | 3 | 26.3 (26.2-26.3) | 0.406 (0.405-0.408) | 2.274 (2.271-2.275) | 50 | 3/3 | 151.9 | 158.1 | 3.57 |
| off | off | 32,000 | 150 | 3 | 26.0 (26.0-26.1) | 0.406 (0.402-0.406) | 6.130 (6.124-6.137) | 150 | 3/3 | 154.0 | 160.1 | 3.85 |
| off | off | 32,000 | 300 | 3 | 25.8 (24.8-25.9) | 0.400 (0.399-0.402) | 11.972 (11.948-12.453) | 300 | 3/3 | 154.5 | 163.5 | 3.95 |
| off | off | 64,000 | 50 | 3 | 23.6 (23.5-23.7) | 0.718 (0.711-0.722) | 2.789 (2.789-2.807) | 50 | 3/3 | 170.8 | 172.6 | 3.57 |
| off | off | 64,000 | 150 | 3 | 23.3 (23.3-23.3) | 0.714 (0.711-0.719) | 7.109 (7.109-7.117) | 150 | 3/3 | 171.5 | 182.1 | 3.85 |
| off | off | 64,000 | 300 | 3 | 23.0 (22.9-23.0) | 0.726 (0.708-0.741) | 13.710 (13.709-13.774) | 300 | 3/3 | 172.6 | 200.7 | 3.95 |
| off | on | 16,000 | 1000 | 3 | 26.9 (26.8-27.1) | 2.810 (2.806-2.864) | 39.882 (39.792-40.089) | 1000 | 3/3 | 147.7 | 158.1 | 3.98 |
| off | on | 16,000 | 2000 | 3 | 26.7 (26.7-26.8) | 2.900 (2.871-2.937) | 77.753 (77.557-77.799) | 2000 | 3/3 | 149.2 | 159.3 | 3.99 |
| off | on | 32,000 | 1000 | 3 | 25.0 (25.0-25.0) | 2.654 (2.605-2.722) | 42.612 (42.584-42.722) | 1000 | 3/3 | 159.4 | 172.6 | 3.98 |
| off | on | 32,000 | 2000 | 3 | 24.8 (24.8-24.9) | 2.661 (2.618-2.673) | 83.135 (83.012-83.225) | 2000 | 3/3 | 160.3 | 175.6 | 3.99 |

### M4 20-step trajectory (per step)

Source: `raw/m4-4bit-spec-off-20261018-193110.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 20.358 (19.917-20.477) | 23.733 (23.283-23.891) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 15.209 (14.931-15.375) | 20.680 (20.349-20.871) | - | 16733 | - | 0 |
| 2 | 3 | 3.122 (3.090-3.264) | 8.602 (8.503-8.780) | - | 18439 | - | 0 |
| 3 | 3 | 3.048 (3.012-3.228) | 7.041 (6.896-7.153) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.249 (3.246-3.253) | 8.535 (7.770-8.641) | 20187 | 21892 | 0.92 | 0 |
| 5 | 3 | 3.347 (3.335-3.366) | 7.660 (7.568-8.982) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.301 (3.244-3.385) | 7.714 (7.591-7.753) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.356 (3.320-3.451) | 6.494 (6.405-6.585) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 3.587 (3.545-3.645) | 7.604 (7.487-7.630) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.529 (3.439-3.535) | 7.502 (7.328-7.529) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.543 (3.520-3.671) | 9.391 (9.244-9.493) | - | 32060 | - | 0 |
| 11 | 3 | 3.733 (3.706-3.757) | 9.598 (9.492-9.656) | - | 33769 | - | 0 |
| 12 | 3 | 3.692 (3.623-3.757) | 9.345 (9.111-9.611) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 3.762 (3.671-3.865) | 9.723 (9.531-9.842) | - | 37191 | - | 0 |
| 14 | 3 | 3.990 (3.939-4.099) | 6.354 (6.273-7.015) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 3.915 (3.882-3.955) | 8.221 (7.681-8.288) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.052 (3.953-4.061) | 8.084 (7.931-8.103) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.170 (4.077-4.272) | 8.203 (8.031-8.345) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.081 (4.028-4.140) | 10.227 (10.092-10.287) | - | 45696 | - | 0 |
| 19 | 3 | 4.299 (4.203-4.332) | 10.451 (10.294-10.509) | - | 47383 | - | 0 |
| 20 | 3 | 4.233 (4.201-4.325) | 10.478 (10.393-10.577) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1066 s/step (steps 2-20: 0.0677 s/step); total e2e per run: 202.4, 206.0, 208.0 s.

23 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M5 concurrency

Source: `raw/m5-4bit-spec-off-20261018-194140.jsonl`.

| aux requests | n | main TTFT s | vs solo | main e2e s | main cached tok | main 429 | aux 429 | aux TTFT s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 3 | 2.788 (2.683-2.913) | 1.00 | 4.271 (4.106-5.041) | 14996 | 0 | 0 | - |
| 1 | 3 | 5.481 (5.402-5.537) | 1.97 | 7.522 (7.444-11.984) | 14996 | 0 | 0 | 2.893 (2.845-2.953) |
| 2 | 3 | 7.141 (7.110-7.466) | 2.56 | 10.809 (10.736-15.861) | 14996 | 0 | 0 | 6.284 (2.735-9.772) |

### M7 tool-call correctness

Source: `raw/m7-4bit-spec-off-20261018-074110.jsonl`.

Passed 24/24.

| Case | Category | Result | Reasons |
| --- | --- | --- | --- |
| m7-01-single | single call | pass | - |
| m7-02-multi-args | multiple args | pass | - |
| m7-03-nested-object | nested objects | pass | - |
| m7-04-array-of-objects | nested objects (array of objects, multi-turn) | pass | - |
| m7-05-array-strings | arrays | pass | - |
| m7-06-array-integers | arrays | pass | - |
| m7-07-enum | enums | pass | - |
| m7-08-key-combo | enums / arrays | pass | - |
| m7-09-numbers | numbers | pass | - |
| m7-10-float-bool | numbers and booleans | pass | - |
| m7-11-booleans | numbers and booleans | pass | - |
| m7-12-chinese-args | Unicode / Chinese args | pass | - |
| m7-13-chinese-instruction | Unicode / Chinese args | pass | - |
| m7-14-unicode-text | Unicode / Chinese args | pass | - |
| m7-15-quotes-newlines | quotes and newlines in strings | pass | - |
| m7-16-commit-message | quotes and newlines in strings (multi-turn) | pass | - |
| m7-17-long-string | long string args | pass | - |
| m7-18-parallel | two parallel calls | pass | - |
| m7-19-similar-tools-glob | choosing between similar tools | pass | - |
| m7-20-similar-tools-http | choosing between similar tools | pass | - |
| m7-21-no-call | no call needed | pass | - |
| m7-22-image-read | call after an image | pass | - |
| m7-23-image-click | call after an image | pass | - |
| m7-24-calendar | nested objects | pass | - |
<!-- agentbench:end summary 4bit-spec-off -->
