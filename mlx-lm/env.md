# mlx-lm: environment, launch, and gate expectations

Recorded 2026-10-17, 23:25 local time. macOS 27.2 (build 26B5101f), Xcode 27.1 (build
27A9275). Nothing in this file was measured with a loaded model. Every claim comes
from source reading (the `file:line` references are in `~/Developer/mlsys/serving/mlx-lm`,
tag v0.32.2, commit 93e6d4a6) or from `--help` output.

## 1. Install

```sh
cd ~/Developer/mlsys/serving/mlx-lm            # git describe: v0.32.2, clean tree
uv venv --python 3.12 .venv                    # CPython 3.12.14 (already on disk)
uv pip install --python .venv/bin/python -e .  # 34 packages, 3m31s, exit 0
```

| Package | Version |
| --- | --- |
| mlx-lm | 0.32.2 (editable, `~/Developer/mlsys/serving/mlx-lm`) |
| mlx | 0.32.4 |
| mlx-metal | 0.32.4 |
| transformers | 5.20.1 |
| tokenizers | 0.23.3 |
| numpy | 2.5.4 |
| huggingface-hub | 2.2.0 |

- Download: about 96 MiB. That is mlx-metal 74.5 MiB, transformers 12.2 MiB, numpy 5.2 MiB,
  tokenizers 3.0 MiB, plus the small mlx wheel. Everything else came from the uv cache.
  The venv on disk is 366 MB.
- I did not pin mlx. uv chose the newest version that satisfies `mlx>=0.32.2`
  (`pyproject.toml`), which is 0.32.4. The uv cache also holds 0.32.3.
- Pillow is not installed. It is only in the `vision` and `test` extras, and Qwen3.8
  has no image processor in mlx-lm (see G2), so it is not needed.
- Checks run: `.venv/bin/mlx_lm.server --help`, `.venv/bin/mlx_lm.benchmark --help`,
  and `.venv/bin/mlx_lm.generate --help` all exit 0. `mx.device_info()` reports
  `max_recommended_working_set_size = 115448725504` (115.4 GB) and
  `max_buffer_length = 86586540032`.
- Tokenizer-only check: no weights, no GPU, run with
  `mlx_lm.tokenizer_utils.load(Path(snapshot))`. It gives `has_thinking=True`
  (`<think>`=248068, `</think>`=248069) and `has_tool_calling=True` with
  `mlx_lm.tool_parsers.qwen3_coder` (`<tool_call>`=248058, `</tool_call>`=248059). All four
  markers are single tokens.
  - With `enable_thinking=false` the prompt ends in
    `<|im_start|>assistant\n<think>\n\n</think>\n\n`.
  - With no kwargs, thinking is on and the template injects a system turn: "Reasoning
    effort is set to xhigh. …".
- The editable build writes `mlx_lm/_version.py`. The repo's `.gitignore` covers that
  file and `.venv`, so `git status` stays clean.

## 2. Checkpoints

| Row | Repo | Status |
| --- | --- | --- |
| 8-bit (secondary) | `mlx-community/Qwen3.8-27B-8bit`, snapshot `815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9` | Cached, 28 GB. Affine 8-bit g64. 333 `vision_tower.*` tensors, no `mtp.*` tensors. `text_config.mtp_num_hidden_layers` is 1, but there are no weights for it. |
| 4-bit (primary) | `mlx-community/Qwen3.8-27B-4bit` | **Not in the HF cache.** Blocked until `scripts/download_models.sh core` runs (16.1 GB). |

The large blobs in the 8-bit entry are symlinks into a shared blob store under
`$HF_HOME/hub/blobs/`. Hands off.

## 3. Launch (port 8701)

Starting the server loads the model right away: the generation thread calls
`load_default()` (`server.py:782`). Follow the GPU-lock protocol in METHODOLOGY section 3
first.

