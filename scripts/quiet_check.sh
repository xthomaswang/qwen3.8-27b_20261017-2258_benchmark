#!/usr/bin/env bash
# Pre-flight for a timed segment: is the machine quiet enough for publishable numbers?
# Prints a provenance block (append it to the run's raw/ provenance) and exits non-zero when not quiet.
# Usage: quiet_check.sh [--allow-pid PID]...   (PIDs of the server under test are excluded)
set -uo pipefail
LOCK="${GPU_LOCK_PATH:-$HOME/Developer/mlsys/experiments/.gpu-lock}"
MAX_LOAD="${QUIET_MAX_LOAD:-2.5}"      # 1-min load average ceiling
MAX_PROC_CPU="${QUIET_MAX_PROC_CPU:-25}" # any single foreign process above this %CPU fails the check
allow=()
while [ $# -gt 0 ]; do case "$1" in --allow-pid) allow+=("$2"); shift 2 ;; *) echo "unknown arg $1" >&2; exit 2 ;; esac; done
fail=0
note() { printf '%s\n' "$*"; }
note "quiet_check: $(date '+%F %T %z')"
if [ -f "$LOCK" ] && grep -q '^holder: local_ai-benchmark session' "$LOCK"; then note "lock: held by us ($(grep '^purpose:' "$LOCK" | cut -c10-))"; else note "lock: NOT held by us"; fail=1; fi
if lsof -nP -iTCP:8500 -sTCP:LISTEN >/dev/null 2>&1; then note "port 8500: LISTENING (agent-benchmark oMLX is up)"; fail=1; else note "port 8500: free"; fi
load1=$(sysctl -n vm.loadavg | awk '{print $2}')
note "load1: $load1 (max $MAX_LOAD)"
awk -v l="$load1" -v m="$MAX_LOAD" 'BEGIN{exit !(l>m)}' && fail=1
busy=$(ps -Ao pid=,pcpu=,comm= | awk -v m="$MAX_PROC_CPU" '$2>m {print}')
for p in "${allow[@]:-}"; do [ -n "$p" ] && busy=$(printf '%s\n' "$busy" | awk -v p="$p" '$1!=p'); done
busy=$(printf '%s\n' "$busy" | grep -v -E 'WindowServer|kernel_task' | sed '/^$/d')
if [ -n "$busy" ]; then note "busy foreign processes (>${MAX_PROC_CPU}% CPU):"; printf '%s\n' "$busy" | sed "s|$HOME|~|g; s/^/  /"; fail=1; else note "busy foreign processes: none"; fi
if pgrep -f 'clang|cc1plus|ninja|cmake --build|make -j|ld64|mlc_llm (convert_weight|compile)|coreai.llm.export|hf download' >/dev/null; then note "build/convert/download tools: RUNNING"; pgrep -fl 'clang|cc1plus|ninja|cmake --build|make -j|ld64|convert_weight|coreai.llm.export|hf download' | cut -c1-120 | sed "s|$HOME|~|g; s/^/  /"; fail=1; else note "build/convert/download tools: none"; fi
therm=$(pmset -g therm 2>/dev/null | grep -E 'level|CPU_Speed_Limit|GPU' | tr '\n' ' ')
note "thermal: ${therm:-no warning recorded}"
note "power: $(pmset -g batt | head -1 | sed "s/Now drawing from //")"
[ $fail -eq 0 ] && note "verdict: QUIET" || note "verdict: NOT QUIET"
exit $fail
