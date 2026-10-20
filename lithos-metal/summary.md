# lithos-metal: results

## Read first

- **Build and checkpoints.** lithos-metal `v0.1.2` plus one local commit, `73b8cb6`
  (`lm_head_rename.patch`): as shipped, v0.1.2 does not bind the untied MLX head
  `language_model.lm_head.*`. Three variants:
  - `4bit-dspark`: `mlx-community/Qwen3.8-27B-4bit`, the same MLX affine 4-bit g64
    checkpoint as the MLX rows, with the `LithosAI/Qwen3.8-27B-DSpark-NVFP4` draft head
    (7 proposals and an anchor);
  - `4bit-no-draft`: the same target with `--no-draft`;
  - `nvfp4-dspark`: `nvidia/Qwen3.8-27B-NVFP4`, which pairs with the same DSpark head on
    its own.

  Full flags are in each raw file's header; `env.md` has the install and the CLI.
- **A reference row, not an agent-backend candidate.**
  - The gate fails G2, G2b and the G3 images: only string message content is accepted
    (HTTP 400).
  - It also fails G4: thinking is hard-wired off. The strict schema rejects
    `chat_template_kwargs`, so the profile strips it.
  - The metric suites therefore run text-only. Each screenshot is replaced by a text
    stand-in with the same token count, and all-text content lists are sent as one string.
    Prompt lengths match the image rows, but no vision encoder runs.
- **When.** The gate, M2, M3 and M7 ran between 2026-10-18 22:37 and 2026-10-19 05:08. M1
  and M4 re-ran text-only on 2026-10-20 from 05:09. The earlier M1 and M4 runs sent
  screenshots, which lithos rejects; they are not used. M4 runs once per variant.
- **Prefix cache.** lithos reuses a cached prefix. In M1 (`4bit-dspark`) the warm TTFT is
  5.0 s with 14,908 of 16,590 tokens cached, against 40.3 s cold.
  - M3's one-message prompts report 0 cached tokens, so the M3 TTFT and e2e columns are
    full prefills (36–218 s).
  - The M3 decode rates are unaffected.
- **Decode with DSpark.** M3 at 16K, cap 150: 60.6 tok/s (`4bit-dspark`) and 75.7
  (`nvfp4-dspark`), against 20.5 without a draft. At 64K: 35.3, 58.7 and 16.1.
- **Prefill.** M2 at 16K / 64K: 425 / 293 tok/s (`4bit-dspark`) and 446 / 308
  (`nvfp4-dspark`). G5 at 64K: TTFT 230.7 and 215.4 s.
