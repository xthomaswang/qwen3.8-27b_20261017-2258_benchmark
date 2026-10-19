# llama.cpp: results

## Read first

- **Build and checkpoint.** llama.cpp `b11717` (`848bbda9`), `llama-server` with the unsloth
  `UD-Q4_K_M` GGUF and its `mmproj`. The variants:
  - `mtp-off` and `mtp-on` (`--spec-type draft-mtp --spec-draft-n-max 3`) run one slot
    (`-np 1`);
  - `conc` runs three slots (`-np 3 -kvu`) and is used only for M5.

  Full flags are in each raw file's header.
- **When.** Every timed suite ran on 2026-10-18 between 19:47 and 21:47, under the battery
  rule (METHODOLOGY.md, "Battery": at least 40 % at each start and never below 20 %). M7
  checks correctness only and reports no timing, so its night runs (05:50, 06:32) are kept.
- **M7 is 23/24, with MTP off and on.** `m7-07-enum` calls `window_list` instead of
  `window_arrange`, deterministically at temperature 0. The 8-bit MLX runs (oMLX and
  vLLM-Metal, 2026-10-19) make the same choice, while the MLX 4-bit runs do not. So this is a
  borderline case for the model rather than a GGUF or server issue.
- **Thinking costs no decode speed:** 23.7 tok/s against 24.0 at 16K, and 22.0 against 22.0
  at 32K. The ~25 % gap seen before came from the night's power cap.
- **MTP** raises decode for structured output from 24.0 to 41.5 tok/s at 16K, and from 23.7
  to 35.0 tok/s with thinking on. The M4 trajectory takes 201 s instead of 250 s.
- **The anchor tag `4bit-mtp-off-anchor`** is M1 at 17:37, with the battery at 96 %. It
  matched the 04:35 night run (battery 29 %, quarantined) within 1 %. That is the
  calibration for the battery rule.
- **Superseded gate.** The 17:30 gate is in `raw/superseded/`.

<!-- agentbench:begin summary 4bit-mtp-off -->
## Results, tag `4bit-mtp-off`

### Gate G1-G5

Source: `raw/gate-4bit-mtp-off-20261018-194702.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path":"docs/setup.md"}; incremental (7 deltas); first call chunk at 24.57 s, e2e 25.30 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **PASS** | tool-message image: read Y3N-9JT; prompt_tokens=1920; control (user message): read Y3N-9JT; prompt_tokens=1935 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 117 chars in thinking_block / text ok ('ready'); reasoning 82 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 116 chars in reasoning_content \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: accepted; reasoning 152 chars in reasoning_content \| G4.effort-minimal: error: HTTP 500: {"error":{"code":500,"message":"\n------------\nWhile executing CallExpression at line 64, column 28 in source:\n...', 'low') %}↵        {{- raise_exception('Unexpected reasoning effort ' ~ reason...\n                                           ^\nError: Jinja Exception: Unexpected reasoning effort m \| G4.default: accepted; reasoning 152 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 154.9 s; configured context: 131072; peak server footprint 18.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-4bit-mtp-off-20261018-195134.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 4.454 (4.209-4.473) | 8.864 (8.683-9.543) | 14945 | 16590 | content | 0 |
| cold | 3 | 31.227 (30.930-31.403) | 35.113 (34.579-35.379) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 7.01x.

### M2 cold prefill

Source: `raw/m2-4bit-mtp-off-20261018-200745.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 28.158 (28.011-28.322) | 568 (565-571) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 61.816 (61.704-62.164) | 518 (515-519) | 32000 | 0 | ttft | 0 |
| 64,000 | 3 | 147.936 (147.373-149.079) | 433 (429-434) | 64000 | 0 | ttft | 0 |

### M3 short structured decode

