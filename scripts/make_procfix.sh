#!/usr/bin/env bash
# make_procfix.sh <tier> [--dry-run | --check]
#
# Builds ~/Developer/mlsys/models/derived/Qwen3.8-27B-<tier>-procfix, the metadata-only view
# that vLLM-Metal serves. transformers 5.17/5.20 has no Qwen3VLImageProcessor class, which the
# 8-bit processor_config.json names, so vLLM-Metal fails with "Unrecognized image processor".
# The view links every snapshot file into the HF cache except two regular files:
#   processor_config.json  image_processor.image_processor_type = Qwen2VLImageProcessor
#   README.md              what was changed and why (the upstream README is NOT linked, so
#                          writing it can never modify the HF cache)
# Runs only once mlx-community/Qwen3.8-27B-<tier> is complete. Idempotent: an existing view is
# verified and never modified; a stale one is reported for manual removal.
# --check only verifies (exit 0 valid, 1 missing or stale). --dry-run prints the plan.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -ge 1 ] || { print_header "${BASH_SOURCE[0]}" >&2; exit "$EX_USAGE"; }
TIER=$1
MODE=build
case "${2:-}" in --check) MODE=check ;; --dry-run) MODE=dry ;; '') ;; *) die "$EX_USAGE" "unknown option: $2" ;; esac
case "$TIER" in 8bit|4bit) ;; *) die "$EX_USAGE" "tier must be 8bit or 4bit" ;; esac
REPO="mlx-community/Qwen3.8-27B-$TIER"
VIEW="$MLSYS/models/derived/Qwen3.8-27B-$TIER-procfix"

QUIET=--quiet; [ "$MODE" = check ] || QUIET=''
SNAP=$(check_snapshot "$REPO" "fetch: scripts/download_models.sh core" --safetensors ${QUIET:+"$QUIET"}) \
  || die "$EX_NOT_READY" "$REPO is not complete yet; nothing done"

"$PY" -I - "$MODE" "$SNAP" "$VIEW" "$HF_HOME" "$REPO" <<'EOF'
import datetime, json, os, sys, tempfile

mode, snap, view, hf_home, repo = sys.argv[1:6]
OLD, NEW = "Qwen3VLImageProcessor", "Qwen2VLImageProcessor"
OWN = ("processor_config.json", "README.md")   # regular files in the view; never links


