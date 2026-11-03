#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-joiners: no clauses joined by `;` or `:`. -0.25 per hit.

every `; ` in prose counts. a colon counts only when both sides read like
clauses (4+ words each, the right side not a list). labels (`fix: ...`,
`**note**: ...`) and list intros stay clear. a heuristic -- a colon-joined
pair of short clauses gets through.
"""
import re

from _lib import *

_COLON = re.compile(r":\s+")
_BOUNDARY = re.compile(r"[.!?]\s+")
_MIN_WORDS = 4


def _clause_colons(line: str) -> list[str]:
    hits = []
    for m in _COLON.finditer(line):
        before = _BOUNDARY.split(line[: m.start()])[-1]
        after = _BOUNDARY.split(line[m.end():])[0]
        if before.rstrip().endswith("**"):
            continue
        if len(before.split()) >= _MIN_WORDS and len(after.split()) >= _MIN_WORDS and "," not in after:
            hits.append(f"':' in {line.strip()[:80]!r}")
    return hits


def score() -> float:
    hits = []
    for line in lofi_prose():
        hits += [f"';' in {line.strip()[:80]!r}"] * line.count("; ")
        hits += _clause_colons(line)
    report("joiner", hits)
    return penalty(len(hits), 0.25)


emit(score)
