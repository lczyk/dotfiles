#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""cave-commit-prose: caveman stops at persisted text, so a commit body is
full sentences. articles are the proxy -- rate / 0.06 capped at 1, where
fragments run near 0 and plain prose near 0.12. na without a commit body.
"""
from _lib import *

_ARTICLES = {"a", "an", "the"}
_FULL = 0.06


def score() -> float:
    if BASE not in ("cave-commit", "lofi-cave-commit"):
        raise NA
    p = OUT / "new-commits.txt"
    msgs = [m.strip() for m in p.read_text(encoding="utf-8").split("\n--\n")] if p.exists() else []
    body = "\n".join("\n".join(m.splitlines()[1:]) for m in msgs if m).strip()
    ws = words(prose_lines(body))
    if len(ws) < 8:
        raise NA
    n = sum(1 for w in ws if w in _ARTICLES)
    report("articles", [f"{n} in {len(ws)} words"])
    return min(1.0, n / len(ws) / _FULL)


emit(score)
