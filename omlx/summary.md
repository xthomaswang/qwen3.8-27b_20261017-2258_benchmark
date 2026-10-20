# omlx: results

## Read first

- **Build and checkpoint.** Stock oMLX `v0.7.1rc1` (`7a5a3d75`) serves
  `mlx-community/Qwen3.8-27B-4bit` (MLX affine 4-bit g64). Its base path is
  `serving/omlx_0.7/.bench-home`, never the user's `~/.omlx`.
  - Speculative decoding is off.
  - Lightning MTP needs `mtp.*` tensors, which this checkpoint lacks. DFlash needs a separate
    draft model. (`env.md`)
  - The `oq8mtp-*` and `oq4mtp-*` tags serve self-converted oQ checkpoints that keep the MTP
    head, with Lightning MTP on (`mtp-on`) or off (`spec-off`); see "Lightning MTP" below.
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
- **~3 s of TTFT after an output that crossed a 2048-token block.** oMLX caches generated
  tokens too, in 2048-token blocks. When a response's output crosses the next block
  boundary, the server stores the block-aligned chain and drops the prompt-end snapshot
  (`omlx/scheduler.py` at `7a5a3d7`, the boundary store in `_get_boundary_store_override`).
  The log then says, for example, "storing 16384/17000 tokens (block aligned)".
  - A request that repeats the prompt then reuses only `floor(prompt / 2048) × 2048` tokens
    and re-prefills the rest. That is 14,336 of 16,000 tokens at 16K and 30,720 of 32,000 at
    32K.
  - In M3 this hits every thinking cell. Its caps of 1000 and 2000 tokens always cross,
    because the 16K and 32K prompts sit 384 and 768 tokens below a boundary. TTFT is
    2.6–3.4 s there, against 0.26–0.53 s with thinking off, whose outputs of at most 300
    tokens never cross.
  - So thinking is not the cause, but long outputs make it likely. The same store decision
    shows with thinking off when an output crosses (M4 step 20, the M5 helpers).
  - llama.cpp and vLLM-Metal show no such gap.
  - M1 and M4 run with thinking off and a 150-token cap. An agent step with thinking on
    pays up to about 2K tokens of re-prefill on top.
- **Streaming granularity.** About 3.9 tokens per SSE chunk, with a chunk-gap p50 of
  ~150 ms. The decode rate is unaffected.
- **The SSD prefix cache persists across restarts,** which is why G1 shows a 1.3 s first call.
  The cold measurements (M1 cold, M2, G5, M4 step 0) carry nonces, so they are not affected.
- **M6, 30 min:** no latency drift (0.99), and the server tree grew by 2 GiB. The 72 "errors"
  in 188 requests are `incomplete_tool_call` stream errors, on the steps where the 150-token
  cap cuts a multi-call output. llama.cpp and vLLM-Metal hit `finish_reason=length` on the
  same steps (2, 10, 11, 13, 18 and 19), so these are not server failures.
- **8-bit (`8bit-spec-off`), 2026-10-19:**
  - G2b fails as at 4-bit: the image is dropped (639 prompt tokens) and the model refuses;
  - G5 at 64K: TTFT 110.7 s, 36.0 GiB;
  - M1: warm 2.77 s, cold 24.6 s;
  - M3 (12:52): decode 18.3 tok/s at 16K and 16.6 at 32K with thinking off, 18.0 and 17.4
    with it on; TTFT 0.31–0.53 s with thinking off and 3.0–3.3 s with it on;
  - M4: about 257 s per run, and step 1 is again a re-prefill (16.0 s);
  - M7: 23/24 (`m7-07-enum`).
- **8-bit at temperature 1.0** (`8bit-spec-off-t1`, M4 only), 2026-10-19 23:50. This is the
  model's own sampling (temperature 1.0, top_p 0.95, top_k 20), as the agent benchmark sends
  it. A run takes 274–289 s, against 256–260 s at temperature 0. Sampling changes the
  outputs: 9–13 steps per run end at the 150-token cap, against 7–8.
- **Lightning MTP on oQ checkpoints** (`oq8mtp-*`, `oq4mtp-*`), 2026-10-20 00:15–06:55:
  - The checkpoints are converted from the BF16 release with oMLX's oQ quantizer, keeping
    the MTP head (`scripts/oq_convert.py`, `preserve_mtp=True`): oQ8 is 28 GB, oQ4 16 GB
    (166 tensors at 5-bit). The mlx-community checkpoints carry no `mtp.*` tensors. MTP is
    switched per model (`mtp_enabled` in the bench `model_settings.json`), at oMLX's
    adaptive depth.
  - M4 total per run, median of 3, MTP on / off: oQ4 158 / 215 s, oQ8 195 / 272 s. At
    temperature 1.0: oQ4 164 / 216 s, oQ8 200 / 272 s. With MTP off, oQ is about 5 % slower
    than the mlx-community checkpoints (215 against 206 s, 272 against 258 s).
  - M3 decode at 16K, MTP on / off: oQ4 68.4 / 27.3 tok/s structured and 45.3 / 25.3 with
    thinking; oQ8 47.2 / 17.7 and 28.1 / 17.7. At temperature 1.0: oQ4 75.1 / 27.8 and
    45.6 / 26.5; oQ8 53.5 / 18.2 and 35.0 / 17.9.
  - MTP loses no speed at temperature 1.0, unlike llama.cpp's. For text requests oMLX
    verifies drafts with standard speculative sampling (`_stochastic_verify_tokens_sparse`
    in `omlx/patches/mlx_lm_mtp/batch_generator.py`, used when top_k ≤ 64). Drafts are
    sampled with the request's filters and accepted with probability min(1, p/q); the first
    rejection resamples from max(p − q, 0). So the output keeps the target's distribution.
    The server log's thinking acceptance rose from 0.64 / 0.57 to 0.70 / 0.73 on oQ8
    (16K / 32K) and from 0.67 / 0.65 to 0.69 / 0.70 on oQ4.
  - The gate with MTP on: G1–G5 pass on both, with the G2 and G3 images going through the
    MTP decoder; G2b fails as on all stock oMLX. G5 at 64K: TTFT 119.3 s (oQ8) and 105.3 s
    (oQ4), against 112.7 and 102.4 s with MTP off.
  - M1 warm / cold with MTP: oQ4 2.59 / 22.2 s, oQ8 2.86 / 26.4 s (without: 3.18 / 23.0 and
    3.94 / 27.1 s).
  - M7: oQ4 24/24, oQ8 23/24 (`m7-07-enum`), with MTP on or off. One trial per case, and
    `m7-07-enum` is borderline, so this does not rank oQ4 above oQ8.
  - M6, oQ4 with MTP, 30 min: 12 runs (11 complete) and 233 requests, against 188 for the
    4-bit row; e2e median 5.92 s; last run over first 1.02; server tree 26 → 33 (peak) →
    22 GiB. The 89 errors are `incomplete_tool_call` at the 150-token cap, the same 38 %
    share as the 4-bit row (72 of 188).
  - M6, oQ8 with MTP, 30 min (2026-10-20 12:30): 10 runs (9 complete) and 190 requests, so
    8-bit weights with MTP keep the 4-bit row's throughput (188); e2e median 7.30 s; last
    run over first 1.01; server tree 46 → 47 (peak) → 42 GiB, against 24 GiB for the 4-bit
    row. The 67 errors are `incomplete_tool_call` at the 150-token cap (35 %).
    - Two earlier attempts were disturbed: at 11:38 by `ReportMemoryException` at 99 % CPU,
      and at 12:13 by Spotlight (`mds`) at 56 %. They stay local in `raw/_unverified/`.
    - The monitor TSV (`monitor-oq8mtp-mtp-on-20261020-112607.tsv`) covers all three
      attempts; the verified run is 12:30–13:02.
  - Thinking-on TTFT stays 2.6–3.4 s on every oQ row (the block boundary above).
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