Source: `raw/m3-4bit-mtp-off-20261018-202036.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 23.7 (23.5-23.9) | 0.095 (0.093-0.104) | 2.168 (2.147-2.183) | 50 | 3/3 | 42.5 | 44.5 | 1.00 |
| off | off | 16,000 | 150 | 3 | 24.0 (23.7-24.1) | 0.095 (0.093-0.098) | 6.316 (6.271-6.392) | 150 | 3/3 | 41.9 | 45.1 | 1.00 |
| off | off | 16,000 | 300 | 3 | 23.8 (23.8-23.9) | 0.097 (0.092-0.098) | 12.636 (12.607-12.639) | 300 | 3/3 | 42.0 | 44.6 | 1.00 |
| off | off | 32,000 | 50 | 3 | 21.7 (21.5-22.0) | 0.113 (0.107-0.116) | 2.371 (2.337-2.392) | 50 | 3/3 | 45.8 | 50.0 | 1.00 |
| off | off | 32,000 | 150 | 3 | 22.0 (22.0-22.1) | 0.112 (0.110-0.118) | 6.885 (6.865-6.889) | 150 | 3/3 | 45.6 | 48.5 | 1.00 |
| off | off | 32,000 | 300 | 3 | 22.0 (22.0-22.1) | 0.109 (0.107-0.114) | 13.684 (13.650-13.684) | 300 | 3/3 | 45.4 | 49.3 | 1.00 |
| off | off | 64,000 | 50 | 3 | 19.5 (18.9-19.6) | 0.142 (0.139-0.143) | 2.651 (2.638-2.730) | 50 | 3/3 | 51.5 | 54.8 | 1.00 |
| off | off | 64,000 | 150 | 3 | 19.3 (19.3-19.3) | 0.142 (0.141-0.146) | 7.848 (7.848-7.865) | 150 | 3/3 | 51.7 | 56.2 | 1.00 |
| off | off | 64,000 | 300 | 3 | 19.3 (19.3-19.4) | 0.144 (0.143-0.145) | 15.621 (15.589-15.656) | 300 | 3/3 | 51.8 | 55.8 | 1.00 |
| off | on | 16,000 | 1000 | 3 | 23.7 (23.6-23.7) | 0.097 (0.095-0.101) | 42.301 (42.263-42.340) | 1000 | 3/3 | 42.4 | 45.4 | 1.00 |
| off | on | 16,000 | 2000 | 3 | 23.6 (23.6-23.6) | 0.095 (0.090-0.097) | 84.723 (84.683-84.816) | 2000 | 3/3 | 42.5 | 45.1 | 1.00 |
| off | on | 32,000 | 1000 | 3 | 22.0 (22.0-22.0) | 0.110 (0.108-0.111) | 45.550 (45.522-45.555) | 1000 | 3/3 | 45.6 | 48.6 | 1.00 |
| off | on | 32,000 | 2000 | 3 | 21.8 (21.7-21.8) | 0.113 (0.111-0.117) | 91.808 (91.735-92.336) | 2000 | 3/3 | 45.8 | 52.9 | 1.00 |

### M4 20-step trajectory (per step)

Source: `raw/m4-4bit-mtp-off-20261018-204432.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 26.872 (26.504-27.077) | 31.966 (31.552-32.152) | 0 | 15030 | 0.00 | 0 |
| 1 | 3 | 4.595 (4.502-4.600) | 10.629 (10.474-10.676) | 15026 | 16733 | 0.90 | 0 |
| 2 | 3 | 4.639 (4.582-4.641) | 10.912 (10.785-10.945) | 16729 | 18439 | 0.91 | 0 |
| 3 | 3 | 4.727 (4.649-4.791) | 8.554 (8.404-8.588) | 18435 | 20140 | 0.92 | 0 |
| 4 | 3 | 4.806 (4.743-4.845) | 11.180 (10.999-11.272) | 20136 | 21838 | 0.92 | 0 |
| 5 | 3 | 4.897 (4.875-4.942) | 9.580 (9.469-9.590) | 21834 | 23565 | 0.93 | 0 |
| 6 | 3 | 4.962 (4.889-4.964) | 9.425 (9.357-9.469) | 23561 | 25264 | 0.93 | 0 |
| 7 | 3 | 5.058 (5.045-5.077) | 8.622 (8.616-8.677) | 25260 | 26950 | 0.94 | 0 |
| 8 | 3 | 5.161 (5.079-5.218) | 10.880 (10.818-10.997) | 26946 | 28660 | 0.94 | 0 |
| 9 | 3 | 5.195 (5.136-5.265) | 11.014 (10.909-11.110) | 28656 | 30367 | 0.94 | 0 |
| 10 | 3 | 5.244 (5.243-5.303) | 11.913 (11.876-12.039) | 30363 | 32060 | 0.95 | 0 |
| 11 | 3 | 5.370 (5.270-5.404) | 12.128 (11.954-12.257) | 32056 | 33769 | 0.95 | 0 |
| 12 | 3 | 5.409 (5.394-5.419) | 11.473 (11.393-11.495) | 33765 | 35481 | 0.95 | 0 |
| 13 | 3 | 5.526 (5.454-5.562) | 12.392 (12.220-12.433) | 35477 | 37191 | 0.95 | 0 |
| 14 | 3 | 5.566 (5.545-5.636) | 9.247 (9.199-9.303) | 37187 | 38906 | 0.96 | 0 |
| 15 | 3 | 5.649 (5.621-5.682) | 10.163 (10.139-10.202) | 38902 | 40612 | 0.96 | 0 |
| 16 | 3 | 5.712 (5.703-5.754) | 10.559 (10.528-10.596) | 40608 | 42305 | 0.96 | 0 |
| 17 | 3 | 5.788 (5.784-5.864) | 10.482 (10.448-10.537) | 42301 | 44009 | 0.96 | 0 |
| 18 | 3 | 5.925 (5.839-5.948) | 13.007 (12.919-13.058) | 44005 | 45696 | 0.96 | 0 |
| 19 | 3 | 5.998 (5.935-6.014) | 13.098 (13.092-13.121) | 45692 | 47383 | 0.96 | 0 |
| 20 | 3 | 6.041 (6.036-6.116) | 13.230 (13.198-13.309) | 47379 | 49097 | 0.97 | 0 |

