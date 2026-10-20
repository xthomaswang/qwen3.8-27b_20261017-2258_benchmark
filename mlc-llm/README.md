# mlc-llm

- [summary.md](summary.md): read-first notes, then the result tables per tag.
- [capabilities.md](capabilities.md): the capability gate (G1–G5) per tag.
- [env.md](env.md): source build, compile, launch flags, and notes from the source.
- `raw/`: one JSONL file per suite run, whose header holds the server flags and the machine
  state, plus the monitor TSVs.

Results land through the `bench/mlc-llm` pull request (a text-only reference row). The gate
is in; the text-only metric suites follow.