- **M4, one run each (text-only):** 320 s (`4bit-dspark`), 315 s (`nvfp4-dspark`) and 382 s
  (no draft).
  - 8–11 of the 21 requests end at the 150-token cap inside a tool call. lithos flags these
    as a stream error ("The model generated an incomplete tool call; increase the output
    budget").
  - They count as latency samples, like oMLX's `incomplete_tool_call`.
- **M7: 21/24 on the 4-bit target and 20/24 on NVFP4.**
  - M7 ran before the forced text-only switch, so its two image cases were sent and
    rejected (HTTP 400).
  - On each variant, one text case ends with "The model generated an invalid tool call;
    retry the request": `m7-02-multi-args` on the 4-bit target, `m7-10-float-bool` on
    NVFP4.
  - NVFP4 also misses `m7-07-enum`, as the 8-bit rows do.

<!-- agentbench:begin summary 4bit-dspark -->
## Results, tag `4bit-dspark`

### Gate G1-G5

Source: `raw/gate-4bit-dspark-20261018-223737.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; incremental (5 deltas); first call chunk at 34.19 s, e2e 34.41 s; finish=tool_calls [profile stripped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 400: {"error":{"message":"messages.0.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.0.content.str","code":"invalid_request_error"}} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 400: {"error":{"message":"messages.2.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.2.content.str","code":"invalid_request_error"}}; prompt_tokens=None; control (user message): rejected: HTTP 400: {"error":{"message":"messages.3.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.3.content.str","code":"invalid_request_error"}}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text ok, tool_use ok, image FAIL, tool_result image FAIL (first failure: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}}); text ok ('ready'); no reasoning |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **FAIL** | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off); off: no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.effort-minimal: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.default: accepted; no reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 230.7 s; configured context: 131072; peak server footprint 27.0 GiB |

### M1 cached-prefix TTFT (text_only)

Source: `raw/m1-4bit-dspark-20261020-050926.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 4.996 (4.837-5.357) | 7.078 (6.474-7.736) | 14908 | 16590 | content | 0 |
| cold | 3 | 40.347 (39.490-42.256) | 41.339 (40.821-43.208) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 8.08x.

### M2 cold prefill

Source: `raw/m2-4bit-dspark-20261018-224246.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 37.673 (37.563-37.692) | 425 (424-426) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 86.192 (85.955-86.436) | 371 (370-372) | 32000 | 0 | ttft | 0 |
| 64,000 | 3 | 218.375 (218.234-218.745) | 293 (293-293) | 64000 | 0 | ttft | 0 |

### M3 short structured decode

Source: `raw/m3-4bit-dspark-20261018-230042.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 50 | 3 | 59.4 (59.3-60.2) | 37.386 (37.359-37.395) | 38.209 (38.185-38.212) | 50 | 3/3 | 76.7 | 157.7 | 4.55 |
| on | off | 16,000 | 150 | 3 | 60.6 (60.4-61.1) | 37.696 (37.615-37.873) | 40.164 (40.053-40.331) | 150 | 3/3 | 76.9 | 133.0 | 4.69 |
| on | off | 16,000 | 300 | 3 | 57.7 (57.4-57.7) | 37.406 (37.308-37.519) | 42.590 (42.491-42.725) | 300 | 3/3 | 77.3 | 116.9 | 4.62 |
| on | off | 32,000 | 50 | 3 | 54.4 (54.3-54.5) | 85.589 (85.518-85.602) | 86.492 (86.417-86.504) | 50 | 3/3 | 88.3 | 168.9 | 5.00 |
| on | off | 32,000 | 150 | 3 | 54.4 (54.2-54.4) | 85.646 (85.540-85.707) | 88.386 (88.287-88.448) | 150 | 3/3 | 98.7 | 157.9 | 5.17 |
| on | off | 32,000 | 300 | 3 | 53.4 (53.1-53.8) | 85.498 (85.374-85.538) | 91.053 (91.011-91.142) | 300 | 3/3 | 99.0 | 139.8 | 5.26 |
| on | off | 64,000 | 50 | 3 | 40.3 (40.2-40.5) | 218.619 (218.348-218.684) | 219.840 (219.566-219.895) | 50 | 3/3 | 131.4 | 202.6 | 5.00 |
| on | off | 64,000 | 150 | 3 | 35.3 (35.2-35.8) | 218.355 (218.189-218.842) | 222.523 (222.408-223.070) | 150 | 3/3 | 132.2 | 190.0 | 4.69 |
| on | off | 64,000 | 300 | 3 | 35.0 (35.0-35.0) | 218.254 (218.234-218.447) | 226.792 (226.769-227.001) | 300 | 3/3 | 132.4 | 172.6 | 4.69 |
| on | on | 16,000 | 1000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| on | on | 16,000 | 2000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| on | on | 32,000 | 1000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| on | on | 32,000 | 2000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |

### M4 20-step trajectory (per step) (text_only)

Source: `raw/m4-4bit-dspark-20261020-051252.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 1 | 35.505 | 36.972 | 0 | 15030 | 0.00 | 0 |
| 1 | 1 | 5.513 | 8.337 | - | 16733 | - | 0 |
| 2 | 1 | 9.031 | 12.264 | - | 18439 | - | 0 |
| 3 | 1 | 9.384 | 12.649 | - | 20140 | - | 0 |
| 4 | 1 | 9.507 | 13.055 | - | 21838 | - | 0 |
| 5 | 1 | 9.806 | 11.735 | 20541 | 23565 | 0.87 | 0 |
| 6 | 1 | 10.002 | 12.291 | 22268 | 25264 | 0.88 | 0 |
| 7 | 1 | 10.239 | 13.839 | 23967 | 26950 | 0.89 | 0 |
| 8 | 1 | 10.422 | 14.367 | 25653 | 28660 | 0.90 | 0 |
| 9 | 1 | 10.636 | 14.586 | 27363 | 30367 | 0.90 | 0 |
| 10 | 1 | 10.888 | 15.911 | - | 32060 | - | 0 |
| 11 | 1 | 11.130 | 14.696 | 30762 | 33769 | 0.91 | 0 |
| 12 | 1 | 11.360 | 14.839 | 32471 | 35481 | 0.92 | 0 |
| 13 | 1 | 11.592 | 15.829 | - | 37191 | - | 0 |
| 14 | 1 | 11.798 | 13.358 | 35893 | 38906 | 0.92 | 0 |
| 15 | 1 | 12.083 | 14.632 | 37608 | 40612 | 0.93 | 0 |
| 16 | 1 | 12.266 | 14.858 | 39314 | 42305 | 0.93 | 0 |
| 17 | 1 | 12.561 | 16.354 | 41007 | 44009 | 0.93 | 0 |
| 18 | 1 | 12.766 | 16.838 | - | 45696 | - | 0 |
| 19 | 1 | 13.063 | 17.455 | - | 47383 | - | 0 |
| 20 | 1 | 13.199 | 15.350 | 46085 | 49097 | 0.94 | 0 |

TTFT slope over steps 1-20: 0.2782 s/step (steps 2-20: 0.2307 s/step); total e2e per run: 320.2 s.

8 of 21 requests ended at the token cap inside a tool call, and the server flagged it as a stream error ("incomplete tool call"). They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M7 tool-call correctness

Source: `raw/m7-4bit-dspark-20261019-000140.jsonl`.

Passed 21/24.

| Case | Category | Result | Reasons |
| --- | --- | --- | --- |
| m7-01-single | single call | pass | - |
| m7-02-multi-args | multiple args | **FAIL** | stream_error: {'message': 'The model generated an invalid tool call; retry the request', 'type': 'server_error', 'code': 'invalid_tool_call'} |
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
| m7-22-image-read | call after an image | **FAIL** | HTTP 400: {"error":{"message":"messages.1.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.1.content.str","code":"invalid_request_error"}} |
| m7-23-image-click | call after an image | **FAIL** | HTTP 400: {"error":{"message":"messages.1.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.1.content.str","code":"invalid_request_error"}} |
| m7-24-calendar | nested objects | pass | - |
<!-- agentbench:end summary 4bit-dspark -->

<!-- agentbench:begin summary 4bit-no-draft -->
## Results, tag `4bit-no-draft`

### M1 cached-prefix TTFT (text_only)

Source: `raw/m1-4bit-no-draft-20261020-061124.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 4.816 (4.700-5.191) | 10.688 (9.757-11.112) | 14908 | 16590 | content | 0 |
| cold | 3 | 38.138 (37.561-40.308) | 42.648 (42.240-43.243) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 7.92x.

### M3 short structured decode

Source: `raw/m3-4bit-no-draft-20261019-010541.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 20.8 (20.8-20.8) | 35.746 (35.736-35.798) | 38.106 (38.097-38.156) | 50 | 3/3 | 384.0 | 393.5 | 6.25 |
| off | off | 16,000 | 150 | 3 | 20.5 (20.5-20.5) | 35.640 (35.639-35.821) | 42.917 (42.906-43.083) | 150 | 3/3 | 385.6 | 397.4 | 7.50 |
| off | off | 16,000 | 300 | 3 | 20.5 (20.4-20.5) | 35.566 (35.560-35.654) | 50.194 (50.179-50.270) | 300 | 3/3 | 394.4 | 397.4 | 7.69 |
| off | off | 32,000 | 50 | 3 | 19.0 (19.0-19.1) | 81.929 (81.906-81.996) | 84.501 (84.479-84.564) | 50 | 3/3 | 418.2 | 426.9 | 6.25 |
| off | off | 32,000 | 150 | 3 | 18.8 (18.8-18.8) | 81.887 (81.870-82.018) | 89.802 (89.780-89.959) | 150 | 3/3 | 426.8 | 437.4 | 7.50 |
| off | off | 32,000 | 300 | 3 | 18.8 (18.8-18.8) | 81.778 (81.756-81.894) | 97.690 (97.646-97.825) | 300 | 3/3 | 427.9 | 437.6 | 7.69 |
| off | off | 64,000 | 50 | 3 | 16.5 (16.4-16.5) | 210.107 (209.877-210.169) | 213.081 (212.862-213.146) | 50 | 3/3 | 483.1 | 494.5 | 6.25 |
| off | off | 64,000 | 150 | 3 | 16.1 (16.1-16.1) | 209.994 (209.784-210.105) | 219.248 (219.017-219.338) | 150 | 3/3 | 495.1 | 506.4 | 7.50 |
| off | off | 64,000 | 300 | 3 | 16.1 (16.1-16.1) | 209.758 (209.756-210.477) | 228.297 (228.290-229.024) | 300 | 3/3 | 494.7 | 506.5 | 7.69 |
| off | on | 16,000 | 1000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| off | on | 16,000 | 2000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| off | on | 32,000 | 1000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| off | on | 32,000 | 2000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |

### M4 20-step trajectory (per step) (text_only)

Source: `raw/m4-4bit-no-draft-20261020-061509.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 1 | 33.969 | 38.624 | 0 | 15030 | 0.00 | 0 |
| 1 | 1 | 4.993 | 12.338 | - | 16733 | - | 0 |
| 2 | 1 | 8.315 | 15.757 | - | 18439 | - | 0 |
| 3 | 1 | 8.459 | 15.964 | - | 20140 | - | 0 |
| 4 | 1 | 8.787 | 16.135 | 18843 | 21838 | 0.86 | 0 |
| 5 | 1 | 9.029 | 13.088 | 20541 | 23565 | 0.87 | 0 |
| 6 | 1 | 9.305 | 17.061 | - | 25264 | - | 0 |
| 7 | 1 | 9.451 | 17.234 | - | 26950 | - | 0 |
| 8 | 1 | 9.714 | 17.608 | - | 28660 | - | 0 |
| 9 | 1 | 10.099 | 17.732 | 27363 | 30367 | 0.90 | 0 |
| 10 | 1 | 10.115 | 18.159 | - | 32060 | - | 0 |
| 11 | 1 | 10.532 | 18.653 | - | 33769 | - | 0 |
| 12 | 1 | 10.729 | 18.123 | 32471 | 35481 | 0.92 | 0 |
| 13 | 1 | 10.934 | 19.193 | - | 37191 | - | 0 |
| 14 | 1 | 11.226 | 15.159 | 35893 | 38906 | 0.92 | 0 |
| 15 | 1 | 11.529 | 17.362 | 37608 | 40612 | 0.93 | 0 |
| 16 | 1 | 11.747 | 16.211 | 39314 | 42305 | 0.93 | 0 |
| 17 | 1 | 11.826 | 17.753 | 41007 | 44009 | 0.93 | 0 |
| 18 | 1 | 12.132 | 20.748 | - | 45696 | - | 0 |
| 19 | 1 | 12.329 | 21.016 | - | 47383 | - | 0 |
| 20 | 1 | 12.670 | 17.786 | 46085 | 49097 | 0.94 | 0 |

TTFT slope over steps 1-20: 0.2853 s/step (steps 2-20: 0.2416 s/step); total e2e per run: 381.7 s.

11 of 21 requests ended at the token cap inside a tool call, and the server flagged it as a stream error ("incomplete tool call"). They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M7 tool-call correctness

Source: `raw/m7-4bit-no-draft-20261019-020648.jsonl`.

Passed 21/24.

| Case | Category | Result | Reasons |
| --- | --- | --- | --- |
| m7-01-single | single call | pass | - |
| m7-02-multi-args | multiple args | **FAIL** | stream_error: {'message': 'The model generated an invalid tool call; retry the request', 'type': 'server_error', 'code': 'invalid_tool_call'} |
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
| m7-22-image-read | call after an image | **FAIL** | HTTP 400: {"error":{"message":"messages.1.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.1.content.str","code":"invalid_request_error"}} |
| m7-23-image-click | call after an image | **FAIL** | HTTP 400: {"error":{"message":"messages.1.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.1.content.str","code":"invalid_request_error"}} |
| m7-24-calendar | nested objects | pass | - |
<!-- agentbench:end summary 4bit-no-draft -->

<!-- agentbench:begin summary nvfp4-dspark -->
## Results, tag `nvfp4-dspark`

### Gate G1-G5

Source: `raw/gate-nvfp4-dspark-20261019-025248.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; incremental (4 deltas); first call chunk at 32.77 s, e2e 32.88 s; finish=tool_calls [profile stripped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 400: {"error":{"message":"messages.0.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.0.content.str","code":"invalid_request_error"}} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 400: {"error":{"message":"messages.2.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.2.content.str","code":"invalid_request_error"}}; prompt_tokens=None; control (user message): rejected: HTTP 400: {"error":{"message":"messages.3.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.3.content.str","code":"invalid_request_error"}}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text ok, tool_use ok, image FAIL, tool_result image FAIL (first failure: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}}); text ok ('ready'); no reasoning |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **FAIL** | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off); off: no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.effort-minimal: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.default: accepted; no reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 215.4 s; configured context: 131072; peak server footprint 25.0 GiB |

### M1 cached-prefix TTFT (text_only)

Source: `raw/m1-nvfp4-dspark-20261020-052353.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 6.684 (6.461-6.834) | 8.010 (7.331-8.420) | 14908 | 16590 | content | 0 |
| cold | 3 | 38.335 (38.045-39.980) | 39.304 (39.125-40.672) | 0 | 16605 | content | 0 |

Cold / warm TTFT (medians): 5.74x.

### M2 cold prefill

Source: `raw/m2-nvfp4-dspark-20261019-025737.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 35.836 (35.669-35.946) | 446 (445-449) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 81.158 (81.066-81.208) | 394 (394-395) | 32000 | 0 | ttft | 0 |
| 64,000 | 3 | 208.072 (207.785-208.238) | 308 (307-308) | 64000 | 0 | ttft | 0 |

### M3 short structured decode

Source: `raw/m3-nvfp4-dspark-20261019-041018.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 50 | 3 | 94.9 (94.6-95.0) | 35.977 (35.916-36.154) | 36.493 (36.433-36.672) | 50 | 3/3 | 55.2 | 66.2 | 5.00 |
| on | off | 16,000 | 150 | 3 | 75.7 (75.3-75.7) | 36.079 (36.043-36.100) | 38.047 (38.012-38.078) | 150 | 3/3 | 55.2 | 66.3 | 4.29 |
| on | off | 16,000 | 300 | 3 | 84.7 (84.4-84.7) | 36.082 (35.987-36.181) | 39.611 (39.531-39.711) | 300 | 3/3 | 55.3 | 66.3 | 4.92 |
| on | off | 32,000 | 50 | 3 | 77.9 (76.8-78.1) | 81.273 (81.256-81.335) | 81.901 (81.885-81.974) | 50 | 3/3 | 66.0 | 66.3 | 4.55 |
| on | off | 32,000 | 150 | 3 | 62.5 (62.5-62.7) | 81.284 (81.158-81.480) | 83.669 (83.542-83.858) | 150 | 3/3 | 66.0 | 66.4 | 3.95 |
| on | off | 32,000 | 300 | 3 | 77.1 (76.2-77.5) | 81.418 (81.335-81.473) | 85.296 (85.195-85.395) | 300 | 3/3 | 66.2 | 77.2 | 5.00 |
| on | off | 64,000 | 50 | 3 | 64.7 (64.6-64.7) | 208.684 (208.418-208.744) | 209.441 (209.178-209.502) | 50 | 3/3 | 76.8 | 86.5 | 4.55 |
| on | off | 64,000 | 150 | 3 | 58.7 (58.7-58.7) | 208.635 (208.581-208.647) | 211.172 (211.121-211.186) | 150 | 3/3 | 77.0 | 84.9 | 4.41 |
| on | off | 64,000 | 300 | 3 | 59.1 (58.9-59.3) | 208.581 (208.329-208.814) | 213.657 (213.371-213.871) | 300 | 3/3 | 77.3 | 88.5 | 4.69 |
| on | on | 16,000 | 1000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| on | on | 16,000 | 2000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| on | on | 32,000 | 1000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |
| on | on | 32,000 | 2000 | 0 | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) | - | - | - | - | - | - | - |

