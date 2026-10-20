#!/usr/bin/env bash
# M8, the interference study, for one framework variant (METHODOLOGY.md, section 4): one server launch,
# blocks B S1 B S2 ... Sn B (B = clean baseline, S = a load from scripts/interference.py), each running
# the same suites: M1 warm TTFT, an M3 subset and a shortened M4.
# The main agent must already hold the GPU lock; like run_framework.sh, this script only releases and
# retakes it for a battery pause before the server starts.
# Usage: run_m8.sh <framework> <variant> <tier> <profile> <tag> [extra run-all args...]
#   e.g. run_m8.sh llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on --spec-label on
#        M8_SCENARIOS="cpu1 cpuall" run_m8.sh omlx spec-off 4bit omlx 4bit-spec-off --spec-label off
#        M8_DRY_RUN=1 run_m8.sh ...    (prints the plan and the load parameters; starts nothing)
# Raw files: <fw>/raw/<suite>-<tag>-m8-base-<ts>.jsonl and <suite>-<tag>-m8-<scenario>-<ts>.jsonl, and one
# monitor TSV per block. Table: (cd harness && uv run agentbench m8-report [--tag <tag>] [--details]).
#
# Per block, in order:
#   1. Server idle, no load: wait for the battery (>= QUIET_MIN_BATTERY %), then the strict quiet check,
#      unchanged (no allowances): the machine is clean before any load starts.
#   2. S only: start the load (one process tree; its root PID is in logs/m8-load.pid and in the block's
#      monitor TSV header), wait until it is ready, start the block's monitor (load PID exempt,
#      allowances), and let it settle M8_SETTLE_S (default 60).
#   3. Each suite as in run_framework.sh: quiet check (load PID exempt, allowances), the harness with
#      --preflight (the same check, stored in the header), --interference (scenario, parameters,
#      allowances, load PID, block, run) and --no-summary (M8 tags stay out of summary.md), verify
#      against the block's monitor, one repeat when disturbed. A suite during which the load stopped
#      is moved to raw/_unverified/ and the block ends.
#   4. S only: stop the load, then cool down M8_COOL_S (default 60) before the next block's check.
# The battery is checked at the block start only (a load drains it; the monitor's 20 % rule still
# holds), for baseline and scenario blocks alike.
# Allowances (`interference.py allowances <scenario>`: load, gpu, thermal, lowpower) reach quietlib as
# --allow and are recorded in the check output, the monitor TSV header and the raw header. The load's
# processes are exempt by PID; every other process is judged as always.
# power: no script runs sudo. The load prints "ACTION NEEDED: ... sudo pmset -a lowpowermode 1" and
# waits up to M8_POWER_WAIT_S (default 1800 s); if nobody runs it, the block is skipped. After the
# block, the restore command for this machine is printed and the runner waits as long again for High
# Power on AC; without it the run ends there (the next baseline cannot run). power comes last by
# default; for an unattended run leave it out and run M8_SCENARIOS=power when the user is present.
# Environment:
#   M8_SCENARIOS  default "cpu1 cpuhalf cpuall gpu disk mem power"
#   M8_SUITES     default m1,m3,m4. SUITE_ARGS_<suite> replaces a suite's M8 defaults: m1 "--cold-trials 0",
#                 m3 "--contexts 16000 --caps 150 --no-thinking-bucket --trials 5", m4 "--runs 1"
#   M8_LOAD_ARGS_<scenario>  extra `interference.py start` options, e.g. M8_LOAD_ARGS_gpu="--duty 0.3"
#   M8_SETTLE_S, M8_COOL_S, M8_POWER_WAIT_S, M8_READY_WAIT_S (default 300 s for a load to be ready),
#   M8_SAMPLE_LAG_S (default 11: the wait for one more monitor sample before verify; tests shorten it)
#   QUIET_*, BATTERY_*, USER_ACTIVE_SETTLE_S, RUN_UNVERIFIED=1 and logs/hold as in run_framework.sh
# The server bring-up and the suite loop mirror run_framework.sh; keep the two in step.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
[ $# -ge 5 ] || { sed -n 2,10p "$0"; exit 2; }
fw=$1 variant=$2 tier=$3 profile=$4 tag=$5; shift 5
PY=/usr/bin/python3
lf() { "$PY" -I scripts/interference.py "$@"; }
SCEN=${M8_SCENARIOS:-"cpu1 cpuhalf cpuall gpu disk mem power"}
SUITES=${M8_SUITES:-m1,m3,m4}
SETTLE_S=${M8_SETTLE_S:-60} COOL_S=${M8_COOL_S:-60} POWER_WAIT_S=${M8_POWER_WAIT_S:-1800} READY_S=${M8_READY_WAIT_S:-300}
LAG_S=${M8_SAMPLE_LAG_S:-11}   # one monitor interval plus a second: a sample after the suite's last write
M8_ARGS_m1="--cold-trials 0"
M8_ARGS_m3="--contexts 16000 --caps 150 --no-thinking-bucket --trials 5"
M8_ARGS_m4="--runs 1"
UNV=${RUN_UNVERIFIED:-0}
if [ "$UNV" = 1 ]; then WAIT_S=${QUIET_WAIT_S:-20} PRE_S=20 HP_S=10 RETRIES=0 BATT_WAIT_S=0
else WAIT_S=${QUIET_WAIT_S:-600} PRE_S=${QUIET_PRESERVE_S:-300} HP_S=60 RETRIES=${QUIET_RETRIES:-1}
  BATT_WAIT_S=${QUIET_BATTERY_WAIT_S:-5400}; fi
MIN_BATT=${QUIET_MIN_BATTERY:-40}
ts() { date '+%T'; }
sargs_of() { local v="SUITE_ARGS_$1" d="M8_ARGS_$1"; if [ -n "${!v:-}" ]; then printf '%s' "${!v}"; else printf '%s' "${!d:-}"; fi; }
largs_of() {   # power waits as long as the runner does; M8_LOAD_ARGS_<scenario> come last and win
  local v="M8_LOAD_ARGS_$1"
  [ "$1" = power ] && printf -- '--wait %s ' "$POWER_WAIT_S"
  printf '%s' "${!v:-}"
}

blocks=base
for s in $SCEN; do
  case $s in base) echo "run_m8: 'base' is not a scenario"; exit 2 ;; esac
  lf allowances "$s" > /dev/null 2>&1 || { echo "run_m8: unknown scenario '$s'"; exit 2; }
  blocks="$blocks $s base"