```sh
cd ~/Developer/mlsys/serving/mlx-lm
M8=$HF_HOME/hub/models--mlx-community--Qwen3.8-27B-8bit/snapshots/815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9
LOGS=~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/logs
lsof -nP -iTCP:8701 -sTCP:LISTEN; lsof -nP -iTCP:8500 -sTCP:LISTEN   # both must be empty
HF_HUB_OFFLINE=1 .venv/bin/mlx_lm.server \
  --model "$M8" --host 127.0.0.1 --port 8701 \
  --max-tokens 4096 \
  --prompt-cache-size 64 --prompt-cache-bytes 48GB \
  --log-level INFO > "$LOGS/mlx-lm-server-8bit.log" 2>&1
```

For the 4-bit row, use the same command with the 4-bit snapshot path once it is
downloaded.

Why these flags:

- **Snapshot path and `HF_HUB_OFFLINE=1`.** Requests carry a `model` field. Any value
  other than `default_model` or the exact `--model` string is treated as a different
  model, and the server loads it, downloading it if needed (`server.py:1301`,
  `server.py:477-484`). Offline mode makes such a mistake fail fast instead of starting a
  download.
  - Sending the repo id `mlx-community/Qwen3.8-27B-8bit` while `--model` is the snapshot path
    still counts as a different `model_key`. The server calls `reset()` and reloads the same
    28 GB (`server.py:410-423`). Every prompt-cache entry is then orphaned, because
    entries are keyed by `model_key` (`server.py:843-845`, `1073-1075`).
  - **The harness must omit `model` or send `"default_model"`.** The same applies to
    `draft_model` (`server.py:1302`).
- **No server-wide `--chat-template-args`.** Per-request `chat_template_kwargs` are merged
  over the server value (`server.py:651-654`). Leaving the server value empty keeps the
  G4 default (thinking on) visible. The harness sends `enable_thinking=false` for the
  latency metrics.
- **`--max-tokens 4096`.** The server default is 512 (`server.py:2012-2017`). Requests can
  override it with `max_tokens` or `max_completion_tokens` (`server.py:1307-1311`).
- **`--prompt-cache-size 64 --prompt-cache-bytes 48GB`.** The default of 10 entries
  (`server.py:2042-2047`) is too small for the hybrid cache behaviour in section 6. A 20-step
  trajectory can create about 2 entries per step. The byte cap is enforced only on the
  batched path (`server.py:886-889`). The constructor receives only the size
  (`server.py:1914`). Treat 48GB as a starting value and record the real value.
- **Leave at default:** `--temp 0.0` (`server.py:1988-1993`), `--prefill-step-size 2048`,
  `--decode-concurrency 32`, `--prompt-concurrency 8` (`server.py:2024-2041`). Do not use
  `--kv-bits`: it disables batching (`server.py:768-773`) and so disables the
  segment checkpoints that M1 depends on.
- **No context-length flag exists.** There is no `--max-kv-size` and no context limit in
  the server. The full list is at `server.py:1923-2078`.
- **Wired memory.** `main()` calls `maybe_set_recommended_wired_limit()`
  (`server.py:2080`, `utils.py:74-83`). That sets the MLX wired limit to Metal's
  recommended working set (115.4 GB here), even though `iogpu.wired_limit_mb` is 0. No sysctl
  change is needed or made.

Health check: `curl -s localhost:8701/health` returns `{"status": "ok"}`
(`server.py:1800-1812`).

## 4. Direct-call commands (no HTTP)

`mlx_lm.benchmark` (`benchmark.py`):

- Defaults: `-p/--prompt-tokens 512`, `-g/--generation-tokens 1024`, `-b/--batch-size 1`,
  `-n/--num-trials 5`, `--prefill-step-size 2048`, `--delay 0` (`benchmark.py:16-82`).
- The prompt is uniform random token ids with no chat template (`benchmark.py:124`). It
  runs 1 warm-up, then N trials (`benchmark.py:152-168`). It prints `prompt_tps`,
  `generation_tps`, `peak_memory` (GB) and `total_time` for each trial, then the means
  (`benchmark.py:155-176`). It does not report the median, min or max, so take them from
  the per-trial lines.
- Batch size 1 runs `stream_generate`. Batch sizes above 1 run `batch_generate`.

