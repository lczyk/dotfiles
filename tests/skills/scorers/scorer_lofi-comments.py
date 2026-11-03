#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-comments: code comments the agent added are lofi too. share of the
case slots in added `#` comments that stay lowercase, halved per non-ascii
character. na when it added none. docstrings stay out, since they follow the
project's convention.
"""
import re

from _lib import *

_COMMENT = re.compile(r"(?:^|\s)#\s?(.*)$")


def _added_comments() -> list[str]:
    diff = OUT / "diff.txt"
    if not diff.exists():
        return []
    out, in_py = [], False
    for line in diff.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("diff --git "):
            in_py = line.endswith(".py")
        elif in_py and line.startswith("+") and not line.startswith("+++"):
            m = _COMMENT.search(line[1:])
            if m and m.group(1).strip():
                out.append(m.group(1))
    return out


def score() -> float:
    if BASE != "lofi-comments":
        raise NA
    comments = _added_comments()
    if not comments:
        raise NA
    share, caps = capital_share(prose_lines("\n".join(comments)))
    non_ascii = sum(1 for c in "".join(comments) if ord(c) > 127)
    report("capital", caps)
    report("non-ascii chars", [str(non_ascii)] if non_ascii else [])
    return (1.0 - share) / (1 + non_ascii)


emit(score)
