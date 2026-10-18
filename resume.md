# Resume — current progress

Updated: 2026-10-17 23:25 (local). Rewritten after every major phase. Read this first when
picking the work back up.

## Phase status

| # | Phase | Status |
| --- | --- | --- |
| 0 | Plan, repo scaffold, methodology | **done**. Repo public at github.com/xthomaswang/qwen3.8-27b_20261017-2258_benchmark |
| 1 | Framework installs + flag research (parallel agents, no GPU) | **in progress** |
| 2 | Harness + fixtures (mock-server tested) | **in progress** |
| 3 | Gate G1–G5, per framework | pending |
| 4 | Metrics M1–M7, per framework, one `bench/<framework>` PR each | pending |
| 5 | Summary comparison PR + summary sent to the agent-benchmark session | pending |

## Decisions so far

- **Model.** Qwen3.8-27B.
  - The primary tier is 4-bit.
  - The MLX stacks also get an 8-bit row, which is the checkpoint the agent benchmark uses.
  - **Ordering changed:** the 8-bit rows run first, because they are the only checkpoint
    already on disk.
- **Large downloads are paused at the user's request.** The network measured ~0.5 MB/s
  (HF 0.45 MB/s, Cloudflare 0.58 MB/s).
  - Partial blobs are kept in the HF cache and resume later:
    - unsloth GGUF: 512 MB of 16.5 GB
    - DSpark head: started
    - MLX 4-bit: not started
  - Resume with `scripts/download_models.sh core gguf`; `extra` covers NVFP4 + BF16.
- **Framework sources and venvs** live in `~/Developer/mlsys/serving/<framework>`, at the
  user's request; this repo holds only the experiment.

  | Framework | Location | Version |
  | --- | --- | --- |
  | llama.cpp | `serving/llama.cpp` | b11717, commit 848bbda; built with Metal (`build/bin`) |
  | oMLX | `serving/omlx_0.7` | v0.7.1rc1, commit 7a5a3d75; isolated base path `.bench-home/` |
  | lithos-metal | `serving/lithos-metal` | v0.1.2, commit 46b2bc4c |
  | vLLM-Metal | `serving/vllm-metal` | v0.31.0, commit e7a0c90b |
  | mlx-lm | `serving/mlx-lm` | v0.32.2, commit 93e6d4a6 |

  `serving/omlx` (0.3.9) belongs to the agent-benchmark session and is never touched.
- **Core AI is reference only.** It has no HTTP server, and its BF16 source download is
  paused.

## Coordination rules (agent-benchmark session "Meta Muse 本地替代方案")

- **Ports.** We use 8701 mlx-lm, 8702 llama-server, 8703 oMLX, 8704 lithos-metal,
  8705 vLLM-Metal. Never 8500 or 8600–8699.
- **GPU lock.** Timed segments hold `~/Developer/mlsys/experiments/.gpu-lock`, which
  records the session name, purpose, start time and ETA. Before starting, check
  `lsof -nP -iTCP:8500 -sTCP:LISTEN`; if anything is listening there, ask that session to
  stop it. Delete the lock as soon as the segment ends.
- **Never touch:** `~/.omlx`, `serving/omlx`, the `mlsys` conda env, the
  `models/hf` links, existing HF cache entries, or `experiments/personal-agent-bench`.
- **Git hygiene.**
  - Repo files are in English.
  - Commit messages carry no co-author trailer.
  - Never commit real agent traces or real screenshots (`fixtures/real/` is gitignored).

## Open questions for the user

1. **Large downloads.** When may they resume? With no downloads at all:
   - lithos-metal can only run off a locally re-quantized 8→4-bit checkpoint, and only
     target-only, since the DSpark head is 1.1 GB.
   - llama.cpp needs either the 16.5 GB GGUF or a local conversion chain.
2. **Merging.** Should results PRs be merged by me, or left open for review?

## Next steps

1. Collect the agent reports: env.md drafts and the harness. Review them, then commit
   the harness to main.
2. Run the gate, then the metrics, with the 8-bit rows first: oMLX → vLLM-Metal → mlx-lm.
   Each run is followed by a `bench/<framework>` PR.
3. lithos-metal and llama.cpp follow once checkpoints are available.