```sh
cd ~/Developer/mlsys/serving/mlx-lm; export HF_HUB_OFFLINE=1
M8=$HF_HOME/hub/models--mlx-community--Qwen3.8-27B-8bit/snapshots/815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9
# Reference, upstream default protocol
.venv/bin/mlx_lm.benchmark --model "$M8"
# M2 analogue (cold prefill): prompt_tps at 16K / 32K / 64K
for p in 16384 32768 65536; do .venv/bin/mlx_lm.benchmark --model "$M8" -p $p -g 1 -n 3; done
# M3 analogue (short decode at long context): generation_tps
for p in 16384 32768 65536; do for g in 50 150 300; do
  .venv/bin/mlx_lm.benchmark --model "$M8" -p $p -g $g -n 3; done; done
```

`mlx_lm.generate` takes `--model`, `--prompt`, `--system-prompt`, `--max-tokens`,
`--temp`, `--chat-template-config`, `--ignore-chat-template`, `--max-kv-size`,
`--prompt-cache-file`, `--kv-bits`, `--draft-model`, `--num-draft-tokens`,
`--prefill-step-size`, `--seed`, `--image` and `--verbose`. The `--image` flag only matters for
models that have a processor. Example run with thinking off:

```sh
.venv/bin/mlx_lm.generate --model "$M8" --max-tokens 150 \
  --chat-template-config '{"enable_thinking": false}' --prompt "List three prime numbers."
```

Minimal Python TTFT and decode probe. It is the direct-call side of the "server overhead"
comparison. Run it with the venv interpreter and `HF_HUB_OFFLINE=1`, under the GPU lock.

```python
import sys, time
from mlx_lm import load, stream_generate          # mlx_lm/__init__.py:10-11
from mlx_lm.sample_utils import make_sampler

model, tok = load(sys.argv[1])                     # snapshot path
msgs = [{"role": "user", "content": open(sys.argv[2]).read()}]
prompt = tok.apply_chat_template(msgs, add_generation_prompt=True,
                                 enable_thinking=False)   # list[int]
t0 = time.perf_counter(); t_first = None
for r in stream_generate(model, tok, prompt, max_tokens=150,
                         sampler=make_sampler(0.0)):
    if t_first is None:
        t_first = time.perf_counter()              # first token sampled and evaluated
    last = r
t_last = time.perf_counter()
n = last.generation_tokens
print(dict(prompt_tokens=last.prompt_tokens, ttft_s=t_first - t0,
           prompt_tps=last.prompt_tps, gen_tps=last.generation_tps,
           decode_tps=(n - 1) / (t_last - t_first), peak_gb=last.peak_memory,
           finish=last.finish_reason))
```

`GenerationResponse` fields are listed at `generate.py:276-303`. To reproduce M1 directly,
prefill the prefix into `make_prompt_cache(model)` once, `copy.deepcopy` that cache for each
trial, and pass it as `prompt_cache=`. This mirrors what the server does
(`cache.py:1652-1672`).

## 5. Gate expectations (G1–G5)

