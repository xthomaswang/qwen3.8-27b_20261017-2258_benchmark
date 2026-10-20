# lithos-metal

- [summary.md](summary.md): read-first notes, then the result tables per tag.
- [capabilities.md](capabilities.md): the capability gate (G1–G5) per tag.
- [env.md](env.md): install, launch flags, and notes from the source.
- [lm_head_rename.patch](lm_head_rename.patch): the one local change, which binds the untied MLX head.
- `raw/`: one JSONL file per suite run, whose header holds the server flags and the machine
  state, plus the monitor TSVs.

Results land through the `bench/lithos-metal` pull request (a text-only reference row).
