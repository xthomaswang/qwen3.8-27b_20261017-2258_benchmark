# llama.cpp

- [summary.md](summary.md): read-first notes, then the result tables per tag.
- [capabilities.md](capabilities.md): the capability gate (G1–G5) per tag.
- [env.md](env.md): install, launch flags, and notes from the source.
- `raw/`: one JSONL file per suite run, whose header holds the server flags and the machine
  state, plus the monitor TSVs. `raw/superseded/` keeps runs replaced by a later one.

Results landed through pull requests #1 (Tier-1, 4-bit) and #4 (Tier-2), and #7 (Tier-3: Q8_0 with MTP, temperature 1.0).
