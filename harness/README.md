# agentbench (harness)

Benchmark client used unchanged against every server in this experiment. See
[../METHODOLOGY.md](../METHODOLOGY.md) for the gate (G1–G5) and metrics (M1–M7), and
[STATUS.md](STATUS.md) for what is implemented so far.

Python 3.12, uv project. Everything runs offline; the tokenizer and chat template come
from the local HF snapshot `$HF_HOME/hub/models--mlx-community--Qwen3.8-27B-8bit/snapshots/<hash>/`.

```bash
cd harness
uv sync                      # creates harness/.venv from uv.lock
uv run pytest -q             # mock-server tests (no model server needed)
uv run agentbench info       # tokenizer snapshot + image-token arithmetic
```

## Implemented today

| Piece | Module |
| --- | --- |
| Streaming OpenAI `/v1/chat/completions` + Anthropic `/v1/messages` client, TTFT, per-chunk timestamps, usage + cached tokens, tool-call assembly, inline `<think>` split, markup-leak check, HTTP/timeout errors | `agentbench.client` |
| SSE parser (comments/keep-alives, multi-line data, named events) | `agentbench.sse` |
| Decode rate `(completion_tokens − 1)/(t_last − t_first)`, chunk-gap p50/p99, tokens/chunk, median/min/max | `agentbench.metrics` |
| Chat-template rendering (HF-compatible Jinja env, `tools`, `enable_thinking`) and token counting; image tokens | `agentbench.tokenizer` |
| Provenance header (harness commit + dirty flag, `sw_vers`, `xcodebuild -version` default + beta, chip, memory; home/HF paths redacted; no hostnames/serials) | `agentbench.provenance` |
| Memory sampler (PID tree, `footprint`, RSS fallback, `vm_stat`) | `agentbench.memory` |
| Mock OpenAI + Anthropic SSE server | `agentbench.mock_server` |
| Concurrent start helper (`asyncio.Barrier`) | `agentbench.client.run_concurrent` |

### Image tokens

`Qwen2VLImageProcessorFast`, `patch_size=16`, `merge_size=2`: resize each side to a
multiple of 32 (`smart_resize`, clamped to 65 536–16 777 216 pixels), then
`tokens = (h/16)·(w/16)/4 = h·w/1024`. A 1280×1024 screenshot is exactly **1280**
`<|image_pad|>` tokens, plus `<|vision_start|>`/`<|vision_end|>` = 1282 prompt tokens.

### Commands available now

```bash
uv run agentbench info
uv run agentbench mock-server --port 8790          # never 8500 or 8600-8699
uv run agentbench mem --pid <server-pid> --interval 2 --duration 60
```

## Planned suite commands (not implemented yet; see STATUS.md)

```bash
uv run agentbench fixtures build
uv run agentbench gate --framework llama.cpp --base-url http://127.0.0.1:8702 \
    --framework-version b11717 --launch-flags "<flags>" --tag 4bit
uv run agentbench m1 --framework omlx --base-url http://127.0.0.1:8703 --trials 5 --tag 4bit
uv run agentbench m2 --framework mlx-lm --base-url http://127.0.0.1:8701
uv run agentbench m3 --framework llama.cpp --base-url http://127.0.0.1:8702 --spec-label on
uv run agentbench m4 --framework vllm-metal --base-url http://127.0.0.1:8705
uv run agentbench m5 --framework omlx --base-url http://127.0.0.1:8703 --helpers 2
uv run agentbench m6 --framework lithos-metal --base-url http://127.0.0.1:8704 --minutes 15 --mem-port 8704
uv run agentbench m7 --framework omlx --base-url http://127.0.0.1:8703
uv run agentbench summarize --framework omlx > ../omlx/summary.md
```
