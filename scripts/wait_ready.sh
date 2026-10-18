#!/usr/bin/env bash
# wait_ready.sh <port> <timeout-s>
#
# Polls a benchmark server on 127.0.0.1 until it is ready, every 2 s. Readiness per port:
#   8701 mlx-lm        GET /health 200. It answers ok while the model is still loading
#                      (no load signal exists); the first request waits for the load.
#   8702 llama-server  GET /health 200 (503 while the model loads).
#   8703 oMLX          GET /health 200 and the model listed in GET /v1/models. Models load
#                      on the first request (none is pinned).
#   8704 lithos-metal  GET /health 200. The port opens only after packing and warmup.
#   8705 vLLM-Metal    GET /health 200 (503 until the engine is up).
# The harness warm-up request absorbs any remaining load time (8701, 8703).
# Fails early if the PID in logs/<framework>.pid exits.
# Exit codes: 0 ready, 1 timeout, 2 usage, 3 the server process exited.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 2 ] || { print_header "${BASH_SOURCE[0]}" >&2; exit "$EX_USAGE"; }
PORT=$1 TIMEOUT=$2
case "$PORT$TIMEOUT" in *[!0-9]*|'') die "$EX_USAGE" "port and timeout must be whole numbers" ;; esac
FW=$(port_fw "$PORT" || true)
PIDF=''; [ -z "$FW" ] || PIDF=$(pidfile_of "$FW")
BODY=$(mktemp "${TMPDIR:-/tmp}/wait_ready.XXXXXX")
trap 'rm -f "$BODY"' EXIT

get() {  # get <path>: sets CODE; body in $BODY
  CODE=$(curl -s --noproxy '*' --max-time 5 -o "$BODY" -w '%{http_code}' "http://127.0.0.1:$PORT$1" 2>/dev/null || true)
  [ -n "$CODE" ] || CODE=000
}
model_ids() { "$PY" -I -c 'import json, sys
try:
    print(" ".join(m.get("id", "?") for m in json.load(open(sys.argv[1])).get("data", [])))
except Exception:
    pass' "$BODY"; }

STATUS='no answer yet'
probe() {
  local ids
  if [ "$FW" = mlc-llm ]; then   # MLC serves no /health; /v1/models answers once the engine is up
    get /v1/models
    case "$CODE" in 200) ids=$(model_ids); STATUS="models: ${ids:-?}"; return 0 ;; 000) STATUS='connection refused (not listening yet)'; return 1 ;; *) STATUS="/v1/models $CODE"; return 1 ;; esac
  fi
  get /health
  case "$CODE" in
    200) ;;
    000) STATUS='connection refused (not listening yet)'; return 1 ;;
    503) STATUS='health 503 (loading)'; return 1 ;;
    *) STATUS="health $CODE"; return 1 ;;
  esac
  case "$FW" in
    mlx-lm) STATUS='health ok (model may still be loading; do not probe /v1/models, it scans the HF cache)'; return 0 ;;
    omlx)
      get /v1/models
      ids=''; [ "$CODE" != 200 ] || ids=$(model_ids)
      [ -n "$ids" ] || { STATUS="health ok, /v1/models $CODE with no models"; return 1; }
      STATUS="models: $ids (loaded on first request)"; return 0 ;;
    *)
      get /v1/models
      ids=''; [ "$CODE" != 200 ] || ids=$(model_ids)
      STATUS="health ok${ids:+, models: $ids}"; return 0 ;;
  esac
}

START=$(now_s)
say "waiting for ${FW:-unknown framework} on 127.0.0.1:$PORT (timeout ${TIMEOUT}s)"
while :; do
  if probe; then
    say "ready after $(( $(now_s) - START ))s: $STATUS"
    exit 0
  fi
  if [ -n "$PIDF" ] && [ -f "$PIDF" ] && ! pid_alive "$(head -1 "$PIDF")"; then
    say "the $FW server (PID $(head -1 "$PIDF")) exited before it became ready; last log lines:"
    CMDF=$(ls -t "$LOG_DIR/$FW"-*.cmd 2>/dev/null | head -1 || true)
    LAST=''; [ -z "$CMDF" ] || LAST="$BENCH_DIR/$(sed -n 's/^# log: *//p' "$CMDF" | head -1)"
    if [ -f "$LAST" ]; then say "  (${LAST#"$BENCH_DIR"/})"; tail -n 20 "$LAST" | sed 's/^/  /'; fi
    exit 3
  fi
  if [ $(( $(now_s) - START )) -ge "$TIMEOUT" ]; then
    say "timeout after ${TIMEOUT}s: $STATUS"
    exit 1
  fi
  sleep 2
done
