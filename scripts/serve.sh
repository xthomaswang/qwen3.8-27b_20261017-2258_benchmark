#!/usr/bin/env bash
# serve.sh <framework> <variant> <model-tier> [--dry-run] [-- extra server args...]
#
# Starts one benchmark server in the foreground with HF_HUB_OFFLINE=1. Stop it with Ctrl-C
# or scripts/stop_server.sh <framework>. A real run writes:
#   logs/<framework>-<variant>-<tier>-<timestamp>.log  stdout+stderr (tee'd; also shown here)
#   logs/<framework>-<variant>-<tier>.cmd              exact command line + provenance
#   logs/<framework>.pid                               the server's PID (serve.sh execs into it)
#
#   framework     variants                   tiers        port
#   mlx-lm        server                     8bit 4bit    8701
#   llama.cpp     mtp-off mtp-on conc        4bit         8702
#   omlx          spec-off  (spec-on: stub)  8bit 4bit    8703
#   lithos-metal  dspark no-draft            4bit nvfp4   8704
#   vllm-metal    spec-off  (spec-on: stub)  8bit 4bit    8705
#
# --dry-run runs every check and prints the exact command; it writes and starts nothing.
# A real run also needs our GPU lock (scripts/gpu_lock.sh acquire), port 8500 free and no
# server on 8701-8705. Words after `--` are appended to the server command (e.g. -lv 4).
# LLAMA_MMPROJ=0 drops --mmproj for llama.cpp (the llama.cpp/env.md fallback for MTP + mmproj).
# Exit codes: 2 usage, 4 checkpoint/config not ready, 5 refused (lock/ports), 6 unsupported variant.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { print_header "${BASH_SOURCE[0]}"; }

DRY=0
POS=()
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    -*) usage >&2; die "$EX_USAGE" "unknown option: $1" ;;
    *) POS+=("$1") ;;
  esac
  shift
done
[ "${#POS[@]}" -eq 3 ] || { usage >&2; exit "$EX_USAGE"; }
FW=${POS[0]} VARIANT=${POS[1]} TIER=${POS[2]}
is_framework "$FW" || die "$EX_USAGE" "unknown framework '$FW' (one of: $FRAMEWORKS)"
PORT=$(fw_port "$FW")

WORKDIR='' MODEL_ID='' SNAP=''
CMD=() ENVV=() NOTES=() CKPTS=() PROV=() NOT_READY=() REFUSE=()

tilde() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }
ok() { say "  ok         $1"; }
need() { NOT_READY+=("$1"); say "  NOT READY  $1"; }
bad_tier() { die "$EX_USAGE" "$FW tiers: $1 (got '$TIER')"; }
bad_variant() { die "$EX_USAGE" "$FW variants: $1 (got '$VARIANT')"; }
unsupported() {
  say "$FW $VARIANT $TIER: not runnable."
  say "$1" | fold -s -w 96 | sed 's/^/  /'
  exit "$EX_UNSUPPORTED"
}
need_exe() { if [ -x "$1" ]; then ok "executable $(tilde "$1")"; else need "missing executable $1"; fi; }

dl_hint() {
  case "$1" in
    mlx-community/Qwen3.8-27B-8bit) echo "already cached for the agent benchmark; never re-download" ;;
    mlx-community/*|LithosAI/*) echo "fetch: scripts/download_models.sh core" ;;
    unsloth/*) echo "fetch: scripts/download_models.sh gguf" ;;
    *) echo "fetch: scripts/download_models.sh extra" ;;
  esac
}
# snapshot <org/name> [hf_snapshot.py args]: sets SNAP, records the checkpoint, flags NOT READY.
snapshot() {
  local repo=$1 rc=0; shift
  SNAP=$(check_snapshot "$repo" "$(dl_hint "$repo")" "$@") || rc=$?
  if [ "$rc" -eq 0 ]; then CKPTS+=("$repo@${SNAP##*/}"); else NOT_READY+=("$repo"); CKPTS+=("$repo (NOT READY)"); fi
  [ -n "$SNAP" ] || SNAP="<$repo: not in the HF cache>"
}

