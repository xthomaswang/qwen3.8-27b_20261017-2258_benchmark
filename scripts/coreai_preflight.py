#!/usr/bin/env python3
# Run with the coreai-models venv, CPU only, no weights read:
#   cd ~/Developer/mlsys/serving/coreai-models
#   .venv/bin/python -I ~/Developer/mlsys/experiments/qwen3.8-27b_20261017-2258_benchmark/scripts/coreai_preflight.py qwen3.8-27b
# See coreai/env.md section 4.1.
"""Weight-free preflight of `coreai.llm.export qwen3.8-27b` (CPU only, no tensor data read).

Resolves the registry preset offline, reads config.json, builds the model on the meta
device, and runs the memory-efficient loader's safetensors key index over the shard
headers. Nothing here allocates weights or touches the GPU.
"""

import os
import sys

os.environ["HF_HUB_OFFLINE"] = "1"

from huggingface_hub import snapshot_download  # noqa: E402

from coreai_models.export.pipeline import resolve_model  # noqa: E402
from coreai_models.llm.export import _resolve_export_config, build_parser  # noqa: E402
from coreai_models.models.base import (  # noqa: E402
    _build_safetensors_key_index,
    _resolve_safetensors_files,
)

short_name = sys.argv[1] if len(sys.argv) > 1 else "qwen3.8-27b"
args = build_parser().parse_args([short_name, "--output-dir", os.devnull])
cfg = _resolve_export_config(args)
resolved = resolve_model(cfg)
print(f"preset -> hf_id={cfg.hf_model_id} compression={cfg.compression} "
      f"precision={cfg.compute_precision} max_ctx={resolved.max_context_length}")
print(f"model_type={resolved.model_type} class={resolved.model_class.__name__} "
      f"quant_cfg={'yes' if resolved.quantization_config else 'no'}")

model_dir = snapshot_download(
    cfg.hf_model_id, allow_patterns=["*.safetensors", "*.safetensors.index.json", "config.json"]
)
print(f"offline snapshot -> {model_dir.replace(os.path.expanduser('~'), '~')}")

cls = resolved.model_class
config = cls._get_reauthored_config(resolved.hf_config, resolved.max_context_length)
model = cls(config=config, model_device="meta")
n_params = sum(p.numel() for p in model.parameters())
print(f"meta model: {n_params / 1e9:.3f} B params "
      f"(kv layers {cls.kv_cache_layer_count(config)}, delta layers {cls.delta_cache_layer_count(config)})")

files = _resolve_safetensors_files(model_dir)
per_layer, shared = _build_safetensors_key_index(
    files,
    num_layers=None,
    hf_state_dict_prefix=resolved.entry.hf_state_dict_prefix,
    extra_shared_keys=cls._extra_hf_shared_keys,
)
n_layer_keys = sum(len(v) for v in per_layer.values())
print(f"loader index: {len(files)} shards, {len(per_layer)} layers, {n_layer_keys} per-layer keys, "
      f"{len(shared)} shared keys: {sorted(shared)[:6]}")
