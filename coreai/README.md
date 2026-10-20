# coreai

- [summary.md](summary.md): read-first notes and the direct-call A/B against `mlx_lm.benchmark`.
- [env.md](env.md): install, the 27B export, benchmark commands, and the gate expectations
  from the source.
- `raw/`: one JSONL file per run, whose header holds the commands, the provenance and the
  quiet pre-flight, plus the monitor TSV of the block.

Results landed through pull request #8 (a direct-call reference row; the `llm-server` gate follows).
