#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-off-case: with lofi off, the reply is back in normal case. share of
the case slots in the final message that start capitalised, the pronoun `I`
included. the final message, since on lofi-off-then the toggle confirmation
comes first.
"""
from _lib import *

_TASKS = {"lofi-seeded-off", "lofi-off-then"}


def score() -> float:
    if TASK not in _TASKS:
        raise NA
    texts = transcript()["texts"]
    if not texts:
        raise NA
    share, caps = capital_share(prose_lines(texts[-1]))
    return share


emit(score)
