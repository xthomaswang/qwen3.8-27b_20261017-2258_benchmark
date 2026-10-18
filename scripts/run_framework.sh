#!/usr/bin/env bash
# Run one framework variant end to end: serve -> wait -> warm-up -> agentbench run-all (--preflight) -> stop.
# The main agent must already hold the GPU lock (scripts/gpu_lock.sh acquire ...); this script never takes it.
# Usage: run_framework.sh <framework> <variant> <tier> <profile> <tag> <suites> [extra run-all args...]
#   e.g. run_framework.sh llama.cpp mtp-on 4bit llamacpp 4bit-mtp-on gate,m1,m2,m3,m4,m5 --spec-label on
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
[ $# -ge 6 ] || { sed -n 2,5p "$0"; exit 2; }
fw=$1 variant=$2 tier=$3 profile=$4 tag=$5 suites=$6; shift 6
grep -q '^holder: local_ai-benchmark session' "$HOME/Developer/mlsys/experiments/.gpu-lock" 2>/dev/null \
  || { echo "run_framework: the GPU lock is not held by us; acquire it first" >&2; exit 5; }
dry=$(scripts/serve.sh "$fw" "$variant" "$tier" --dry-run) || { echo "$dry" | tail -5; exit 4; }
model=$(printf '%s\n' "$dry" | sed -n 's/^ *# model id: *//p' | head -1)
base=$(printf '%s\n' "$dry" | sed -n 's/^ *# endpoint: *//p' | head -1 | sed 's#/v1$##')
port=${base##*:}
scripts/serve.sh "$fw" "$variant" "$tier" > /dev/null 2>&1 &
sleep 2
scripts/wait_ready.sh "$port" 1800 || { scripts/stop_server.sh "$fw"; exit 3; }
pid=$(cat "logs/$fw.pid")
flags=$(grep -v '^#' "logs/$fw-$variant-$tier.cmd" | tail -1 | sed "s|$HOME|~|g")
version=$(grep -m1 '# framework:' "logs/$fw-$variant-$tier.cmd" | sed 's/.*# framework: *//')
# Warm-up: one short request so model load / first-request compilation never lands in a measurement.
warm_model="$model"; [ "$profile" = mlxlm ] && warm_model=default_model
curl -s -m 900 "$base/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$warm_model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with: ok\"}],\"max_tokens\":8,\"temperature\":0}" \
  -o /dev/null -w "warm-up: HTTP %{http_code} in %{time_total}s\n"
sleep 20   # let the system settle before the quiet check
(cd harness && uv run agentbench run-all --profile "$profile" --base-url "$base" --model "$model" \
  --framework "$fw" --framework-version "$version" --launch-flags "$flags" --tag "$tag" \
  --server-pid "$pid" --suites "$suites" --preflight \
  --preflight-cmd "$ROOT/scripts/quiet_check.sh --allow-pid $pid" "$@")
rc=$?
scripts/stop_server.sh "$fw"
exit $rc