### M6 memory and stability

Source: `raw/m6-4bit-spec-off-20261019-062357.jsonl`.

| Metric | Value |
| --- | --- |
| footprint at 64,000 tokens: server tree peak GiB | 24.00 |
| footprint: system used peak GiB | 69.17 |
| loop minutes / runs (complete) / requests | 30.0 / 9 (8) / 188 |
| errors | 72 |
| server tree GiB start / peak / end | 24.00 / 30.00 / 26.00 |
| server tree growth GiB | 2.00 |
| system used GiB start / end | 69.16 / 71.33 |
| e2e last run / first run (median per step) | 0.99 |
| e2e s over all requests | 7.709 (6.121-24.407) |

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

<!-- agentbench:begin summary 8bit-spec-off -->
## Results, tag `8bit-spec-off`

### Gate G1-G5

Source: `raw/gate-8bit-spec-off-20261019-072034.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 21.10 s, e2e 21.11 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. T", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 121 chars in thinking_block / text ok ('ready'); reasoning 51 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 110.7 s; configured context: 131072; peak server footprint 36.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-8bit-spec-off-20261019-072418.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 2.772 (2.653-3.569) | 9.003 (8.343-9.475) | 14996 | 16644 | content | 0 |
| cold | 3 | 24.563 (24.039-24.624) | 29.646 (29.135-29.728) | 0 | 16659 | content | 0 |

Cold / warm TTFT (medians): 8.86x.

### M3 short structured decode

Source: `raw/m3-8bit-spec-off-20261019-125236.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 18.3 (18.3-18.3) | 0.306 (0.306-0.308) | 2.978 (2.977-2.987) | 50 | 3/3 | 162.9 | 165.6 | 2.78 |
| off | off | 16,000 | 150 | 3 | 18.3 (18.3-18.3) | 0.314 (0.310-0.315) | 8.463 (8.453-8.470) | 150 | 3/3 | 163.4 | 171.0 | 2.94 |
| off | off | 16,000 | 300 | 3 | 17.8 (16.7-18.2) | 0.337 (0.312-0.370) | 17.167 (16.711-18.309) | 300 | 3/3 | 168.1 | 174.4 | 2.97 |
| off | off | 32,000 | 50 | 3 | 16.6 (16.5-16.6) | 0.530 (0.522-0.537) | 3.493 (3.477-3.499) | 50 | 3/3 | 178.6 | 190.2 | 2.78 |
| off | off | 32,000 | 150 | 3 | 16.6 (16.3-17.0) | 0.525 (0.503-0.526) | 9.486 (9.250-9.645) | 150 | 3/3 | 181.3 | 185.4 | 2.94 |
| off | off | 32,000 | 300 | 3 | 17.5 (17.2-17.6) | 0.468 (0.451-0.488) | 17.547 (17.395-17.864) | 300 | 3/3 | 170.4 | 178.6 | 2.97 |
| off | off | 64,000 | 50 | 3 | 16.5 (16.5-16.5) | 0.727 (0.727-0.730) | 3.703 (3.701-3.706) | 50 | 3/3 | 181.1 | 191.0 | 2.78 |
| off | off | 64,000 | 150 | 3 | 16.3 (16.3-16.3) | 0.731 (0.730-0.736) | 9.895 (9.881-9.896) | 150 | 3/3 | 183.0 | 191.1 | 2.94 |
| off | off | 64,000 | 300 | 3 | 16.1 (16.1-16.2) | 0.736 (0.730-0.743) | 19.259 (19.201-19.279) | 300 | 3/3 | 185.8 | 194.0 | 2.97 |
| off | on | 16,000 | 1000 | 3 | 18.0 (18.0-18.0) | 3.337 (3.216-3.343) | 58.893 (58.738-58.975) | 1000 | 3/3 | 167.5 | 174.6 | 2.99 |
| off | on | 16,000 | 2000 | 3 | 18.0 (18.0-18.0) | 3.175 (3.167-3.256) | 114.197 (114.096-114.209) | 2000 | 3/3 | 167.1 | 173.5 | 2.99 |
| off | on | 32,000 | 1000 | 3 | 17.4 (17.4-17.4) | 3.023 (2.997-3.035) | 60.381 (60.378-60.397) | 1000 | 3/3 | 172.6 | 181.5 | 2.99 |
| off | on | 32,000 | 2000 | 3 | 17.4 (17.4-17.4) | 2.990 (2.984-3.020) | 118.155 (118.135-118.216) | 2000 | 3/3 | 173.1 | 183.7 | 2.99 |

### M4 20-step trajectory (per step)

Source: `raw/m4-8bit-spec-off-20261019-072645.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 21.366 (21.244-21.642) | 28.055 (27.930-28.329) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 15.985 (7.435-15.996) | 23.846 (15.306-23.864) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.407 (3.405-3.644) | 11.557 (11.555-11.792) | 16780 | 18439 | 0.91 | 0 |
| 3 | 3 | 3.124 (3.104-3.366) | 8.293 (8.217-8.539) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.183 (3.119-3.481) | 11.385 (11.315-11.685) | - | 21838 | - | 0 |
| 5 | 3 | 3.382 (3.324-3.652) | 9.293 (9.230-9.567) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.397 (3.384-3.844) | 9.135 (9.113-9.579) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.447 (3.344-3.680) | 9.463 (8.421-10.717) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 3.833 (3.634-3.880) | 11.964 (10.985-12.134) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.486 (3.448-3.819) | 9.339 (9.301-9.655) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.604 (3.534-4.127) | 12.010 (11.932-12.592) | - | 32060 | - | 0 |
| 11 | 3 | 3.901 (3.807-4.243) | 12.351 (12.253-12.692) | - | 33769 | - | 0 |
| 12 | 3 | 3.987 (3.871-4.218) | 12.369 (8.328-12.479) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 3.874 (3.769-4.125) | 12.401 (12.315-12.652) | - | 37191 | - | 0 |
| 14 | 3 | 4.385 (4.121-4.420) | 9.609 (9.346-9.642) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 3.957 (3.852-4.207) | 9.610 (9.530-9.869) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.138 (4.018-4.422) | 10.494 (10.204-11.644) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.286 (4.218-4.633) | 10.031 (9.899-10.366) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.281 (4.211-4.505) | 12.978 (12.898-13.185) | - | 45696 | - | 0 |
| 19 | 3 | 4.553 (4.501-4.719) | 13.239 (13.188-13.409) | - | 47383 | - | 0 |
| 20 | 3 | 4.335 (4.329-4.922) | 13.094 (13.083-13.680) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1115 s/step (steps 2-20: 0.0727 s/step); total e2e per run: 255.5, 259.9, 257.5 s.

22 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M7 tool-call correctness

Source: `raw/m7-8bit-spec-off-20261019-074049.jsonl`.

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
<!-- agentbench:end summary 8bit-spec-off -->

<!-- agentbench:begin summary 8bit-spec-off-t1 -->
## Results, tag `8bit-spec-off-t1`

### M4 20-step trajectory (per step)

Source: `raw/m4-8bit-spec-off-t1-20261019-235031.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 23.041 (19.699-23.558) | 27.822 (27.785-31.946) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 16.803 (15.887-17.483) | 25.076 (20.956-25.902) | 6144 | 16733 | 0.37 | 0 |
| 2 | 3 | 3.574 (3.419-3.726) | 11.869 (11.745-12.177) | 16780 | 18439 | 0.91 | 0 |
| 3 | 3 | 3.708 (3.549-5.937) | 9.590 (9.132-9.801) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.821 (3.620-4.050) | 11.949 (11.013-12.271) | 20187 | 21838 | 0.92 | 0 |
| 5 | 3 | 3.867 (3.792-4.150) | 10.126 (9.580-12.143) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.907 (3.845-4.133) | 12.431 (12.186-12.972) | 23612 | 25264 | 0.93 | 0 |
| 7 | 3 | 3.905 (3.758-4.387) | 11.817 (11.310-12.255) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 4.137 (3.960-4.331) | 12.443 (10.063-12.744) | 26997 | 28660 | 0.94 | 0 |
| 9 | 3 | 3.916 (3.891-4.009) | 12.514 (10.179-12.579) | 28707 | 30367 | 0.94 | 0 |
| 10 | 3 | 4.043 (4.029-4.167) | 12.718 (12.591-12.727) | - | 32060 | - | 0 |
| 11 | 3 | 4.205 (4.188-4.247) | 12.825 (12.524-12.866) | 32107 | 33769 | 0.95 | 0 |
| 12 | 3 | 4.194 (3.703-4.374) | 12.734 (11.465-13.111) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 4.211 (3.805-13.012) | 12.902 (12.404-13.013) | 35528 | 37191 | 0.95 | 0 |
| 14 | 3 | 4.458 (4.450-4.467) | 8.241 (8.202-13.107) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 4.332 (4.250-4.505) | 11.973 (8.986-13.103) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.446 (4.382-4.718) | 12.823 (11.534-13.086) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.636 (4.601-4.908) | 13.471 (11.975-13.845) | 42352 | 44009 | 0.96 | 0 |
| 18 | 3 | 4.649 (4.551-4.763) | 13.532 (13.409-13.705) | - | 45696 | - | 0 |
| 19 | 3 | 4.732 (4.687-4.920) | 13.622 (13.562-13.960) | - | 47383 | - | 0 |
| 20 | 3 | 4.714 (4.551-4.788) | 11.893 (9.693-12.829) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1277 s/step (steps 2-20: 0.0614 s/step); total e2e per run: 279.6, 289.3, 273.9 s.

