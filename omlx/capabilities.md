# omlx: capabilities

<!-- agentbench:begin gate 4bit-spec-off -->
## Gate G1-G5 + G2b, tag `4bit-spec-off`

Run 2026-10-18 18:53; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `e495e19ac5`. Raw: `raw/gate-4bit-spec-off-20261018-185130.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 1.26 s, e2e 1.26 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer 'The screen shows a dialog with a verific', expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 111 chars in thinking_block / text ok ('ready'); reasoning 104 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 108 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 105.6 s; configured context: 131072; peak server footprint 23.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer 'The screen shows a dialog with a verific', expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 111 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 104 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 2.25 s, e2e 2.25 s |
| G3.image | Claude Code, image block (base64) | HTTP 200 | read Y3N-9JT |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1969 (sum 1969) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1979 (sum 1979) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 108 chars in reasoning_content |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 153 chars in reasoning_content |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 105.6 s; configured context: 131072; peak server footprint 23.0 GiB |
<!-- agentbench:end gate 4bit-spec-off -->

<!-- agentbench:begin gate 8bit-spec-off -->
## Gate G1-G5 + G2b, tag `8bit-spec-off`

Run 2026-10-19 07:24; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `37fde74759`. Raw: `raw/gate-8bit-spec-off-20261019-072034.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 21.10 s, e2e 21.11 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. T", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 121 chars in thinking_block / text ok ('ready'); reasoning 51 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 110.7 s; configured context: 131072; peak server footprint 36.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer "I'm sorry, but I can't help with that. T", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 121 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 51 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 25.27 s, e2e 25.27 s |
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
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 110.7 s; configured context: 131072; peak server footprint 36.0 GiB |
<!-- agentbench:end gate 8bit-spec-off -->

<!-- agentbench:begin gate oq8mtp-spec-off -->
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
<!-- agentbench:end gate oq8mtp-spec-off -->

<!-- agentbench:begin gate oq4mtp-spec-off -->
## Gate G1-G5 + G2b, tag `oq4mtp-spec-off`

Run 2026-10-20 02:29; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `d444d30b5f`. Raw: `raw/gate-oq4mtp-spec-off-20261020-022606.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 18.49 s, e2e 18.49 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer 'The screen shows a blank white display w', expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 130 chars in thinking_block / text ok ('ready'); reasoning 99 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 108 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 102.4 s; configured context: 131072; peak server footprint 24.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer 'The screen shows a blank white display w', expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 130 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 99 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 21.40 s, e2e 21.40 s |
| G3.image | Claude Code, image block (base64) | HTTP 200 | read Y3N-9JT |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1969 (sum 1969) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1979 (sum 1979) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 108 chars in reasoning_content |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 153 chars in reasoning_content |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 102.4 s; configured context: 131072; peak server footprint 24.0 GiB |
<!-- agentbench:end gate oq4mtp-spec-off -->

<!-- agentbench:begin gate oq8mtp-mtp-on -->
## Gate G1-G5 + G2b, tag `oq8mtp-mtp-on`

Run 2026-10-20 04:45; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `bea3159abe`. Raw: `raw/gate-oq8mtp-mtp-on-20261020-044238.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 1.03 s, e2e 1.03 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 43 chars in thinking_block / text ok ('ready'); reasoning 116 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 119.3 s; configured context: 131072; peak server footprint 40.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 43 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 116 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 1.75 s, e2e 1.75 s |
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
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 119.3 s; configured context: 131072; peak server footprint 40.0 GiB |
<!-- agentbench:end gate oq8mtp-mtp-on -->

<!-- agentbench:begin gate oq4mtp-mtp-on -->
## Gate G1-G5 + G2b, tag `oq4mtp-mtp-on`

Run 2026-10-20 04:50; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `bea3159abe`. Raw: `raw/gate-oq4mtp-mtp-on-20261020-044829.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 0.75 s, e2e 0.76 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I don't see a dialog with a verification", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 98 chars in thinking_block / text ok ('ready'); reasoning 123 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 108 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 153 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 153 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 105.3 s; configured context: 131072; peak server footprint 24.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer "I don't see a dialog with a verification", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 98 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 123 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 1.11 s, e2e 1.11 s |
| G3.image | Claude Code, image block (base64) | HTTP 200 | read Y3N-9JT |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1969 (sum 1969) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1979 (sum 1979) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 108 chars in reasoning_content |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 153 chars in reasoning_content |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 153 chars in reasoning_content |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 105.3 s; configured context: 131072; peak server footprint 24.0 GiB |
<!-- agentbench:end gate oq4mtp-mtp-on -->

<!-- agentbench:begin gate oq5mtp-mtp-on-prec -->
## Gate G1-G5 + G2b, tag `oq5mtp-mtp-on-prec`

Run 2026-10-21 23:12; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `38387b5c03`. Raw: `raw/gate-oq5mtp-mtp-on-prec-20261021-230952.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 0.83 s, e2e 0.83 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 56 chars in thinking_block / text ok ('ready'); reasoning 110 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 45 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 146 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 146 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 120.6 s; configured context: 131072; peak server footprint 29.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 56 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 110 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 1.81 s, e2e 1.81 s |
| G3.image | Claude Code, image block (base64) | HTTP 200 | read Y3N-9JT |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1969 (sum 1969) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1979 (sum 1979) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 45 chars in reasoning_content |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 146 chars in reasoning_content |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 146 chars in reasoning_content |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 146 chars in reasoning_content |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 120.6 s; configured context: 131072; peak server footprint 29.0 GiB |
<!-- agentbench:end gate oq5mtp-mtp-on-prec -->