TTFT slope over steps 1-20: 0.0772 s/step (steps 2-20: 0.0774 s/step); total e2e per run: 248.4, 251.6, 250.6 s.

### M7 tool-call correctness

Source: `raw/m7-4bit-mtp-off-20261018-055049.jsonl`.

Passed 23/24.

| Case | Category | Result | Reasons |
| --- | --- | --- | --- |
| m7-01-single | single call | pass | - |
| m7-02-multi-args | multiple args | pass | - |
| m7-03-nested-object | nested objects | pass | - |
| m7-04-array-of-objects | nested objects (array of objects, multi-turn) | pass | - |
| m7-05-array-strings | arrays | pass | - |
| m7-06-array-integers | arrays | pass | - |
| m7-07-enum | enums | **FAIL** | called 'window_list' instead of 'window_arrange' |
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
<!-- agentbench:end summary 4bit-mtp-off -->

<!-- agentbench:begin summary 4bit-mtp-on -->
## Results, tag `4bit-mtp-on`

### M1 cached-prefix TTFT

Source: `raw/m1-4bit-mtp-on-20261018-210013.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 4.510 (4.224-4.715) | 6.904 (6.840-7.416) | 14945 | 16590 | content | 0 |
| cold | 3 | 33.523 (31.732-35.599) | 35.806 (33.806-37.534) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 7.43x.

### M3 short structured decode

Source: `raw/m3-4bit-mtp-on-20261018-210313.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 50 | 3 | 48.7 (47.9-51.1) | 0.089 (0.083-0.093) | 1.095 (1.043-1.118) | 50 | 3/3 | 0.1 | 82.2 | 1.00 |
| on | off | 16,000 | 150 | 3 | 41.5 (41.3-42.1) | 0.093 (0.089-0.093) | 3.682 (3.631-3.700) | 150 | 3/3 | 0.1 | 83.5 | 1.00 |
| on | off | 16,000 | 300 | 3 | 44.1 (43.7-44.3) | 0.091 (0.089-0.092) | 6.867 (6.844-6.931) | 300 | 3/3 | 0.1 | 88.0 | 1.00 |
| on | off | 32,000 | 50 | 3 | 42.9 (42.9-44.5) | 0.103 (0.100-0.106) | 1.246 (1.202-1.248) | 50 | 3/3 | 0.1 | 92.6 | 1.00 |
| on | off | 32,000 | 150 | 3 | 41.8 (41.3-41.8) | 0.105 (0.101-0.107) | 3.668 (3.664-3.714) | 150 | 3/3 | 0.1 | 92.4 | 1.00 |
| on | off | 32,000 | 300 | 3 | 41.1 (41.0-41.2) | 0.106 (0.105-0.107) | 7.389 (7.357-7.405) | 300 | 3/3 | 0.1 | 98.7 | 1.00 |
| on | off | 64,000 | 50 | 3 | 37.0 (36.9-38.4) | 0.136 (0.134-0.138) | 1.464 (1.411-1.466) | 50 | 3/3 | 0.1 | 105.4 | 1.00 |
| on | off | 64,000 | 150 | 3 | 34.0 (34.0-34.5) | 0.137 (0.136-0.139) | 4.516 (4.454-4.524) | 150 | 3/3 | 0.1 | 108.9 | 1.00 |
| on | off | 64,000 | 300 | 3 | 33.6 (33.1-33.6) | 0.137 (0.135-0.139) | 9.049 (9.046-9.173) | 300 | 3/3 | 0.1 | 113.9 | 1.00 |
| on | on | 16,000 | 1000 | 3 | 35.0 (34.9-35.0) | 0.091 (0.091-0.092) | 28.668 (28.612-28.690) | 1000 | 3/3 | 0.1 | 90.1 | 1.00 |
| on | on | 16,000 | 2000 | 3 | 37.9 (37.9-37.9) | 0.090 (0.089-0.090) | 52.848 (52.810-52.850) | 2000 | 3/3 | 0.1 | 89.8 | 1.00 |
| on | on | 32,000 | 1000 | 3 | 38.8 (38.7-38.8) | 0.104 (0.101-0.106) | 25.845 (25.839-25.896) | 1000 | 3/3 | 0.1 | 98.4 | 1.00 |
| on | on | 32,000 | 2000 | 3 | 39.4 (39.3-39.5) | 0.104 (0.104-0.107) | 50.814 (50.709-50.984) | 2000 | 3/3 | 0.1 | 98.6 | 1.00 |