32 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.
<!-- agentbench:end summary 8bit-spec-off-t1 -->

<!-- agentbench:begin summary oq8mtp-spec-off -->
## Results, tag `oq8mtp-spec-off`

### Gate G1-G5

Source: `raw/gate-oq8mtp-spec-off-20261020-001515.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 20.93 s, e2e 20.93 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. T", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 114 chars in thinking_block / text ok ('ready'); reasoning 120 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 112.7 s; configured context: 131072; peak server footprint 37.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-oq8mtp-spec-off-20261020-001902.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 3.935 (3.575-3.974) | 9.895 (9.438-10.267) | 14996 | 16644 | content | 0 |
| cold | 3 | 27.092 (26.891-27.289) | 32.426 (32.102-32.687) | 0 | 16659 | content | 0 |

Cold / warm TTFT (medians): 6.88x.

### M3 short structured decode

Source: `raw/m3-oq8mtp-spec-off-20261020-002143.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 17.8 (17.3-18.4) | 0.362 (0.321-0.599) | 3.147 (3.115-3.267) | 50 | 3/3 | 168.0 | 172.7 | 2.78 |
| off | off | 16,000 | 150 | 3 | 17.7 (17.7-17.8) | 0.337 (0.332-0.347) | 8.733 (8.729-8.736) | 150 | 3/3 | 169.0 | 174.2 | 2.94 |
| off | off | 16,000 | 300 | 3 | 17.8 (17.7-17.8) | 0.347 (0.339-0.350) | 17.177 (17.162-17.197) | 300 | 3/3 | 169.2 | 173.2 | 2.97 |
| off | off | 32,000 | 50 | 3 | 17.2 (17.2-17.4) | 0.485 (0.477-0.984) | 3.335 (3.329-3.803) | 50 | 3/3 | 173.4 | 179.5 | 2.78 |
| off | off | 32,000 | 150 | 3 | 17.1 (17.1-17.1) | 0.480 (0.478-0.492) | 9.204 (9.199-9.208) | 150 | 3/3 | 175.8 | 179.5 | 2.94 |
| off | off | 32,000 | 300 | 3 | 17.0 (16.8-17.0) | 0.488 (0.488-0.491) | 18.080 (18.047-18.250) | 300 | 3/3 | 176.6 | 182.1 | 2.97 |
| off | off | 64,000 | 50 | 3 | 16.0 (15.6-16.4) | 0.784 (0.742-1.755) | 3.881 (3.844-4.748) | 50 | 3/3 | 186.4 | 194.8 | 2.78 |
| off | off | 64,000 | 150 | 3 | 15.8 (15.8-15.8) | 0.767 (0.764-0.768) | 10.177 (10.174-10.180) | 150 | 3/3 | 189.5 | 194.9 | 2.94 |
| off | off | 64,000 | 300 | 3 | 15.8 (15.8-15.8) | 0.774 (0.763-0.798) | 19.730 (19.718-19.748) | 300 | 3/3 | 189.9 | 197.6 | 2.97 |
| off | on | 16,000 | 1000 | 3 | 17.7 (17.7-17.7) | 3.352 (3.340-3.465) | 59.794 (59.773-60.046) | 1000 | 3/3 | 170.1 | 176.1 | 2.99 |
| off | on | 16,000 | 2000 | 3 | 17.7 (17.6-17.7) | 3.361 (3.335-3.401) | 116.555 (116.461-116.790) | 2000 | 3/3 | 170.3 | 177.5 | 2.99 |
| off | on | 32,000 | 1000 | 3 | 17.1 (17.1-17.1) | 2.994 (2.982-3.345) | 61.296 (61.287-61.846) | 1000 | 3/3 | 175.4 | 186.0 | 2.99 |
| off | on | 32,000 | 2000 | 3 | 17.1 (17.0-17.1) | 3.028 (2.993-3.076) | 120.180 (120.151-120.391) | 2000 | 3/3 | 176.0 | 189.4 | 2.99 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq8mtp-spec-off-20261020-005108.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 22.743 (21.952-23.037) | 29.505 (28.646-29.853) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 17.007 (7.891-17.169) | 25.172 (15.749-25.216) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.621 (3.578-3.812) | 11.961 (11.895-12.027) | - | 18439 | - | 0 |
| 3 | 3 | 3.546 (3.512-3.762) | 8.774 (8.735-8.887) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.694 (3.665-3.776) | 12.036 (11.978-12.067) | - | 21838 | - | 0 |
| 5 | 3 | 3.883 (3.865-4.090) | 10.006 (9.880-10.105) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.944 (3.922-4.032) | 9.766 (9.664-9.799) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.873 (3.847-4.109) | 9.967 (9.101-12.355) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 4.043 (4.037-4.420) | 12.509 (12.418-12.522) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 4.056 (3.904-4.192) | 10.030 (9.849-10.042) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 4.090 (4.034-4.297) | 12.714 (12.640-12.845) | - | 32060 | - | 0 |
| 11 | 3 | 4.438 (4.321-4.647) | 13.081 (13.040-13.088) | - | 33769 | - | 0 |
| 12 | 3 | 4.296 (4.262-4.660) | 12.628 (9.115-12.988) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 4.286 (4.215-4.558) | 13.054 (12.934-13.122) | - | 37191 | - | 0 |
| 14 | 3 | 4.608 (4.534-4.865) | 9.898 (9.865-10.080) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 4.377 (4.311-4.719) | 10.151 (10.061-10.380) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.533 (4.444-4.860) | 10.808 (10.608-10.893) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.695 (4.602-5.064) | 10.490 (10.443-10.825) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.653 (4.591-4.984) | 13.563 (13.539-13.773) | - | 45696 | - | 0 |
| 19 | 3 | 4.802 (4.779-5.289) | 13.733 (13.684-14.082) | - | 47383 | - | 0 |
| 20 | 3 | 4.707 (4.665-5.154) | 13.736 (13.626-14.068) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1245 s/step (steps 2-20: 0.0679 s/step); total e2e per run: 264.2, 273.7, 272.2 s.

