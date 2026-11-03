#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-repo-commit: repo instructions win for committed artefacts. the
fixture's AGENTS.md asks for a capitalised commit body in full sentences, so
this is the share of the body's case slots that start capitalised. 0 when the
agent committed without a body, na when it didn't commit.
"""
from _lib import *


def score() -> float:
    if BASE != "lofi-repo-rules":
        raise NA
    p = OUT / "new-commits.txt"
    msgs = [m.strip() for m in p.read_text(encoding="utf-8").split("\n--\n")] if p.exists() else []
    msgs = [m for m in msgs if m]
    if not msgs:
        raise NA
    bodies = ["\n".join(m.splitlines()[1:]).strip() for m in msgs]
    body = "\n".join(b for b in bodies if b)
    if not body:
        report("no body", [msgs[0].splitlines()[0]])
        return 0.0
    share, caps = capital_share(prose_lines(body))
    return share


emit(score)
