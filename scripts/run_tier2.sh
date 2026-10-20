#!/usr/bin/env bash
# Tier-2 block: M6 stability for the three agent-backend candidates, the 8-bit rows, and the
# text-only reference frameworks. Same rules as run_tier1.sh: the GPU lock must already be
# held, each step is one run_framework.sh call, and a failing step is logged and skipped.
# Usage: run_tier2.sh [step ...]     (default: all steps, in order)
#   M6 (sustained 20-step trajectory loop): m6-llama (MTP on, 30 min) m6-omlx (30 min)
#     m6-vllm (15 min). The two finalists get 30 min, the other candidate 15 (METHODOLOGY.md, M6).
#     M6 gets two repeats: a 30 min window is the most exposed to a daemon burst.
#     m6-omlx-oq4mtp (30 min): oMLX with Lightning MTP on the oQ4 checkpoint, the frontrunner
#     after the 2026-10-20 oQ runs. m6-omlx-oq8mtp (30 min): the same on oQ8, the A1/A2 choice.
#   MLC-LLM, text-only reference (2026-10-20): mlc-gate first, then mlc-text (M1-M4, M7; M4 runs
#     once, because without a prefix cache every step is a cold prefill). Tool calls go through
#     structured output in constraint mode (mlc-llm/env.md, section 5.4).
#     mlc-text-trim: every MLC request is a cold prefill (126 tok/s at 13K, 78 tok/s at 64K in the
#     gate), so the full set takes about 9 h. This one runs M1 (2 + 2 trials), M2 at 16K / 32K,
#     M3 at 16K / 32K with cap 150 and no thinking bucket (thinking is fixed per chat config),
#     and M7: about 2 h.
#   Core AI llm-server (port 8706): coreai-gate, the gate with the generic profile.
#   8-bit rows, gate + M1/M4/M7: omlx-8bit vllm-8bit mlxlm-8bit
#   references (the harness switches them to text-only): mlxlm-4bit lithos-dspark
#     lithos-nodraft lithos-nvfp4
#   2026-10-19 additions: omlx-8bit-m3 (thinking-on TTFT at 8-bit), llama-q8-off llama-q8-on
#     (the Q8_0 GGUF; MTP uses the same Q4_0 draft head), and the M1/M4 re-runs with forced
#     text-only (commit c9581b1): mlxlm-8bit-fix mlxlm-4bit-fix lithos-dspark-fix
#     lithos-nodraft-fix lithos-nvfp4-fix. lithos's M4 runs once: the invalid runs (image
#     content arrays) never hit its prefix cache and took ~40 min; with all-text strings it
#     caches, and one run takes ~5 min (2026-10-20).
#   oMLX with Lightning MTP on oQ checkpoints that keep the MTP head (2026-10-19 night): oq8-convert
#     oq4-convert, then omlx-oq8-off omlx-oq8-mtp omlx-oq8-mtp-t1 omlx-oq8-off-t1 and the oq4 set;
#     omlx-oq8-mtp-gate omlx-oq4-mtp-gate run the gate with MTP on (G2/G3 images through the MTP
#     decoder; the other oq steps run the gate with MTP off only)
#   sampling at the model's own settings (temperature 1.0, top_p 0.95, top_k 20): q8-on-t1
#     q8-off-t1 q4-on-t1 q4-off-t1 (M3 at 16K/32K, cap 150 and thinking cap 1000; M4 for MTP on)
# Between steps the machine idles COOL_S seconds (default 120) so each server starts cool.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
COOL_S=${COOL_S:-120}
ts() { date '+%T'; }
steps=${*:-"lithos-dspark lithos-nodraft lithos-nvfp4 m6-llama m6-omlx m6-vllm omlx-8bit vllm-8bit mlxlm-8bit mlxlm-4bit"}   # lithos-metal first (the user, 2026-10-18)
export SUITE_ARGS_m7="--trials 1"   # M7 is deterministic at temperature 0; one pass per prompt
( while kill -0 $$ 2>/dev/null; do caffeinate -u -t 1; sleep 60; done ) > /dev/null 2>&1 &   # user activity across the cool-downs too (see run_framework.sh)
rf=scripts/run_framework.sh
# The model's own sampling (Qwen3.8 generation_config), as the agent benchmark sends it: MTP
# acceptance is lower than under greedy decoding, so the *-t1 steps re-measure the MTP gain.
SAMP='{"temperature": 1.0, "top_p": 0.95, "top_k": 20}'
M3_T1="--contexts 16000,32000 --caps 150 --think-contexts 16000,32000 --think-caps 1000"
OMLX_PY="$HOME/Developer/mlsys/serving/omlx_0.7/.venv/bin/python"   # oQ conversion (scripts/oq_convert.py)
MLC_BODY='{"debug_config": {"grammar_execution_mode": "constraint"}}'   # jump-forward rolls back the GDN state
first=1 failed=""
for step in $steps; do
  [ "$first" = 1 ] || { echo "$(ts) cool-down ${COOL_S}s"; sleep "$COOL_S"; }
  first=0
  echo "$(ts) ===== $step ====="
  case $step in
    m6-llama)       QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 30" $rf llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on m6 --spec-label on ;;
    m6-omlx)        QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 30" $rf omlx spec-off 4bit omlx 4bit-spec-off m6 --spec-label off ;;
    m6-vllm)        QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 15" $rf vllm-metal spec-off 4bit vllm 4bit-spec-off m6 --spec-label off ;;
    m6-omlx-oq4mtp) QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 30" $rf omlx mtp-on oq4mtp omlx oq4mtp-mtp-on m6 --spec-label on ;;
    m6-omlx-oq8mtp) QUIET_RETRIES=2 SUITE_ARGS_m6="--minutes 30" $rf omlx mtp-on oq8mtp omlx oq8mtp-mtp-on m6 --spec-label on ;;
    mlc-gate)       $rf mlc-llm server 4bit mlc 4bit gate --spec-label off --extra-body "$MLC_BODY" ;;
    mlc-text)       SUITE_ARGS_m4="--runs 1" $rf mlc-llm server 4bit mlc 4bit m1,m2,m3,m4,m7 --spec-label off --extra-body "$MLC_BODY" ;;
    mlc-text-trim)  SUITE_ARGS_m1="--trials 2 --cold-trials 2" SUITE_ARGS_m2="--sizes 16000,32000" \
                    SUITE_ARGS_m3="--contexts 16000,32000 --caps 150 --no-thinking-bucket" \
                    $rf mlc-llm server 4bit mlc 4bit m1,m2,m3,m7 --spec-label off --extra-body "$MLC_BODY" ;;
    coreai-gate)    $rf coreai server 4bit generic 4bit gate --spec-label off ;;
    omlx-8bit)      $rf omlx spec-off 8bit omlx 8bit-spec-off gate,m1,m4,m7 --spec-label off ;;
    vllm-8bit)      $rf vllm-metal spec-off 8bit vllm 8bit-spec-off gate,m1,m4,m7 --spec-label off ;;
    mlxlm-8bit)     $rf mlx-lm server 8bit mlxlm 8bit gate,m1,m4,m7 --spec-label off ;;
    mlxlm-4bit)     $rf mlx-lm server 4bit mlxlm 4bit gate,m1,m2,m3,m4,m7 --spec-label off ;;
    lithos-dspark)  $rf lithos-metal dspark 4bit lithos 4bit-dspark gate,m1,m2,m3,m4,m7 --spec-label on ;;
    lithos-nodraft) $rf lithos-metal no-draft 4bit lithos 4bit-no-draft m1,m3,m4,m7 --spec-label off ;;
    lithos-nvfp4)   $rf lithos-metal dspark nvfp4 lithos nvfp4-dspark gate,m1,m2,m3,m4,m7 --spec-label on ;;
    omlx-8bit-m3)   $rf omlx spec-off 8bit omlx 8bit-spec-off m3 --spec-label off ;;
    llama-q8-off)   $rf llama.cpp mtp-off 8bit llamacpp 8bit-mtp-off gate,m1,m3,m4,m7 --spec-label off ;;
    llama-q8-on)    $rf llama.cpp mtp-on 8bit llamacpp 8bit-mtp-on m1,m3,m4,m7 --spec-label on ;;
    llama-q8-off-m3) $rf llama.cpp mtp-off 8bit llamacpp 8bit-mtp-off m3 --spec-label off ;;
    q8-on-t1)       SUITE_ARGS_m3="$M3_T1" $rf llama.cpp mtp-on 8bit llamacpp 8bit-mtp-on-t1 m3,m4 --spec-label on --extra-body "$SAMP" ;;
    q8-off-t1)      SUITE_ARGS_m3="$M3_T1" $rf llama.cpp mtp-off 8bit llamacpp 8bit-mtp-off-t1 m3 --spec-label off --extra-body "$SAMP" ;;
    q4-on-t1)       SUITE_ARGS_m3="$M3_T1" $rf llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on-t1 m3,m4 --spec-label on --extra-body "$SAMP" ;;
    q4-off-t1)      SUITE_ARGS_m3="$M3_T1" $rf llama.cpp mtp-off 4bit llamacpp 4bit-mtp-off-t1 m3 --spec-label off --extra-body "$SAMP" ;;
    omlx8-t1)       $rf omlx spec-off 8bit omlx 8bit-spec-off-t1 m4 --spec-label off --extra-body "$SAMP" ;;
    oq8-convert|oq4-convert)
                    lvl=${step#oq}; lvl=${lvl%-convert}
                    HF_HUB_OFFLINE=1 "$OMLX_PY" -u scripts/oq_convert.py --level "$lvl" ;;
    omlx-oq8-off|omlx-oq4-off)
                    t=${step#omlx-}; t=${t%-off}; $rf omlx spec-off ${t}mtp omlx ${t}mtp-spec-off gate,m1,m3,m4,m7 --spec-label off ;;
    omlx-oq8-mtp|omlx-oq4-mtp)
                    t=${step#omlx-}; t=${t%-mtp}; $rf omlx mtp-on ${t}mtp omlx ${t}mtp-mtp-on m1,m3,m4,m7 --spec-label on ;;
    omlx-oq8-mtp-t1|omlx-oq4-mtp-t1)
                    t=${step#omlx-}; t=${t%-mtp-t1}; SUITE_ARGS_m3="$M3_T1" $rf omlx mtp-on ${t}mtp omlx ${t}mtp-mtp-on-t1 m3,m4 --spec-label on --extra-body "$SAMP" ;;
    omlx-oq8-off-t1|omlx-oq4-off-t1)
                    t=${step#omlx-}; t=${t%-off-t1}; SUITE_ARGS_m3="$M3_T1" $rf omlx spec-off ${t}mtp omlx ${t}mtp-spec-off-t1 m3,m4 --spec-label off --extra-body "$SAMP" ;;
    omlx-oq8-mtp-gate|omlx-oq4-mtp-gate)
                    t=${step#omlx-}; t=${t%-mtp-gate}; $rf omlx mtp-on ${t}mtp omlx ${t}mtp-mtp-on gate --spec-label on ;;
    mlxlm-8bit-fix) $rf mlx-lm server 8bit mlxlm 8bit m1,m4 --spec-label off ;;
    mlxlm-4bit-fix) $rf mlx-lm server 4bit mlxlm 4bit m1,m4 --spec-label off ;;
    lithos-dspark-fix)  SUITE_ARGS_m4="--runs 1" $rf lithos-metal dspark 4bit lithos 4bit-dspark m1,m4 --spec-label on ;;
    lithos-nodraft-fix) SUITE_ARGS_m4="--runs 1" $rf lithos-metal no-draft 4bit lithos 4bit-no-draft m1,m4 --spec-label off ;;
    lithos-nvfp4-fix)   SUITE_ARGS_m4="--runs 1" $rf lithos-metal dspark nvfp4 lithos nvfp4-dspark m1,m4 --spec-label on ;;
    *) echo "unknown step $step"; failed="$failed $step"; continue ;;
  esac
  rc=$?
  echo "$(ts) ===== $step: rc $rc ====="
  [ "$rc" -eq 0 ] || failed="$failed $step"
done
echo "$(ts) tier-2 block done; failed steps:${failed:- none}"
[ -z "$failed" ]
