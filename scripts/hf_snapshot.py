#!/usr/bin/env python3
"""Resolve a Hugging Face cache snapshot and check that the files a server needs are complete.

Usage: hf_snapshot.py <org/name> [--safetensors] [--file REL]... [--hint TEXT] [--quiet]

- The snapshot is `$HF_HUB_CACHE` (or `$HF_HOME/hub`) / `models--<org>--<name>/snapshots/<refs/main>`.
- `--safetensors` requires config.json, model.safetensors.index.json and every shard it lists.
- A file is complete when it resolves (the cache links through `hub/blobs/`) and its size equals
  the size recorded in `trees/<commit>.json`. Safetensors shards must also match the size their
  own header declares; GGUF files must start with the GGUF magic.
- Leftover `.incomplete` blobs from paused downloads are ignored once the real file is complete.
  They are reported only for files that are still missing.

Prints the snapshot directory on stdout whenever refs/main resolves, even when files are missing,
and status lines on stderr. Exit 0 = complete, 4 = missing or incomplete, 2 = usage error.
Stdlib only; reads metadata and file headers, never weights. Run it with `python3 -I`.
"""

import argparse
import json
import os
import struct
import sys
import time


def hub_dir():
    if os.environ.get("HF_HUB_CACHE"):
        return os.environ["HF_HUB_CACHE"]
    home = os.environ.get("HF_HOME") or os.path.expanduser("~/Developer/ml_source/huggingface")
    return os.path.join(home, "hub")


def human(n):
    if n >= 1e8:
        return "%.2f GB" % (n / 1e9)
    if n >= 1e5:
        return "%.1f MB" % (n / 1e6)
    return "%d B" % n


def partial_note(blobs, key, expected):
    """Describe the newest .incomplete blob for one blob key (LFS sha256 or git blob id)."""
    if not key or not os.path.isdir(blobs):
        return "not downloaded yet"
    newest = None
    for name in os.listdir(blobs):
        if name.startswith(key + ".") and name.endswith(".incomplete"):
            st = os.stat(os.path.join(blobs, name))
            if newest is None or st.st_mtime > newest.st_mtime:
                newest = st
    if newest is None:
        return "not downloaded yet"
    age = time.time() - newest.st_mtime
    state = "downloading" if age < 120 else "partial download paused"
    total = (" of " + human(expected)) if expected else ""
    return "%s: %s%s, last write %ds ago" % (state, human(newest.st_size), total, age)


def safetensors_problem(path, size):
    with open(path, "rb") as f:
        head = f.read(8)
        if len(head) < 8:
            return "truncated safetensors header"
        n = struct.unpack("<Q", head)[0]
        if n > 200_000_000 or 8 + n > size:
            return "safetensors header length out of range"
        meta = json.loads(f.read(n))
    end = max((v["data_offsets"][1] for k, v in meta.items() if k != "__metadata__"), default=0)
    if 8 + n + end != size:
        return "size %d != %d declared by its safetensors header" % (size, 8 + n + end)
    return None


def gguf_problem(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GGUF":
            return "not a GGUF file (bad magic)"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", help="org/name")
    ap.add_argument("--safetensors", action="store_true", help="require config, index and all shards")
    ap.add_argument("--file", action="append", default=[], help="required file, relative to the snapshot")
    ap.add_argument("--hint", default="", help="how to fetch it, shown when it is missing")
    ap.add_argument("--quiet", action="store_true", help="print nothing on success")
    a = ap.parse_args()
    if a.repo.count("/") != 1:
        ap.error("repo must look like org/name")

    hint = (" (" + a.hint + ")") if a.hint else ""

    def bad(msg):
        sys.stderr.write("  NOT READY  %s: %s%s\n" % (a.repo, msg, hint))
        return 4

    repo_dir = os.path.join(hub_dir(), "models--" + a.repo.replace("/", "--"))
    if not os.path.isdir(repo_dir):
        return bad("not in the HF cache")
    ref = os.path.join(repo_dir, "refs", "main")
    if not os.path.isfile(ref):
        return bad("no refs/main yet")
    with open(ref) as f:
        commit = f.read().strip()
    snap = os.path.join(repo_dir, "snapshots", commit)
    print(snap)
    if not os.path.isdir(snap):
        return bad("snapshot %s is missing" % commit[:8])

    tree = {}
    tree_path = os.path.join(repo_dir, "trees", commit + ".json")
    if os.path.isfile(tree_path):
        with open(tree_path) as f:
            tree = json.load(f).get("files", {})

    required = list(a.file)
    if a.safetensors:
        required += ["config.json", "model.safetensors.index.json"]
        index = os.path.join(snap, "model.safetensors.index.json")
        if os.path.exists(index):
            with open(index) as f:
                required += sorted(set(json.load(f)["weight_map"].values()))

    blobs = os.path.join(repo_dir, "blobs")
    problems, total = [], 0
    for rel in dict.fromkeys(required):  # keep order, drop duplicates
        path = os.path.join(snap, rel)
        entry = tree.get(rel) or {}
        expected = entry.get("size")
        if not os.path.exists(path):  # follows the snapshot -> blobs -> shared store links
            key = entry.get("lfs_sha256") or entry.get("blob_id")
            problems.append("%s missing (%s)" % (rel, partial_note(blobs, key, expected)))
            continue
        size = os.stat(path).st_size
        total += size
        if expected is not None and size != expected:
            problems.append("%s is %s, expected %s" % (rel, human(size), human(expected)))
        elif size == 0 and expected != 0:
            problems.append("%s is empty" % rel)
        elif rel.endswith(".safetensors"):
            p = safetensors_problem(path, size)
            if p:
                problems.append("%s: %s" % (rel, p))
        elif rel.endswith(".gguf"):
            p = gguf_problem(path)
            if p:
                problems.append("%s: %s" % (rel, p))

    if problems:
        sys.stderr.write("  NOT READY  %s @ %s%s\n" % (a.repo, commit[:8], hint))
        for p in problems:
            sys.stderr.write("             - %s\n" % p)
        return 4
    if not a.quiet:
        shards = sum(1 for r in required if r.endswith((".safetensors", ".gguf")))
        sys.stderr.write("  ok         %s @ %s: %d weight file(s), %s%s\n" % (
            a.repo, commit[:8], shards, human(total), "" if tree else " (no trees/ record; sizes unchecked)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
