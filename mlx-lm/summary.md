# mlx-lm: results

## Read first

- **Build and checkpoints.** mlx-lm `v0.32.2` (`93e6d4a6`, mlx 0.32.4) runs `mlx_lm.server`
  with `--prompt-cache-size 64 --prompt-cache-bytes 48GB --max-tokens 4096`. It serves
  `mlx-community/Qwen3.8-27B-4bit` and `-8bit`, the same checkpoints as oMLX and vLLM-Metal.
  - No speculative decoding.
  - Full flags are in each raw file's header; `env.md` has the install.
- **A reference row, not an agent-backend candidate.**
  - The gate fails G2 and G2b: only text content parts are accepted (HTTP 404).
  - It also fails G3: there is no `/v1/messages`.
  - G1, G4 and G5 pass.
  - The metric suites therefore run text-only. Each screenshot is replaced by a text
    stand-in with the same token count, so prompt lengths match the image rows, but no
    vision encoder runs.
- **Request shape.**
  - The harness omits `model`: any value other than `default_model` reloads the model.
  - It drops `seed`, which forces the unbatched path without prompt-cache checkpoints.
  - `reasoning_effort=none` alone does not disable thinking; `chat_template_kwargs` does.
- **When.** The gate, M2, M3 and M7 ran on 2026-10-19 between 08:19 and 09:05. M1 and M4
  re-ran text-only on 2026-10-20 between 04:21 and 05:00. The earlier M1 and M4 runs sent
  screenshots, which mlx-lm rejects; they are not used.
- **4-bit:**
  - M1: warm 2.78 s, cold 25.5 s;
  - M2: 697 tok/s at 16K and 554 at 64K;
  - M3 at 16K: decode 28.2 tok/s structured and 27.8 with thinking. TTFT stays about 0.1 s
    with thinking on too, because the cached prefix is reused;
  - M4: 194 s per run (text-only);
  - M7: 22/24.
- **8-bit (gate, M1, M4, M7):**
  - G5 at 64K: TTFT 126.6 s;
  - M1: warm 2.87 s, cold 26.4 s;
  - M4: 267 s per run;
  - M7: 21/24. It also misses `m7-07-enum`, as the other 8-bit rows do.
- **M7's image cases.** M7 ran before the forced text-only switch, so its two image cases
  were sent and rejected (HTTP 404). Those are the 2 failures at 4-bit.

<!-- agentbench:begin summary 8bit -->
## Results, tag `8bit`

### Gate G1-G5

Source: `raw/gate-8bit-20261019-081920.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 22.29 s, e2e 22.35 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 404: {"error": "Only 'text' content type is supported."} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None; control (user message): rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: transport: ReadError: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 152 chars in reasoning; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 152 chars in reasoning \| G4.effort-high: accepted; reasoning 152 chars in reasoning \| G4.effort-minimal: accepted; reasoning 152 chars in reasoning \| G4.default: accepted; reasoning 152 chars in reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 126.6 s; configured context: unknown; peak server footprint 45.0 GiB |

### M1 cached-prefix TTFT (text_only)

Source: `raw/m1-8bit-20261020-042152.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 2.867 (2.819-3.028) | 8.454 (8.027-9.997) | 14948 | 16590 | content | 0 |
| cold | 3 | 26.427 (25.874-27.993) | 30.835 (29.259-31.305) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 9.22x.

### M4 20-step trajectory (per step) (text_only)

