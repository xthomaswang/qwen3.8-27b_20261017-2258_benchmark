# coreai

- [summary.md](summary.md): read-first notes, the `llm-server` gate in brief, and the
  direct-call A/B against `mlx_lm.benchmark`.
- [capabilities.md](capabilities.md): the `llm-server` capability gate (G1–G5) per tag.
- [env.md](env.md): install, the 27B export, benchmark commands, and the gate expectations
  from the source.
- `raw/`: one JSONL file per run, whose header holds the commands, the provenance and the
  quiet pre-flight, plus the monitor TSV of the block.

Results landed through pull request #8 (the direct-call A/B) and pull request #10 (the
`llm-server` gate). No metric suite ran on `llm-server`: the campaign closed after the gate.