21 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M7 tool-call correctness

Source: `raw/m7-oq8mtp-spec-off-20261020-010452.jsonl`.

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
<!-- agentbench:end summary oq8mtp-spec-off -->

<!-- agentbench:begin summary oq8mtp-mtp-on -->
## Results, tag `oq8mtp-mtp-on`

### Gate G1-G5

Source: `raw/gate-oq8mtp-mtp-on-20261020-044238.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 1.03 s, e2e 1.03 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 43 chars in thinking_block / text ok ('ready'); reasoning 116 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 119.3 s; configured context: 131072; peak server footprint 40.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-oq8mtp-mtp-on-20261020-011007.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 2.858 (2.412-3.109) | 5.186 (5.177-5.635) | 14996 | 16644 | content | 0 |
| cold | 3 | 26.414 (24.498-27.442) | 28.813 (26.728-29.746) | 0 | 16659 | content | 0 |

Cold / warm TTFT (medians): 9.24x.

### M3 short structured decode

Source: `raw/m3-oq8mtp-mtp-on-20261020-011213.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 50 | 3 | 49.0 (49.0-49.3) | 0.339 (0.338-0.339) | 1.339 (1.332-1.339) | 50 | 3/3 | 136.7 | 191.4 | 5.56 |
| on | off | 16,000 | 150 | 3 | 47.2 (46.3-48.1) | 0.355 (0.333-0.355) | 3.510 (3.433-3.577) | 150 | 3/3 | 147.4 | 212.7 | 6.82 |
| on | off | 16,000 | 300 | 3 | 45.3 (44.7-46.1) | 0.366 (0.360-0.368) | 6.964 (6.858-7.043) | 300 | 3/3 | 152.8 | 234.7 | 6.98 |
| on | off | 32,000 | 50 | 3 | 38.7 (38.1-38.7) | 0.504 (0.490-0.510) | 1.771 (1.757-1.798) | 50 | 3/3 | 150.8 | 238.7 | 5.56 |
| on | off | 32,000 | 150 | 3 | 36.2 (36.0-36.2) | 0.503 (0.491-0.503) | 4.624 (4.605-4.644) | 150 | 3/3 | 166.3 | 260.7 | 6.25 |
| on | off | 32,000 | 300 | 3 | 41.3 (40.0-42.2) | 0.494 (0.492-0.500) | 7.729 (7.584-7.970) | 300 | 3/3 | 166.2 | 250.3 | 6.82 |
| on | off | 64,000 | 50 | 3 | 31.9 (31.2-32.1) | 0.791 (0.777-0.794) | 2.316 (2.313-2.366) | 50 | 3/3 | 157.5 | 261.7 | 5.00 |
| on | off | 64,000 | 150 | 3 | 35.8 (35.2-36.7) | 0.788 (0.783-0.813) | 4.947 (4.877-5.012) | 150 | 3/3 | 169.4 | 274.8 | 6.25 |
| on | off | 64,000 | 300 | 3 | 34.2 (33.4-36.5) | 0.811 (0.785-0.812) | 9.561 (8.984-9.778) | 300 | 3/3 | 169.7 | 292.8 | 6.00 |
| on | on | 16,000 | 1000 | 3 | 28.1 (28.1-28.6) | 3.345 (3.337-3.389) | 38.933 (38.303-38.982) | 1000 | 3/3 | 163.4 | 269.4 | 4.98 |
| on | on | 16,000 | 2000 | 3 | 28.8 (28.6-30.1) | 3.333 (3.282-3.466) | 72.944 (69.752-73.278) | 2000 | 3/3 | 155.1 | 264.0 | 5.08 |
| on | on | 32,000 | 1000 | 3 | 25.9 (25.6-25.9) | 3.025 (3.003-3.052) | 41.602 (41.562-42.045) | 1000 | 3/3 | 163.2 | 250.1 | 4.61 |
| on | on | 32,000 | 2000 | 3 | 26.6 (26.3-26.7) | 3.064 (3.026-3.200) | 78.388 (77.868-79.118) | 2000 | 3/3 | 161.0 | 250.6 | 4.69 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq8mtp-mtp-on-20261020-012742.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 22.819 (22.098-23.404) | 25.122 (24.323-25.711) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 16.692 (16.209-17.205) | 20.535 (19.786-21.032) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.428 (3.355-3.572) | 8.023 (7.962-8.257) | - | 18439 | - | 0 |
| 3 | 3 | 3.459 (3.276-3.484) | 6.208 (5.927-6.216) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.612 (3.442-3.658) | 8.341 (7.951-8.379) | - | 21838 | - | 0 |
| 5 | 3 | 3.780 (3.549-3.885) | 6.572 (5.977-6.875) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.679 (3.584-3.960) | 5.814 (5.620-6.173) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.667 (3.538-3.719) | 6.366 (6.282-6.384) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 4.039 (3.830-4.133) | 8.324 (7.192-8.744) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.740 (3.621-3.897) | 7.081 (6.765-7.191) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.912 (3.791-3.999) | 8.864 (8.732-9.191) | - | 32060 | - | 0 |
| 11 | 3 | 4.156 (4.001-4.206) | 8.387 (7.949-8.532) | - | 33769 | - | 0 |
| 12 | 3 | 4.120 (3.952-4.124) | 8.250 (6.276-8.420) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 4.183 (4.036-4.242) | 8.926 (8.741-9.244) | - | 37191 | - | 0 |
| 14 | 3 | 4.356 (4.233-4.589) | 6.870 (6.625-7.104) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 4.325 (4.262-4.362) | 7.056 (7.042-7.080) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.386 (4.325-4.526) | 7.393 (7.206-7.430) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.621 (4.491-4.702) | 7.918 (7.705-8.092) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.515 (4.436-4.595) | 9.606 (9.178-9.880) | - | 45696 | - | 0 |
| 19 | 3 | 4.666 (4.551-4.814) | 9.515 (9.211-9.831) | - | 47383 | - | 0 |
| 20 | 3 | 4.618 (4.590-4.714) | 9.564 (9.522-9.636) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1203 s/step (steps 2-20: 0.0700 s/step); total e2e per run: 187.4, 194.8, 198.0 s.

21 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M6 memory and stability

Source: `raw/m6-oq8mtp-mtp-on-20261020-123031.jsonl`.

