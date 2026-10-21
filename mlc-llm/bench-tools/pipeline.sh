#!/bin/bash
# MLC artifact pipeline (CPU only): convert_weight --device cpu, gen_config, compile (Metal lib).
# Usage: pipeline.sh <tiny|27b> [first_step]   (steps: convert config compile think)
set -u
B=~/Developer/mlsys/serving/mlc-llm_bench
PY="$B/.venv/bin/python"
H="$PY -I $HOME/Developer/mlsys/serving/mlc-llm_bench/bench-tools/heavy.py --"
export HF_HOME=~/Developer/ml_source/huggingface HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
export CCACHE_DIR="$B/.ccache"
M=~/Developer/mlsys/models/mlc
case ${1:?tiny or 27b} in
  tiny) SRC=$HF_HOME/hub/models--Qwen--Qwen3.5-0.8B/snapshots/2fc06364715b967f1860aea9cf38778875588b17
        NAME=Qwen3.5-0.8B-q4f16_1-MLC; LIBN=Qwen3.5-0.8B-q4f16_1-ctx131072-bs1-metal.dylib ;;
  27b)  SRC=$HF_HOME/hub/models--Qwen--Qwen3.8-27B/snapshots/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0
        NAME=Qwen3.8-27B-q4f16_1-MLC; LIBN=Qwen3.8-27B-q4f16_1-ctx131072-bs1-metal.dylib ;;
  *) echo "bad model"; exit 2 ;;
esac
DST=$M/$NAME
LOGP=$B/logs/pipeline-$1
mkdir -p "$DST"
cd "$B" || exit 1
steps=(convert config compile think)
start=${2:-convert}
run=0
for s in "${steps[@]}"; do
  [ "$s" = "$start" ] && run=1
  [ $run = 1 ] || continue
  log="$LOGP-$s.log"
  echo "=== $1 step $s -> $log ($(date '+%F %T'))"
  case $s in
    convert) $H $PY -m mlc_llm convert_weight "$SRC" --quantization q4f16_1 --model-type qwen3_5 \
                  --device cpu --output "$DST" > "$log" 2>&1 ;;
    config)  $PY -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 \
                  --conv-template qwen3_5_nothink --context-window-size 131072 \
                  --prefill-chunk-size 2048 --max-batch-size 1 --output "$DST" > "$log" 2>&1 ;;
    compile) $H $PY -m mlc_llm compile "$DST/mlc-chat-config.json" --device metal \
                  --output "$DST/$LIBN" > "$log" 2>&1 ;;
    think)   mkdir -p "$DST-think" &&
             $PY -m mlc_llm gen_config "$SRC" --quantization q4f16_1 --model-type qwen3_5 \
                  --conv-template qwen3_5 --context-window-size 131072 \
                  --prefill-chunk-size 2048 --max-batch-size 1 --output "$DST-think" > "$log" 2>&1 &&
             ln -sf "$DST"/params_shard_*.bin "$DST"/tensor-cache*.json "$DST-think"/ ;;
  esac
  rc=$?
  echo "=== $1 step $s exit=$rc ($(date '+%F %T'))"
  grep '^\[heavy' "$log" | tail -2
  [ $rc = 0 ] || { echo "FAILED at $s"; tail -40 "$log"; exit $rc; }
done
ls -la "$DST" | head -20; du -sh "$DST"