build_mlx_lm() {
  case "$TIER" in 8bit|4bit) ;; *) bad_tier "8bit 4bit" ;; esac
  case "$VARIANT" in server) ;; *) bad_variant "server" ;; esac
  local exe; exe=$(fw_exe mlx-lm)
  WORKDIR="$SERVING/mlx-lm"
  snapshot "mlx-community/Qwen3.8-27B-$TIER" --safetensors
  need_exe "$exe"
  ENVV+=(PYTHONUNBUFFERED=1)
  CMD=("$exe" --model "$SNAP" --host 127.0.0.1 --port "$PORT"
       --max-tokens 4096
       --prompt-cache-size 64 --prompt-cache-bytes 48GB
       --log-level INFO)
  MODEL_ID='omit "model" or send "default_model" (any other value reloads the model)'
  PROV+=("$(dist_versions "$WORKDIR/.venv" mlx_lm mlx mlx_metal)")
  NOTES+=("/health answers ok while the model is still loading; the first request waits for the load")
}

build_llama() {
  case "$TIER" in 4bit) ;; *) bad_tier "4bit (unsloth UD-Q4_K_M GGUF)" ;; esac
  case "$VARIANT" in mtp-off|mtp-on|conc) ;; *) bad_variant "mtp-off mtp-on conc" ;; esac
  local exe main=Qwen3.8-27B-UD-Q4_K_M.gguf mmproj=mmproj-F16.gguf mtp=MTP/mtp-Qwen3.8-27B-Q4_0.gguf
  local -a files=(--file "$main")
  exe=$(fw_exe llama.cpp)
  WORKDIR="$SERVING/llama.cpp"
  [ "${LLAMA_MMPROJ:-1}" = 0 ] || files+=(--file "$mmproj")
  [ "$VARIANT" != mtp-on ] || files+=(--file "$mtp")
  snapshot unsloth/Qwen3.8-27B-GGUF "${files[@]}"
  need_exe "$exe"
  CMD=("$exe" -m "$SNAP/$main")
  if [ "${LLAMA_MMPROJ:-1}" = 0 ]; then
    NOTES+=("LLAMA_MMPROJ=0: --mmproj omitted (llama.cpp/env.md section 3 fallback); text-only")
  else
    CMD+=(--mmproj "$SNAP/$mmproj")
  fi
  CMD+=(--host 127.0.0.1 --port "$PORT" --alias qwen3.8-27b
        -c 131072 -ngl all -fa on -ctk f16 -ctv f16
        --jinja --reasoning-format deepseek
        --ctx-checkpoints 32 --checkpoint-min-step 8192
        --cache-ram 8192
        --metrics --slots --no-webui --offline)
  case "$VARIANT" in
    mtp-off) CMD+=(-np 1 --spec-type none) ;;
    mtp-on) CMD+=(-np 1 -md "$SNAP/$mtp" --spec-type draft-mtp --spec-draft-n-max 3) ;;
    conc) CMD+=(-np 3 -kvu --spec-type none) ;;
  esac
  MODEL_ID=qwen3.8-27b
  NOTES+=("the server log is the tee'd stderr; env.md's --log-file is not passed (it would duplicate every line)")
}

build_omlx() {
  case "$TIER" in 8bit|4bit) ;; *) bad_tier "8bit 4bit" ;; esac
  case "$VARIANT" in
    spec-off) ;;
    spec-on) unsupported "oMLX speculative decoding cannot run from local files. Lightning MTP \
(mtp_enabled) needs MTP head weights in the target checkpoint, and mlx-community/Qwen3.8-27B-8bit \
and -4bit ship none (0 mtp.* tensors), so it would silently measure target-only decoding. DFlash \
(dflash_enabled) needs a Qwen3.8-27B DFlash draft checkpoint, and none is cached. The Splash \
external engine needs the splash launcher (not installed) plus a DFlash2 draft. Record oMLX M3 \
spec-on as n/a until one of these exists; then switch per run through PUT \
/admin/api/models/<id>/settings (omlx/env.md, 'Spec on' and 'Speculative decoding requirements')." ;;
    *) bad_variant "spec-off (spec-on is a stub)" ;;
  esac
  local exe base models entry="models--mlx-community--Qwen3.8-27B-$TIER" id="mlx-community--Qwen3.8-27B-$TIER" ctx k missing=''
  exe=$(fw_exe omlx)
  WORKDIR="$SERVING/omlx_0.7"; base="$WORKDIR/.bench-home"; models="$MLSYS/models/hf-bench"
  snapshot "mlx-community/Qwen3.8-27B-$TIER" --safetensors
  need_exe "$exe"
  if [ -d "$base" ]; then ok "base path $(tilde "$base")"; else need "missing base path $base (omlx/env.md resume step 5)"; fi
  if [ -L "$models/$entry" ] && [ "$(readlink "$models/$entry")" = "$HF_HUB/$entry" ]; then
    ok "model link $(tilde "$models/$entry")"
  else
    need "model link $models/$entry -> $HF_HUB/$entry missing or different (run scripts/omlx_configure.sh)"
  fi
  local read_ctx='import json, sys
