#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-format: lofi's markdown and number rules. -0.25 per hit.

- bullets use `-`, not `*` / `+`
- a bold lead-in has no dot inside or after the bold
- a list is all lead-in or none (one hit per mixed list)
- no thousands separators in numbers (`50000`, not `50,000`)
"""
import re

from _lib import *

_BULLET = re.compile(r"^(\s*)([-*+])\s+(.*)$")
_LEAD_IN = re.compile(r"^\*\*([^*]+)\*\*(.?)")
_THOUSANDS = re.compile(r"(?<![\d.,])\d{1,3}(?:,\d{3})+(?![\d,])")


def _lists(lines: list[str]) -> list[list[tuple[str, str]]]:
    """consecutive bullet lines at one indent, as (marker, body) pairs. a blank
    or non-bullet line ends a list, deeper bullets don't."""
    out, cur, indent = [], [], None
    for line in lines:
        m = _BULLET.match(line)
        if m and (indent is None or len(m.group(1)) == indent):
            indent = len(m.group(1))
            cur.append((m.group(2), m.group(3)))
        elif m and len(m.group(1)) > indent:
            continue
        else:
            if cur:
                out.append(cur)
            cur, indent = [], None
            if m:
                indent = len(m.group(1))
                cur.append((m.group(2), m.group(3)))
    if cur:
        out.append(cur)
    return out


def score() -> float:
    lines = lofi_prose(keep_blank=True)
    hits = []
    for items in _lists(lines):
        leads = 0
        for marker, body in items:
            if marker != "-":
                hits.append(f"{marker!r} bullet: {body[:60]!r}")
            m = _LEAD_IN.match(body)
            if not m:
                continue
            leads += 1
            if m.group(1).rstrip().endswith(".") or m.group(2) == ".":
                hits.append(f"dot in lead-in: {body[:60]!r}")
        if 0 < leads < len(items):
            hits.append(f"mixed lead-ins ({leads}/{len(items)}): {items[0][1][:60]!r}")
    for line in lines:
        hits += [f"separator {m.group(0)!r} in {line.strip()[:60]!r}" for m in _THOUSANDS.finditer(line)]
    report("format", hits)
    return penalty(len(hits), 0.25)


emit(score)
