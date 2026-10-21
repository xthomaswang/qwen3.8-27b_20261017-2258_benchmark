#!/bin/bash
# Source build of tvm-ffi, tvm-ffi-orcjit, TVM and MLC-LLM into the bench venv.
# Every heavy step runs under heavy.py (CPU-courtesy policy around the GPU lock).
# Usage: build_all.sh [first_step]   (steps: ffi orcjit tvm tvm_py mlc)
set -u
B=~/Developer/mlsys/serving/mlc-llm_bench
H="$B/.venv/bin/python -I $HOME/Developer/mlsys/serving/mlc-llm_bench/bench-tools/heavy.py --restartable --"
UVI="uv pip install --python $B/.venv/bin/python --no-build-isolation --no-deps -v"
export CCACHE_DIR="$B/.ccache" CCACHE_MAXSIZE=8G
export LLVM_PREFIX=/opt/homebrew/opt/llvm@23
cd "$B" || exit 1
steps=(ffi orcjit tvm tvm_py mlc)
start=${1:-ffi}
run=0
for s in "${steps[@]}"; do
  [ "$s" = "$start" ] && run=1
  [ $run = 1 ] || continue
  log="$B/logs/build-$s.log"
  echo "=== step $s -> $log ($(date '+%F %T'))"
  case $s in
    ffi)    $H $UVI ./3rdparty/tvm/3rdparty/tvm-ffi > "$log" 2>&1 ;;
    orcjit) $H $UVI -C cmake.define.ZLIB_STATIC=$(xcrun --show-sdk-path)/usr/lib/libz.tbd \
                 -C cmake.define.ZSTD_STATIC=/opt/homebrew/opt/zstd/lib/libzstd.a \
                 ./3rdparty/tvm/3rdparty/tvm-ffi/addons/tvm_ffi_orcjit > "$log" 2>&1 ;;
    tvm)    $H cmake --build 3rdparty/tvm/build > "$log" 2>&1 ;;
    tvm_py) $H $UVI -C cmake.build-type=RelWithDebInfo -e ./3rdparty/tvm > "$log" 2>&1 ;;
    mlc)    $H $UVI -e . > "$log" 2>&1 ;;
  esac
  rc=$?
  echo "=== step $s exit=$rc ($(date '+%F %T'))"
  grep '^\[heavy' "$log" | tail -3
  [ $rc = 0 ] || { echo "FAILED at $s"; tail -30 "$log"; exit $rc; }
done
echo "=== all steps done ($(date '+%F %T'))"
