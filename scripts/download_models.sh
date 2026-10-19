#!/usr/bin/env bash
# Download the benchmark checkpoints into the shared HF cache, in priority order.
# Files stay in $HF_HOME (never copied into this repo); frameworks load them by repo id
# or by snapshot path. Interrupted downloads resume from the .incomplete blobs.
#
# Usage: download_models.sh [core] [gguf] [gguf_q8] [extra]   (default: core gguf)
#   core  : DSpark draft head + MLX affine 4-bit (unblocks lithos-metal and the MLX 4-bit rows)
#   gguf  : llama.cpp target, MTP draft head, vision projector
#   gguf_q8 : llama.cpp Q8_0 target for the 8-bit row (29.05 GB)
#   extra : NVFP4 target (lithos-metal native path) + BF16 source (Core AI export)
# The 8-bit MLX row uses mlx-community/Qwen3.8-27B-8bit, which is already cached.
set -euo pipefail

: "${HF_HOME:?HF_HOME must point at the shared cache (~/Developer/ml_source/huggingface)}"

step() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }

core() {
  step "LithosAI/Qwen3.8-27B-DSpark-NVFP4"
  hf download LithosAI/Qwen3.8-27B-DSpark-NVFP4
  step "mlx-community/Qwen3.8-27B-4bit"
  hf download mlx-community/Qwen3.8-27B-4bit
}

gguf() {
  step "unsloth/Qwen3.8-27B-GGUF (UD-Q4_K_M + MTP + mmproj-F16)"
  hf download unsloth/Qwen3.8-27B-GGUF \
    Qwen3.8-27B-UD-Q4_K_M.gguf \
    MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
    mmproj-F16.gguf \
    config.json README.md
}

gguf_q8() {
  step "unsloth/Qwen3.8-27B-GGUF Q8_0 (29.05 GB; llama.cpp 8-bit row, added 2026-10-19)"
  hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-Q8_0.gguf
}

extra() {
  step "nvidia/Qwen3.8-27B-NVFP4"
  hf download nvidia/Qwen3.8-27B-NVFP4
  step "Qwen/Qwen3.8-27B (BF16)"
  hf download Qwen/Qwen3.8-27B
}

groups=("$@")
[ ${#groups[@]} -eq 0 ] && groups=(core gguf)
for g in "${groups[@]}"; do
  case "$g" in
    core|gguf|gguf_q8|extra) "$g" ;;
    *) echo "unknown group: $g" >&2; exit 2 ;;
  esac
done
step "done: ${groups[*]}"
