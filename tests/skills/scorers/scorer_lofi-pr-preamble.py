#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-pr-preamble: a PR body opens with the description. 0 when its first
line is a heading (the fixture repo has no template to keep) or a stock
opener (`here's`, `summary`, `overview`, ...), else 1. a one-line "this PR
adds X." lead-in is fine.

the body is the longest fenced block in the reply, or the whole reply when
there is none.
"""
import re

from _lib import *

_FENCE = re.compile(r"^\s*(```|~~~)")
_OPENER = re.compile(
    r"^\s*(?:\*\*)?(?:here(?:'s| is)|below is|summary|overview|description|tl;?dr|this pr (?:introduces|implements) the following)\b",
    re.IGNORECASE,
)


def _blocks(text: str) -> list[list[str]]:
    blocks, cur = [], None
    for line in text.splitlines():
        if _FENCE.match(line):
            if cur is None:
                cur = []
            else:
                blocks.append(cur)
                cur = None
        elif cur is not None:
            cur.append(line)
    return blocks


def score() -> float:
    if TASK != "lofi-pr-body":
        raise NA
    reply = "\n".join(transcript()["texts"])
    blocks = _blocks(reply)
    body = max(blocks, key=lambda b: len("\n".join(b))) if blocks else reply.splitlines()
    first = next((line for line in body if line.strip()), "")
    if not first:
        raise NA
    bad = first.lstrip().startswith("#") or _OPENER.match(first)
    report("preamble", [repr(first.strip()[:80])] if bad else [])
    return 0.0 if bad else 1.0


emit(score)
