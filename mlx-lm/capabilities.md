# mlx-lm: capabilities

<!-- agentbench:begin gate 8bit -->
## Gate G1-G5 + G2b, tag `8bit`

Run 2026-10-19 08:22; profile `mlxlm`; framework version `v0.32.2 (93e6d4a6), clean`; harness `37fde74759`. Raw: `raw/gate-8bit-20261019-081920.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 22.29 s, e2e 22.35 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 404: {"error": "Only 'text' content type is supported."} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None; control (user message): rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: transport: ReadError: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 152 chars in reasoning; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 152 chars in reasoning \| G4.effort-high: accepted; reasoning 152 chars in reasoning \| G4.effort-minimal: accepted; reasoning 152 chars in reasoning \| G4.default: accepted; reasoning 152 chars in reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 126.6 s; configured context: unknown; peak server footprint 45.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G2.image | Hermes, image_url data URI + question | HTTP 404 | rejected: HTTP 404: {"error": "Only 'text' content type is supported."} (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 404 | rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 404 | rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.text-adaptive | Claude Code, thinking=adaptive | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.text-nothinking | Claude Code, thinking=absent | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.tool_use | Claude Code, tools, thinking absent | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.image | Claude Code, image block (base64) | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | transport | rejected: transport: ReadError: ; input_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | transport | rejected: transport: ReadError: ; input_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 126.6 s; configured context: unknown; peak server footprint 45.0 GiB (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
<!-- agentbench:end gate 8bit -->

<!-- agentbench:begin gate 4bit -->
## Gate G1-G5 + G2b, tag `4bit`

Run 2026-10-19 08:31; profile `mlxlm`; framework version `v0.32.2 (93e6d4a6), clean`; harness `37fde74759`. Raw: `raw/gate-4bit-20261019-082922.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 19.97 s, e2e 20.00 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **FAIL** | rejected: HTTP 404: {"error": "Only 'text' content type is supported."} |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None; control (user message): rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **FAIL** | text FAIL, tool_use FAIL, image FAIL, tool_result image FAIL (first failure: transport: ReadError: ) |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 152 chars in reasoning; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 152 chars in reasoning \| G4.effort-high: accepted; reasoning 152 chars in reasoning \| G4.effort-minimal: accepted; reasoning 152 chars in reasoning \| G4.default: accepted; reasoning 152 chars in reasoning |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 120.2 s; configured context: unknown; peak server footprint 33.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G2.image | Hermes, image_url data URI + question | HTTP 404 | rejected: HTTP 404: {"error": "Only 'text' content type is supported."} (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 404 | rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 404 | rejected: HTTP 404: {"error": "Only 'text' content type is supported."}; prompt_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.text-adaptive | Claude Code, thinking=adaptive | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.text-nothinking | Claude Code, thinking=absent | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.tool_use | Claude Code, tools, thinking absent | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.image | Claude Code, image block (base64) | transport | transport: ReadError:  (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | transport | rejected: transport: ReadError: ; input_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | transport | rejected: transport: ReadError: ; input_tokens=None (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 152 chars in reasoning (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 120.2 s; configured context: unknown; peak server footprint 33.0 GiB (mlxlm: omitted model (any other value reloads the model and drops the prompt cache)) |
<!-- agentbench:end gate 4bit -->