<!-- agentbench:begin gate oq6mtp-mtp-on-prec -->
## Gate G1-G5 + G2b, tag `oq6mtp-mtp-on-prec`

Run 2026-10-21 23:18; profile `omlx`; framework version `v0.7.1rc1 (7a5a3d75), clean`; harness `38387b5c03`. Raw: `raw/gate-oq6mtp-mtp-on-prec-20261021-231538.jsonl`.

| ID | Requirement | Result | Detail |
| --- | --- | --- | --- |
| G1 | OpenAI chat completions + SSE + Qwen3.8 tool calls | **PASS** | fs_read_file {"path": "docs/setup.md"}; one delta; first call chunk at 20.67 s, e2e 20.67 s; finish=tool_calls |
| G2 | Image input (base64 PNG image_url), code read back | **PASS** | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b | Image inside a tool result (role=tool image_url, Hermes path), code read back | **FAIL** | tool-message image: code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control; control (user message): read Y3N-9JT; prompt_tokens=1936 |
| G3 | Anthropic /v1/messages: text, tool_use, image, image in tool_result | **PASS** | text ok, tool_use ok, image ok, tool_result image ok; text ok ('ready'); reasoning 114 chars in thinking_block / text ok ('ready'); reasoning 115 chars in thinking_block |
| G4 | Thinking control (enable_thinking / reasoning_effort) | **PASS** | Hermes off: no reasoning; Hermes on: reasoning 117 chars in reasoning_content; note: reasoning_effort=none alone does not disable thinking (top-level effort ignored) \| G4.effort-none-only: accepted; reasoning 117 chars in reasoning_content \| G4.effort-high: accepted; reasoning 131 chars in reasoning_content \| G4.effort-minimal: accepted; reasoning 117 chars in reasoning_content \| G4.default: accepted; reasoning 131 chars in reasoning_content |
| G5 | Context >= 64K: a 64,000-token prompt completes | **PASS** | 64000-token prompt completed: prompt_tokens=64000, TTFT 114.6 s; configured context: 131072; peak server footprint 33.0 GiB |

### Probes

| Probe | Request shape | HTTP | Outcome |
| --- | --- | --- | --- |
| G1.hermes | Hermes (reasoning_effort=none, enable_thinking=false) | HTTP 200 | fs_read_file {"path": "docs/setup.md"} |
| G2.image | Hermes, image_url data URI + question | HTTP 200 | read Y3N-9JT correctly; prompt_tokens=1319 |
| G2b.tool-image | Hermes, screenshot as image_url inside the role=tool message | HTTP 200 | code not read (answer "I'm sorry, but I can't help with that. I", expected Y3N-9JT); prompt_tokens=639; image dropped: 1297 fewer prompt tokens than the control |
| G2b.user-control | Hermes, same screenshot in a following user message (control) | HTTP 200 | read Y3N-9JT; prompt_tokens=1936 |
| G3.text-adaptive | Claude Code, thinking=adaptive | HTTP 200 | text ok ('ready'); reasoning 114 chars in thinking_block |
| G3.text-nothinking | Claude Code, thinking=absent | HTTP 200 | text ok ('ready'); reasoning 115 chars in thinking_block |
| G3.tool_use | Claude Code, tools, thinking absent | HTTP 200 | tool_use fs_read_file {'path': 'docs/setup.md'}; one delta; first call chunk at 23.54 s, e2e 23.54 s |
| G3.image | Claude Code, image block (base64) | HTTP 200 | read Y3N-9JT |
| G3.tool_result-image | Claude Code, screenshot as image block inside tool_result | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1969 (sum 1969) |
| G3.tool_result-control | Claude Code, same image after the tool_result (control) | HTTP 200 | read Y3N-9JT; input_tokens=0+cache_creation 1979 (sum 1979) |
| G4.hermes-off | reasoning_effort=none, chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.hermes-on | reasoning_effort=medium, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 117 chars in reasoning_content |
| G4.kwargs-off | chat_template_kwargs={'enable_thinking': False} | HTTP 200 | no reasoning |
| G4.kwargs-on | chat_template_kwargs={'enable_thinking': True} | HTTP 200 | reasoning 131 chars in reasoning_content |
| G4.effort-none-only | reasoning_effort=none | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.effort-high | reasoning_effort=high, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 131 chars in reasoning_content |
| G4.effort-minimal | reasoning_effort=minimal, chat_template_kwargs={'enable_thinking': True} | HTTP 200 | accepted; reasoning 117 chars in reasoning_content |
| G4.default | no thinking fields | HTTP 200 | accepted; reasoning 131 chars in reasoning_content |
| G5.cold-64000 | Hermes off, cold prompt with nonce | HTTP 200 | 64000-token prompt completed: prompt_tokens=64000, TTFT 114.6 s; configured context: 131072; peak server footprint 33.0 GiB |
<!-- agentbench:end gate oq6mtp-mtp-on-prec -->
