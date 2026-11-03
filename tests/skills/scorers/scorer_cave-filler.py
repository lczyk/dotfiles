#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""cave-filler: no filler, pleasantries or hedging in the reply. -0.25 per
hit. word lists from the caveman skill, plus common hedges.
"""
import re

from _lib import *

_PHRASES = [
    # filler
    r"just", r"really", r"basically", r"actually", r"simply",
    # pleasantries
    r"(?<!make )sure", r"certainly", r"of course", r"happy to", r"glad to", r"let me know",
    r"hope this helps",
    # hedging
    r"i think", r"i believe", r"it seems", r"perhaps", r"probably", r"might want to",
    r"you may want to", r"it's possible that",
    #
]

_RE = re.compile(r"\b(?:" + "|".join(_PHRASES) + r")\b", re.IGNORECASE)


def score() -> float:
    hits = [f"{m.group(0)!r} in {line.strip()[:60]!r}" for line in cave_prose() for m in _RE.finditer(line)]
    report("filler", hits)
    return penalty(len(hits), 0.25)


emit(score)
