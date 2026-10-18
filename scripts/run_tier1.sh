#!/usr/bin/env bash
# Formal Tier-1 block: the three agent-backend candidates at 4-bit, one after another.
# The GPU lock must already be held (run_framework.sh checks). Each step is one
# run_framework.sh call; a failing step is logged and the block moves on.
# Usage: run_tier1.sh [step ...]     (default: all steps, in order)
#   steps: llama-off llama-on llama-conc omlx vllm
#   remainder after the 2026-10-18 interruptions (gates re-run for G2b, plus an M1 anchor
#   compared with the 04:35 llama.cpp run): vllm-rest llama-gate llama-anchor omlx-gate,
#   then vllm-m5m7 (vllm-rest stopped before m5 while mediaanalysisd was busy)
#   battery re-run (the night's timed suites ran with the battery at 6-29 %; see
#   METHODOLOGY.md): vllm-rerun omlx-rerun llama-off-rerun llama-on-rerun llama-conc-rerun
# Between steps the machine idles COOL_S seconds (default 120) so each server starts cool.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
COOL_S=${COOL_S:-120}
ts() { date '+%T'; }
steps=${*:-"llama-off llama-on llama-conc omlx vllm"}
export SUITE_ARGS_m7="--trials 1"   # M7 is deterministic at temperature 0; one pass per prompt
( while kill -0 $$ 2>/dev/null; do caffeinate -u -t 1; sleep 60; done ) > /dev/null 2>&1 &   # user activity across the cool-downs too (see run_framework.sh)
first=1 failed=""
for step in $steps; do
  [ "$first" = 1 ] || { echo "$(ts) cool-down ${COOL_S}s"; sleep "$COOL_S"; }
  first=0
  echo "$(ts) ===== $step ====="
  case $step in
    llama-off)  scripts/run_framework.sh llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off gate,m1,m2,m3,m4,m7 --spec-label off ;;
    llama-on)   scripts/run_framework.sh llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on m1,m3,m4,m7 --spec-label on ;;
    llama-conc) scripts/run_framework.sh llama.cpp conc 4bit llamacpp 4bit-conc m5 ;;
    omlx)       scripts/run_framework.sh omlx spec-off 4bit omlx 4bit-spec-off gate,m1,m2,m3,m4,m5,m7 --spec-label off ;;
    vllm)       scripts/run_framework.sh vllm-metal spec-off 4bit vllm 4bit-spec-off gate,m1,m2,m3,m4,m5,m7 --spec-label off ;;
    vllm-rest)  scripts/run_framework.sh vllm-metal spec-off 4bit vllm 4bit-spec-off gate,m3,m4,m5,m7 --spec-label off ;;
    vllm-m5m7)  scripts/run_framework.sh vllm-metal spec-off 4bit vllm 4bit-spec-off m5,m7 --spec-label off ;;
    vllm-rerun)       scripts/run_framework.sh vllm-metal spec-off 4bit vllm 4bit-spec-off gate,m1,m2 --spec-label off ;;
    omlx-rerun)       scripts/run_framework.sh omlx spec-off 4bit omlx 4bit-spec-off gate,m1,m2,m3,m4,m5 --spec-label off ;;
    llama-off-rerun)  scripts/run_framework.sh llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off gate,m1,m2,m3,m4 --spec-label off ;;
    llama-on-rerun)   scripts/run_framework.sh llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on m1,m3,m4 --spec-label on ;;
    llama-conc-rerun) scripts/run_framework.sh llama.cpp conc 4bit llamacpp 4bit-conc m5 ;;
    llama-gate) scripts/run_framework.sh llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off gate --spec-label off ;;
    llama-anchor) scripts/run_framework.sh llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off-anchor m1 --spec-label off ;;
    omlx-gate)  scripts/run_framework.sh omlx spec-off 4bit omlx 4bit-spec-off gate --spec-label off ;;
    *) echo "unknown step $step"; failed="$failed $step"; continue ;;
  esac
  rc=$?
  echo "$(ts) ===== $step: rc $rc ====="
  [ "$rc" -eq 0 ] || failed="$failed $step"
done
echo "$(ts) tier-1 block done; failed steps:${failed:- none}"
[ -z "$failed" ]
