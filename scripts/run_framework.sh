#!/usr/bin/env bash
# Run one framework variant end to end: serve -> wait -> warm-up -> one `agentbench run-all` per suite -> stop.
# The main agent must already hold the GPU lock (scripts/gpu_lock.sh acquire ...); this script never takes it.
# Usage: run_framework.sh <framework> <variant> <tier> <profile> <tag> <suites> [extra run-all args...]
#   e.g. run_framework.sh llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on m1,m3,m4,m7 --spec-label on
#
# Quiet-machine rule (METHODOLOGY.md):
# - Before each suite: wait until quiet_check passes (QUIET_WAIT_S, default 600 s); give up otherwise.
# - The harness pre-flight (quiet_check --settle 90) is stored in each raw file's header.
# - quietlib.py monitor samples every 10 s for the whole run (<fw>/raw/monitor-<tag>-<ts>.tsv).
#   A suite with a DISTURBED sample in its window is moved to raw/_unverified/ and run again
#   (QUIET_RETRIES, default 1). State changes are printed to logs/monitor-<fw>-<tag>.events.
# - summary.md is regenerated at the end from the verified files only.
# - `caffeinate -u` declares user activity for the whole run. macOS then defers discretionary
#   background work (suggestd harvesting, mediaanalysisd, Spotlight) that otherwise starts on an
#   idle machine on AC power; the one-off burst it triggers is absorbed by the pre-serve wait.
# Per-suite extra arguments: SUITE_ARGS_<suite>, e.g. SUITE_ARGS_m7="--trials 1".
# RUN_UNVERIFIED=1: a mechanics check. Everything goes to raw/_unverified/, summary.md is untouched,
#   quiet checks are reported but never block (short waits), and nothing is repeated.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
[ $# -ge 6 ] || { sed -n 2,5p "$0"; exit 2; }
fw=$1 variant=$2 tier=$3 profile=$4 tag=$5 suites=$6; shift 6
UNV=${RUN_UNVERIFIED:-0}
if [ "$UNV" = 1 ]; then WAIT_S=${QUIET_WAIT_S:-20} PRE_S=20 HP_S=10 RETRIES=0
else WAIT_S=${QUIET_WAIT_S:-600} PRE_S=${QUIET_PRESERVE_S:-300} HP_S=60 RETRIES=${QUIET_RETRIES:-1}; fi
PY=/usr/bin/python3
ts() { date '+%T'; }
grep -q '^holder: local_ai-benchmark session' "$HOME/Developer/mlsys/experiments/.gpu-lock" 2>/dev/null \
  || { echo "run_framework: the GPU lock is not held by us; acquire it first" >&2; exit 5; }
dry=$(scripts/serve.sh "$fw" "$variant" "$tier" --dry-run) || { echo "$dry" | tail -5; exit 4; }
model=$(printf '%s\n' "$dry" | sed -n 's/^ *# model id: *//p' | head -1)
base=$(printf '%s\n' "$dry" | sed -n 's/^ *# endpoint: *//p' | head -1 | sed 's#/v1$##')
port=${base##*:}
raw="$ROOT/$fw/raw"; mkdir -p "$raw" logs
vdir="$raw" unv_arg="" move_arg="--move"
[ "$UNV" = 1 ] && { vdir="$raw/_unverified" unv_arg="--unverified" move_arg=""; mkdir -p "$vdir"; }
echo "$(ts) run_framework: $fw $variant $tier, tag $tag, suites $suites"
caffeinate -u -t 86400 -w $$ > /dev/null 2>&1 &
sleep "${USER_ACTIVE_SETTLE_S:-45}"   # declaring activity sets off a ~30 s "user returned" burst; let it pass
# Before loading anything: the GPU must be idle with no other model resident.
if ! scripts/quiet_check.sh --allow-pid $$ --settle "$PRE_S" --max-gpu-gb "${QUIET_MAX_GPU_GB_IDLE:-6}" > "logs/quiet-$fw-$tag.preserve" 2>&1; then
  echo "$(ts) machine not quiet before serving:"; sed 's/^/  /' "logs/quiet-$fw-$tag.preserve"
  [ "$UNV" = 1 ] || { echo "$(ts) nothing started"; exit 6; }
fi
scripts/serve.sh "$fw" "$variant" "$tier" > /dev/null 2>&1 &
mon=""
cleanup() { [ -z "$mon" ] || kill "$mon" 2>/dev/null; scripts/stop_server.sh "$fw" --children; }
trap 'cleanup; exit 130' INT TERM
sleep 2
scripts/wait_ready.sh "$port" 1800 || { scripts/stop_server.sh "$fw" --children; exit 3; }
pid=$(cat "logs/$fw.pid")
flags=$(grep -v '^#' "logs/$fw-$variant-$tier.cmd" | tail -1 | sed "s|$HOME|~|g")
version=$(grep -m1 '# framework:' "logs/$fw-$variant-$tier.cmd" | sed 's/.*# framework: *//')
echo "$(ts) server pid $pid; process tree: $(pgrep -P "$pid" | tr '\n' ' ')"
# Warm-up: one short request so model load / first-request compilation never lands in a measurement.
warm_model="$model"; [ "$profile" = mlxlm ] && warm_model=default_model
curl -s -m 900 "$base/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$warm_model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with: ok\"}],\"max_tokens\":8,\"temperature\":0}" \
  -o /dev/null -w "$(ts) warm-up: HTTP %{http_code} in %{time_total}s\n"

mon_tsv="$vdir/monitor-$tag-$(date +%Y%m%d-%H%M%S).tsv"
events="logs/monitor-$fw-$tag.events"
start_monitor() {
  "$PY" -I scripts/quietlib.py monitor --log "$mon_tsv" --interval 10 --allow-pid $$ --until-pid $$ >> "$events" 2>&1 &
  mon=$!
}
: > "$events"; start_monitor

rc=0 verified=0
for s in $(printf '%s' "$suites" | tr ',' ' '); do
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    kill -0 "$pid" 2>/dev/null || { echo "$(ts) server $pid is gone; stopping before $s"; rc=1; break 2; }
    kill -0 "$mon" 2>/dev/null || { echo "$(ts) monitor had exited (see $events); restarted"; start_monitor; sleep 11; }
    if ! scripts/quiet_check.sh --allow-pid $$ --settle "$WAIT_S" > "logs/quiet-$fw-$tag.last" 2>&1; then
      echo "$(ts) not quiet after ${WAIT_S}s before $s. Last check:"; sed 's/^/  /' "logs/quiet-$fw-$tag.last"
      [ "$UNV" = 1 ] || { echo "$(ts) stopping"; rc=1; break 2; }
    fi
    sv="SUITE_ARGS_$s"; sargs=${!sv:-}
    echo "$(ts) == $s (attempt $attempt)${sargs:+, $sargs} =="
    t0=$(date +%s)
    (cd harness && uv run agentbench run-all --profile "$profile" --base-url "$base" --model "$model" \
      --framework "$fw" --framework-version "$version" --launch-flags "$flags" --tag "$tag" \
      --server-pid "$pid" --suites "$s" --preflight \
      --preflight-cmd "$ROOT/scripts/quiet_check.sh --settle $HP_S --allow-pid $$" $unv_arg "$@" $sargs) > "logs/run-$fw-$tag-$s.log" 2>&1
    src=$?
    grep -E "^(preflight|.* failed:)" "logs/run-$fw-$tag-$s.log" | sed 's/^/  /'
    sleep 11   # let the monitor take one more sample after the suite's last write
    vout=$("$PY" -I scripts/quietlib.py verify --log "$mon_tsv" --raw-dir "$vdir" --since "$t0" $move_arg)
    [ -z "$vout" ] || printf '%s\n' "$vout" | sed 's/^/  /'
    [ "$UNV" = 1 ] && { echo "$(ts) $s: mechanics check done (harness rc $src)"; [ "$src" -eq 0 ] || rc=1; break; }
    if printf '%s\n' "$vout" | grep -q "^verify: $s-$tag-[0-9-]*\.jsonl: quiet"; then
      verified=$((verified + 1)); echo "$(ts) $s: verified (harness rc $src)"
      [ "$src" -eq 0 ] || rc=1
      break
    fi
    if [ "$src" -ne 0 ] && ! printf '%s\n' "$vout" | grep -q DISTURBED \
       && ! grep -q "preflight: machine is NOT quiet" "logs/run-$fw-$tag-$s.log"; then
      echo "$(ts) $s: harness error (rc $src), not a disturbance; not repeated (logs/run-$fw-$tag-$s.log)"; rc=1; break
    fi
    [ "$attempt" -gt "$RETRIES" ] && { echo "$(ts) $s: disturbed on every attempt; left in raw/_unverified/"; rc=1; break; }
    echo "$(ts) $s: disturbed (monitor or pre-flight); repeating"
  done
done

kill "$mon" 2>/dev/null; wait "$mon" 2>/dev/null
if [ "$UNV" = 1 ]; then
  echo "$(ts) mechanics check: results stay in raw/_unverified/; summary.md untouched"
elif [ "$verified" -gt 0 ]; then
  (cd harness && uv run agentbench summarize --framework "$fw" --tag "$tag" --write) > "logs/summarize-$fw-$tag.log" 2>&1 \
    && echo "$(ts) summary.md regenerated for tag $tag" || { echo "$(ts) summarize failed (logs/summarize-$fw-$tag.log)"; rc=1; }
else
  mkdir -p "$raw/_unverified"; mv "$mon_tsv" "$raw/_unverified/" 2>/dev/null
fi
scripts/stop_server.sh "$fw" --children
echo "$(ts) run_framework: done, $verified verified suite(s), rc $rc"
exit $rc
