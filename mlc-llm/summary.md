# mlc-llm: results

## Read first

- **Build and artifact.**
  - MLC-LLM `8978ea9a` (`v0.26.dev0-20-g8978ea9a`) and TVM `201fa000`, built from source with
    Metal (`env.md` sections 3–4).
  - The artifact is `Qwen3.8-27B-q4f16_1-MLC`: 4-bit weights in groups of 32 with fp16
    scales. It is text-only, because the convert drops `model.visual.*` and `mtp.*`.
  - Its chat config has thinking off.
- **Serving flags.** The server runs with `--mode interactive --prefix-cache-mode disable` and
  `max_total_seq_length=131072` (`env.md` section 5.1).
  - Without these flags, the GDN state is forked or rolled back wrongly.
  - As a result, there is no prefix reuse, no concurrency and no speculative decoding. Every
    request is a cold prefill.
- **Tool calls go through structured output, not the OpenAI `tools` field.**
  - The harness inlines the tool list into the system message and sends MLC's own
    `response_format`, an anyOf over the tools.
  - It sets `grammar_execution_mode = "constraint"`. The default jump-forward mode rolls
    tokens back, which the GDN state cannot do (`env.md` sections 5.3–5.4).
- **A reference row, not an agent-backend candidate.**
  - G1 passes only through that structured-output path, which is non-standard.
  - G2 and G2b fail, because the artifact is text-only. The HTTP 500s themselves come from
    the server's image decoder importing PIL, which the venv does not have.
  - G3 fails: there is no `/v1/messages` (HTTP 404).
  - G4 fails: the served chat config fixes thinking (`qwen3_5` or `qwen3_5_nothink`), and no
    request field changes it.
  - G5 passes: a 64,000-token prompt completes, with a 25.0 GiB peak server footprint.
  - Two probes end in a transport `ReadError`: G2b's tool-message image and G3's first text
    request. Each came right after a request that raised in the server (the PIL import), and
    the server log has no entry for either. So the client most likely reused a connection
    the server had closed. Their outcomes would not change.
- **No prefix reuse (M1).** A repeated 14,469-token agent prompt takes 94.0 s to the first
  token warm and 92.6 s cold (0.99×), with 0 cached tokens. The warm TTFT is 2.7 s on oMLX
  4-bit and 4.5 s on llama.cpp 4-bit. So every agent turn re-prefills the whole conversation.
- **Prefill is slow (M2).**
  - 151 tok/s at 16K (105.6 s) and 116 tok/s at 32K (275.6 s), against 765 and 728 tok/s on
    oMLX 4-bit, and 568 and 518 tok/s on llama.cpp 4-bit.
  - The gate's long prompts agree: G1's 12,849 tokens took 102.3 s (126 tok/s), and G5's
    64,000 tokens 815.1 s (78.5 tok/s), against 102–119 s on the oMLX rows.
  - MLC's GDN prefill reuses the sequential recurrent decode kernel (#3480 is open), as
    `env.md` expected.
- **Decode slows with context (M3).** With the grammar on, thinking off and cap 150, decode is
  9.1 tok/s at 16K and 5.5 tok/s at 32K. At 16K, oMLX 4-bit decodes 27.4 tok/s and llama.cpp
  4-bit 24.0, both without speculative decoding.
  - With the cold prefill, one capped answer takes 121.5 s at 16K and 302.4 s at 32K, end to
    end.
  - The gate's short samples agree: about 41 tok/s after a 40-token prompt (G4), and 3 tok/s
    at 64K (G5).
- **When.** The gate ran on 2026-10-20 between 13:05 and 13:21. M1, M2 and M3 ran on
  2026-10-21 between 07:28 and 08:47. All ran on AC power, under macOS 27.2 (26B5101f), and
  each passed the quiet pre-flight and the monitor.
  - This was a trimmed text-only set (`run_tier2.sh mlc-text-trim`): M1 with 2 warm and 2
    cold trials, and M2 and M3 at 16K and 32K only, M3 with cap 150 and no thinking bucket.
  - M2's first attempt was disturbed by `airportd` at 50 % CPU (07:44) and repeated. It stays
    local in `raw/_unverified/`.
- **Not run.**
  - M7 did not complete. Its first attempt was disturbed by `mobileassetd` at 62 % CPU (09:00),
    and the repeat was stopped at 09:39, when the campaign closed. Neither file is published.
  - The full text-only set (`mlc-text`: the default trial counts and sizes, M3's thinking
    bucket and a one-run M4) was not run, and image cases cannot run on this text-only
    artifact.

<!-- agentbench:begin summary 4bit -->
## Results, tag `4bit`

### Gate G1-G5 (text_only, tool calls via structured output)

Source: `raw/gate-4bit-20261020-130554.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS via structured output (non-standard)** | fs_read_file {"path": "docs/setup.md"}; JSON content in 19 chunks; first chunk at 102.26 s, e2e 104.07 s; finish=stop |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 500: Internal Server Error |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: transport: ReadError: ; prompt_tokens=None; control (user message): rejected: HTTP 500: Internal Server Error; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: transport: ReadError: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **FAIL** | N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped; off: no reasoning [shaped: mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted)] \| G4.effort-none-only: accepted; no reasoning [shaped: mlc: stripped reasoning_effort='none' (only [] accepted)] \| G4.effort-high: N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped \| G4.effort-minimal: N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped \| G4.default: accepted; no reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 815.1 s; configured context: unknown; peak server footprint 25.0 GiB |

### M1 cached-prefix TTFT (text_only, tool calls via structured output)

Source: `raw/m1-4bit-20261021-072837.jsonl`.

| Phase | n | TTFT s | e2e s | cached tok (med) | prompt tok (med) | first chunk | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| warm | 2 | 94.014 (92.855-95.174) | 98.011 (96.850-99.171) | 0 | 14469 | content | 0 |
| cold | 2 | 92.606 (92.483-92.730) | 96.604 (96.479-96.729) | 0 | 14486 | content | 0 |

Cold / warm TTFT (medians): 0.99x.

### M2 cold prefill (text_only, tool calls via structured output)

Source: `raw/m2-4bit-20261021-075801.jsonl`.

| Prompt tokens (target) | n | prefill s (TTFT) | throughput tok/s | prompt tok (server) | cached tok | timing | errors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16,000 | 3 | 105.615 (105.437-105.735) | 151 (151-152) | 16000 | 0 | ttft | 0 |
| 32,000 | 3 | 275.582 (275.488-275.905) | 116 (116-116) | 32000 | 0 | ttft | 0 |

### M3 short structured decode (text_only, tool calls via structured output)

Source: `raw/m3-4bit-20261021-081902.jsonl`.

| spec | thinking | context | cap | n | decode tok/s | TTFT s | e2e s | out tok (med) | hit cap | gap p50 ms | gap p99 ms | tok/chunk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| off | off | 16,000 | 150 | 3 | 9.1 (9.1-9.1) | 105.178 (105.109-105.215) | 121.519 (121.431-121.547) | 150 | 3/3 | 109.6 | 110.1 | 1.00 |
| off | off | 32,000 | 150 | 3 | 5.5 (5.5-5.5) | 275.288 (275.034-275.541) | 302.446 (302.187-302.689) | 150 | 3/3 | 182.4 | 182.8 | 1.00 |
<!-- agentbench:end summary 4bit -->
