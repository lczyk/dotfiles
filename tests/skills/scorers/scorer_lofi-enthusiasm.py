#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-enthusiasm: exclamation marks almost never. -0.25 per `!` ending a
word in prose (`!=`, shebangs and code are out already or don't match).
"""
import re

from _lib import *

_BANG = re.compile(r"(?<=[\w)])!+(?![=\w])")


def score() -> float:
    hits = [f"'!' in {line.strip()[:80]!r}" for line in lofi_prose() for _ in _BANG.finditer(line)]
    report("exclamation", hits)
    return penalty(len(hits), 0.25)


emit(score)