try:
    print(json.load(open(sys.argv[1]))["models"][sys.argv[2]].get("max_context_window", ""))
except Exception:
    print("")'
  ctx=$("$PY" -I -c "$read_ctx" "$base/model_settings.json" "$id" 2>/dev/null || true)
  if [ "$ctx" = 131072 ]; then ok "max_context_window 131072 for $id"; else need "max_context_window for $id is '${ctx:-unset}', want 131072 (run scripts/omlx_configure.sh)"; fi
  for k in bonsai decode_fast glm_moe_dsa minimax_m3 qwen35_prefill; do
    ls "$WORKDIR/omlx/custom_kernels/$k/"_ext*.so >/dev/null 2>&1 || missing="$missing $k"
  done
  if [ -z "$missing" ]; then ok "native kernel modules built (5 of 5 _ext*.so)"; else need "native kernels not built:$missing (omlx/env.md resume step 2)"; fi
  # oMLX 0.7 writes ~/.omlx/bin/omlx-cluster-python and scans ~/.omlx/cluster/runtime on every start,
  # whatever OMLX_BASE_PATH says (omlx/cluster/worker_shim.py, cluster/launch.py). ~/.omlx belongs to the
  # agent-benchmark session, so this process gets its own HOME; every other path here is absolute.
  mkdir -p "$base/home"
  ENVV+=(HOME="$base/home" OMLX_BASE_PATH="$base" OMLX_HOST=127.0.0.1 OMLX_PORT="$PORT" OMLX_MODEL_DIR="$models"
         OMLX_HF_CACHE_ENABLED=false PYTHONUNBUFFERED=1)
  CMD=("$exe" serve --base-path "$base" --headless)
  MODEL_ID=$id
  PROV+=("$(dist_versions "$WORKDIR/.venv" omlx mlx mlx_lm mlx_vlm)")
  NOTES+=("HOME is isolated to .bench-home/home so the cluster shim and reaper never touch ~/.omlx")
  NOTES+=("models load on the first request (none is pinned); hf-bench lists every linked tier, so send exactly \"$id\"")
}

build_vllm() {
  case "$TIER" in 8bit|4bit) ;; *) bad_tier "8bit 4bit" ;; esac
  case "$VARIANT" in
    spec-off) ;;
    spec-on) unsupported "vLLM-Metal v0.31.0 has no speculative decoding for this model: hybrid GDN \
targets are excluded (docs/speculative_decoding.md:32), the Metal MTP path is Gemma4-only, the \
mlx-community checkpoints carry no mtp.* tensors, and any --speculative-config on a hybrid model \
disables prefix caching. Record vLLM-Metal M3 spec-on as unsupported (vllm-metal/env.md section 4)." ;;
    *) bad_variant "spec-off (spec-on is a stub)" ;;
  esac
  local exe venv view="$MLSYS/models/derived/Qwen3.8-27B-$TIER-procfix" out
  exe=$(fw_exe vllm-metal)
  WORKDIR="$SERVING/vllm-metal"; venv="$WORKDIR/.venv"
  snapshot "mlx-community/Qwen3.8-27B-$TIER" --safetensors
  if out=$("$SCRIPTS_DIR/make_procfix.sh" "$TIER" --check 2>&1); then
    ok "procfix view $(tilde "$view")"
    printf '%s\n' "$out" | grep -i 'warning' | sed 's/^/             /' || true
  else
    need "procfix view $view missing or stale (run scripts/make_procfix.sh $TIER)"
    printf '%s\n' "$out" | sed 's/^/             /'
  fi
  need_exe "$exe"
  ENVV+=(VIRTUAL_ENV="$venv" PATH="$venv/bin:$PATH" PYTHONUNBUFFERED=1)
  CMD=("$exe" serve "$view"
       --host 127.0.0.1 --port "$PORT"
       --served-model-name "qwen3.8-27b-$TIER"
       --max-model-len 131072
       --gpu-memory-utilization 0.55 --max-num-seqs 4
       --enable-auto-tool-choice --tool-call-parser qwen3_coder
       --reasoning-parser qwen3
       --enable-prefix-caching
       --enable-prompt-tokens-details)
  MODEL_ID="qwen3.8-27b-$TIER"
  PROV+=("$(dist_versions "$venv" vllm vllm_metal mlx mlx_lm mlx_vlm transformers)")
  NOTES+=("serves the procfix view, not the bare snapshot (processor_config.json; see the view's README.md)")
}