def fail(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def linked_names():
    return sorted(n for n in os.listdir(snap) if not n.startswith(".") and n not in OWN)


def patched():
    with open(os.path.join(snap, "processor_config.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    ip = cfg.get("image_processor")
    if not isinstance(ip, dict) or "image_processor_type" not in ip:
        fail("%s: processor_config.json has no image_processor.image_processor_type" % repo)
    shipped = ip["image_processor_type"]
    if shipped not in (OLD, NEW):
        fail("%s: unexpected image_processor_type %r; not patching" % (repo, shipped))
    ip["image_processor_type"] = NEW
    return cfg, shipped


def verify(where):
    """Return (problems, warnings) for a view directory."""
    problems, warnings = [], []
    for n in linked_names():
        p = os.path.join(where, n)
        if not os.path.islink(p):
            problems.append("%s: not a symlink" % n)
        elif os.readlink(p) != os.path.join(snap, n):
            problems.append("%s -> %s, expected %s" % (n, os.readlink(p), os.path.join(snap, n)))
        elif not os.path.exists(p):
            problems.append("%s: dangling link" % n)
    pc = os.path.join(where, "processor_config.json")
    if os.path.islink(pc) or not os.path.isfile(pc):
        problems.append("processor_config.json: not a regular file")
    else:
        with open(pc, encoding="utf-8") as f:
            if json.load(f) != patched()[0]:
                problems.append("processor_config.json differs from the patched snapshot file")
    rd = os.path.join(where, "README.md")
    if os.path.islink(rd):
        warnings.append("warning: README.md is a symlink to %s; anything written to it lands in "
                        "the HF cache" % os.path.realpath(rd))
    elif not os.path.isfile(rd):
        warnings.append("warning: README.md is missing")
    extra = sorted(set(os.listdir(where)) - set(linked_names()) - set(OWN))
    if extra:
        warnings.append("warning: extra entries not in the snapshot: %s" % " ".join(extra))
    return problems, warnings


def report(problems, warnings):
    for w in warnings:
        print("  " + w)
    for p in problems:
        print("  problem: " + p)


def readme(shipped):
    commit = os.path.basename(snap)
    tier = repo.rsplit("-", 1)[1]
    if shipped == OLD:
        change = ("`processor_config.json` changes `image_processor.image_processor_type` from\n"
                  "`Qwen3VLImageProcessor` (not a class in transformers 5.17 or 5.20) to the equivalent\n"
                  "`Qwen2VLImageProcessor`, the class `preprocessor_config.json` already names, with the\n"
                  "same patch_size 16 / merge_size 2.")
    else:
        change = ("This snapshot already ships `Qwen2VLImageProcessor` in `processor_config.json`, so the\n"
                  "file here is content-identical to the shipped one (only re-serialized). The view exists\n"
                  "so that both vLLM-Metal tiers launch the same way; the 8-bit snapshot does need the fix.")
    return ("# Qwen3.8-27B-%s-procfix\n\n"
            "Metadata-only view of the HF cache snapshot `%s`\n(`%s`). Every file is a symlink into "
            "that snapshot except `processor_config.json`\nand this README. The upstream `README.md` is "
            "deliberately not linked, so writing this file\ncan never modify the HF cache.\n\n"
            "%s\n\nWeights and preprocessing parameters are unchanged. Made %s by\n"
            "`scripts/make_procfix.sh %s` for the vLLM-Metal rows of the qwen3.8-27b serving benchmark.\n"
            % (tier, repo, commit, change, datetime.date.today().isoformat(), tier))


def create(path, text):
    # O_EXCL: never follows or replaces an existing entry, so nothing is written through a link.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)


cfg, shipped = patched()
exists = os.path.lexists(view)
if mode == "check" or exists:
    if not exists:
        print("%s does not exist (run scripts/make_procfix.sh %s)" % (view, repo.rsplit("-", 1)[1]))
        sys.exit(1)
    problems, warnings = verify(view)
    report(problems, warnings)
    if problems:
        fail("%s exists but is stale; it was not modified. Remove it (rm -r) and rerun." % view)
    print("ok    %s matches %s @ %s" % (view, repo, os.path.basename(snap)[:8]))
    sys.exit(0)

parent = os.path.dirname(view)
cache = os.path.realpath(hf_home)
if os.path.realpath(parent) == cache or os.path.realpath(parent).startswith(cache + os.sep):
    fail("refusing: %s resolves into the HF cache (%s)" % (parent, cache))
note = "already %s; written unchanged" % NEW if shipped == NEW else "%s -> %s" % (OLD, NEW)
if mode == "dry":
    print("would create %s:" % view)
    print("  %d symlinks into %s" % (len(linked_names()), snap))
    print("  processor_config.json (%s)" % note)
    print("  README.md")
    sys.exit(0)
os.makedirs(parent, exist_ok=True)
tmp = tempfile.mkdtemp(dir=parent, prefix="." + os.path.basename(view) + ".")
for n in linked_names():
    os.symlink(os.path.join(snap, n), os.path.join(tmp, n))
create(os.path.join(tmp, "processor_config.json"), json.dumps(cfg, indent=2) + "\n")
create(os.path.join(tmp, "README.md"), readme(shipped))
os.chmod(tmp, 0o755)
problems, warnings = verify(tmp)
if problems:
    report(problems, warnings)
    fail("internal error: the new view does not verify; left at %s" % tmp)
os.rename(tmp, view)   # fails if the view appeared meanwhile; nothing is overwritten
print("created %s: %d symlinks, processor_config.json (%s), README.md" % (view, len(linked_names()), note))
EOF
