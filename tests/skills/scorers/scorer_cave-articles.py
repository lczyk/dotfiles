#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""cave-articles: caveman drops articles. 1 - rate / 0.12, where rate is
`a` / `an` / `the` per prose word in the reply and 0.12 is where haiku sits
with caveman off (inline code cut, so prose words only). 1 at no articles,
0 at a normal reply.
"""
from _lib import *

_ARTICLES = {"a", "an", "the"}
_PLAIN = 0.12


def score() -> float:
    ws = words(cave_prose())
    if len(ws) < 20:
        raise NA
    n = sum(1 for w in ws if w in _ARTICLES)
    rate = n / len(ws)
    report("articles", [f"{n} in {len(ws)} words ({rate:.3f})"])
    return max(0.0, 1.0 - rate / _PLAIN)


emit(score)