| Gate | Expectation | Evidence |
| --- | --- | --- |
| G1 Chat Completions + SSE + Qwen tool calls | **Expected pass, verify.** | Routes are `/v1/chat/completions`, `/chat/completions` and `/v1/completions` (`server.py:1243-1247`). SSE uses `text/event-stream` (`server.py:1229-1233`) and ends with `data: [DONE]` (`server.py:1693`). The parser is `qwen3_coder`, picked automatically because the checkpoint template contains `<tool_call>\n<function=` (`tokenizer_utils.py:648-652`). `tokenizer_config.json` has no `tool_parser_type` (`tokenizer_utils.py:735-739`). Parsing: `qwen3_coder.py:124-131`, and parameter values are converted using the tool's JSON schema (`qwen3_coder.py:37-91`). Arguments are serialized with `json.dumps` (`server.py:73`). Stream deltas carry `index`, `id`, `type`, `function.name` and `function.arguments` (`server.py:71-82`). Text inside `<tool_call>…</tool_call>` is held back (`server.py:1646-1649`), so **each call arrives as one complete delta** rather than as incremental argument fragments. `finish_reason` is `tool_calls` (`server.py:1670-1671`). The state machine strips the markers from `content` (`generate.py:1062-1072`). |
| G2 Image input | **Expected fail: the request is rejected, not silently dropped.** | Only `muse_spark` has a processor (`processors/__init__.py:10-22`), so `processor` is None for qwen3_5 and `keep_images=False`. A content list with an `image_url` part then raises `ValueError("Only 'text' content type is supported.")` (`server.py:228-233`, `641-643`). The client receives **HTTP 404** with `{"error": ...}` (`server.py:1577-1581`), which is an unusual status for a bad request. At load time, `vision_tower.*` and `model.visual*` weights are filtered out (`models/qwen3_5.py:429-443`) and MTP weights are dropped (`models/qwen3_5.py:354`). The image path in mlx-lm does exist (`server.py:166-194`, `660-675`, `1083-1092`), but only for models with a processor. mlx-vlm is the MLX VLM route. It is not installed. |
| G3 Anthropic `/v1/messages` | **Expected fail.** | There is no route for it. Any other path gets 404 `Not Found` (`server.py:1249-1253`). There is no `anthropic` or `messages` handling anywhere in `mlx_lm/`. The fallback is a translating proxy. |
| G4 Thinking control | **Partial pass expected, verify.** | `chat_template_kwargs` is read for each request (`server.py:1330`) and passed to the template (`server.py:651-659`). If the request does not set it, `enable_thinking` defaults to `has_thinking`, which is True (`tokenizer_utils.py:394-395`). **Top-level `reasoning_effort` is ignored.** It appears nowhere in `mlx_lm/`. So a Hermes-style `"reasoning_effort": "medium"` with thinking on runs at the template default **xhigh** (`chat_template.jinja:46-49`). Sent inside `chat_template_kwargs`, `reasoning_effort` does work. With thinking on, any value other than xhigh, medium or low makes the template raise, and the client gets HTTP 404. With `enable_thinking=false` the template ignores `reasoning_effort` (`chat_template.jinja:46`) and pre-fills `<think>\n\n</think>\n\n` (`chat_template.jinja:165-166`), so no reasoning is expected. Reasoning is separated into a **`reasoning`** field, not `reasoning_content` (`server.py:1510-1511`). The harness must accept that name. Assistant history is read back through `message.reasoning_content` (`chat_template.jinja:111-117`). |
| G5 Context ≥ 64K | **Unknown, verify. Expected to fit.** | There is no context cap and no max-kv flag in the server (`server.py:1923-2078`). `KVCache` grows without a limit (`models/qwen3_5.py:347-348`). `max_position_embeddings` is 262144. Estimated KV for the 16 full-attention layers × 4 KV heads × 256 dim × K and V × bf16 is 64 KiB per token, so about 4 GiB at 64K and 8 GiB at 128K. The 48 GDN layers add a fixed state per sequence, roughly 70–150 MB (estimate, dtype not verified). Weights are 29.5 GB at 8-bit. The total stays below the 115.4 GB wired limit, but prompt-cache entries add to it (section 6). Record the peak from `vm_stat` or Activity Monitor and the `Prompt Cache: … GB` log lines (`server.py:563-572`). |

## 6. Prompt cache across requests (hybrid GDN): critical for M1 and M4

How it works:

- Qwen3.5 makes `ArraysCache(size=2)` for each GDN layer and `KVCache` for each
  full-attention layer (`models/qwen3_5.py:347-348`).
- `ArraysCache` does not override `is_trimmable`, so it inherits `False` from
  `_BaseCache` (`cache.py:164-165`). That makes `can_trim_prompt_cache()` False for the
  whole model (`cache.py:115-119`).
- Both cache types implement `merge` (`cache.py:410`, `cache.py:698`). So the model is
  batchable (`server.py:459-463`) and plain text requests use the `BatchGenerator` path.
