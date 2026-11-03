#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-pr-template: repo template headers stay as written. share of the
headers in verbatim.txt that appear in the reply exactly, case included.
"""
from _lib import *


def score() -> float:
    p = OUT / "verbatim.txt"
    if BASE != "lofi-pr-template" or not p.exists():
        raise NA
    headers = [h.strip() for h in p.read_text(encoding="utf-8").splitlines() if h.strip()]
    lines = {line.strip() for t in transcript()["texts"] for line in t.splitlines()}
    missing = [h for h in headers if h not in lines]
    report("missing header", missing)
    return 1.0 - len(missing) / len(headers)


emit(score)
