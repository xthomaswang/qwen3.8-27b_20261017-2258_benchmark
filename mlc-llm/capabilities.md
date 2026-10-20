# mlc-llm: capabilities

<!-- agentbench:begin gate 4bit -->
## Gate G1-G5 + G2b, tag `4bit`

Run 2026-10-20 13:21; profile `mlc`; framework version `v0.26.dev0-20-g8978ea9a (8978ea9a), clean`; harness `7828212e62`; tool calls via **structured output** (`response_format` `mlc`, anyOf; non-standard). Raw: `raw/gate-4bit-20261020-130554.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS via structured output (non-standard)** | fs_read_file {"path": "docs/setup.md"}; JSON content in 19 chunks; first chunk at 102.26 s, e2e 104.07 s; finish=stop |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 500: Internal Server Error |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: transport: ReadError: ; prompt_tokens=None; control (user message): rejected: HTTP 500: Internal Server Error; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: transport: ReadError: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **FAIL** | N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped; off: no reasoning [shaped: mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted)] \| G4.effort-none-only: accepted; no reasoning [shaped: mlc: stripped reasoning_effort='none' (only [] accepted)] \| G4.effort-high: N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped \| G4.effort-minimal: N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped \| G4.default: accepted; no reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 815.1 s; configured context: unknown; peak server footprint 25.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | structured output (response_format=mlc, tools inlined) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} (mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted); structured output: 44 tools inlined into the system message, `tools` not sent, response_format=mlc (anyOf)) |
| G2.image | Hermes, image_url data URI + question | HTTP 500 | rejected: HTTP 500: Internal Server Error (mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted)) |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | transport | rejected: transport: ReadError: ; prompt_tokens=None (mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted); structured output: tool history flattened (calls as JSON step objects, results as user messages); structured output: 1 tools inlined into the system message, `tools` not sent, response_format=mlc (anyOf)) |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 500 | rejected: HTTP 500: Internal Server Error; prompt_tokens=None (mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted); structured output: tool history flattened (calls as JSON step objects, results as user messages); structured output: 1 tools inlined into the system message, `tools` not sent, response_format=mlc (anyOf)) |
| G3.text-adaptive | Claude Code, thinking=adaptive | transport | transport: ReadError:  |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 404 | HTTP 404: {"detail":"Not Found"} |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 404 | HTTP 404: {"detail":"Not Found"} |
| G3.image | Claude Code, image block (base64) | HTTP 404 | HTTP 404: {"detail":"Not Found"} |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 404 | rejected: HTTP 404: {"detail":"Not Found"}; input_tokens=None |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 404 | rejected: HTTP 404: {"detail":"Not Found"}; input_tokens=None |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning [shaped: mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted)] |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning [shaped: mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | not sent | N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; no reasoning [shaped: mlc: stripped reasoning_effort='none' (only [] accepted)] |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: mlc: no per-request thinking control (fixed by the served model config, qwen3_5 vs qwen3_5_nothink); thinking fields are stripped |
| G4.default | no thinking fields | HTTP 200 | accepted; no reasoning |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 815.1 s; configured context: unknown; peak server footprint 25.0 GiB (mlc: stripped chat_template_kwargs (strict schema rejects it with HTTP 400); mlc: stripped reasoning_effort='none' (only [] accepted)) |
<!-- agentbench:end gate 4bit -->