- `LRUPromptCache.fetch_nearest_cache` (`cache.py:1652-1672`) handles three cases:
  - **Exact match:** a deep copy of the whole cache, with no prefill.
  - **A stored entry is a strict prefix of the new prompt:** that entry is reused and only
    the remaining tokens are prefilled. This works for hybrid models.
  - **A stored entry is longer than, or diverges from, the new prompt:** reuse requires
    trimming. For hybrid models this case is skipped and the lookup falls through to a
    shorter entry, or to none.
- Prefix entries are not pruned for non-trimmable caches (`cache.py:1699-1703`), so the
  entry count grows faster. Eviction is LRU with the type order assistant, then user,
  then system (`cache.py:1606-1640`).
- **Segment checkpoints** apply on the batched path, when the last message has role
  `user` and the prompt has no images. The prompt is split into a system segment, a user
  segment, and a thinking tail of up to 11 tokens (`server.py:701-750`). A cache snapshot
  is saved at the end of each segment (`server.py:954-970`). When a request finishes,
  its prompt plus generated tokens are saved as an `assistant` entry (`server.py:1001-1008`).

What this means for the metrics:

- **M1 (fixed ≈15K system + tools prefix):** the system segment covers the system
  message and the tool schemas, because Qwen renders tools into the system turn
  (`chat_template.jinja:57-75`). It is checkpointed, and later trials reuse it as a
  "shorter" hit. Cached tokens should be about the prefix length.
  - **Precondition:** the checkpoint is created only by a request whose last message has role
    `user` (`server.py:703-704`). So the M1 warm-up request must end with a user message,
    even if the trials end with a `tool` message. Otherwise every trial reports
    `cached_tokens=0`.
  - M1 as specified includes a screenshot, which G2 rejects, so only a text-only variant can
    run on mlx-lm.
  - Switching thinking on or off changes the system turn: thinking-on injects the xhigh
    instruction (section 1). The two modes therefore never share a system-prefix entry.
- **M4 as specified (one screenshot per step) cannot run on mlx-lm at all.** Every step
  carries an image, and G2 rejects images. Only a text-only trajectory can be measured, as
  a reference row.
- **M4 (trajectory) risk:** agent steps usually end with a `tool` message. With no `user`
  last message, no segmentation happens (`server.py:703-704`), so only the final
  prompt-plus-completion entry is saved. The next step reuses it only if the template
  re-renders the previous assistant turn **token-identically** to what the model
  generated (`chat_template.jinja:116-145`). With thinking off, the empty
  `<think>\n\n</think>\n\n` block matches. Re-rendered tool calls can differ in
  parameter order, whitespace or `tojson` formatting. If they differ, the lookup falls
  back to an older entry, and because the cache cannot be trimmed, latency then grows with
  history. Check the per-step `cached_tokens` values.
- **Requests that go through `_serve_single`** are those with images, a `seed`, `--kv-bits`
  or a draft model (`server.py:768-773`, `817-820`, `904-906`). They save only the final
  cache (`server.py:1144-1147`), with no segment checkpoints. **The harness must not send
  `seed`.**
- **Reporting:** `usage.prompt_tokens_details.cached_tokens` is the number of prompt
  tokens taken from the cache (`server.py:846`, `1076`). Non-streaming responses always
  include it (`server.py:1494-1497`). Streaming responses include it only with
  `stream_options: {"include_usage": true}`, as a final chunk with empty `choices`
  (`server.py:1682-1692`, `1720-1743`). Do not send `stream_options` without the
  `include_usage` key: the code indexes `["include_usage"]` directly.
- **Memory:** every hit is `copy.deepcopy`'d (`cache.py:1656`, `1670`), so a large entry is
  briefly held twice.

## 7. Speculative decoding and MTP

- **Off is the only mode.** `--draft-model` and `--num-draft-tokens` exist
  (`server.py:1952-1963`), but `speculative_generate_step` raises "Speculative decoding
  requires a trimmable prompt cache" for `ArraysCache` (`generate.py:542-545`).
- There is no MTP path. `mtp.*` weights are dropped at sanitize
  (`models/qwen3_5.py:354`), and this checkpoint has none anyway.
