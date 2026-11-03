#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-toggle-state: lofi starts off, and "lofi on" must remove the marker
file. lofi-status: asking for the status must leave it in place.
"""
from _lib import *


def score() -> float:
    marker = (OUT / "agent-state" / "lofi-off").exists()
    if TASK == "lofi-toggle-on":
        return float(not marker)
    if TASK == "lofi-status":
        return float(marker)
    raise NA


emit(score)
