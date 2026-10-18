#!/usr/bin/env bash
# Download every checkpoint used by this benchmark into the shared HF cache.
# Files stay in $HF_HOME (never copied into this repo); frameworks load them by repo id
# or by snapshot path. Order follows the measurement order (llama.cpp first).
set -euo pipefail

: "${HF_HOME:?HF_HOME must point at the shared cache (~/Developer/ml_source/huggingface)}"

step() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }

# llama.cpp: 4-bit GGUF target, MTP draft head, vision projector (F16 and BF16).
step "unsloth/Qwen3.8-27B-GGUF (UD-Q4_K_M + MTP + mmproj)"
hf download unsloth/Qwen3.8-27B-GGUF \
  Qwen3.8-27B-UD-Q4_K_M.gguf \
  MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
  mmproj-F16.gguf mmproj-BF16.gguf \
  config.json README.md

# MLX stacks (mlx-lm, oMLX, vLLM-Metal) and lithos-metal's affine-4bit path.
step "mlx-community/Qwen3.8-27B-4bit"
hf download mlx-community/Qwen3.8-27B-4bit

# lithos-metal's native path: NVFP4 target + DSpark draft head.
step "nvidia/Qwen3.8-27B-NVFP4"
hf download nvidia/Qwen3.8-27B-NVFP4
step "LithosAI/Qwen3.8-27B-DSpark-NVFP4"
hf download LithosAI/Qwen3.8-27B-DSpark-NVFP4

# Core AI export source (reference row only).
step "Qwen/Qwen3.8-27B (BF16)"
hf download Qwen/Qwen3.8-27B

step "done"
