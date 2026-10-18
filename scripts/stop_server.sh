#!/usr/bin/env bash
# stop_server.sh <framework> [--children]
#
# Stops the server whose PID is in logs/<framework>.pid, and nothing else.
# - It refuses unless that PID is ours: it started before the pidfile was written (so it is
#   not a recycled PID), it runs our framework executable (or listens on that framework's
#   port), and it does not listen on 8500 or 8600-8699.
# - Graceful first: SIGINT (the same as Ctrl-C), then SIGTERM, then SIGKILL as a last resort.
#   Waits: STOP_INT_S (default 30 s), then STOP_TERM_S (default 20 s).
# - Child processes (vLLM's engine core, for example) are recorded before any signal. If any
#   outlive the server they are reported; --children also stops those exact processes.
# Exit codes: 0 stopped or nothing to stop, 1 something is still running, 2 usage / not ours.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -ge 1 ] || { print_header "${BASH_SOURCE[0]}" >&2; exit "$EX_USAGE"; }
FW=$1; shift
CHILDREN=0
case "${1:-}" in --children) CHILDREN=1 ;; '') ;; *) die "$EX_USAGE" "unknown option: $1" ;; esac
is_framework "$FW" || die "$EX_USAGE" "unknown framework '$FW' (one of: $FRAMEWORKS)"
PIDF=$(pidfile_of "$FW")
PORT=$(fw_port "$FW")

port_report() {
  local d i=0
  while [ "$i" -lt 5 ]; do
    d=$(describe_port "$PORT"); [ -n "$d" ] || { say "port $PORT is free"; return 0; }
    sleep 1; i=$((i + 1))
  done
  say "warning: port $PORT is still in use:"; say "$d" | sed 's/^/  /'
  return 1
}

if [ ! -f "$PIDF" ]; then
  say "no pidfile ${PIDF#"$BENCH_DIR"/}: nothing of ours to stop"
  D=$(describe_port "$PORT")
  [ -z "$D" ] && exit 0
  say "note: port $PORT is in use by a process that is not in our pidfile; not touching it:"
  say "$D" | sed 's/^/  /'
  exit 1
fi
PID=$(head -1 "$PIDF")
case "$PID" in ''|*[!0-9]*) die "$EX_USAGE" "unexpected content in $PIDF" ;; esac
if ! pid_alive "$PID"; then
  say "PID $PID ($FW) is not running; removing the stale pidfile"
  rm -f "$PIDF"
  port_report || exit 1
  exit 0
fi
pid_owned "$FW" "$PID" "$PIDF" || die "$EX_USAGE" "not stopping PID $PID: $OWN_REASON (pidfile left in place)"

descendants() { local c; for c in $(pgrep -P "$1" 2>/dev/null || true); do echo "$c"; descendants "$c"; done; }
KIDS='' KID_CMDS=''
for c in $(descendants "$PID"); do
  CMDLINE=$(pid_cmd "$c")
  case "$CMDLINE" in   # serve.sh's own log tee and caffeinate; they exit with the server
    "tee -a $LOG_DIR/"*|"caffeinate -ims -w $PID") continue ;;
  esac
  KIDS="$KIDS${KIDS:+ }$c"
  KID_CMDS="$KID_CMDS$c $CMDLINE"$'\n'
done
[ -z "$KIDS" ] || say "child processes of $PID: $KIDS"

wait_gone() {  # wait_gone <pid> <seconds>
  local i=0
  while pid_alive "$1"; do [ "$i" -ge "$2" ] && return 1; sleep 1; i=$((i + 1)); done
}

say "stopping $FW (PID $PID, port $PORT): SIGINT"
kill -INT "$PID" 2>/dev/null || true
if ! wait_gone "$PID" "${STOP_INT_S:-30}"; then
  say "still running after ${STOP_INT_S:-30}s: SIGTERM"
  kill -TERM "$PID" 2>/dev/null || true
  if ! wait_gone "$PID" "${STOP_TERM_S:-20}"; then
    say "still running after ${STOP_TERM_S:-20}s: SIGKILL"
    kill -KILL "$PID" 2>/dev/null || true
    wait_gone "$PID" 10 || die 1 "PID $PID survived SIGKILL"
  fi
fi
say "PID $PID exited"
rm -f "$PIDF"

# Children that outlive the server. Only the exact processes recorded above are considered.
LEFT=''
for c in $KIDS; do
  pid_alive "$c" || continue
  [ "$c $(pid_cmd "$c")" = "$(printf '%s' "$KID_CMDS" | grep "^$c " | head -1)" ] && LEFT="$LEFT $c"
done
if [ -n "$LEFT" ]; then
  if [ "$CHILDREN" -eq 0 ]; then
    say "child process(es) of the server are still alive and may hold GPU memory:"
    for c in $LEFT; do say "  $c $(pid_cmd "$c" | cut -c1-160)"; done
    say "stop them with: kill -TERM$LEFT   (or pass --children next time)"
    exit 1
  fi
  say "stopping leftover children:$LEFT (SIGTERM)"
  for c in $LEFT; do kill -TERM "$c" 2>/dev/null || true; done
  for c in $LEFT; do
    wait_gone "$c" 15 && continue
    say "child $c still running: SIGKILL"; kill -KILL "$c" 2>/dev/null || true
    wait_gone "$c" 5 || say "child $c survived SIGKILL"
  done
fi
port_report || exit 1
