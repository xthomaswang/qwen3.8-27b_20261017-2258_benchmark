# Superseded runs

Verified runs (quiet machine, battery at 90 % or more) that a later run of the same suite
replaced. `summary.md` and `capabilities.md` use the newer run. These are kept for the
record.

The gates here ran before commit `e495e19`. That commit changed G3's tool_result-image drop
check to add up `input_tokens`, `cache_creation_input_tokens` and `cache_read_input_tokens`,
because every framework here splits Anthropic usage across those fields. These older runs
compared `input_tokens` only, so their G3 token counts are not comparable. Their verdicts
are the same as the newer runs'.
