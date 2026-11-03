#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-toggle-off: "lofi off" reached the lofi skill, which creates its
marker file so the hooks stop injecting the style.
"""
from _lib import *

_TASKS = {"lofi-toggle", "lofi-off-then"}


def score() -> float:
    if TASK not in _TASKS:
        raise NA
    return float((OUT / "agent-state" / "lofi-off").exists())


emit(score)
