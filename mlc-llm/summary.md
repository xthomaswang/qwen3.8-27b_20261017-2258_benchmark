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
- **Prefill is slow.**
  - G1's 12,849-token prompt took 102.3 s to the first token (126 tok/s).
  - G5's 64,000 tokens took 815.1 s (78.5 tok/s), against 102–119 s on the oMLX rows.
  - MLC's GDN prefill reuses the sequential recurrent decode kernel (#3480 is open), as
    `env.md` expected.
- **Decode slows with context.** These come from short samples of 4, 20 and 8 tokens; M3
  measures decode properly.
  - About 41 tok/s after a 40-token prompt (G4).
  - 11 tok/s at 12.8K with the grammar on (G1).
  - 3 tok/s at 64K (G5).
- **When.** The gate ran on 2026-10-20 between 13:05 and 13:21, on AC power, under macOS 27.2
  (26B5101f). It passed the quiet pre-flight and the monitor.

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
<!-- agentbench:end summary 4bit -->
