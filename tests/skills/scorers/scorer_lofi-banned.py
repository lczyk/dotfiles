#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-banned: none of lofi's banned phrasing (llm filler, framing openers,
`gate` / `corpus`). -0.25 per hit. us spellings are lofi-engb.

word lists, not judgement: only unambiguous entries. `key`, `navigate` and
`license` stay out, since their banned sense needs context.
"""
import re

from _lib import *

_BANNED = [
    r"moving the needle", r"at the end of the day", r"deep dive", r"elephant in the room",
    r"boil the ocean", r"cutting[- ]edge", r"swing for the fences", r"seamless(?:ly)?",
    r"robust(?:ly|ness)?", r"leverag(?:e|es|ed|ing)", r"delv(?:e|es|ed|ing)", r"tapestry",
    r"vibrant", r"intricate", r"foster(?:s|ed|ing)?", r"garner(?:s|ed|ing)?", r"crucial(?:ly)?",
    r"testament to", r"pivotal", r"evolving landscape", r"serves as", r"stands as", r"boasts",
    r"the real question is", r"at its core", r"fundamentally", r"great question",
    r"absolutely", r"it'?s worth noting", r"keep in mind that",
    r"gat(?:e|es|ed|ing)", r"corpus", r"corpora",
    #
]

_RE = re.compile(r"\b(?:" + "|".join(_BANNED) + r")\b", re.IGNORECASE)


def score() -> float:
    hits = [m.group(0) for line in lofi_prose() for m in _RE.finditer(line)]
    report("banned", hits)
    return penalty(len(hits), 0.25)


emit(score)
