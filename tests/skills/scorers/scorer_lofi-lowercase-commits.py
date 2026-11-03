#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-lowercase-commits: lofi-lowercase over the messages of the commits
the agent made. na without commits, and on lofi-repo-rules, whose repo asks
for capitalised commit bodies.
"""
from _lib import *


def score() -> float:
    if BASE == "lofi-repo-rules":
        raise NA
    return lowercase_score("commits")


emit(score)