lithos_head_patch_check() {
  local sp f=''
  for sp in "$SERVING/lithos-metal/.venv"/lib/python3.*/site-packages; do
    [ -f "$sp/monolith/models/qwen3_5/weights.py" ] && f="$sp/monolith/models/qwen3_5/weights.py"
  done
  [ -n "$f" ] || f="$SERVING/lithos-metal/monolith/models/qwen3_5/weights.py"   # editable install
  if grep -q '"language_model.lm_head."' "$f" 2>/dev/null; then
    ok "lm_head rename present in $(tilde "$f")"
  else
    need "installed lithos-metal lacks the lm_head rename ($(tilde "$f")); the 4-bit head is language_model.lm_head.* (apply lithos-metal/lm_head_rename.patch and reinstall, lithos-metal/env.md section 4)"
  fi
}

build_lithos() {
  case "$TIER" in 4bit|nvfp4) ;; *) bad_tier "4bit nvfp4" ;; esac
  case "$VARIANT" in dspark|no-draft) ;; *) bad_variant "dspark no-draft" ;; esac
  local exe model served='' head=LithosAI/Qwen3.8-27B-DSpark-NVFP4 packs ctx
  exe=$(fw_exe lithos-metal)
  WORKDIR="$SERVING/lithos-metal"; packs="$WORKDIR/.cache/packs"
  if [ "$TIER" = nvfp4 ]; then
    model=nvidia/Qwen3.8-27B-NVFP4
    snapshot "$model" --safetensors
  else
    model=mlx-community/Qwen3.8-27B-4bit; served=Qwen3.8-27B-4bit
    snapshot "$model" --safetensors
    lithos_head_patch_check
  fi
  [ "$VARIANT" = no-draft ] || snapshot "$head" --safetensors
  need_exe "$exe"
  # DSpark capacity is max-context + 6; --no-draft at 131078 reuses the same target pack (env.md section 5).
  if [ "$VARIANT" = dspark ]; then ctx=131072; else ctx=131078; fi
  CMD=("$exe" serve --model "$model")
  case "$TIER/$VARIANT" in
    nvfp4/dspark) CMD+=(--local-files-only --host 127.0.0.1 --port "$PORT" --max-context "$ctx" --pack "$packs") ;;
    nvfp4/no-draft) CMD+=(--local-files-only --no-draft --host 127.0.0.1 --port "$PORT" --max-context "$ctx" --pack "$packs") ;;
    4bit/dspark) CMD+=(--draft "$head" --local-files-only --served-model-name "$served"
                       --host 127.0.0.1 --port "$PORT" --max-context "$ctx" --pack "$packs") ;;
    4bit/no-draft) CMD+=(--no-draft --local-files-only --served-model-name "$served"
                         --host 127.0.0.1 --port "$PORT" --max-context "$ctx" --pack "$packs") ;;
  esac
  ENVV+=(PYTHONUNBUFFERED=1)
  MODEL_ID=${served:-$model}
  PROV+=("$(dist_versions "$WORKDIR/.venv" lithos_metal)")
  NOTES+=("requests must omit chat_template_kwargs, send reasoning_effort only as \"none\" and omit Anthropic thinking (env.md section 14)")
  NOTES+=("cached prompt tokens are only in this log ('Generation: {... cached_prompt_tokens ...}')")
  [ "$VARIANT" = dspark ] || NOTES+=("--no-draft also drops the tuned recipes: spec-off means generic kernels here (env.md section 6)")
}

say "== serve.sh $FW $VARIANT $TIER$( [ "$DRY" -eq 1 ] && printf '  (dry run)' )"
say "checks:"
case "$FW" in
  mlx-lm) build_mlx_lm ;;
  llama.cpp) build_llama ;;
  omlx) build_omlx ;;
  vllm-metal) build_vllm ;;
  lithos-metal) build_lithos ;;
