#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-lowercase: share of the spots where capitals slip in that stay
lowercase -- the start of each line, sentence, bullet, heading, table cell and
the text after a colon, plus every pronoun `i`.

exempt words: all-caps (`PR`, `HINT`), and identifier-shaped ones (inner
capitals, digits, underscores). inline code, urls and double-quoted text are
already cut by lofi_prose().
"""
import re

from _lib import *

_LEAD = re.compile(r"^\s*(?:>\s*)*(?:#{1,6}\s+|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)?")
_SENTENCE = re.compile(r"(?:[.!?]|:)\s+")
_WORD = re.compile(r"^[^A-Za-z]*([A-Za-z][\w'-]*)")
_PRONOUN = re.compile(r"(?<![\w'/-])I(?=['\s,.!?]|$)")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}")


def _exempt(word: str) -> bool:
    return (
        (len(word) > 1 and word.upper() == word)
        or any(c.isdigit() or c == "_" for c in word)
        or any(c.isupper() for c in word[1:])
    )


def _starts(line: str) -> list[str]:
    """the first word of every slot in a line where lofi wants lowercase."""
    if _TABLE_SEP.match(line):
        return []
    cells = line.strip().strip("|").split("|") if line.lstrip().startswith("|") else [line]
    words = []
    for cell in cells:
        body = _LEAD.sub("", cell, count=1)
        for chunk in _SENTENCE.split(body):
            m = _WORD.match(chunk)
            if m:
                words.append(m.group(1))
    return words


def score() -> float:
    opps = 0
    hits = []
    for line in lofi_prose():
        for w in _starts(line):
            if w == "I":
                continue  # the pronoun pass below counts it
            opps += 1
            if w[0].isupper() and not _exempt(w):
                hits.append(f"{w!r} in {line.strip()[:80]!r}")
        for _ in _PRONOUN.finditer(line):
            opps += 1
            hits.append(f"'I' in {line.strip()[:80]!r}")
    if not opps:
        raise NA
    report("capital", hits)
    return 1.0 - len(hits) / opps


emit(score)