| Metric | Value |
| --- | --- |
| footprint at 64,000 tokens: server tree peak GiB | 46.00 |
| footprint: system used peak GiB | 72.51 |
| loop minutes / runs (complete) / requests | 30.0 / 10 (9) / 190 |
| errors | 67 |
| server tree GiB start / peak / end | 46.00 / 47.00 / 42.00 |
| server tree growth GiB | -4.00 |
| system used GiB start / end | 72.52 / 69.19 |
| e2e last run / first run (median per step) | 1.01 |
| e2e s over all requests | 7.297 (5.782-25.666) |

### M7 tool-call correctness

Source: `raw/m7-oq8mtp-mtp-on-20261020-013735.jsonl`.

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
<!-- agentbench:end summary oq8mtp-mtp-on -->

<!-- agentbench:begin summary oq8mtp-mtp-on-t1 -->
## Results, tag `oq8mtp-mtp-on-t1`

### M3 short structured decode

Source: `raw/m3-oq8mtp-mtp-on-t1-20261020-014155.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 150 | 3 | 53.5 (49.6-53.5) | 0.346 (0.340-0.349) | 3.136 (3.127-3.348) | 150 | 3/3 | 132.5 | 196.8 | 6.82 |
| on | off | 32,000 | 150 | 3 | 42.0 (41.9-42.5) | 0.488 (0.486-0.494) | 4.040 (3.993-4.043) | 150 | 3/3 | 150.6 | 223.9 | 6.52 |
| on | on | 16,000 | 1000 | 3 | 35.0 (33.9-35.1) | 3.317 (3.175-3.322) | 31.901 (31.599-32.753) | 1000 | 3/3 | 156.7 | 255.4 | 5.68 |
| on | on | 32,000 | 1000 | 3 | 34.8 (32.8-37.0) | 2.826 (2.822-2.963) | 31.551 (29.807-33.460) | 1000 | 3/3 | 152.9 | 265.2 | 5.81 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq8mtp-mtp-on-t1-20261020-014649.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 23.183 (23.013-23.360) | 25.661 (25.080-25.967) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 16.991 (16.937-17.694) | 19.087 (17.695-19.749) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.523 (3.468-3.581) | 7.921 (7.741-8.118) | - | 18439 | - | 0 |
| 3 | 3 | 3.426 (3.403-3.458) | 7.177 (5.394-7.667) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.658 (3.560-5.534) | 7.618 (5.534-8.142) | 20187 | 21892 | 0.92 | 0 |
| 5 | 3 | 3.787 (3.755-3.843) | 7.462 (6.322-8.034) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.766 (3.724-3.783) | 7.256 (6.024-8.682) | 23612 | 25264 | 0.93 | 0 |
| 7 | 3 | 3.701 (3.687-3.731) | 8.059 (7.578-8.079) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 3.979 (3.886-3.988) | 8.009 (6.423-8.771) | 26997 | 28660 | 0.94 | 0 |
| 9 | 3 | 3.818 (3.733-3.846) | 7.533 (6.770-7.913) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.919 (3.899-3.930) | 8.942 (8.804-9.308) | 30414 | 32060 | 0.95 | 0 |
| 11 | 3 | 4.179 (4.124-4.221) | 8.554 (7.573-8.831) | 32107 | 33823 | 0.95 | 0 |
| 12 | 3 | 4.168 (4.065-4.234) | 8.462 (7.795-9.342) | 33816 | 35481 | 0.95 | 0 |
| 13 | 3 | 4.225 (4.194-4.244) | 8.588 (8.315-8.792) | 35528 | 37191 | 0.95 | 0 |
| 14 | 3 | 4.356 (4.354-4.397) | 7.606 (6.522-7.631) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 4.233 (4.198-4.321) | 8.201 (7.253-8.220) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.438 (4.365-4.444) | 7.210 (7.094-7.968) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.622 (4.607-4.659) | 9.356 (7.795-10.214) | 42352 | 44009 | 0.96 | 0 |
| 18 | 3 | 4.541 (4.512-4.563) | 9.340 (9.218-9.505) | - | 45696 | - | 0 |
| 19 | 3 | 4.639 (4.620-4.719) | 9.657 (9.611-9.873) | - | 47383 | - | 0 |
| 20 | 3 | 4.603 (4.578-4.709) | 9.881 (8.337-9.975) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1268 s/step (steps 2-20: 0.0672 s/step); total e2e per run: 203.2, 192.6, 199.5 s.

27 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.
<!-- agentbench:end summary oq8mtp-mtp-on-t1 -->

<!-- agentbench:begin summary oq8mtp-spec-off-t1 -->
## Results, tag `oq8mtp-spec-off-t1`

### M3 short structured decode

Source: `raw/m3-oq8mtp-spec-off-t1-20261020-015953.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 150 | 3 | 18.2 (18.2-18.3) | 0.323 (0.317-0.329) | 8.498 (8.478-8.508) | 150 | 3/3 | 164.2 | 169.7 | 2.94 |
| off | off | 32,000 | 150 | 3 | 17.4 (16.8-17.6) | 0.481 (0.464-0.501) | 9.059 (8.949-9.354) | 150 | 3/3 | 171.8 | 179.0 | 2.94 |
| off | on | 16,000 | 1000 | 3 | 17.9 (17.7-18.1) | 3.285 (3.258-3.312) | 59.123 (58.402-59.786) | 1000 | 3/3 | 168.7 | 175.7 | 2.99 |
| off | on | 32,000 | 1000 | 3 | 17.0 (17.0-17.1) | 3.041 (3.022-3.068) | 61.749 (61.454-61.867) | 1000 | 3/3 | 176.2 | 187.5 | 2.99 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq8mtp-spec-off-t1-20261020-020923.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 22.657 (22.058-22.959) | 29.293 (25.666-30.866) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 17.211 (16.551-24.689) | 24.013 (21.932-24.690) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.737 (3.554-5.209) | 11.775 (6.884-12.033) | 16780 | 18493 | 0.91 | 0 |
| 3 | 3 | 3.667 (3.529-6.521) | 8.303 (6.521-12.059) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.615 (3.386-3.693) | 11.258 (11.248-11.633) | 20187 | 21892 | 0.92 | 0 |
| 5 | 3 | 3.828 (3.785-3.942) | 10.995 (9.792-12.089) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.898 (3.840-3.904) | 10.288 (9.932-12.259) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.826 (3.782-3.869) | 8.846 (8.524-10.613) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 4.027 (3.924-4.032) | 10.857 (10.378-12.555) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.971 (3.887-3.973) | 12.427 (11.627-12.540) | 28707 | 30367 | 0.94 | 0 |
| 10 | 3 | 4.026 (3.971-4.127) | 12.578 (12.568-12.641) | - | 32060 | - | 0 |
| 11 | 3 | 4.253 (4.240-4.444) | 12.888 (11.090-12.932) | 32107 | 33769 | 0.95 | 0 |
| 12 | 3 | 4.330 (4.275-4.474) | 13.010 (10.736-13.027) | 33816 | 35481 | 0.95 | 0 |
| 13 | 3 | 4.335 (4.171-4.446) | 13.059 (12.924-13.088) | - | 37191 | - | 0 |
| 14 | 3 | 4.649 (4.401-6.785) | 7.705 (6.786-9.714) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 4.290 (4.151-4.435) | 10.324 (10.115-12.204) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.454 (4.444-4.616) | 11.884 (9.903-13.224) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.686 (4.680-4.849) | 13.536 (13.004-13.661) | 42352 | 44009 | 0.96 | 0 |
| 18 | 3 | 4.610 (4.569-4.715) | 13.523 (13.482-13.546) | - | 45696 | - | 0 |
| 19 | 3 | 4.882 (4.721-4.899) | 13.716 (13.704-13.808) | - | 47383 | - | 0 |
| 20 | 3 | 4.740 (4.616-4.916) | 13.617 (11.311-13.707) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1281 s/step (steps 2-20: 0.0674 s/step); total e2e per run: 270.4, 272.4, 272.1 s.