esac
ENVV=(HF_HUB_OFFLINE=1 HF_HOME="$HF_HOME" ${ENVV[@]+"${ENVV[@]}"})

# Real-run requirements (reported in a dry run, enforced in a real one).
refuse() { REFUSE+=("$1"); if [ "$DRY" -eq 1 ]; then say "  (real run would refuse) $1"; else say "  REFUSED    $1"; fi; }
if lock_is_ours; then ok "GPU lock held by us, purpose: $(sed -n 's/^purpose: //p' "$GPU_LOCK" | head -1)"
elif lock_exists; then refuse "the GPU lock is held by the other side ($GPU_LOCK)"
else refuse "GPU lock not held (scripts/gpu_lock.sh acquire <purpose> <eta-minutes>)"; fi
if [ -n "$(listen_pids "$PEER_PORT")" ]; then refuse "port 8500 is up — ask the agent-benchmark session to stop it"; else ok "port 8500 free"; fi
UP=$(our_listeners)
if [ -n "$UP" ]; then refuse "a server already listens (port pid): $(echo $UP)"; else ok "ports 8701-8705 free"; fi
PIDF=$(pidfile_of "$FW")
if [ -f "$PIDF" ] && pid_alive "$(head -1 "$PIDF")"; then refuse "${PIDF#"$BENCH_DIR"/}: PID $(head -1 "$PIDF") is still running"; fi

TS=$(/bin/date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/$FW-$VARIANT-$TIER-$TS.log"
CMDF="$LOG_DIR/$FW-$VARIANT-$TIER.cmd"
CMDLINE="cd $(q "$WORKDIR") && $(quote_cmd env "${ENVV[@]}" "${CMD[@]}" ${EXTRA[@]+"${EXTRA[@]}"})"

cmdfile() {
  local c n
  say "# serve.sh $FW $VARIANT $TIER   $(iso_time "$(now_s)")"
  say "# log:        ${LOG#"$BENCH_DIR"/}"
  say "# pid file:   ${PIDF#"$BENCH_DIR"/}"
  say "# framework:  $(git_desc "$(fw_srcdir "$FW")")"
  for c in ${PROV[@]+"${PROV[@]}"}; do say "# packages:   $c"; done
  for c in "${CKPTS[@]}"; do say "# checkpoint: $c"; done
  say "# model id:   $MODEL_ID"
  say "# endpoint:   http://127.0.0.1:$PORT/v1"
  for n in ${NOTES[@]+"${NOTES[@]}"}; do say "# note:       $n"; done
  [ "${#EXTRA[@]}" -eq 0 ] || say "# extra args: $(quote_cmd "${EXTRA[@]}")"
  say "$CMDLINE"
}

if [ "$DRY" -eq 1 ]; then
  say "would write ${CMDF#"$BENCH_DIR"/}:"
  cmdfile | sed 's/^/  /'
  if [ "${#NOT_READY[@]}" -gt 0 ]; then say "dry run: NOT READY (${#NOT_READY[@]} item(s) above)"; exit "$EX_NOT_READY"; fi
  say "dry run: ready$( [ "${#REFUSE[@]}" -eq 0 ] || printf ' (a real run still needs the lock/ports above)' )"
  exit 0
fi

[ "${#NOT_READY[@]}" -eq 0 ] || die "$EX_NOT_READY" "not ready; nothing started"
[ "${#REFUSE[@]}" -eq 0 ] || die "$EX_REFUSED" "refused; nothing started"

mkdir -p "$LOG_DIR"
cmdfile > "$CMDF.tmp.$$" && mv -f "$CMDF.tmp.$$" "$CMDF"
printf '%s\n' "$$" > "$PIDF.tmp.$$" && mv -f "$PIDF.tmp.$$" "$PIDF"
caffeinate -ims -w "$$" >/dev/null 2>&1 &          # no idle/system sleep while the server lives
# tee ignores INT/TERM so it keeps logging the server's shutdown after Ctrl-C.
exec > >(trap '' INT TERM; exec tee -a "$LOG") 2>&1
cat "$CMDF"
say "# server output follows"
cd "$WORKDIR"
exec env "${ENVV[@]}" "${CMD[@]}" ${EXTRA[@]+"${EXTRA[@]}"}
