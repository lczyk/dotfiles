#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-engb: en-gb spelling where it differs from us. -0.25 per us spelling.
a word list of the unambiguous ones, so `license` (the en-gb verb) stays out.
"""
import re

from _lib import *

_US = [
    r"behaviors?", r"behavioral", r"colors?", r"colored", r"favorite", r"favors?",
    r"honors?", r"initializ\w*", r"organiz\w*", r"optimiz\w*", r"analyz\w*", r"recogniz\w*",
    r"customiz\w*", r"serializ\w*", r"normaliz\w*", r"prioritiz\w*", r"minimiz\w*",
    r"maximiz\w*", r"summariz\w*", r"utiliz\w*", r"reorganiz\w*", r"standardiz\w*", r"canceled", r"canceling", r"modeling",
    r"modeled", r"traveled", r"traveling", r"labeled", r"labeling", r"catalog", r"defense",
    #
]

_RE = re.compile(r"\b(?:" + "|".join(_US) + r")\b", re.IGNORECASE)


def score() -> float:
    hits = [m.group(0) for line in lofi_prose() for m in _RE.finditer(line)]
    report("us spelling", hits)
    return penalty(len(hits), 0.25)


emit(score)