Source: `raw/m4-8bit-20261020-042445.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 24.419 (21.802-24.446) | 31.589 (28.927-31.620) | 0 | 15030 | 0.00 | 0 |
| 1 | 3 | 3.476 (3.096-3.490) | 11.044 (9.737-11.526) | 15029 | 16733 | 0.90 | 0 |
| 2 | 3 | 3.489 (2.952-3.569) | 12.159 (11.561-12.314) | 16732 | 18439 | 0.91 | 0 |
| 3 | 3 | 3.514 (3.099-3.565) | 12.215 (11.731-12.325) | 18438 | 20140 | 0.92 | 0 |
| 4 | 3 | 3.605 (3.556-3.629) | 12.281 (9.129-12.307) | 20139 | 21838 | 0.92 | 0 |
| 5 | 3 | 3.688 (3.595-3.706) | 9.541 (9.419-9.594) | 21837 | 23565 | 0.93 | 0 |
| 6 | 3 | 3.714 (3.688-3.760) | 10.533 (10.510-10.603) | 23564 | 25264 | 0.93 | 0 |
| 7 | 3 | 3.754 (3.669-3.784) | 8.923 (8.761-10.175) | 25263 | 26950 | 0.94 | 0 |
| 8 | 3 | 3.859 (3.797-3.950) | 11.968 (11.863-12.140) | 26949 | 28660 | 0.94 | 0 |
| 9 | 3 | 3.838 (3.748-4.023) | 12.381 (10.472-12.710) | 28659 | 30367 | 0.94 | 0 |
| 10 | 3 | 4.093 (3.837-4.187) | 13.130 (12.833-13.190) | 30366 | 32060 | 0.95 | 0 |
| 11 | 3 | 4.143 (3.941-4.167) | 13.201 (12.995-13.234) | 32059 | 33769 | 0.95 | 0 |
| 12 | 3 | 3.977 (3.899-4.139) | 12.538 (12.174-12.657) | 33768 | 35481 | 0.95 | 0 |
| 13 | 3 | 3.969 (3.944-4.189) | 13.174 (13.091-13.329) | 35480 | 37191 | 0.95 | 0 |
| 14 | 3 | 4.195 (4.023-4.227) | 9.759 (9.605-9.763) | 37190 | 38906 | 0.96 | 0 |
| 15 | 3 | 4.096 (3.993-4.247) | 10.674 (10.647-10.921) | 38905 | 40612 | 0.96 | 0 |
| 16 | 3 | 4.149 (4.123-4.299) | 11.512 (9.537-11.700) | 40611 | 42305 | 0.96 | 0 |
| 17 | 3 | 4.197 (4.188-4.266) | 11.727 (11.602-13.458) | 42304 | 44009 | 0.96 | 0 |
| 18 | 3 | 4.240 (4.224-4.286) | 13.567 (13.561-13.698) | 44008 | 45696 | 0.96 | 0 |
| 19 | 3 | 4.285 (4.238-4.360) | 13.651 (13.595-13.825) | 45695 | 47383 | 0.96 | 0 |
| 20 | 3 | 4.339 (4.316-4.447) | 13.795 (13.699-13.979) | 47382 | 49097 | 0.97 | 0 |

TTFT slope over steps 1-20: 0.0460 s/step (steps 2-20: 0.0456 s/step); total e2e per run: 264.7, 268.1, 267.1 s.

### M7 tool-call correctness

Source: `raw/m7-8bit-20261019-082417.jsonl`.

Passed 21/24.

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
| m7-22-image-read | call after an image | **FAIL** | HTTP 404: {"error": "Only 'text' content type is supported."} |
| m7-23-image-click | call after an image | **FAIL** | HTTP 404: {"error": "Only 'text' content type is supported."} |
| m7-24-calendar | nested objects | pass | - |
<!-- agentbench:end summary 8bit -->

<!-- agentbench:begin summary 4bit -->
## Results, tag `4bit`

### Gate G1-G5

Source: `raw/gate-4bit-20261019-082922.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 19.97 s, e2e 20.00 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 404: {"error": "Only 'text' content type is supported."} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None; control (user message): rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: transport: ReadError: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 152 chars in reasoning; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 152 chars in reasoning \| G4.effort-high: accepted; reasoning 152 chars in reasoning \| G4.effort-minimal: accepted; reasoning 152 chars in reasoning \| G4.default: accepted; reasoning 152 chars in reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 120.2 s; configured context: unknown; peak server footprint 33.0 GiB |

