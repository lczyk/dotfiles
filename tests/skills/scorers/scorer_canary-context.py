#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""canary-context: did the session-start hook text reach the agent? 1 iff the
agent's own output quotes the lofi heading, which only the lofi hook injects.
"""
from _lib import *

_HEADING = "lofi -- personal writing style"


def score() -> float:
    t = transcript()
    if not t["raw"]:
        raise NA
    hay = "\n".join(t["texts"]) if t["parsed"] else t["raw"]
    return float(_HEADING in hay)


emit(score)
