# vllm-metal: results

## Read first

- **Build and checkpoint.** vLLM-Metal `v0.31.0` (`e7a0c90b`) serves the MLX 4-bit
  checkpoint with one processor-config fix (`models/derived/Qwen3.8-27B-4bit-procfix`, from
  `scripts/make_procfix.sh`).
  - The checkpoint's `image_processor_type: Qwen3VLImageProcessor` is unknown to
    transformers 5.17, so the fix uses the equivalent `Qwen2VLImageProcessorFast` (`env.md`).
  - Server flags: `--gpu-memory-utilization 0.55 --max-num-seqs 4 --enable-prefix-caching`,
    the `qwen3_coder` tool parser and the `qwen3` reasoning parser.
  - Speculative decoding is off; the checkpoint has no MTP tensors.
- **When**, on 2026-10-18:
  - the gate, M1 and M2 at 18:28–18:48;
  - M3 and M4 at 16:37–17:13;
  - M5 and M7 at 17:48–17:53.

  The battery stayed above 90 % throughout.
- **Memory.** vLLM reserves 0.55 × RAM for the KV cache at startup, so the G5 peak footprint
  is 62.3 GiB whatever the prompt size.
- **Thinking effort.** `reasoning_effort` accepts only `xhigh` (the default), `medium` and
  `low`; `high` and `minimal` get HTTP 400.
- **Cached long context.** M3 TTFT with a cached 64K context is ~2.0 s, against 0.14 s for
  llama.cpp and 0.71 s for oMLX.
- **Superseded gate.** The 16:32 gate is in `raw/superseded/`.

<!-- agentbench:begin summary 4bit-spec-off -->
## Results, tag `4bit-spec-off`

### Gate G1-G5

Source: `raw/gate-4bit-spec-off-20261018-182820.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; incremental (6 deltas); first call chunk at 23.10 s, e2e 23.81 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **PASS** | tool-message image: read Y3N-9JT; prompt_tokens=1920; control (user message): read Y3N-9JT; prompt_tokens=1935 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 98 chars in thinking_block / text ok ('ready'); reasoning 47 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 44 chars in reasoning \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: error: HTTP 400: {"error":{"message":"Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low.","type":"BadRequestError","param":null,"code":400}} \| G4.effort-minimal: error: HTTP 400: {"error":{"message":"Unexpected reasoning effort minimal. Supported types are xhigh (default), medium, and low.","type":"BadRequestError","param":null,"code":400}} \| G4.default: accepted; reasoning 152 chars in reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 165.5 s; configured context: 131072; peak server footprint 62.3 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-4bit-spec-off-20261018-183243.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 4.101 (3.837-4.185) | 8.514 (7.676-8.850) | 14896 | 16590 | content | 0 |
| cold | 3 | 29.524 (29.497-29.579) | 33.161 (33.141-33.162) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 7.20x.

### M2 cold prefill

Source: `raw/m2-4bit-spec-off-20261018-183523.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 26.043 (25.879-26.267) | 614 (609-618) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 61.698 (61.519-62.436) | 519 (513-520) | 32000 | 0 | ttft | 0 |
| 64,000 | 3 | 163.845 (162.587-163.912) | 391 (390-394) | 64000 | 0 | ttft | 0 |

### M3 short structured decode

