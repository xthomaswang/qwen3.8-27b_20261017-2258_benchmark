## Gate G1-G5 + G2b, tag `oq8mtp-spec-off`

Run 2026-10-20 00:18; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `d444d30b5f`. Raw: `raw/gate-oq8mtp-spec-off-20261020-001515.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 20.93 s, e2e 20.93 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. T", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 114 chars in thinking_block / text ok ('ready'); reasoning 120 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 112.7 s; configured context: 131072; peak server footprint 37.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer "I'm sorry, but I can't help with that. T", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 114 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 120 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 25.91 s, e2e 25.92 s |
| G3.image | Claude Code, image block (base64) | HTTP 200 | read Y3N-9JT |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1969 (sum 1969) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1979 (sum 1979) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 117 chars in reasoning_content |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 153 chars in reasoning_content |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 112.7 s; configured context: 131072; peak server footprint 37.0 GiB |
