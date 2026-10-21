"""CPU-only verification of the source-built TVM + MLC-LLM (no Metal device is created)."""
import ctypes
import json
import sys

import tvm
import mlc_llm  # noqa: F401  (loads libmlc_llm_module)
import mlc_llm.base
from tvm import support

print("python", sys.version.split()[0], sys.executable)
print("tvm", tvm.__version__, tvm.__file__)
print("mlc_llm", mlc_llm.__file__)
info = support.libinfo()
for k in ["GIT_COMMIT_HASH", "GIT_COMMIT_TIME", "USE_LLVM", "LLVM_VERSION", "USE_METAL",
          "HIDE_PRIVATE_SYMBOLS", "USE_Z3", "CMAKE_BUILD_TYPE", "USE_RPC", "INDEX_DEFAULT_I64",
          "BUILD_STATIC_RUNTIME", "USE_CCACHE"]:
    print(f"  libinfo {k}: {info.get(k)}")
print("tvm._RUNTIME_ONLY", tvm.base._RUNTIME_ONLY)
print("tvm loaded libs:", {k: v._name for k, v in tvm.base._LOADED_LIBS.items()})
print("mlc_llm lib:", mlc_llm.base._LIB_PATH)

# Every TVM/MLC image mapped into this process (one copy each is expected).
libc = ctypes.CDLL(None)
libc._dyld_image_count.restype = ctypes.c_uint32
libc._dyld_get_image_name.restype = ctypes.c_char_p
libc._dyld_get_image_name.argtypes = [ctypes.c_uint32]
names = [libc._dyld_get_image_name(i).decode() for i in range(libc._dyld_image_count())]
keys = ["tvm", "mlc", "orcjit", "tokenizers", "LLVM", "z3"]
hits = [n for n in names if any(s in n for s in keys)]
for n in hits:
    print("  image:", n)
base = [n.rsplit("/", 1)[-1] for n in hits]
dups = sorted({b for b in base if base.count(b) > 1})
print("duplicate images:", dups or "none")

# xgrammar is compiled into libmlc_llm; check the serve/grammar FFI surface is registered.
import tvm_ffi
names_ffi = [n for n in tvm_ffi.registry.list_global_func_names() if n.startswith("mlc.")]
print("mlc.* global funcs:", len(names_ffi), [n for n in names_ffi if "grammar" in n.lower() or "json" in n.lower()][:8])

# LLVM JIT on CPU (the path `convert_weight --device cpu` takes): needs tvm_ffi_orcjit.
import numpy as np
from tvm import relax
from tvm.script import ir as I
from tvm.script import relax as R


@I.ir_module
class Mod:
    @R.function
    def main(x: R.Tensor((4,), "float32")):
        y = R.add(x, x)
        return y


ex = relax.build(Mod, target="llvm")
vm = relax.VirtualMachine(ex, tvm.cpu())
out = vm["main"](tvm.runtime.tensor(np.arange(4, dtype="float32"))).numpy()
print("cpu jit add:", out.tolist())
import tvm_ffi_orcjit
print("orcjit", getattr(tvm_ffi_orcjit, "__version__", "?"), tvm_ffi_orcjit.__file__)

# OpenAI protocol: response_format / debug_config validation (pydantic only, no engine).
from mlc_llm.protocol.openai_api_protocol import ChatCompletionRequest

schema = {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}
base_req = {"messages": [{"role": "user", "content": "hi"}]}
cases = {
    "mlc shape (schema as string)": {"type": "json_object", "schema": json.dumps(schema)},
    "schema as object": {"type": "json_object", "schema": schema},
    "openai json_schema type": {"type": "json_schema", "json_schema": {"name": "x", "schema": schema}},
    "json_object + key json_schema": {"type": "json_object", "json_schema": json.dumps(schema)},
}
for label, rf in cases.items():
    try:
        r = ChatCompletionRequest.model_validate({**base_req, "response_format": rf})
        print(f"  [{label}] OK -> type={r.response_format.type!r} schema={'set' if r.response_format.json_schema else None}")
    except Exception as e:  # pylint: disable=broad-except
        print(f"  [{label}] {type(e).__name__}: {str(e).splitlines()[0][:120]}")
r = ChatCompletionRequest.model_validate({**base_req, "debug_config": {"grammar_execution_mode": "constraint"},
                                          "tools": [{"type": "function", "function": {"name": "f", "parameters": {}}}],
                                          "tool_choice": "auto", "stream": True, "stream_options": {"include_usage": True}})
print("  debug_config:", r.debug_config.grammar_execution_mode, "| tools accepted:", len(r.tools), "| tool_choice:", r.tool_choice)
try:
    ChatCompletionRequest.model_validate({**base_req, "stream_options": {"include_usage": True}})
except Exception as e:  # pylint: disable=broad-except
    print("  stream_options without stream:", type(e).__name__)
from mlc_llm.serve import engine_utils
g = engine_utils.get_generation_config(ChatCompletionRequest.model_validate(
    {**base_req, "response_format": cases["mlc shape (schema as string)"],
     "debug_config": {"grammar_execution_mode": "constraint"}}))
print("  generation_config json:", g.model_dump_json(include={"response_format", "debug_config"}, by_alias=True)[:300])
# Thinking control: per-request fields are not part of the protocol (pydantic ignores them).
r = ChatCompletionRequest.model_validate({**base_req, "chat_template_kwargs": {"enable_thinking": False},
                                          "reasoning_effort": "none", "enable_thinking": False})
print("  thinking fields accepted and dropped:",
      [k for k in ("chat_template_kwargs", "reasoning_effort", "enable_thinking") if hasattr(r, k)] or "none kept")

# MLC conversation templates vs. the HF Qwen3.8 chat template (rendered strings, CPU only).
import copy
import os
from mlc_llm.conversation_template import ConvTemplateRegistry
from transformers import AutoTokenizer

snap = os.path.expanduser("~/Developer/ml_source/huggingface/hub/models--Qwen--Qwen3.8-27B/snapshots/"
                          "1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0")
tok = AutoTokenizer.from_pretrained(snap, local_files_only=True)
msgs = [{"role": "system", "content": "SYS"}, {"role": "user", "content": "Hello"}]


def mlc_render(name):
    conv = copy.deepcopy(ConvTemplateRegistry.get_conv_template(name))
    conv.system_message = "SYS"
    conv.messages.append(("user", "Hello"))
    conv.messages.append(("assistant", None))
    return "".join(p for p in conv.as_prompt() if isinstance(p, str))


hf = {
    "hf enable_thinking=False": tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True,
                                                        enable_thinking=False),
    "hf thinking on, effort=medium": tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True,
                                                             reasoning_effort="medium"),
    "hf thinking on, default (xhigh)": tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True),
}
mlc = {"mlc qwen3_5_nothink": mlc_render("qwen3_5_nothink"), "mlc qwen3_5": mlc_render("qwen3_5")}
for k, v in {**hf, **mlc}.items():
    print(f"  {k}: {v!r}")
print("  nothink == hf enable_thinking=False:", mlc["mlc qwen3_5_nothink"] == hf["hf enable_thinking=False"])
print("  qwen3_5 == hf effort=medium:", mlc["mlc qwen3_5"] == hf["hf thinking on, effort=medium"])
print("  qwen3_5 == hf default xhigh:", mlc["mlc qwen3_5"] == hf["hf thinking on, default (xhigh)"])
print("VERIFY OK")