27 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.
<!-- agentbench:end summary oq8mtp-spec-off-t1 -->

<!-- agentbench:begin summary oq4mtp-spec-off -->
## Results, tag `oq4mtp-spec-off`

### Gate G1-G5

Source: `raw/gate-oq4mtp-spec-off-20261020-022606.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 18.49 s, e2e 18.49 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer 'The screen shows a blank white display w', expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 130 chars in thinking_block / text ok ('ready'); reasoning 99 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 108 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 102.4 s; configured context: 131072; peak server footprint 24.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-oq4mtp-spec-off-20261020-022920.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 3.182 (3.028-3.300) | 7.143 (6.617-7.434) | 14996 | 16644 | content | 0 |
| cold | 3 | 22.955 (22.751-23.216) | 26.397 (26.099-26.697) | 0 | 16659 | content | 0 |

Cold / warm TTFT (medians): 7.21x.

### M3 short structured decode

Source: `raw/m3-oq4mtp-spec-off-20261020-023154.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 50 | 3 | 27.3 (27.1-28.1) | 0.272 (0.267-0.574) | 2.078 (2.065-2.319) | 50 | 3/3 | 145.9 | 147.8 | 3.57 |
| off | off | 16,000 | 150 | 3 | 27.3 (27.2-27.3) | 0.269 (0.266-0.270) | 5.736 (5.725-5.756) | 150 | 3/3 | 147.1 | 154.5 | 3.85 |
| off | off | 16,000 | 300 | 3 | 27.2 (27.1-27.2) | 0.270 (0.263-0.272) | 11.260 (11.247-11.292) | 300 | 3/3 | 147.1 | 153.7 | 3.95 |
| off | off | 32,000 | 50 | 3 | 25.7 (25.6-25.8) | 0.411 (0.408-0.941) | 2.327 (2.318-2.843) | 50 | 3/3 | 155.3 | 160.7 | 3.57 |
| off | off | 32,000 | 150 | 3 | 25.7 (25.5-25.7) | 0.406 (0.405-0.407) | 6.207 (6.204-6.245) | 150 | 3/3 | 156.4 | 161.7 | 3.85 |
| off | off | 32,000 | 300 | 3 | 25.6 (25.6-25.6) | 0.405 (0.402-0.409) | 12.077 (12.076-12.091) | 300 | 3/3 | 156.0 | 166.7 | 3.95 |
| off | off | 64,000 | 50 | 3 | 22.8 (22.4-24.0) | 0.724 (0.723-1.731) | 2.907 (2.869-3.775) | 50 | 3/3 | 172.8 | 183.2 | 3.57 |
| off | off | 64,000 | 150 | 3 | 22.2 (22.1-22.5) | 0.730 (0.723-0.730) | 7.434 (7.346-7.459) | 150 | 3/3 | 179.2 | 189.1 | 3.85 |
| off | off | 64,000 | 300 | 3 | 21.8 (21.8-22.0) | 0.728 (0.720-0.740) | 14.438 (14.297-14.475) | 300 | 3/3 | 181.3 | 211.7 | 3.90 |
| off | on | 16,000 | 1000 | 3 | 25.3 (25.2-25.3) | 3.024 (3.020-3.084) | 42.582 (42.563-42.739) | 1000 | 3/3 | 158.2 | 175.8 | 3.98 |
| off | on | 16,000 | 2000 | 3 | 25.4 (25.3-25.4) | 2.914 (2.904-2.932) | 81.642 (81.545-81.941) | 2000 | 3/3 | 156.8 | 172.1 | 3.99 |
| off | on | 32,000 | 1000 | 3 | 24.1 (24.1-24.1) | 2.764 (2.690-3.110) | 44.260 (44.209-44.520) | 1000 | 3/3 | 165.7 | 181.7 | 3.98 |
| off | on | 32,000 | 2000 | 3 | 24.1 (24.0-24.1) | 2.768 (2.733-2.779) | 85.853 (85.768-86.244) | 2000 | 3/3 | 165.7 | 182.8 | 3.99 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq4mtp-spec-off-20261020-025328.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 20.831 (20.405-21.148) | 24.380 (23.876-24.717) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 15.604 (7.357-18.244) | 21.333 (12.987-23.961) | - | 16733 | - | 0 |
| 2 | 3 | 3.201 (3.188-3.488) | 8.956 (8.897-9.081) | - | 18439 | - | 0 |
| 3 | 3 | 3.173 (3.167-3.401) | 6.543 (6.530-6.763) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.393 (3.305-3.561) | 9.175 (9.101-9.239) | - | 21838 | - | 0 |
| 5 | 3 | 3.501 (3.470-3.655) | 8.000 (7.937-8.051) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.451 (3.404-3.761) | 7.548 (7.468-7.715) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.460 (3.458-3.768) | 7.428 (7.124-9.391) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 3.710 (3.626-3.918) | 8.341 (8.264-8.512) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.571 (3.553-3.814) | 7.876 (7.690-9.533) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.730 (3.691-3.889) | 9.723 (9.700-9.783) | - | 32060 | - | 0 |
| 11 | 3 | 3.886 (3.873-4.253) | 9.948 (9.915-10.215) | - | 33769 | - | 0 |
| 12 | 3 | 3.910 (3.856-4.065) | 9.629 (9.382-9.704) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 3.999 (3.933-4.184) | 10.119 (10.094-10.237) | - | 37191 | - | 0 |
| 14 | 3 | 4.098 (4.090-4.385) | 7.118 (7.111-7.370) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 3.992 (3.963-4.299) | 8.330 (8.314-8.561) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.114 (4.073-4.344) | 8.372 (8.303-8.547) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.374 (4.288-4.575) | 8.471 (8.387-8.743) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.257 (4.230-4.461) | 10.551 (10.535-10.732) | - | 45696 | - | 0 |
| 19 | 3 | 4.424 (4.413-4.730) | 10.730 (10.714-11.011) | - | 47383 | - | 0 |
| 20 | 3 | 4.428 (4.367-4.655) | 10.841 (10.758-11.040) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1081 s/step (steps 2-20: 0.0702 s/step); total e2e per run: 207.5, 216.8, 215.1 s.

26 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M7 tool-call correctness

Source: `raw/m7-oq4mtp-spec-off-20261020-030421.jsonl`.

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
<!-- agentbench:end summary oq4mtp-spec-off -->

<!-- agentbench:begin summary oq4mtp-mtp-on -->
## Results, tag `oq4mtp-mtp-on`

### Gate G1-G5

Source: `raw/gate-oq4mtp-mtp-on-20261020-044829.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 0.75 s, e2e 0.76 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I don't see a dialog with a verification", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 98 chars in thinking_block / text ok ('ready'); reasoning 123 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 108 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 105.3 s; configured context: 131072; peak server footprint 24.0 GiB |

### M1 cached-prefix TTFT

Source: `raw/m1-oq4mtp-mtp-on-20261020-031056.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 5 | 2.594 (2.271-2.746) | 4.254 (4.114-4.352) | 14996 | 16644 | content | 0 |
| cold | 3 | 22.196 (22.170-22.311) | 23.679 (23.574-23.845) | 0 | 16659 | content | 0 |

