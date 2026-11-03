#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""cave-stop: a bare "normal mode" prompt switches caveman off -- the hook
drops the caveman-active state file.
"""
from _lib import *


def score() -> float:
    if TASK != "cave-stop":
        raise NA
    return float(not (OUT / "agent-state" / "caveman-active").exists())


emit(score)
