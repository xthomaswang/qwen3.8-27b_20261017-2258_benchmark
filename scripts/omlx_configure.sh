#!/usr/bin/env bash
# omlx_configure.sh [--dry-run]
#
# Prepares oMLX 0.7 for the benchmark without starting a server. Idempotent.
# For each tier (8bit, 4bit) whose mlx-community/Qwen3.8-27B-<tier> snapshot is complete:
#   1. links ~/Developer/mlsys/models/hf-bench/models--mlx-community--Qwen3.8-27B-<tier>
#      to its HF cache entry, in the same style as the existing 8-bit link;
#   2. sets max_context_window: 131072 for model id mlx-community--Qwen3.8-27B-<tier> in
#      serving/omlx_0.7/.bench-home/model_settings.json ({"version": 1, "models": {...}};
#      omlx/env.md "Context 131072"), keeping every other setting and model as it is.
# Incomplete tiers are skipped. Refuses while anything listens on 8703, because a running
# server rewrites model_settings.json. An existing file is backed up before it changes.
# OMLX_BENCH_HOME and OMLX_BENCH_MODELS override the two paths (tests only).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DRY=0
case "${1:-}" in --dry-run) DRY=1 ;; '') ;; -h|--help) print_header "${BASH_SOURCE[0]}"; exit 0 ;;
  *) print_header "${BASH_SOURCE[0]}" >&2; exit "$EX_USAGE" ;; esac
BASE="${OMLX_BENCH_HOME:-$SERVING/omlx_0.7/.bench-home}"
MODELS="${OMLX_BENCH_MODELS:-$MLSYS/models/hf-bench}"
CTX=131072

if [ -n "$(listen_pids 8703)" ]; then
  die "$EX_REFUSED" "port 8703 is in use (oMLX running?): stop it first; a running server rewrites model_settings.json"
fi
[ -d "$BASE" ] || die 1 "missing base path $BASE (omlx/env.md resume step 5 creates it)"
[ -d "$MODELS" ] || die 1 "missing model dir $MODELS"

IDS=()
for TIER in 8bit 4bit; do
  REPO="mlx-community/Qwen3.8-27B-$TIER"
  ENTRY="models--mlx-community--Qwen3.8-27B-$TIER"
  if ! check_snapshot "$REPO" "fetch: scripts/download_models.sh core" --safetensors --quiet >/dev/null; then
    say "skip $TIER: snapshot not complete"
    continue
  fi
  LINK="$MODELS/$ENTRY" TARGET="$HF_HUB/$ENTRY"
  if [ -L "$LINK" ]; then
    [ "$(readlink "$LINK")" = "$TARGET" ] || die 1 "$LINK points to $(readlink "$LINK"), expected $TARGET; not changing it"
    say "ok    link $ENTRY"
  elif [ -e "$LINK" ]; then
    die 1 "$LINK exists and is not a symlink; not changing it"
  elif [ "$DRY" -eq 1 ]; then
    say "would link $LINK -> $TARGET"
  else
    ln -s "$TARGET" "$LINK"
    say "linked $LINK -> $TARGET"
  fi
  IDS+=("mlx-community--Qwen3.8-27B-$TIER")
done
[ "${#IDS[@]}" -gt 0 ] || die "$EX_NOT_READY" "no complete tier; nothing to configure"

"$PY" -I - "$BASE/model_settings.json" "$CTX" "$DRY" "${IDS[@]}" <<'EOF'
import json, os, shutil, sys, tempfile, time

path, ctx, dry, ids = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "1", sys.argv[4:]
if os.path.islink(path):
    sys.exit("%s is a symlink; refusing to write through it" % path)
existed = os.path.exists(path)
data = {"version": 1, "models": {}}
if existed:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict) or data.get("version", 1) != 1 or not isinstance(data.get("models", {}), dict):
        sys.exit("%s: unexpected format; not touching it" % path)
models = data.setdefault("models", {})
changes = []
for mid in ids:
    entry = models.setdefault(mid, {})
    if not isinstance(entry, dict):
        sys.exit("%s: settings for %s are not an object; not touching it" % (path, mid))
    if entry.get("max_context_window") == ctx:
        print("ok    %s max_context_window %d" % (mid, ctx))
    else:
        changes.append((mid, entry.get("max_context_window")))
        entry["max_context_window"] = ctx
if not changes:
    sys.exit(0)
for mid, old in changes:
    print("%s %s max_context_window: %s -> %d" % ("would set" if dry else "set  ", mid, old, ctx))
if dry:
    sys.exit(0)
if existed:
    backup = path + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, backup)
    print("backup %s" % backup)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".model_settings.", suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)  # the layout oMLX itself writes
    f.flush()
    os.fsync(f.fileno())
os.chmod(tmp, 0o644)
os.replace(tmp, path)
print("wrote %s" % path)
EOF
