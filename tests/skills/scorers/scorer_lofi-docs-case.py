#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-docs-case: lofi stops at end-user docs that are already formal. share
of the prose lines the agent added to docs/USAGE.md that start capitalised,
like the rest of the file. 0 when it added nothing.
"""
import re

from _lib import *

_DOC = "docs/USAGE.md"
_LEAD = re.compile(r"^\s*(?:#{1,6}\s+|[-*+]\s+)?")
_INLINE_CODE = re.compile(r"`[^`]*`")
_WORD = re.compile(r"[A-Za-z]")


def _added_lines(diff: str) -> list[str]:
    lines, in_doc = [], False
    for line in diff.splitlines():
        if line.startswith("diff --git "):
            in_doc = line.endswith(f" b/{_DOC}")
        elif in_doc and line.startswith("+") and not line.startswith("+++"):
            lines.append(line[1:])
    return lines


def score() -> float:
    if BASE != "lofi-docs-match":
        raise NA
    diff = OUT / "diff.txt"
    added = _added_lines(diff.read_text(encoding="utf-8")) if diff.exists() else []
    starts = []
    in_fence = False
    for line in added:
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = _WORD.search(_INLINE_CODE.sub(" ", _LEAD.sub("", line, count=1)))
        if m:
            starts.append((m.group(0), line.strip()))
    lower = [line for c, line in starts if c.islower()]
    report("lowercase doc line", lower)
    return (len(starts) - len(lower)) / len(starts) if starts else 0.0


emit(score)
