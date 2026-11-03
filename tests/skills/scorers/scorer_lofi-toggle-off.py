#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-toggle-off: "lofi off pls" reached the lofi skill, which drops its
state file so the hooks stop injecting the style.
"""
from _lib import *


def score() -> float:
    if TASK != "lofi-toggle":
        raise NA
    return float((OUT / "agent-state" / "lofi-off").exists())


emit(score)
