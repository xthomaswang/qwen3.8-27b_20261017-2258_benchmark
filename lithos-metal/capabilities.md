# lithos-metal: capabilities

<!-- agentbench:begin gate 4bit-dspark -->
## Gate G1-G5 + G2b, tag `4bit-dspark`

Run 2026-10-18 22:42; profile `lithos`; framework version `v0.1.2-1-g73b8cb6 (73b8cb6d), clean`; harness `37fde74759`. Raw: `raw/gate-4bit-dspark-20261018-223737.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; incremental (5 deltas); first call chunk at 34.19 s, e2e 34.41 s; finish=tool_calls [profile stripped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 400: {"error":{"message":"messages.0.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.0.content.str","code":"invalid_request_error"}} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 400: {"error":{"message":"messages.2.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.2.content.str","code":"invalid_request_error"}}; prompt_tokens=None; control (user message): rejected: HTTP 400: {"error":{"message":"messages.3.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.3.content.str","code":"invalid_request_error"}}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text ok, tool_use ok, image FAIL, tool_result image FAIL (first failure: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}}); text ok ('ready'); no reasoning |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **FAIL** | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off); off: no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.effort-minimal: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.default: accepted; no reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 230.7 s; configured context: 131072; peak server footprint 27.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G2.image | Hermes, image_url data URI + question | HTTP 400 | rejected: HTTP 400: {"error":{"message":"messages.0.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.0.content.str","code":"invalid_request_error"}} (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 400 | rejected: HTTP 400: {"error":{"message":"messages.2.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.2.content.str","code":"invalid_request_error"}}; prompt_tokens=None (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 400 | rejected: HTTP 400: {"error":{"message":"messages.3.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.3.content.str","code":"invalid_request_error"}}; prompt_tokens=None (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G3.text-adaptive | Claude Code, thinking=adaptive | not sent | N/A: lithos: Anthropic thinking='adaptive' would be stripped (server accepts only absent or 'disabled') |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); no reasoning |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 0.67 s, e2e 0.67 s |
| G3.image | Claude Code, image block (base64) | HTTP 400 | HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}} |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 400 | rejected: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Only text content is supported; image, audio and document inputs are unavailable"}}; input_tokens=None |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 400 | rejected: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}}; input_tokens=None |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; no reasoning |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.default | no thinking fields | HTTP 200 | accepted; no reasoning |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 230.7 s; configured context: 131072; peak server footprint 27.0 GiB (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
<!-- agentbench:end gate 4bit-dspark -->

<!-- agentbench:begin gate nvfp4-dspark -->
## Gate G1-G5 + G2b, tag `nvfp4-dspark`

Run 2026-10-19 02:57; profile `lithos`; framework version `v0.1.2-1-g73b8cb6 (73b8cb6d), clean`; harness `37fde74759`. Raw: `raw/gate-nvfp4-dspark-20261019-025248.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; incremental (4 deltas); first call chunk at 32.77 s, e2e 32.88 s; finish=tool_calls [profile stripped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 400: {"error":{"message":"messages.0.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.0.content.str","code":"invalid_request_error"}} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 400: {"error":{"message":"messages.2.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.2.content.str","code":"invalid_request_error"}}; prompt_tokens=None; control (user message): rejected: HTTP 400: {"error":{"message":"messages.3.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.3.content.str","code":"invalid_request_error"}}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text ok, tool_use ok, image FAIL, tool_result image FAIL (first failure: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}}); text ok ('ready'); no reasoning |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **FAIL** | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off); off: no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] \| G4.effort-none-only: accepted; no reasoning \| G4.effort-high: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.effort-minimal: N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) \| G4.default: accepted; no reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 215.4 s; configured context: 131072; peak server footprint 25.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G2.image | Hermes, image_url data URI + question | HTTP 400 | rejected: HTTP 400: {"error":{"message":"messages.0.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.0.content.str","code":"invalid_request_error"}} (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 400 | rejected: HTTP 400: {"error":{"message":"messages.2.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.2.content.str","code":"invalid_request_error"}}; prompt_tokens=None (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 400 | rejected: HTTP 400: {"error":{"message":"messages.3.content.str: Input should be a valid string","type":"invalid_request_error","param":"messages.3.content.str","code":"invalid_request_error"}}; prompt_tokens=None (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
| G3.text-adaptive | Claude Code, thinking=adaptive | not sent | N/A: lithos: Anthropic thinking='adaptive' would be stripped (server accepts only absent or 'disabled') |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); no reasoning |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 2.19 s, e2e 2.19 s |
| G3.image | Claude Code, image block (base64) | HTTP 400 | HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}} |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 400 | rejected: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Only text content is supported; image, audio and document inputs are unavailable"}}; input_tokens=None |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 400 | rejected: HTTP 400: {"type":"error","error":{"type":"invalid_request_error","message":"Unsupported Messages content block: image"}}; input_tokens=None |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning [shaped: lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)] |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; no reasoning |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | not sent | N/A: lithos: thinking cannot be enabled (chat_template_kwargs and reasoning_effort other than 'none' are stripped; the server hard-wires thinking off) |
| G4.default | no thinking fields | HTTP 200 | accepted; no reasoning |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 215.4 s; configured context: 131072; peak server footprint 25.0 GiB (lithos: stripped chat_template_kwargs (strict schema rejects it with HTTP 400)) |
<!-- agentbench:end gate nvfp4-dspark -->