Cold / warm TTFT (medians): 8.56x.

### M3 short structured decode

Source: `raw/m3-oq4mtp-mtp-on-20261020-031241.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 50 | 3 | 57.5 (55.8-58.4) | 0.288 (0.285-0.291) | 1.138 (1.130-1.167) | 50 | 3/3 | 141.7 | 165.1 | 6.25 |
| on | off | 16,000 | 150 | 3 | 68.4 (67.6-68.4) | 0.293 (0.289-0.300) | 2.480 (2.468-2.497) | 150 | 3/3 | 110.4 | 171.5 | 7.14 |
| on | off | 16,000 | 300 | 3 | 67.0 (65.7-68.3) | 0.293 (0.292-0.302) | 4.764 (4.673-4.841) | 300 | 3/3 | 112.3 | 175.4 | 7.89 |
| on | off | 32,000 | 50 | 3 | 50.8 (49.4-51.2) | 0.430 (0.430-0.435) | 1.396 (1.387-1.427) | 50 | 3/3 | 119.6 | 191.0 | 5.56 |
| on | off | 32,000 | 150 | 3 | 57.5 (54.6-57.7) | 0.430 (0.427-0.435) | 3.021 (3.019-3.159) | 150 | 3/3 | 121.9 | 189.8 | 6.82 |
| on | off | 32,000 | 300 | 3 | 56.4 (53.8-56.7) | 0.434 (0.429-0.440) | 5.734 (5.709-5.995) | 300 | 3/3 | 121.8 | 187.2 | 7.14 |
| on | off | 64,000 | 50 | 3 | 41.1 (40.7-41.9) | 0.762 (0.759-0.765) | 1.952 (1.934-1.968) | 50 | 3/3 | 124.6 | 196.6 | 5.00 |
| on | off | 64,000 | 150 | 3 | 50.9 (50.1-52.2) | 0.759 (0.754-0.759) | 3.683 (3.613-3.733) | 150 | 3/3 | 132.9 | 196.2 | 6.52 |
| on | off | 64,000 | 300 | 3 | 50.1 (50.0-50.5) | 0.763 (0.755-0.768) | 6.727 (6.679-6.744) | 300 | 3/3 | 131.7 | 216.4 | 6.98 |
| on | on | 16,000 | 1000 | 3 | 45.3 (44.5-45.3) | 2.884 (2.843-2.888) | 24.954 (24.911-25.357) | 1000 | 3/3 | 117.4 | 197.9 | 5.88 |
| on | on | 16,000 | 2000 | 3 | 48.6 (46.6-51.1) | 2.853 (2.851-2.900) | 44.020 (41.958-45.711) | 2000 | 3/3 | 118.9 | 196.4 | 6.37 |
| on | on | 32,000 | 1000 | 3 | 39.1 (38.9-41.8) | 2.682 (2.632-2.723) | 28.258 (26.544-28.408) | 1000 | 3/3 | 124.8 | 203.1 | 5.46 |
| on | on | 32,000 | 2000 | 3 | 46.0 (44.0-46.5) | 2.635 (2.562-2.643) | 46.095 (45.527-48.115) | 2000 | 3/3 | 124.1 | 201.7 | 6.17 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq4mtp-mtp-on-20261020-032242.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 20.343 (20.161-20.843) | 21.691 (21.406-22.181) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 14.957 (14.724-15.268) | 17.476 (17.193-17.829) | - | 16733 | - | 0 |
| 2 | 3 | 3.077 (3.035-3.158) | 6.081 (6.016-6.189) | - | 18439 | - | 0 |
| 3 | 3 | 3.011 (2.992-3.054) | 4.992 (4.768-5.387) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.100 (3.060-3.213) | 6.202 (5.757-6.213) | 20187 | 21838 | 0.92 | 0 |
| 5 | 3 | 3.282 (3.228-3.352) | 5.355 (5.260-5.417) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.263 (3.186-3.344) | 4.577 (4.527-4.669) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.348 (3.201-3.354) | 6.204 (5.784-6.667) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 3.513 (3.430-3.530) | 5.741 (5.728-5.863) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.437 (3.354-3.518) | 5.696 (5.597-5.813) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.513 (3.439-3.569) | 7.013 (6.921-7.107) | - | 32060 | - | 0 |
| 11 | 3 | 3.668 (3.576-3.756) | 6.194 (6.132-6.302) | - | 33769 | - | 0 |
| 12 | 3 | 3.703 (3.586-3.740) | 6.481 (6.227-6.561) | 33816 | 35535 | 0.95 | 0 |
| 13 | 3 | 3.761 (3.672-3.795) | 7.416 (7.348-7.525) | - | 37191 | - | 0 |
| 14 | 3 | 3.921 (3.847-4.023) | 5.461 (5.437-5.561) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 3.836 (3.753-3.871) | 5.917 (5.699-5.955) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 3.972 (3.821-4.008) | 6.090 (5.885-6.156) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.169 (3.992-4.245) | 6.291 (6.047-6.310) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.069 (3.985-4.072) | 7.413 (7.202-7.514) | - | 45696 | - | 0 |
| 19 | 3 | 4.200 (4.104-4.257) | 7.586 (7.499-7.787) | - | 47383 | - | 0 |
| 20 | 3 | 4.190 (4.073-4.395) | 8.243 (8.025-8.424) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1028 s/step (steps 2-20: 0.0687 s/step); total e2e per run: 155.8, 158.3, 159.9 s.

24 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.

### M6 memory and stability

Source: `raw/m6-oq4mtp-mtp-on-20261020-062438.jsonl`.

| Metric | Value |
| --- | --- |
| footprint at 64,000 tokens: server tree peak GiB | 26.00 |
| footprint: system used peak GiB | 53.20 |
| loop minutes / runs (complete) / requests | 30.0 / 12 (11) / 233 |
| errors | 89 |
| server tree GiB start / peak / end | 26.00 / 33.00 / 22.00 |
| server tree growth GiB | -4.00 |
| system used GiB start / end | 53.20 / 49.33 |
| e2e last run / first run (median per step) | 1.02 |
| e2e s over all requests | 5.917 (4.485-23.160) |

### M7 tool-call correctness

Source: `raw/m7-oq4mtp-mtp-on-20261020-033049.jsonl`.

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
<!-- agentbench:end summary oq4mtp-mtp-on -->

<!-- agentbench:begin summary oq4mtp-mtp-on-t1 -->
## Results, tag `oq4mtp-mtp-on-t1`

### M3 short structured decode

Source: `raw/m3-oq4mtp-mtp-on-t1-20261020-033459.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| on | off | 16,000 | 150 | 3 | 75.1 (67.3-76.3) | 0.290 (0.287-0.292) | 2.276 (2.240-2.508) | 150 | 3/3 | 137.4 | 170.2 | 9.38 |
| on | off | 32,000 | 150 | 3 | 55.6 (55.2-59.1) | 0.426 (0.422-0.428) | 3.109 (2.948-3.121) | 150 | 3/3 | 110.1 | 162.0 | 6.52 |
| on | on | 16,000 | 1000 | 3 | 45.6 (44.5-47.2) | 2.933 (2.664-3.362) | 24.552 (24.550-25.388) | 1000 | 3/3 | 121.0 | 197.5 | 6.13 |
| on | on | 32,000 | 1000 | 3 | 47.4 (43.3-49.1) | 2.588 (2.470-2.691) | 23.680 (22.820-25.781) | 1000 | 3/3 | 115.6 | 191.9 | 6.21 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq4mtp-mtp-on-t1-20261020-033847.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 20.942 (20.455-21.569) | 22.051 (22.016-22.483) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 15.304 (15.190-15.310) | 17.179 (16.813-18.052) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.082 (2.988-3.112) | 6.552 (6.006-6.853) | 16780 | 18439 | 0.91 | 0 |
| 3 | 3 | 3.040 (3.022-3.748) | 5.863 (3.748-6.491) | 18486 | 20140 | 0.92 | 0 |
| 4 | 3 | 3.228 (3.059-3.280) | 6.760 (5.533-6.837) | 20187 | 21892 | 0.92 | 0 |
| 5 | 3 | 3.309 (3.290-3.316) | 5.591 (5.356-5.985) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.344 (3.332-3.394) | 5.714 (5.138-5.911) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.353 (3.308-3.363) | 6.825 (6.410-6.912) | - | 26950 | - | 0 |
| 8 | 3 | 3.519 (3.493-3.578) | 6.182 (6.157-7.056) | 26997 | 28714 | 0.94 | 0 |
| 9 | 3 | 3.460 (3.402-3.536) | 5.762 (5.425-7.017) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.579 (3.504-4.957) | 7.205 (4.958-7.328) | 30414 | 32060 | 0.95 | 0 |
| 11 | 3 | 3.790 (3.686-3.837) | 6.707 (6.215-7.320) | 32107 | 33769 | 0.95 | 0 |
| 12 | 3 | 3.762 (3.695-3.808) | 6.718 (6.128-7.276) | 33816 | 35481 | 0.95 | 0 |
| 13 | 3 | 3.852 (3.772-3.961) | 7.204 (7.200-7.413) | - | 37191 | - | 0 |
| 14 | 3 | 4.039 (3.921-4.067) | 6.087 (5.304-6.764) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 3.890 (3.830-3.916) | 5.938 (5.660-6.506) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 3.950 (3.934-3.982) | 6.694 (6.584-6.724) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.206 (4.158-4.255) | 7.191 (6.313-7.789) | 42352 | 44063 | 0.96 | 0 |
| 18 | 3 | 4.101 (4.066-4.102) | 7.577 (7.549-8.150) | - | 45696 | - | 0 |
| 19 | 3 | 4.217 (4.216-4.304) | 7.696 (7.693-7.793) | - | 47383 | - | 0 |
| 20 | 3 | 4.196 (4.190-4.278) | 8.126 (6.798-8.770) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1080 s/step (steps 2-20: 0.0678 s/step); total e2e per run: 163.7, 163.4, 166.9 s.