Source: `raw/m3-4bit-spec-off-20261018-163703.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 26.3 (26.2-26.3) | 0.695 (0.623-0.700) | 2.559 (2.490-2.563) | 50 | 3/3 | 38.6 | 40.7 | 1.02 |
| off | off | 16,000 | 150 | 3 | 26.2 (25.9-26.3) | 0.718 (0.655-0.739) | 6.407 (6.390-6.421) | 150 | 3/3 | 38.2 | 40.3 | 1.01 |
| off | off | 16,000 | 300 | 3 | 26.0 (25.9-26.0) | 0.708 (0.705-0.712) | 12.225 (12.220-12.246) | 300 | 3/3 | 38.6 | 40.1 | 1.00 |
| off | off | 32,000 | 50 | 3 | 24.6 (24.4-25.3) | 1.544 (1.451-1.698) | 3.556 (3.386-3.691) | 50 | 3/3 | 41.8 | 43.2 | 1.02 |
| off | off | 32,000 | 150 | 3 | 24.2 (23.9-24.2) | 1.649 (1.630-1.670) | 7.828 (7.816-7.876) | 150 | 3/3 | 42.0 | 43.0 | 1.01 |
| off | off | 32,000 | 300 | 3 | 24.0 (23.9-24.0) | 1.619 (1.607-1.670) | 14.108 (14.077-14.151) | 300 | 3/3 | 42.2 | 43.0 | 1.00 |
| off | off | 64,000 | 50 | 3 | 21.9 (21.2-22.2) | 1.807 (1.788-1.998) | 4.045 (3.991-4.305) | 50 | 3/3 | 46.4 | 48.2 | 1.02 |
| off | off | 64,000 | 150 | 3 | 20.7 (20.6-20.8) | 1.988 (1.967-2.071) | 9.167 (9.162-9.307) | 150 | 3/3 | 48.8 | 50.2 | 1.01 |
| off | off | 64,000 | 300 | 3 | 20.5 (20.4-20.5) | 1.964 (1.954-2.001) | 16.601 (16.508-16.613) | 300 | 3/3 | 49.2 | 51.3 | 1.00 |
| off | on | 16,000 | 1000 | 3 | 25.5 (25.4-25.5) | 0.754 (0.743-0.765) | 39.960 (39.909-40.144) | 1000 | 3/3 | 39.5 | 40.3 | 1.00 |
| off | on | 16,000 | 2000 | 3 | 25.5 (25.4-25.5) | 0.712 (0.706-0.795) | 79.259 (79.119-79.310) | 2000 | 3/3 | 39.4 | 40.6 | 1.00 |
| off | on | 32,000 | 1000 | 3 | 23.5 (23.5-23.6) | 1.675 (1.667-1.689) | 44.113 (44.084-44.135) | 1000 | 3/3 | 42.7 | 43.7 | 1.00 |
| off | on | 32,000 | 2000 | 3 | 23.6 (23.5-23.6) | 1.658 (1.633-1.675) | 86.372 (86.163-86.596) | 2000 | 3/3 | 42.6 | 43.3 | 1.00 |

### M4 20-step trajectory (per step)

Source: `raw/m4-4bit-spec-off-20261018-170036.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 24.784 (24.540-25.061) | 28.375 (28.156-28.677) | 0 | 15030 | 0.00 | 0 |
| 1 | 3 | 4.212 (4.169-4.262) | 9.641 (9.565-9.703) | 14896 | 16733 | 0.89 | 0 |
| 2 | 3 | 4.549 (4.478-4.683) | 10.324 (10.200-10.504) | 16464 | 18439 | 0.89 | 0 |
| 3 | 3 | 4.881 (4.810-4.911) | 7.909 (7.839-7.942) | 18032 | 20140 | 0.90 | 0 |
| 4 | 3 | 5.142 (4.994-5.179) | 10.950 (10.813-11.041) | 19600 | 21838 | 0.90 | 0 |
| 5 | 3 | 5.766 (5.686-5.802) | 10.597 (10.484-10.627) | 21168 | 23565 | 0.90 | 0 |
| 6 | 3 | 4.465 (4.391-4.475) | 8.680 (8.591-10.445) | 23520 | 25264 | 0.93 | 0 |
| 7 | 3 | 4.785 (4.662-4.796) | 9.004 (8.672-10.842) | 25088 | 26950 | 0.93 | 0 |
| 8 | 3 | 5.171 (5.169-5.175) | 11.146 (11.106-11.148) | 26656 | 28660 | 0.93 | 0 |
| 9 | 3 | 5.510 (5.498-5.533) | 9.736 (9.646-11.732) | 28224 | 30367 | 0.93 | 0 |
| 10 | 3 | 5.892 (5.830-5.970) | 12.123 (12.113-12.242) | 29792 | 32060 | 0.93 | 0 |
| 11 | 3 | 6.514 (6.481-6.540) | 12.818 (12.764-12.865) | 31360 | 33769 | 0.93 | 0 |
| 12 | 3 | 5.073 (5.071-5.161) | 11.047 (10.999-11.138) | 33712 | 35481 | 0.95 | 0 |
| 13 | 3 | 5.438 (5.434-5.440) | 11.853 (11.831-11.867) | 35280 | 37191 | 0.95 | 0 |
| 14 | 3 | 5.916 (5.833-5.923) | 9.168 (8.714-9.277) | 36848 | 38906 | 0.95 | 0 |
| 15 | 3 | 6.286 (6.262-6.292) | 11.003 (10.937-11.023) | 38416 | 40612 | 0.95 | 0 |
| 16 | 3 | 6.812 (6.755-6.841) | 11.182 (11.050-11.470) | 39984 | 42305 | 0.95 | 0 |
| 17 | 3 | 7.505 (7.441-7.560) | 14.150 (14.075-14.202) | 41552 | 44009 | 0.94 | 0 |
| 18 | 3 | 5.679 (5.609-5.738) | 12.371 (12.286-12.457) | 43904 | 45696 | 0.96 | 0 |
| 19 | 3 | 6.022 (5.947-6.070) | 12.780 (12.695-12.851) | 45472 | 47383 | 0.96 | 0 |
| 20 | 3 | 6.594 (6.549-6.671) | 13.368 (13.345-13.445) | 47040 | 49097 | 0.96 | 0 |

TTFT slope over steps 1-20: 0.1124 s/step (steps 2-20: 0.1065 s/step); total e2e per run: 246.8, 249.6, 253.3 s.

### M5 concurrency

Source: `raw/m5-4bit-spec-off-20261018-174811.jsonl`.

| aux requests | n | main TTFT s | vs solo | main e2e s | main cached tok | main 429 | aux 429 | aux TTFT s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 3 | 3.814 (3.742-3.865) | 1.00 | 6.236 (5.161-6.353) | 14896 | 0 | 0 | - |
| 1 | 3 | 6.410 (6.185-6.469) | 1.68 | 7.896 (7.834-10.949) | 14896 | 0 | 0 | 6.868 (6.640-6.927) |
| 2 | 3 | 9.292 (9.170-9.485) | 2.44 | 12.498 (10.891-14.515) | 14896 | 0 | 0 | 9.768 (9.621-9.986) |

### M7 tool-call correctness

Source: `raw/m7-4bit-spec-off-20261018-175127.jsonl`.

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
