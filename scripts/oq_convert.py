#!/usr/bin/env python3
"""Convert the BF16 Qwen3.8-27B checkpoint to an oMLX oQ checkpoint that keeps the MTP head.

The mlx-community 4-bit and 8-bit checkpoints carry no mtp.* tensors, so oMLX's Lightning MTP
cannot run on them. oQ (omlx/oq.py) quantizes tensor by tensor from the BF16 source and, with
preserve_mtp, keeps the MTP head, which is what the oMLX-with-MTP rows need.

Run with the benchmark's oMLX interpreter, outside any timed segment (it loads the GPU), e.g.
  HF_HUB_OFFLINE=1 ~/Developer/mlsys/serving/omlx_0.7/.venv/bin/python scripts/oq_convert.py
Writes ~/Developer/mlsys/models/oq/Qwen3.8-27B-oQ4-mtp (self-converted models live in
~/Developer/mlsys/models). Then it links the directory into models/hf-bench and sets
max_context_window 131072 for it in the bench oMLX's model_settings.json, as
scripts/omlx_configure.sh does for the mlx-community tiers.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

HOME = Path.home()
SOURCE = HOME / "Developer/ml_source/huggingface/hub/models--Qwen--Qwen3.8-27B/snapshots"
MODELS = HOME / "Developer/mlsys/models"
SETTINGS = HOME / "Developer/mlsys/serving/omlx_0.7/.bench-home/model_settings.json"


def snapshot_dir() -> Path:
    snaps = sorted(p for p in SOURCE.iterdir() if (p / "config.json").exists())
    if not snaps:
        sys.exit(f"no BF16 snapshot under {SOURCE}")
    return snaps[-1]


def register(out: Path) -> None:
    link = MODELS / "hf-bench" / out.name
    if not link.is_symlink():
        link.symlink_to(Path("..") / "oq" / out.name)
        print(f"linked {link} -> ../oq/{out.name}")
    data = json.loads(SETTINGS.read_text()) if SETTINGS.exists() else {"version": 1, "models": {}}
    entry = data.setdefault("models", {}).setdefault(out.name, {})
    if entry.get("max_context_window") != 131072:
        entry["max_context_window"] = 131072
        tmp = SETTINGS.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        tmp.replace(SETTINGS)
        print(f"max_context_window 131072 set for {out.name} in {SETTINGS}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--level", type=float, default=4, help="oQ level (default 4)")
    ap.add_argument("--register-only", action="store_true", help="only link and configure an existing output")
    a = ap.parse_args()
    name = f"Qwen3.8-27B-oQ{a.level:g}-mtp"
    out = MODELS / "oq" / name
    if a.register_only:
        register(out)
        return 0
    if out.exists():
        sys.exit(f"{out} exists; delete it first or use --register-only")
    out.parent.mkdir(parents=True, exist_ok=True)
    src = snapshot_dir()
    from omlx.oq import quantize_oq_streaming

    last = [0.0]

    def progress(phase: str, pct: float, detail: str = "", meta: dict | None = None) -> None:
        now = time.time()
        if now - last[0] >= 30 or pct >= 100:
            print(f"{time.strftime('%T')} {pct:5.1f}% {phase.split('|', 1)[0]} {detail}", flush=True)
            last[0] = now

    print(f"{time.strftime('%T')} oQ{a.level:g} with the MTP head: {src} -> {out}", flush=True)
    t0 = time.time()
    quantize_oq_streaming(str(src), str(out), a.level, 64, progress, False, None, None, "", "bfloat16", True, True)
    print(f"{time.strftime('%T')} done in {time.time() - t0:.0f} s", flush=True)
    register(out)
    return 0


if __name__ == "__main__":
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    sys.exit(main())