### M4 20-step trajectory (per step)

Source: `raw/m4-4bit-mtp-on-20261018-213020.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 27.722 (26.857-27.827) | 30.166 (29.286-30.177) | 0 | 15030 | 0.00 | 0 |
| 1 | 3 | 4.658 (4.627-4.696) | 7.796 (7.776-7.807) | 15026 | 16733 | 0.90 | 0 |
| 2 | 3 | 4.676 (4.663-4.682) | 8.006 (7.993-8.030) | 16729 | 18439 | 0.91 | 0 |
| 3 | 3 | 4.748 (4.732-4.785) | 6.964 (6.957-6.976) | 18435 | 20140 | 0.92 | 0 |
| 4 | 3 | 4.825 (4.819-4.869) | 8.221 (8.207-8.231) | 20136 | 21838 | 0.92 | 0 |
| 5 | 3 | 4.957 (4.915-4.979) | 7.607 (7.590-7.611) | 21834 | 23565 | 0.93 | 0 |
| 6 | 3 | 4.973 (4.970-5.030) | 7.618 (7.501-7.627) | 23561 | 25264 | 0.93 | 0 |
| 7 | 3 | 5.063 (5.051-5.063) | 7.008 (6.994-7.029) | 25260 | 26950 | 0.94 | 0 |
| 8 | 3 | 5.164 (5.118-5.205) | 8.858 (8.836-8.898) | 26946 | 28660 | 0.94 | 0 |
| 9 | 3 | 5.242 (5.205-5.260) | 8.190 (8.141-8.200) | 28656 | 30367 | 0.94 | 0 |
| 10 | 3 | 5.305 (5.301-5.359) | 9.508 (9.495-9.512) | 30363 | 32060 | 0.95 | 0 |
| 11 | 3 | 5.379 (5.364-5.413) | 9.167 (9.138-9.176) | 32056 | 33769 | 0.95 | 0 |
| 12 | 3 | 5.471 (5.458-5.497) | 9.060 (8.982-9.338) | 33765 | 35481 | 0.95 | 0 |
| 13 | 3 | 5.572 (5.556-5.594) | 9.367 (9.325-9.379) | 35477 | 37191 | 0.95 | 0 |
| 14 | 3 | 5.636 (5.598-5.724) | 7.748 (7.737-7.773) | 37187 | 38906 | 0.96 | 0 |
| 15 | 3 | 5.784 (5.674-5.819) | 8.192 (8.164-8.300) | 38902 | 40612 | 0.96 | 0 |
| 16 | 3 | 5.811 (5.808-5.855) | 8.397 (8.384-8.418) | 40608 | 42305 | 0.96 | 0 |
| 17 | 3 | 5.914 (5.889-5.924) | 8.611 (8.610-8.617) | 42301 | 44009 | 0.96 | 0 |
| 18 | 3 | 5.932 (5.914-6.016) | 10.080 (10.039-10.106) | 44005 | 45696 | 0.96 | 0 |
| 19 | 3 | 5.995 (5.993-6.064) | 10.326 (10.291-10.384) | 45692 | 47383 | 0.96 | 0 |
| 20 | 3 | 6.087 (6.071-6.203) | 10.101 (10.050-10.130) | 47379 | 49097 | 0.97 | 0 |

TTFT slope over steps 1-20: 0.0789 s/step (steps 2-20: 0.0798 s/step); total e2e per run: 200.0, 200.9, 201.3 s.

### M6 memory and stability

Source: `raw/m6-4bit-mtp-on-20261019-054803.jsonl`.

| Metric | Value |
| --- | --- |
| footprint at 64,000 tokens: server tree peak GiB | 12.00 |
| footprint: system used peak GiB | 74.50 |
| loop minutes / runs (complete) / requests | 30.0 / 9 (8) / 187 |
| errors | 0 |
| server tree GiB start / peak / end | 17.00 / 25.00 / 24.00 |
| server tree growth GiB | 7.00 |
| system used GiB start / end | 78.36 / 86.43 |
| e2e last run / first run (median per step) | 1.00 |
| e2e s over all requests | 8.468 (6.998-30.493) |

### M7 tool-call correctness

Source: `raw/m7-4bit-mtp-on-20261018-063252.jsonl`.

Passed 23/24.

| Case | Category | Result | Reasons |
| --- | --- | --- | --- |
| m7-01-single | single call | pass | - |
| m7-02-multi-args | multiple args | pass | - |
| m7-03-nested-object | nested objects | pass | - |
| m7-04-array-of-objects | nested objects (array of objects, multi-turn) | pass | - |
| m7-05-array-strings | arrays | pass | - |
| m7-06-array-integers | arrays | pass | - |
| m7-07-enum | enums | **FAIL** | called 'window_list' instead of 'window_arrange' |
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
<!-- agentbench:end summary 4bit-mtp-on -->

<!-- agentbench:begin summary 4bit-conc -->
## Results, tag `4bit-conc`

### M5 concurrency

Source: `raw/m5-4bit-conc-20261018-214328.jsonl`.

| aux requests | n | main TTFT s | vs solo | main e2e s | main cached tok | main 429 | aux 429 | aux TTFT s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 3 | 4.416 (4.075-4.460) | 1.00 | 6.961 (6.549-7.244) | 14949 | 0 | 0 | - |
| 1 | 3 | 8.415 (7.903-8.462) | 1.91 | 12.440 (9.706-12.457) | 14949 | 0 | 0 | 5.176 (4.906-5.215) |
| 2 | 3 | 11.005 (10.842-11.695) | 2.49 | 15.521 (13.050-19.008) | 14949 | 0 | 0 | 9.934 (8.000-12.064) |
<!-- agentbench:end summary 4bit-conc -->

<!-- agentbench:begin summary 4bit-mtp-off-anchor -->
## Results, tag `4bit-mtp-off-anchor`

### M1 cached-prefix TTFT

Source: `raw/m1-4bit-mtp-off-anchor-20261018-173749.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 4.402 (4.070-4.486) | 8.819 (8.685-9.539) | 14945 | 16590 | content | 0 |
| cold | 3 | 31.390 (30.941-32.175) | 35.283 (34.637-35.491) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 7.13x.
<!-- agentbench:end summary 4bit-mtp-off-anchor -->
