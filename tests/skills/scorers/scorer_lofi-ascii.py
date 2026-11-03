#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-ascii: no non-ascii characters (em-dashes, arrows, curly quotes, emoji)
in the agent's reply or commit messages. counts code too -- lofi output has no
reason to carry any. 1 / (1 + n), so one slip already halves the score.
"""
from _lib import *


def score() -> float:
    hits = sorted({c for c in lofi_raw() if ord(c) > 127})
    n = sum(lofi_raw().count(c) for c in hits)
    report("non-ascii", [f"{c!r} U+{ord(c):04X}" for c in hits])
    return 1.0 / (1 + n)


emit(score)
