# Harness status (paused 2026-10-17 ~23:35)

Work stopped early because of a time budget. Nothing is committed (review first).

## Done

- uv project `harness/` (Python 3.12, `pyproject.toml`, `uv.lock`, package `agentbench`,
  CLI entry point `agentbench`). Deps: httpx, jinja2, jsonschema, numpy, pillow,
  tokenizers; dev: pytest, pytest-asyncio. Repo `.gitignore` now ignores `fixtures/generated/`.
- `client.py`: async streaming OpenAI + Anthropic clients and `RequestRecord`
  (send time, TTFT by the METHODOLOGY rule, per-chunk timestamps/text, last-token time,
  e2e, raw usage + llama.cpp `timings`, cached tokens from
  `prompt_tokens_details.cached_tokens` / `cache_read_input_tokens` / `cached_tokens` /
  `prompt_cache_hit_tokens` / `timings.cache_n`, finish reason, assembled
  content/reasoning/tool calls, inline `<think>` split incl. bare `</think>`, markup-leak
  check, HTTP / read-timeout / total-timeout / mid-stream errors). `ServerConfig` holds
  base URL, model, max-tokens field name, extra body (deep-merged), `stream_options`
  toggle, timeouts. `run_concurrent` starts N requests behind an `asyncio.Barrier`.
- `sse.py`, `metrics.py` (decode rate, gap p50/p99, tokens/chunk, tokenizer fallback,
  median/min/max), `tokenizer.py` (HF-compatible Jinja env, `tools`, `enable_thinking`,
  string→dict tool-call arguments, image-token formula), `provenance.py` (header; path
  redaction; no hostnames/serials/UUIDs), `memory.py` (PID tree, `footprint`, RSS
  fallback, `vm_stat`, background sampler), `mock_server.py` (stdlib asyncio, chunked SSE).
- Tests: `uv run pytest -q` → **16 passed** (role-only first chunk, keep-alive comments,
  progress events, split tool_call deltas with two parallel calls, final-chunk usage with
  cached tokens, reasoning_content, inline `<think>`, leak flag, HTTP 400/500, read and
  total timeouts, stream error event, Anthropic event stream with thinking/text/tool_use
  input_json_delta, concurrency runner, SSE rules, image tokens, template render/count,
  memory parsers). One harmless `PytestUnraisableExceptionWarning` from the mock server
  loop closing while the "stall" handler sleeps.
- Verified: 1280×1024 → 1280 image tokens (+2 vision start/end).

## Not done yet

1. **Fixtures** (`agentbench fixtures build`, deterministic, seeded):
   Pillow fake-UI screenshots 1280×1024 (use Pillow's bundled font via
   `ImageFont.load_default(size)` for byte-stable output) + G2 `VERIFY: XXX-XXX` image;
   ~40 tool schemas (computer/fs/shell/browser/mail/calendar/notes/http) in OpenAI and
   Anthropic format + system prompt sized to 14.5K–15.5K rendered tokens; ≈250-token tool
   results; cold prompts 16K/32K/64K(/128K) as 16,000/32,000/64,000/128,000 rendered tokens
   with a digits-only nonce (fixed token count) at the very start; M3 fillers + long-JSON
   instruction; canned 20-step M4 trajectory; ~20-case M7 suite; `fixtures/manifest.json`
   with sha256 of every generated file. Text-only equivalents (equal-token text per image).
2. **Suites**: `gate` (G1–G5 table), `m1`–`m7`, `--text-only`, `summarize`; JSONL writer
   to `<framework>/raw/<suite>-<tag>-<timestamp>.jsonl` with the provenance header first;
   per-framework config (TOML) + CLI flags; `--mem-pid/--mem-port` hookup.
3. Tests for the suites/summarize output; `fixtures build --check` determinism test.

## Design decisions to keep when resuming

- With `tools`, the Qwen template renders the tools block **before** the system text, so a
  cache-busting nonce for runs with tools must go in the first tool's description.
- M1: warm-up request = prefix (system+tools+task) + generation prompt; each trial =
  prefix + canned assistant call + unique tool result (random digits `request_id`) +
  unique screenshot. The warm prompt is then an exact token prefix of every trial (matters
  for hybrid-attention caches that checkpoint at prompt end). Offer `--rewarm`.
- M4: canned assistant turns render with an empty `<think>\n\n</think>\n\n`, identical to
  the thinking-off generation prompt, so step k's prompt is an exact prefix of step k+1's.
- Screenshots go in a user message after the tool message by default (most portable);
  make placement configurable.
- Sizes use decimal K (64K = 64,000) to leave headroom under 65,536 contexts.

## Resume

```bash
cd harness && uv sync && uv run pytest -q
```
Then implement items 1–3 above in `src/agentbench/fixtures/`, `src/agentbench/suites/`,
`src/agentbench/summarize.py`, and wire them into `cli.py` (subcommands already stubbed).