28 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.
<!-- agentbench:end summary oq4mtp-mtp-on-t1 -->

<!-- agentbench:begin summary oq4mtp-spec-off-t1 -->
## Results, tag `oq4mtp-spec-off-t1`

### M3 short structured decode

Source: `raw/m3-oq4mtp-spec-off-t1-20261020-035009.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 150 | 3 | 27.8 (27.3-28.2) | 0.259 (0.258-0.269) | 5.626 (5.540-5.727) | 150 | 3/3 | 143.9 | 150.7 | 3.85 |
| off | off | 32,000 | 150 | 3 | 25.6 (25.5-25.6) | 0.411 (0.411-0.424) | 6.240 (6.239-6.279) | 150 | 3/3 | 156.7 | 161.7 | 3.85 |
| off | on | 16,000 | 1000 | 3 | 26.5 (25.1-26.7) | 2.896 (2.757-3.003) | 40.425 (40.349-42.802) | 1000 | 3/3 | 151.0 | 160.2 | 3.98 |
| off | on | 32,000 | 1000 | 3 | 23.7 (23.7-23.8) | 2.730 (2.696-2.814) | 44.908 (44.601-44.970) | 1000 | 3/3 | 168.3 | 189.9 | 3.98 |

### M4 20-step trajectory (per step)

Source: `raw/m4-oq4mtp-spec-off-t1-20261020-040801.jsonl`.

| Step | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | cached share | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 (start) | 3 | 20.596 (20.213-21.214) | 25.298 (24.752-25.746) | 0 | 15084 | 0.00 | 0 |
| 1 | 3 | 15.383 (15.217-18.331) | 19.525 (17.655-24.065) | 6144 | 16787 | 0.37 | 0 |
| 2 | 3 | 3.177 (3.118-3.211) | 8.835 (8.698-8.916) | - | 18439 | - | 0 |
| 3 | 3 | 3.234 (3.183-4.554) | 8.932 (4.555-8.978) | 18486 | 20194 | 0.92 | 0 |
| 4 | 3 | 3.288 (3.230-3.323) | 8.863 (6.705-9.062) | 20187 | 21838 | 0.92 | 0 |
| 5 | 3 | 3.415 (3.344-3.482) | 9.043 (7.599-9.167) | 21885 | 23619 | 0.93 | 0 |
| 6 | 3 | 3.399 (3.306-3.406) | 7.519 (7.313-7.528) | 23612 | 25318 | 0.93 | 0 |
| 7 | 3 | 3.477 (3.471-6.151) | 6.701 (6.152-8.893) | 25311 | 27004 | 0.94 | 0 |
| 8 | 3 | 3.638 (3.637-3.718) | 9.399 (7.863-9.558) | 26997 | 28660 | 0.94 | 0 |
| 9 | 3 | 3.494 (3.441-3.516) | 7.369 (6.877-8.661) | 28707 | 30421 | 0.94 | 0 |
| 10 | 3 | 3.585 (3.516-3.648) | 9.595 (9.403-9.686) | - | 32060 | - | 0 |
| 11 | 3 | 3.801 (3.708-3.810) | 9.235 (8.788-9.806) | 32107 | 33823 | 0.95 | 0 |
| 12 | 3 | 3.804 (3.791-3.882) | 9.751 (7.018-9.974) | 33816 | 35481 | 0.95 | 0 |
| 13 | 3 | 3.877 (3.756-3.947) | 10.031 (9.767-10.074) | - | 37191 | - | 0 |
| 14 | 3 | 4.060 (3.944-4.128) | 8.339 (7.624-8.422) | 37238 | 38960 | 0.96 | 0 |
| 15 | 3 | 3.949 (3.941-4.007) | 9.830 (9.296-10.044) | 38953 | 40666 | 0.96 | 0 |
| 16 | 3 | 4.152 (4.083-4.152) | 8.640 (8.253-9.804) | 40659 | 42359 | 0.96 | 0 |
| 17 | 3 | 4.283 (4.253-4.335) | 10.393 (8.260-10.511) | 42352 | 44009 | 0.96 | 0 |
| 18 | 3 | 4.206 (4.143-4.232) | 9.774 (7.863-10.503) | 44056 | 45750 | 0.96 | 0 |
| 19 | 3 | 4.394 (4.359-4.427) | 10.715 (10.579-10.731) | - | 47383 | - | 0 |
| 20 | 3 | 4.308 (4.282-4.382) | 10.637 (9.313-10.767) | 47430 | 49151 | 0.96 | 0 |

TTFT slope over steps 1-20: -0.1073 s/step (steps 2-20: 0.0684 s/step); total e2e per run: 208.5, 216.3, 218.9 s.

25 of 63 requests ended at the token cap inside a tool call, and the server flagged it as an `incomplete_tool_call` stream error. They count as latency samples. They have no usage chunk, so they report no cached tokens.
<!-- agentbench:end summary oq4mtp-spec-off-t1 -->
