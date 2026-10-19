#!/usr/bin/env bash
# Tier-2 block: M6 stability for the three agent-backend candidates, the 8-bit rows, and the
# text-only reference frameworks. Same rules as run_tier1.sh: the GPU lock must already be
# held, each step is one run_framework.sh call, and a failing step is logged and skipped.
# Usage: run_tier2.sh [step ...]     (default: all steps, in order)
#   M6 (sustained 20-step trajectory loop): m6-llama (MTP on, 30 min) m6-omlx (30 min)
#     m6-vllm (15 min). The two finalists get 30 min, the other candidate 15 (METHODOLOGY.md, M6).
#     M6 gets two repeats: a 30 min window is the most exposed to a daemon burst.
#   8-bit rows, gate + M1/M4/M7: omlx-8bit vllm-8bit mlxlm-8bit
#   references (the harness switches them to text-only): mlxlm-4bit lithos-dspark
#     lithos-nodraft lithos-nvfp4
# Between steps the machine idles COOL_S seconds (default 120) so each server starts cool.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
COOL_S=${COOL_S:-120}
ts() { date '+%T'; }
steps=${*:-"m6-llama m6-omlx m6-vllm omlx-8bit vllm-8bit mlxlm-8bit mlxlm-4bit lithos-dspark lithos-nodraft lithos-nvfp4"}
export SUITE_ARGS_m7="--trials 1"   # M7 is deterministic at temperature 0; one pass per prompt
( while kill -0 $$ 2>/dev/null; do caffeinate -u -t 1; sleep 60; done ) > /dev/null 2>&1 &   # user activity across the cool-downs too (see run_framework.sh)
rf=scripts/run_framework.sh
first=1 failed=""
for step in $steps; do
  [ "$first" = 1 ] || { echo "$(ts) cool-down ${COOL_S}s"; sleep "$COOL_S"; }
  first=0
  echo "$(ts) ===== $step ====="
  case $step in
    m6-llama)       QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 30" $rf llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on m6 --spec-label on ;;
    m6-omlx)        QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 30" $rf omlx spec-off 4bit omlx 4bit-spec-off m6 --spec-label off ;;
    m6-vllm)        QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 15" $rf vllm-metal spec-off 4bit vllm 4bit-spec-off m6 --spec-label off ;;
    omlx-8bit)      $rf omlx spec-off 8bit omlx 8bit-spec-off gate,m1,m4,m7 --spec-label off ;;
    vllm-8bit)      $rf vllm-metal spec-off 8bit vllm 8bit-spec-off gate,m1,m4,m7 --spec-label off ;;
    mlxlm-8bit)     $rf mlx-lm server 8bit mlxlm 8bit gate,m1,m4,m7 --spec-label off ;;
    mlxlm-4bit)     $rf mlx-lm server 4bit mlxlm 4bit gate,m1,m2,m3,m4,m7 --spec-label off ;;
    lithos-dspark)  $rf lithos-metal dspark 4bit lithos 4bit-dspark gate,m1,m2,m3,m4,m7 --spec-label on ;;
    lithos-nodraft) $rf lithos-metal no-draft 4bit lithos 4bit-no-draft m1,m3,m4,m7 --spec-label off ;;
    lithos-nvfp4)   $rf lithos-metal dspark nvfp4 lithos nvfp4-dspark gate,m1,m2,m3,m4,m7 --spec-label on ;;
    *) echo "unknown step $step"; failed="$failed $step"; continue ;;
  esac
  rc=$?
  echo "$(ts) ===== $step: rc $rc ====="
  [ "$rc" -eq 0 ] || failed="$failed $step"
done
echo "$(ts) tier-2 block done; failed steps:${failed:- none}"
[ -z "$failed" ]
