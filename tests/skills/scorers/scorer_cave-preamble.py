#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""cave-preamble: tool calls fire direct, no plan or progress note before or
between them. 1 / (1 + n), n = assistant text blocks followed by a tool call.
claude stream-json only, na for other harnesses.
"""
import json

from _lib import *


def _blocks() -> list[str]:
    """the assistant's content blocks in order, as `text` / `tool_use`."""
    out = []
    p = OUT / "stdout.log"
    if not p.exists():
        return out
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        msg = ev.get("message") if ev.get("type") == "assistant" else None
        if not isinstance(msg, dict):
            continue
        for c in msg.get("content") or []:
            if isinstance(c, dict) and c.get("type") in ("text", "tool_use"):
                if c["type"] == "tool_use" or str(c.get("text", "")).strip():
                    out.append(c["type"])
    return out


def score() -> float:
    if TASK not in CAVE_PROSE:
        raise NA
    blocks = _blocks()
    if "tool_use" not in blocks:
        raise NA
    last_tool = len(blocks) - 1 - blocks[::-1].index("tool_use")
    n = sum(1 for b in blocks[:last_tool] if b == "text")
    report("text before a tool call", [str(n)] if n else [])
    return 1.0 / (1 + n)


emit(score)