- A draft model would also force sequential serving (`server.py:460`). M3 "spec on" is
  therefore N/A for mlx-lm, which matches METHODOLOGY.

## 8. Concurrency (M5)

Plain text requests are batched by default: up to 32 decoding at once
(`--decode-concurrency`) and 8 prompts in prefill at once (`--prompt-concurrency`)
(`server.py:2024-2035`, `912-918`). A request with images or a seed, or a server started
with `--kv-bits` or a draft model, drains the batch and is served alone
(`server.py:922-927`).

## 9. Caveats

- Errors raised during tokenization or by the template come back as **HTTP 404** with a
  JSON `error` (`server.py:1577-1581`). Bad sampling parameters give 400
  (`server.py:1331-1337`). Do not treat a 404 as "endpoint missing" without reading the body.
- A tool call that fails to parse is **dropped with only a log warning**
  (`server.py:90-97`). Count it as an M7 failure. Check the server log too.
- The sampling defaults come from the CLI (temp 0, top_p 1, top_k 0), not from
  `generation_config.json` (temperature 1.0, top_k 20, top_p 0.95)
  (`server.py:1312-1317`).
- SSE progress lines (`: keepalive N/M`) are written during long prefills
  (`server.py:1563-1568`). They are comments, not data. TTFT must ignore them, as
  METHODOLOGY already says.
- `GET /v1/models` scans the whole HF cache with `scan_cache_dir()`
  (`server.py:1838-1842`). That is read-only but slow on a large cache. Do not use it as a
  health probe.
- The server is meant for development only (`server.py:1894-1897`). Bind it to 127.0.0.1.

## 10. Status / remaining work

Done (23:25): venv and editable install, versions above, `--help` checks, source review
for all research questions.

Not done. No model was loaded and no gate test has run. To resume:

1. Take the GPU lock (`~/Developer/mlsys/experiments/.gpu-lock`). Check that ports 8500
   and 8701 have no listener.
2. Start the server with the command in section 3 (8-bit). Wait for `/health` to return
   `ok`. Record peak memory after loading.
3. Run the G1–G5 probes with the harness: tool-call stream assembly; an image request,
   expected 404 "Only 'text'…"; `POST /v1/messages`, expected 404; thinking with
   `enable_thinking` true and false, top-level `reasoning_effort`, and `reasoning_effort`
   inside `chat_template_kwargs`; a 64K prompt with `max_tokens=1`, recording memory.
   Write `mlx-lm/capabilities.md`.
4. Check the cache in the logs: two requests with the same system prefix should show
   `cached_tokens` ≈ prefix length. Run a 3-step tool-role trajectory to see whether
   `cached_tokens` keeps up with the history.
5. Run the direct-call commands in section 4 for the 8-bit row, then the HTTP metrics.
   Release the lock.
6. The 4-bit row is blocked until `mlx-community/Qwen3.8-27B-4bit` is downloaded
   (`scripts/download_models.sh core`). Then repeat steps 2–5 with that snapshot.
7. If the venv must be rebuilt, run the install commands in section 1 (about 96 MiB of
   downloads).

## Smoke test, 2026-10-18 00:35 (8-bit, manual, not timed)

`mlx_lm.server` was started with the launch command above, against the 8-bit HF snapshot;
it was ready in about 6 s. Requests sent `model: "default_model"`. These are first-request
timings, not benchmark numbers.

| Probe | Result |
| --- | --- |
| Streaming text | OK, TTFT 1.44 s |
| Streaming tool call | OK: `get_weather {"city": "Paris", "unit": "c"}`, `finish_reason=tool_calls`. The whole call arrives in a single delta at the end of generation, so "TTFT" for a tool-only reply is ≈ end-to-end (2.80 s vs 2.85 s). |
| Image | HTTP 404 `Only 'text' content type is supported.` — G2 fails, as predicted |
| Thinking on | Reasoning returned in the `reasoning` field |
| `/v1/messages` | HTTP 404 — G3 fails, as predicted |
