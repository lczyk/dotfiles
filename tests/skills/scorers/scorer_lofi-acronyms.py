#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-acronyms: common acronyms and product names stay lowercase in prose
(`json`, `http`, `github`). -0.25 per hit.

a word list of the common ones only, since lofi keeps obscure acronyms
capitalised. `PR` is exempt. lofi-lowercase skips all-caps and inner-capital
words, so it doesn't see these.
"""
import re

from _lib import *

_COMMON = [
    "HTTPS?", "JSON", "LLMs?", "CI", "CD", "URLs?", "CPUs?", "RAM", "AI", "TCP", "UDP",
    "ASCII", "IDs?", "APIs?", "CLIs?", "HTML", "SQL", "YAML", "TOML", "SSH", "UTF-8",
    "GitHub", "SQLite",
    #
]

_RE = re.compile(r"(?<![\w/.-])(?:" + "|".join(_COMMON) + r")(?![\w-])")


def score() -> float:
    hits = [f"{m.group(0)!r} in {line.strip()[:80]!r}" for line in lofi_prose() for m in _RE.finditer(line)]
    report("acronym", hits)
    return penalty(len(hits), 0.25)


emit(score)