done
nb=$(echo $blocks | wc -w | tr -d ' ')

if [ "${M8_DRY_RUN:-0}" = 1 ]; then
  echo "run_m8 plan: $fw $variant $tier (profile $profile), tag $tag, $nb blocks: $blocks"
  for s in $(printf '%s' "$SUITES" | tr ',' ' '); do echo "  suite $s: $(sargs_of "$s") $*"; done
  i=0
  for b in $blocks; do
    i=$((i + 1))
    if [ "$b" = base ]; then echo "  block $i/$nb base: tag $tag-m8-base, no load"; continue; fi
    p=$(lf start "$b" --dry-run $(largs_of "$b")) || exit 2
    echo "  block $i/$nb $b: tag $tag-m8-$b, allowances $(lf allowances "$b"), settle ${SETTLE_S}s, cool-down ${COOL_S}s; $p"
  done
  exit 0
fi

LOCKFILE="$HOME/Developer/mlsys/experiments/.gpu-lock"
hold_wait() {   # the driving session's work window (logs/hold), as in run_framework.sh; here also between blocks
  [ -e logs/hold ] || return 0
  echo "$(ts) HOLD: logs/hold exists; waiting before $1"
  while [ -e logs/hold ]; do sleep 15; done
  echo "$(ts) HOLD released"
}
hold_wait "$fw $variant $tier (M8)"
batt_pct() { pmset -g batt | grep -o '[0-9]*%' | head -1 | tr -d %; }
# Battery pause before the server starts, as in run_framework.sh. An M8 run is a long step (about two
# hours), so it needs BATTERY_PAUSE_LONG % (default 60) to start.
if [ "$UNV" != 1 ] && grep -q '^holder: local_ai-benchmark session' "$LOCKFILE" 2>/dev/null; then
  need=${BATTERY_PAUSE_LONG:-60}
  b=$(batt_pct)
  if [ -n "$b" ] && [ "$b" -lt "$need" ]; then
    purpose=$(sed -n 's/^purpose: //p' "$LOCKFILE")
    eta_iso=$(sed -n 's/^eta: \([^ ]*\).*/\1/p' "$LOCKFILE")
    eta_s=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$eta_iso" +%s 2>/dev/null || echo 0)
    rem=$(( (eta_s - $(date +%s)) / 60 )); [ "$rem" -ge 60 ] || rem=60
    echo "$(ts) BATTERY-PAUSE: ${b}% < ${need}% before $fw $variant $tier (M8); releasing the lock until ${BATTERY_RESUME_AT:-80}%"
    scripts/gpu_lock.sh release > /dev/null
    "$PY" -I scripts/quietlib.py battery --min "${BATTERY_RESUME_AT:-80}" --wait 43200 || { echo "$(ts) battery did not recover; stopping"; exit 6; }
    echo "$(ts) BATTERY-READY: $(batt_pct)%; taking the lock again at $(date -v+10M '+%T') (10 min notice)"
    sleep 600
    until scripts/gpu_lock.sh acquire "$purpose" "$rem" > /dev/null 2>&1; do sleep 60; done
    echo "$(ts) RESUMED: lock taken again ($rem min ETA); battery $(batt_pct)%"
  fi
