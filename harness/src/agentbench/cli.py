"""agentbench CLI. Suites (gate, m1-m7, summarize, fixtures) are NOT implemented yet;
see harness/STATUS.md. Implemented: `info`, `mock-server`, `mem`."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="agentbench")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info", help="print tokenizer snapshot and image-token arithmetic")
    ms = sub.add_parser("mock-server", help="run the mock OpenAI/Anthropic SSE server")
    ms.add_argument("--port", type=int, default=8790)
    mem = sub.add_parser("mem", help="sample memory of a PID tree every --interval s")
    mem.add_argument("--pid", type=int, required=True)
    mem.add_argument("--interval", type=float, default=2.0)
    mem.add_argument("--duration", type=float, default=10.0)
    for name in ("gate", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "summarize", "fixtures"):
        sub.add_parser(name, help="not implemented yet (see STATUS.md)")
    a = ap.parse_args(argv)

    if a.cmd == "info":
        from .tokenizer import QwenPrompt, image_tokens
        p = QwenPrompt()
        print(json.dumps({"snapshot": p.snap.name, "preprocessor": p.pre,
                          "image_tokens_1280x1024": image_tokens(1280, 1024, p.pre)}, indent=2))
        return 0
    if a.cmd == "mock-server":
        if a.port == 8500 or 8600 <= a.port <= 8699:
            print("port reserved for the agent benchmark", file=sys.stderr)
            return 2
        from .mock_server import MockServer
        s = MockServer(port=a.port).start()
        print(f"mock server on {s.url}")
        while True:
            time.sleep(3600)
    if a.cmd == "mem":
        from .memory import sample_once

        async def run() -> None:
            end = time.time() + a.duration
            while time.time() < end:
                print(json.dumps(await sample_once(a.pid)))
                await asyncio.sleep(a.interval)

        asyncio.run(run())
        return 0
    print(f"`{a.cmd}` is not implemented yet; see harness/STATUS.md", file=sys.stderr)
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
