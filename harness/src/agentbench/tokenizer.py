"""Local Qwen3.8 tokenizer, chat-template rendering, and image-token arithmetic.

Only the local HF cache snapshot of mlx-community/Qwen3.8-27B-8bit is used
($HF_HOME/hub/models--mlx-community--Qwen3.8-27B-8bit/snapshots/<hash>/). No network.

Image tokens (Qwen2VLImageProcessorFast, patch_size=16, merge_size=2):
  factor = patch_size * merge_size = 32
  (h, w) = smart_resize(H, W): round each side to a multiple of 32, then rescale into
           [min_pixels, max_pixels] = [65536, 16777216] if needed
  tokens = (h / 16) * (w / 16) / merge_size**2 = (h * w) / 1024
  1280x1024 -> 1280 x 1024 (already multiples of 32) -> 80 * 64 / 4 = 1280 tokens,
  plus <|vision_start|> and <|vision_end|> = 1282 prompt tokens per screenshot.
"""

from __future__ import annotations

import json
import math
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

REPO_ID = "mlx-community/Qwen3.8-27B-8bit"


def snapshot_dir() -> Path:
    hf_home = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
    snaps = hf_home / "hub" / ("models--" + REPO_ID.replace("/", "--")) / "snapshots"
    cands = sorted(p for p in snaps.glob("*") if (p / "tokenizer.json").exists()) if snaps.exists() else []
    if not cands:
        raise FileNotFoundError(f"no local snapshot of {REPO_ID} under $HF_HOME/hub")
    return cands[-1]


def smart_resize(height: int, width: int, factor: int = 32, min_pixels: int = 65536,
                 max_pixels: int = 16777216) -> tuple[int, int]:
    if max(height, width) / min(height, width) > 200:
        raise ValueError("aspect ratio > 200")
    h = round(height / factor) * factor
    w = round(width / factor) * factor
    if h * w > max_pixels:
        beta = math.sqrt(height * width / max_pixels)
        h = max(factor, math.floor(height / beta / factor) * factor)
        w = max(factor, math.floor(width / beta / factor) * factor)
    elif h * w < min_pixels:
        beta = math.sqrt(min_pixels / (height * width))
        h = math.ceil(height * beta / factor) * factor
        w = math.ceil(width * beta / factor) * factor
    return h, w


def image_tokens(width: int, height: int, cfg: dict[str, Any] | None = None) -> int:
    """Number of <|image_pad|> tokens for one image (excluding vision start/end)."""
    cfg = cfg or {}
    patch = cfg.get("patch_size", 16)
    merge = cfg.get("merge_size", 2)
    size = cfg.get("size", {})
    h, w = smart_resize(height, width, patch * merge, size.get("shortest_edge", 65536),
                        size.get("longest_edge", 16777216))
    return (h // patch) * (w // patch) // (merge * merge)


class QwenPrompt:
    """Renders chat requests with the model's own chat_template.jinja (HF-compatible
    Jinja environment) and counts tokens with tokenizer.json."""

    def __init__(self, snap: Path | None = None) -> None:
        import jinja2
        from jinja2.sandbox import ImmutableSandboxedEnvironment
        from tokenizers import Tokenizer

        self.snap = snap or snapshot_dir()
        self.tok = Tokenizer.from_file(str(self.snap / "tokenizer.json"))
        self.pre = json.loads((self.snap / "preprocessor_config.json").read_text())
        env = ImmutableSandboxedEnvironment(trim_blocks=True, lstrip_blocks=True,
                                            extensions=["jinja2.ext.loopcontrols"])

        def tojson(x, ensure_ascii=False, indent=None, separators=None, sort_keys=False):
            return json.dumps(x, ensure_ascii=ensure_ascii, indent=indent, separators=separators, sort_keys=sort_keys)

        def raise_exception(msg):
            raise jinja2.TemplateError(msg)

        env.filters["tojson"] = tojson
        env.globals["raise_exception"] = raise_exception
        self.template = env.from_string((self.snap / "chat_template.jinja").read_text())

    def count_text(self, text: str) -> int:
        return len(self.tok.encode(text, add_special_tokens=False).ids)

    @staticmethod
    def _template_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        out = []
        for m in messages:
            m = dict(m)
            if m.get("tool_calls"):
                calls = []
                for tc in m["tool_calls"]:
                    tc = json.loads(json.dumps(tc))
                    fn = tc.get("function", tc)
                    if isinstance(fn.get("arguments"), str):
                        fn["arguments"] = json.loads(fn["arguments"] or "{}")
                    calls.append(tc)
                m["tool_calls"] = calls
            out.append(m)
        return out

    def render(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None,
               enable_thinking: bool = False, add_generation_prompt: bool = True, **kw: Any) -> str:
        return self.template.render(messages=self._template_messages(messages), tools=tools,
                                    enable_thinking=enable_thinking, add_generation_prompt=add_generation_prompt, **kw)

    def count(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None,
              enable_thinking: bool = False, image_sizes: list[tuple[int, int]] | None = None, **kw: Any) -> int:
        """Prompt tokens: rendered text tokens, with each <|image_pad|> expanded to the
        per-image token count (default 1280x1024 when sizes are not given)."""
        text = self.render(messages, tools, enable_thinking=enable_thinking, **kw)
        n = self.count_text(text)
        n_img = text.count("<|image_pad|>")
        sizes = image_sizes or [(1280, 1024)] * n_img
        return n + sum(image_tokens(w, h, self.pre) - 1 for w, h in sizes[:n_img])


@lru_cache(maxsize=1)
def default_prompt() -> QwenPrompt:
    return QwenPrompt()
