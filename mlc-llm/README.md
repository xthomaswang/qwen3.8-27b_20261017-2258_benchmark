# mlc-llm

- [summary.md](summary.md): read-first notes, then the result tables per tag.
- [capabilities.md](capabilities.md): the capability gate (G1–G5) per tag.
- [env.md](env.md): source build, compile, launch flags, and notes from the source.
- `raw/`: one JSONL file per suite run, whose header holds the server flags and the machine
  state, plus the monitor TSVs.

Results land through pull request #9 (a text-only reference row): the gate, then M1–M3 from a
trimmed text-only set. M7 did not complete; the campaign closed on 2026-10-21.
