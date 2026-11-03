#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""canary-hooks: fraction of the injected marker hooks that fired in the
sandbox. anything under 1 means the seeded settings didn't load as expected.
"""
from _lib import *

_EVENTS = ("session-start", "user-prompt-submit", "pre-tool-use")


def score() -> float:
    return sum((OUT / "canary" / e).exists() for e in _EVENTS) / len(_EVENTS)


emit(score)