fi
grep -q '^holder: local_ai-benchmark session' "$LOCKFILE" 2>/dev/null \
  || { echo "run_m8: the GPU lock is not held by us; acquire it first" >&2; exit 5; }
dry=$(scripts/serve.sh "$fw" "$variant" "$tier" --dry-run) || { echo "$dry" | tail -5; exit 4; }
model=$(printf '%s\n' "$dry" | sed -n 's/^ *# model id: *//p' | head -1)
base=$(printf '%s\n' "$dry" | sed -n 's/^ *# endpoint: *//p' | head -1 | sed 's#/v1$##')
port=${base##*:}
raw="$ROOT/$fw/raw"; mkdir -p "$raw" logs
vdir="$raw" unv_arg="" move_arg="--move"
[ "$UNV" = 1 ] && { vdir="$raw/_unverified" unv_arg="--unverified" move_arg=""; mkdir -p "$vdir"; }
RUN=$(date +%Y%m%d-%H%M%S)
lpf=logs/m8-load.pid
llog="logs/m8-load-$fw-$tag-$RUN.log"
events="logs/monitor-$fw-$tag-m8.events"
if [ -e "$lpf" ]; then   # a load left over from an earlier run would be invisible to the checks below
  echo "$(ts) a load pidfile exists; stopping it first"; lf stop --pidfile "$lpf" | sed 's/^/  /'
  [ ! -e "$lpf" ] || { echo "$(ts) could not stop it; nothing started"; exit 6; }
fi
echo "$(ts) run_m8: $fw $variant $tier, tag $tag, run $RUN, $nb blocks: $blocks"
( while kill -0 $$ 2>/dev/null; do caffeinate -u -t 1; sleep 60; done ) > /dev/null 2>&1 &
sleep "${USER_ACTIVE_SETTLE_S:-45}"   # declaring activity sets off a ~30 s "user returned" burst; let it pass
if ! "$PY" -I scripts/quietlib.py battery --min "$MIN_BATT" --wait "$BATT_WAIT_S"; then
  [ "$UNV" = 1 ] || { echo "$(ts) battery below ${MIN_BATT}% after ${BATT_WAIT_S}s; nothing started"; exit 6; }
fi
if ! scripts/quiet_check.sh --allow-pid $$ --settle "$PRE_S" --max-gpu-gb "${QUIET_MAX_GPU_GB_IDLE:-6}" --min-battery "$MIN_BATT" > "logs/quiet-$fw-$tag-m8.preserve" 2>&1; then
  echo "$(ts) machine not quiet before serving:"; sed 's/^/  /' "logs/quiet-$fw-$tag-m8.preserve"
  [ "$UNV" = 1 ] || { echo "$(ts) nothing started"; exit 6; }
fi
scripts/serve.sh "$fw" "$variant" "$tier" > /dev/null 2>&1 &
mon="" lpid="" restore=""
stop_mon() { [ -z "$mon" ] || { kill "$mon" 2>/dev/null; wait "$mon" 2>/dev/null; }; mon=""; }
stop_load() {   # prints what stop reports; keeps the power restore command; fails if anything survived
  local out src
  [ -e "$lpf" ] || return 0
  out=$(lf stop --pidfile "$lpf" 2>&1); src=$?
  printf '%s\n' "$out" | sed 's/^/  /'
  restore=$(printf '%s\n' "$out" | sed -n 's/^power restore: //p')
  lpid=""
  return $src
}
cleanup() { stop_mon; stop_load; scripts/stop_server.sh "$fw" --children; }
trap 'cleanup; exit 130' INT TERM
sleep 2
scripts/wait_ready.sh "$port" 1800 || { scripts/stop_server.sh "$fw" --children; exit 3; }
pid=$(cat "logs/$fw.pid")
# lithos reports cached tokens only in its server log; point the harness at this run's log.
slog_arg=""
if [ "$profile" = lithos ]; then
  slog=$(ls -t "logs/$fw-$variant-$tier-"*.log 2>/dev/null | head -1)
  [ -n "$slog" ] && slog_arg="--server-log $ROOT/$slog"
fi
flags=$(grep -v '^#' "logs/$fw-$variant-$tier.cmd" | tail -1 | sed "s|$HOME|~|g")
version=$(grep -m1 '# framework:' "logs/$fw-$variant-$tier.cmd" | sed 's/.*# framework: *//')
echo "$(ts) server pid $pid; process tree: $(pgrep -P "$pid" | tr '\n' ' ')"
warm_model="$model"; [ "$profile" = mlxlm ] && warm_model=default_model
curl -s -m 900 "$base/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$warm_model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with: ok\"}],\"max_tokens\":8,\"temperature\":0}" \
  -o /dev/null -w "$(ts) warm-up: HTTP %{http_code} in %{time_total}s\n"

: > "$events"
qallow=""
start_mon() {   # the block's monitor: our tree plus the load's (qallow), with the block's allowances
  "$PY" -I scripts/quietlib.py monitor --log "$1" --interval 10 --allow-pid $$ $qallow --until-pid $$ >> "$events" 2>&1 &
  mon=$!
}
quarantine() {   # $1 suite, $2 epoch: this attempt's raw files go to raw/_unverified/ (the load was not running)
  local f
  mkdir -p "$raw/_unverified"
  for f in "$vdir/$1-$btag-"*.jsonl; do
    [ -f "$f" ] && [ "$(stat -f %m "$f")" -ge "$2" ] || continue
    mv "$f" "$raw/_unverified/" && echo "  moved ${f##*/} -> raw/_unverified/ (the load was not running)"
  done
}

rc=0 verified=0 incomplete="" i=0
for b in $blocks; do
  i=$((i + 1)); btag="$tag-m8-$b"
  hold_wait "block $i/$nb ($b)"
  kill -0 "$pid" 2>/dev/null || { echo "$(ts) server $pid is gone; stopping before block $i"; rc=1; break; }
  # 1. a clean machine before any load starts
  if ! bout=$("$PY" -I scripts/quietlib.py battery --min "$MIN_BATT" --wait "$BATT_WAIT_S"); then
    echo "$(ts) $bout"
    [ "$UNV" = 1 ] || { echo "$(ts) stopping before block $i"; rc=1; break; }
  fi
  case $bout in *waiting*) echo "$(ts) charged before block $i: $(printf '%s\n' "$bout" | tail -1)" ;; esac
  if ! scripts/quiet_check.sh --allow-pid $$ --settle "$WAIT_S" --min-battery "$MIN_BATT" > "logs/quiet-$fw-$btag.clean" 2>&1; then
    echo "$(ts) not quiet after ${WAIT_S}s before block $i ($b), no load running:"; sed 's/^/  /' "logs/quiet-$fw-$btag.clean"
    [ "$UNV" = 1 ] || { echo "$(ts) stopping"; rc=1; break; }
  fi
  # 2. the load
  qallow=""
  if [ "$b" = base ]; then
    meta=$(lf meta --scenario base study=m8 run="$RUN" block=$i blocks=$nb base_tag="$tag" settle_s=0)
  else
    allow=$(lf allowances "$b")
    "$PY" -I scripts/interference.py start "$b" --pidfile "$lpf" --until-pid $$ $(largs_of "$b") >> "$llog" 2>&1 &
    lstart=$!
    rw=$READY_S; [ "$b" = power ] && rw=$((POWER_WAIT_S + 60))
    if ! lf status --pidfile "$lpf" --wait-ready "$rw" --pid "$lstart"; then
      echo "$(ts) block $i/$nb $b: the load did not start; block skipped ($llog):"; tail -3 "$llog" | sed 's/^/  /'
      stop_load; rc=1; incomplete="$incomplete $b"; continue
    fi
    lpid=$(lf meta --pidfile "$lpf" --field load_pid)
    qallow="--allow-pid $lpid --allow $allow"
    meta=$(lf meta --pidfile "$lpf" study=m8 run="$RUN" block=$i blocks=$nb base_tag="$tag" settle_s="$SETTLE_S")
  fi
  mon_tsv="$vdir/monitor-$btag-$(date +%Y%m%d-%H%M%S).tsv"
  start_mon "$mon_tsv"
  [ "$b" = base ] || { echo "$(ts) block $i/$nb $b: load pid $lpid ready (allowances $allow); settling ${SETTLE_S}s"; sleep "$SETTLE_S"; }
  echo "$(ts) block $i/$nb $b (tag $btag)"
  bver=0 bdone=1
  for s in $(printf '%s' "$SUITES" | tr ',' ' '); do
    attempt=0
    while :; do
      attempt=$((attempt + 1))
      kill -0 "$pid" 2>/dev/null || { echo "$(ts) server $pid is gone; stopping before $s"; rc=1; break 3; }
      kill -0 "$mon" 2>/dev/null || { echo "$(ts) monitor had exited (see $events); restarted"; start_mon "$mon_tsv"; sleep "$LAG_S"; }
      if [ "$b" != base ] && ! lf status --pidfile "$lpf" > /dev/null; then
        echo "$(ts) $b: the load is not running before $s ($(lf status --pidfile "$lpf")); the block ends"; bdone=0; rc=1; break 2
      fi
      if ! scripts/quiet_check.sh --allow-pid $$ $qallow --settle "$WAIT_S" > "logs/quiet-$fw-$btag.last" 2>&1; then
        echo "$(ts) not quiet after ${WAIT_S}s before $s. Last check:"; sed 's/^/  /' "logs/quiet-$fw-$btag.last"
        [ "$UNV" = 1 ] || { echo "$(ts) stopping"; rc=1; break 3; }
      fi
      sargs=$(sargs_of "$s") rlog="logs/run-$fw-$btag-b$i-$s.log"   # baseline blocks share a tag; keep each block's log
      echo "$(ts) == $b: $s (attempt $attempt)${sargs:+, $sargs} =="
      t0=$(date +%s)
      (cd harness && uv run agentbench run-all --profile "$profile" --base-url "$base" --model "$model" \
        --framework "$fw" --framework-version "$version" --launch-flags "$flags" --tag "$btag" \
        --server-pid "$pid" --suites "$s" --preflight --no-summary --interference "$meta" \
        --preflight-cmd "$ROOT/scripts/quiet_check.sh --settle $HP_S --allow-pid $$ $qallow" $unv_arg $slog_arg "$@" $sargs) \
        > "$rlog" 2>&1
      src=$?
      grep -E "^(preflight|.* failed:)" "$rlog" | sed 's/^/  /'
      lok=1
      [ "$b" = base ] || lf status --pidfile "$lpf" > /dev/null || lok=0
      sleep "$LAG_S"   # let the monitor take one more sample after the suite's last write
      vout=$("$PY" -I scripts/quietlib.py verify --log "$mon_tsv" --raw-dir "$vdir" --since "$t0" $move_arg)
      [ -z "$vout" ] || printf '%s\n' "$vout" | sed 's/^/  /'
      if [ "$lok" = 0 ]; then
        echo "$(ts) $b: the load stopped during $s ($(lf status --pidfile "$lpf")); the block ends"
        [ "$UNV" = 1 ] || quarantine "$s" "$t0"
        bdone=0; rc=1; break 2
      fi
      [ "$UNV" = 1 ] && { echo "$(ts) $s: mechanics check done (harness rc $src)"; [ "$src" -eq 0 ] || rc=1; break; }
      if printf '%s\n' "$vout" | grep -q "^verify: $s-$btag-[0-9-]*\.jsonl: quiet"; then
        verified=$((verified + 1)) bver=$((bver + 1)); echo "$(ts) $s: verified (harness rc $src)"
        [ "$src" -eq 0 ] || rc=1
        break
      fi
      if [ "$src" -ne 0 ] && ! printf '%s\n' "$vout" | grep -q DISTURBED \
         && ! grep -q "preflight: machine is NOT quiet" "$rlog"; then
        echo "$(ts) $s: harness error (rc $src), not a disturbance; not repeated ($rlog)"; rc=1; break
      fi
      [ "$attempt" -gt "$RETRIES" ] && { echo "$(ts) $s: disturbed on every attempt; left in raw/_unverified/"; rc=1; bdone=0; break; }
      echo "$(ts) $s: disturbed (monitor or pre-flight); repeating"
    done
  done
  # 4. end of the block
  stop_mon
  if [ "$bver" -eq 0 ] && [ "$UNV" != 1 ]; then mkdir -p "$raw/_unverified"; mv "$mon_tsv" "$raw/_unverified/" 2>/dev/null; fi
  [ "$bdone" = 1 ] || incomplete="$incomplete $b"
  [ "$b" = base ] && continue
  stop_load || { echo "$(ts) the $b load could not be stopped; stopping the run"; rc=1; break; }
  if [ "$b" = power ]; then
    if [ -n "$restore" ]; then lf wait-power --want high --wait "$POWER_WAIT_S" --hint "$restore"
    else lf wait-power --want high --wait "$POWER_WAIT_S"; fi \
      || { echo "$(ts) High Power on AC was not restored; stopping (the next baseline cannot run)"; rc=1; break; }
  fi
  [ "$i" -lt "$nb" ] && { echo "$(ts) cool-down ${COOL_S}s"; sleep "$COOL_S"; }
done

stop_mon
# a block ended by `break 3` (server gone, machine not quiet) skipped the per-block handling above
if [ "$UNV" != 1 ] && [ "${bver:-1}" -eq 0 ] && [ -e "${mon_tsv:-}" ]; then mkdir -p "$raw/_unverified"; mv "$mon_tsv" "$raw/_unverified/"; fi
stop_load || rc=1
scripts/stop_server.sh "$fw" --children
echo "$(ts) run_m8: done, $verified verified suite(s)${incomplete:+; incomplete blocks:$incomplete}, rc $rc"
m8u=""; [ "$UNV" = 1 ] && m8u=--unverified
(cd harness && uv run agentbench m8-report --framework "$fw" --tag "$tag" $m8u) 2>&1 | sed 's/^/  /'
exit $rc