### M1 cached-prefix TTFT (text_only)

Source: `raw/m1-4bit-20261020-045342.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 2.776 (2.524-2.876) | 6.350 (4.531-6.638) | 14948 | 16590 | content | 0 |
| cold | 3 | 25.485 (24.381-25.501) | 26.973 (25.868-28.980) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 9.18x.

### M2 cold prefill

Source: `raw/m2-4bit-20261019-083232.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 22.942 (22.820-23.030) | 697 (695-701) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 49.418 (49.374-50.132) | 648 (638-648) | 32000 | 0 | ttft | 0 |
| 64,000 | 3 | 115.485 (114.443-116.474) | 554 (549-559) | 64000 | 0 | ttft | 0 |

### M3 short structured decode

Source: `raw/m3-4bit-20261019-084230.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 28.7 (28.3-29.6) | 0.097 (0.097-0.106) | 1.803 (1.764-1.832) | 50 | 3/3 | 35.3 | 67.8 | 1.04 |
| off | off | 16,000 | 150 | 3 | 28.2 (28.1-28.2) | 0.097 (0.097-0.100) | 5.387 (5.383-5.405) | 150 | 3/3 | 35.6 | 71.5 | 1.05 |
| off | off | 16,000 | 300 | 3 | 28.3 (28.2-28.3) | 0.096 (0.096-0.097) | 10.680 (10.671-10.685) | 300 | 3/3 | 35.5 | 71.3 | 1.05 |
| off | off | 32,000 | 50 | 3 | 26.7 (26.2-27.3) | 0.148 (0.121-0.149) | 1.959 (1.943-2.018) | 50 | 3/3 | 37.5 | 75.6 | 1.04 |
| off | off | 32,000 | 150 | 3 | 26.8 (26.7-27.1) | 0.125 (0.123-0.126) | 5.677 (5.630-5.698) | 150 | 3/3 | 37.1 | 75.2 | 1.06 |
| off | off | 32,000 | 300 | 3 | 26.9 (26.9-26.9) | 0.126 (0.123-0.127) | 11.224 (11.221-11.241) | 300 | 3/3 | 37.1 | 74.7 | 1.06 |
| off | off | 64,000 | 50 | 3 | 23.8 (23.5-24.0) | 0.538 (0.170-0.632) | 2.583 (2.228-2.716) | 50 | 3/3 | 41.9 | 81.8 | 1.04 |
| off | off | 64,000 | 150 | 3 | 23.7 (23.6-23.8) | 0.174 (0.170-0.486) | 6.454 (6.446-6.811) | 150 | 3/3 | 42.1 | 85.6 | 1.05 |
| off | off | 64,000 | 300 | 3 | 23.6 (23.5-23.6) | 0.173 (0.171-0.176) | 12.867 (12.855-12.883) | 300 | 3/3 | 42.2 | 85.7 | 1.05 |
| off | on | 16,000 | 1000 | 3 | 27.8 (27.7-27.8) | 0.102 (0.101-0.113) | 36.080 (36.045-36.157) | 1000 | 3/3 | 36.1 | 72.6 | 1.05 |
| off | on | 16,000 | 2000 | 3 | 27.9 (27.9-28.0) | 0.102 (0.100-0.103) | 71.741 (71.575-71.814) | 2000 | 3/3 | 35.9 | 72.3 | 1.04 |
| off | on | 32,000 | 1000 | 3 | 26.6 (26.6-26.6) | 0.131 (0.127-0.156) | 37.742 (37.720-37.763) | 1000 | 3/3 | 37.5 | 75.0 | 1.02 |
| off | on | 32,000 | 2000 | 3 | 26.5 (26.5-26.5) | 0.129 (0.129-0.134) | 75.596 (75.542-75.691) | 2000 | 3/3 | 37.7 | 75.3 | 1.02 |

### M4 20-step trajectory (per step) (text_only)

Source: `raw/m4-4bit-20261020-045604.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 22.909 (19.961-23.101) | 26.212 (23.209-26.421) | 0 | 15030 | 0.00 | 0 |
| 1 | 3 | 3.194 (3.016-3.272) | 8.568 (8.199-8.606) | 15029 | 16733 | 0.90 | 0 |
| 2 | 3 | 3.181 (2.971-3.199) | 8.463 (8.095-8.516) | 16732 | 18439 | 0.91 | 0 |
| 3 | 3 | 3.169 (3.088-3.358) | 8.260 (7.503-8.550) | 18438 | 20140 | 0.92 | 0 |
| 4 | 3 | 3.345 (3.169-3.349) | 8.464 (8.117-8.524) | 20139 | 21838 | 0.92 | 0 |
| 5 | 3 | 3.289 (3.212-3.454) | 6.336 (6.193-6.537) | 21837 | 23565 | 0.93 | 0 |
| 6 | 3 | 3.405 (3.138-3.493) | 8.036 (6.133-8.949) | 23564 | 25264 | 0.93 | 0 |
| 7 | 3 | 3.351 (3.264-3.409) | 8.802 (8.668-8.821) | 25263 | 26950 | 0.94 | 0 |
| 8 | 3 | 3.404 (3.315-3.465) | 8.474 (8.197-8.563) | 26949 | 28660 | 0.94 | 0 |
| 9 | 3 | 3.501 (3.464-3.506) | 8.668 (8.614-8.789) | 28659 | 30367 | 0.94 | 0 |
| 10 | 3 | 3.625 (3.557-3.677) | 9.231 (9.142-9.289) | 30366 | 32060 | 0.95 | 0 |
| 11 | 3 | 3.655 (3.610-3.732) | 9.276 (9.250-9.459) | 32059 | 33769 | 0.95 | 0 |
| 12 | 3 | 3.779 (3.721-3.859) | 9.109 (8.983-9.157) | 33768 | 35481 | 0.95 | 0 |
| 13 | 3 | 3.719 (3.673-3.857) | 9.464 (9.453-9.636) | 35480 | 37191 | 0.95 | 0 |
| 14 | 3 | 3.781 (3.738-3.896) | 6.228 (6.174-6.314) | 37190 | 38906 | 0.96 | 0 |
| 15 | 3 | 3.722 (3.653-3.828) | 7.839 (7.691-8.612) | 38905 | 40612 | 0.96 | 0 |
| 16 | 3 | 3.882 (3.869-3.968) | 6.982 (6.877-7.600) | 40611 | 42305 | 0.96 | 0 |
| 17 | 3 | 3.954 (3.952-4.056) | 8.002 (7.913-9.843) | 42304 | 44009 | 0.96 | 0 |
| 18 | 3 | 3.975 (3.971-3.995) | 9.934 (9.879-10.074) | 44008 | 45696 | 0.96 | 0 |
| 19 | 3 | 4.029 (3.975-4.045) | 9.983 (9.976-10.165) | 45695 | 47383 | 0.96 | 0 |
| 20 | 3 | 4.072 (4.026-4.093) | 7.554 (7.413-7.636) | 47382 | 49097 | 0.97 | 0 |

TTFT slope over steps 1-20: 0.0496 s/step (steps 2-20: 0.0507 s/step); total e2e per run: 190.3, 195.2, 194.1 s.

### M7 tool-call correctness

Source: `raw/m7-4bit-20261019-090341.jsonl`.

Passed 22/24.

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
| m7-22-image-read | call after an image | **FAIL** | HTTP 404: {"error": "Only 'text' content type is supported."} |
| m7-23-image-click | call after an image | **FAIL** | HTTP 404: {"error": "Only 'text' content type is supported."} |
| m7-24-calendar | nested objects | pass | - |
<!-- agentbench:end summary 4bit -->