### M4 20-step trajectory (per step) (text_only)

Source: `raw/m4-nvfp4-dspark-20261020-052716.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 1 | 34.725 | 36.615 | - | 15030 | - | 0 |
| 1 | 1 | 6.646 | 7.908 | 14923 | 16733 | 0.89 | 0 |
| 2 | 1 | 9.749 | 11.110 | 15436 | 18439 | 0.84 | 0 |
| 3 | 1 | 10.017 | 12.522 | - | 20140 | - | 0 |
| 4 | 1 | 10.374 | 12.793 | - | 21838 | - | 0 |
| 5 | 1 | 10.632 | 11.857 | 20541 | 23565 | 0.87 | 0 |
| 6 | 1 | 10.811 | 12.244 | 22268 | 25264 | 0.88 | 0 |
| 7 | 1 | 11.000 | 12.130 | 23967 | 26950 | 0.89 | 0 |
| 8 | 1 | 11.284 | 13.832 | 25653 | 28660 | 0.90 | 0 |
| 9 | 1 | 11.637 | 13.695 | 27363 | 30367 | 0.90 | 0 |
| 10 | 1 | 11.829 | 14.750 | - | 32060 | - | 0 |
| 11 | 1 | 12.480 | 14.310 | - | 33769 | - | 0 |
| 12 | 1 | 12.405 | 14.434 | 32471 | 35481 | 0.92 | 0 |
| 13 | 1 | 12.689 | 15.309 | - | 37191 | - | 0 |
| 14 | 1 | 12.998 | 14.189 | 35893 | 38906 | 0.92 | 0 |
| 15 | 1 | 13.150 | 15.049 | 37608 | 40612 | 0.93 | 0 |
| 16 | 1 | 13.389 | 15.753 | 39314 | 42305 | 0.93 | 0 |
| 17 | 1 | 13.740 | 16.839 | - | 44009 | - | 0 |
| 18 | 1 | 14.068 | 16.122 | - | 45696 | - | 0 |
| 19 | 1 | 14.192 | 16.522 | - | 47383 | - | 0 |
| 20 | 1 | 14.338 | 17.220 | 46085 | 49097 | 0.94 | 0 |

TTFT slope over steps 1-20: 0.3019 s/step (steps 2-20: 0.2606 s/step); total e2e per run: 315.2 s.

9 of 21 requests ended at the token cap inside a tool call, and the server flagged it as a stream error ("incomplete tool call"). They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M7 tool-call correctness

Source: `raw/m7-nvfp4-dspark-20261019-050757.jsonl`.

Passed 20/24.

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
| m7-10-float-bool | numbers and booleans | **FAIL** | stream_error: {'message': 'The model generated an invalid tool call; retry the request', 'type': 'server_error', 'code': 'invalid_tool_call'} |
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
| m7-22-image-read | call after an image | **FAIL** | HTTP 400: {"error":{"message":"messages.1.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.1.content.str","code":"invalid_request_error"}} |
| m7-23-image-click | call after an image | **FAIL** | HTTP 400: {"error":{"message":"messages.1.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.1.content.str","code":"invalid_request_error"}} |
| m7-24-calendar | nested objects | pass | - |
<!-- agentbench:end summary nvfp4-dspark -->
