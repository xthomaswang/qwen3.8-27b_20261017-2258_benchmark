# Environment

Recorded 2026-10-17. Each framework's `env.md` repeats the OS/Xcode builds that were
current at the time of its own run.

## Machine

| Item | Value |
| --- | --- |
| Model | MacBook Pro (Mac17,7) |
| Chip | Apple M5 Max — 18-core CPU (6 Super + 12 Performance), 40-core GPU, Metal 4 |
| Memory | 128 GB unified |
| GPU wired limit | `iogpu.wired_limit_mb = 0` (macOS default) |
| Power | AC power, battery 100%; `powermode 2` (High Power); sleep prevented with `caffeinate` during runs |

## Software

| Item | Value |
| --- | --- |
| macOS | 27.2, build 26B5101f |
| Xcode (default, `xcode-select`) | Xcode 27.1, build 27A9275 |
| Xcode beta (Core AI only, via `DEVELOPER_DIR`) | Xcode 27.2, build 27B5028f |
| uv | 0.12.19 |
| cmake | 4.4.3 |
| huggingface_hub CLI (`hf`) | 2.2.0 |

## Checkpoints

All checkpoints live in the shared Hugging Face cache (`$HF_HOME`). None are copied into
this repo. `scripts/download_models.sh` fetches them.

| Use | Repo | Files | Size |
| --- | --- | --- | --- |
| llama.cpp target | `unsloth/Qwen3.8-27B-GGUF` | `Qwen3.8-27B-UD-Q4_K_M.gguf` | 16.5 GB |
| llama.cpp MTP draft | `unsloth/Qwen3.8-27B-GGUF` | `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` | 1.4 GB |
| llama.cpp vision projector | `unsloth/Qwen3.8-27B-GGUF` | `mmproj-F16.gguf` / `mmproj-BF16.gguf` | 0.9 GB each |
| MLX stacks, lithos-metal (affine) | `mlx-community/Qwen3.8-27B-4bit` | all | 16.1 GB |
| lithos-metal native | `nvidia/Qwen3.8-27B-NVFP4` | all | 22.0 GB |
| lithos-metal DSpark draft | `LithosAI/Qwen3.8-27B-DSpark-NVFP4` | all | 1.1 GB |
| Core AI export source | `Qwen/Qwen3.8-27B` (BF16) | all | 55.6 GB |
| Optional 8-bit reference row | `mlx-community/Qwen3.8-27B-8bit` | already cached | 28 GB |
