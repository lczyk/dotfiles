"""shared helpers for the dotfiles pats scorers. not a scorer itself (no exec
bit, no shebang) -- imported by each scorer_<id>.py via `from _lib import *`.

a scorer receives the pair's output dir (env PATS_OUTPUT_DIR), which holds what
tasks/collect.sh gathered:

    stdout.log, stderr.log  the harness transcript (written by pats)
    canary/<event>          marker files from the injected canary hooks
    agent-state/            the skills' state dir (lofi-off, caveman mode)
    seed.sha                the fixture's last commit before the agent ran
    git-log.txt             fixture repo log, `%H%n%B%n--` per commit
    new-commits.txt         messages of the agent's commits, `%B%n--` each
    diff.txt                everything changed since seed.sha, incl. uncommitted
    git-status.txt          `git status --porcelain` after the run
    git-branches.txt        local branch names

transcript() is adapted from mason's tests/skills/scorers/_lib.py.
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections.abc import Callable
from pathlib import Path

__all__ = [
    "BASE",
    "CAVE_PROSE",
    "LOFI_PROSE",
    "NA",
    "OUT",
    "TASK",
    "capital_share",
    "case_slots",
    "cave_prose",
    "emit",
    "lofi_prose",
    "lofi_raw",
    "lowercase_score",
    "penalty",
    "pronouns",
    "prose_lines",
    "report",
    "transcript",
    "words",
]

OUT = Path(os.environ["PATS_OUTPUT_DIR"])
TASK = os.environ.get("PATS_TASK_ID", "")
# the lofi-cave-* suite reruns lofi-* tasks with caveman on, so task-specific
# checks key on the lofi- name.
BASE = TASK.replace("lofi-cave-", "lofi-", 1)

# tasks whose chat reply and commit messages should be lofi.
LOFI_PROSE = {
    "lofi-explain", "lofi-pr-body", "lofi-commit", "lofi-docs-match", "lofi-comments",
    "lofi-engb", "lofi-repo-rules", "lofi-pr-template", "lofi-long",
    "lofi-cave-explain", "lofi-cave-pr-body", "lofi-cave-commit", "lofi-cave-docs-match",
    #
}
# tasks whose chat reply should be caveman-terse.
CAVE_PROSE = {
    "cave-explain", "cave-commit",
    "lofi-cave-explain", "lofi-cave-pr-body", "lofi-cave-commit", "lofi-cave-docs-match",
    #
}

_FENCE = re.compile(r"^\s*(```|~~~)")
_INLINE_CODE = re.compile(r"`[^`]*`")
_URL = re.compile(r"https?://\S+")
_DQUOTED = re.compile(r'"[^"\n]*"')
_MD_LEAD = re.compile(r"^[\s>#*+-]*")

_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_WRITE_TOOLS = {"write", "edit", "multiedit", "notebookedit", "patch"}
_PATH_KEYS = ("file_path", "filePath", "path", "notebook_path")


class NA(Exception):
    """raised by a scorer that does not apply to this pair -> prints 'na'."""


def emit(fn: Callable[[], float]) -> None:
    """run a scorer and print its verdict: a [0,1] float, or 'na' on NA."""
    try:
        print(f"{fn():.4f}")
    except NA:
        print("na")


def report(what: str, hits: list[str]) -> None:
    """list what a scorer counted against the pair, on stderr for debugging."""
    for h in hits:
        print(f"{what}: {h}", file=sys.stderr)


def penalty(hits: int, per_hit: float) -> float:
    return max(0.0, 1.0 - per_hit * hits)


def _commits() -> str:
    p = OUT / "new-commits.txt"
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


def lofi_raw(source: str = "all") -> str:
    """the lofi text under test, as written. source picks it -- `reply` (the
    agent's output), `last` (its final message), `commits` (messages of the
    commits it made) or `all` (reply + commits). NA outside the lofi prose
    tasks, or when the source is empty."""
    if TASK not in LOFI_PROSE:
        raise NA
    texts = transcript()["texts"]
    parts = {
        "reply": texts,
        "last": texts[-1:],
        "commits": [_commits()],
        "all": [*texts, _commits()],
    }[source]
    text = "\n".join(parts).strip()
    if not text:
        raise NA
    return text


def _norm(line: str) -> str:
    return _MD_LEAD.sub("", line).strip()


def _quoted() -> set[str]:
    """lines the agent may quote in their source case, normalised -- the file
    lines in diff.txt (a reply quoting a file it edited) and the task's
    verbatim.txt (repo template headers)."""
    out = set()
    diff = OUT / "diff.txt"
    if diff.exists():
        for line in diff.read_text(encoding="utf-8", errors="replace").splitlines():
            if line[:1] in "+- " and not line.startswith(("+++", "---")):
                body = _norm(line[1:])
                if len(body.split()) >= 3:
                    out.add(body)
    verbatim = OUT / "verbatim.txt"
    if verbatim.exists():
        out |= {_norm(v) for v in verbatim.read_text(encoding="utf-8").splitlines() if v.strip()}
    return out


def prose_lines(text: str, keep_blank: bool = False) -> list[str]:
    """text as prose lines: no fenced blocks, no quoted lines (see _quoted),
    and inline code, urls and double-quoted text cut out, since those keep
    their source spelling. keep_blank keeps empty lines, so list and paragraph
    breaks survive."""
    quoted = _quoted()
    lines = []
    in_fence = False
    for line in text.splitlines():
        if _FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence or _norm(line) in quoted:
            continue
        line = _DQUOTED.sub(" ", _URL.sub(" ", _INLINE_CODE.sub(" ", line)))
        if line.strip() or keep_blank:
            lines.append(line)
    return lines


def lofi_prose(keep_blank: bool = False, source: str = "all") -> list[str]:
    """lofi_raw(source) as prose_lines()."""
    return prose_lines(lofi_raw(source), keep_blank)


def cave_prose() -> list[str]:
    """the agent's reply as prose_lines(). NA outside the caveman tasks."""
    if TASK not in CAVE_PROSE:
        raise NA
    text = "\n".join(transcript()["texts"]).strip()
    if not text:
        raise NA
    return prose_lines(text)


_WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")


def words(lines: list[str]) -> list[str]:
    return [w.lower() for line in lines for w in _WORD_RE.findall(line)]


# the spots where capitals slip in -- the start of each line, sentence, bullet,
# heading, table cell, and the text after a colon.
_CASE_LEAD = re.compile(r"^\s*(?:>\s*)*(?:#{1,6}\s+|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)?")
_SENTENCE = re.compile(r"(?:[.!?]|:)\s+")
_FIRST_WORD = re.compile(r"^[^A-Za-z]*([A-Za-z][\w'-]*)")
_PRONOUN = re.compile(r"(?<![\w'/.-])[Ii](?=['\s,!?]|\.(?!\w)|$)")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}")


def _case_exempt(word: str) -> bool:
    """words whose case says nothing about the style -- all-caps (`PR`), and
    identifier-shaped ones (inner capitals, digits, underscores)."""
    return (
        (len(word) > 1 and word.upper() == word)
        or any(c.isdigit() or c == "_" for c in word)
        or any(c.isupper() for c in word[1:])
    )


def case_slots(lines: list[str]) -> list[tuple[str, str]]:
    """(word, line) for the first word of every slot, minus exempt words and
    the pronoun (see pronouns())."""
    out = []
    for line in lines:
        if _TABLE_SEP.match(line):
            continue
        cells = line.strip().strip("|").split("|") if line.lstrip().startswith("|") else [line]
        for cell in cells:
            body = _CASE_LEAD.sub("", cell, count=1)
            for chunk in _SENTENCE.split(body):
                m = _FIRST_WORD.match(chunk)
                if m and m.group(1) not in ("I", "i") and not _case_exempt(m.group(1)):
                    out.append((m.group(1), line))
    return out


def pronouns(lines: list[str]) -> list[tuple[str, str]]:
    """(`I` or `i`, line) for every first-person pronoun."""
    return [(m.group(0), line) for line in lines for m in _PRONOUN.finditer(line)]


def capital_share(lines: list[str]) -> tuple[float, list[str]]:
    """share of the case slots and pronouns in lines that start capitalised,
    and the capitalised ones. NA when there are none."""
    slots = case_slots(lines) + pronouns(lines)
    if not slots:
        raise NA
    caps = [f"{w!r} in {line.strip()[:80]!r}" for w, line in slots if w[0].isupper()]
    return len(caps) / len(slots), caps


def lowercase_score(source: str) -> float:
    """1 - capital_share() of lofi_prose(source), capitals reported."""
    share, caps = capital_share(lofi_prose(source=source))
    report("capital", caps)
    return 1.0 - share


def _jsonl(path: Path):
    """yield parsed json objects from a jsonl file, skipping non-json lines."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except ValueError:
            continue


def transcript() -> dict:
    """parse the run transcript (stdout.log) into what the agent said and did.

        texts     assistant-visible output text (not tool results, so a scorer
                  grepping for a phrase doesn't match a file the agent read)
        commands  bash commands the agent ran
        writes    file paths touched via write/edit-style tools
        parsed    True when a structured format matched. False -> plain-text
                  fallback, only `raw` is meaningful
        raw       ansi-stripped stdout+stderr, all formats

    formats: claude stream-json (lines carry "message" / "session_id"),
    opencode --format json (lines carry a "part" object), codex --json (lines
    are item.started / item.completed carrying an "item" object).
    """
    texts: list[str] = []
    commands: list[str] = []
    writes: list[str] = []
    saw_claude = saw_oc = saw_codex = False

    for ev in _jsonl(OUT / "stdout.log"):
        # codex: only the completed events carry a result, item.started would
        # double-count.
        item = ev.get("item")
        if isinstance(item, dict) and str(ev.get("type", "")).startswith("item."):
            saw_codex = True
            if ev.get("type") == "item.completed":
                kind = item.get("type")
                if kind == "agent_message":
                    texts.append(str(item.get("text", "")))
                elif kind == "command_execution":
                    commands.append(str(item.get("command", "")))
                elif kind == "file_change":
                    for ch in item.get("changes") or []:
                        if isinstance(ch, dict) and ch.get("path"):
                            writes.append(str(ch["path"]))
            continue

        if "message" in ev or "session_id" in ev:
            saw_claude = True
        msg = ev.get("message")
        if not isinstance(msg, dict):
            msg = {}
        for c in msg.get("content") or []:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "text" and msg.get("role") == "assistant":
                texts.append(str(c.get("text", "")))
            elif c.get("type") == "tool_use":
                inp = c.get("input") or {}
                name = str(c.get("name", "")).lower()
                if name == "bash":
                    commands.append(str(inp.get("command", "")))
                elif name in _WRITE_TOOLS:
                    writes.extend(str(inp[k]) for k in _PATH_KEYS if k in inp)

        part = ev.get("part")
        if not isinstance(part, dict):
            continue
        saw_oc = True
        if ev.get("type") == "text":
            texts.append(str(part.get("text", "")))
        elif ev.get("type") == "tool_use":
            state = part.get("state") or {}
            inp = state.get("input") or {}
            tool = str(part.get("tool", "")).lower()
            if "command" in inp:
                commands.append(str(inp.get("command", "")))
            elif tool in _WRITE_TOOLS:
                # by tool name only: opencode's read carries file_path too.
                writes.extend(str(inp[k]) for k in _PATH_KEYS if k in inp)

    chunks = []
    for name in ("stdout.log", "stderr.log"):
        p = OUT / name
        if p.exists():
            chunks.append(_ANSI.sub("", p.read_text(encoding="utf-8", errors="replace")))
    return {
        "texts": texts,
        "commands": commands,
        "writes": writes,
        "parsed": saw_claude or saw_oc or saw_codex,
        "raw": "\n".join(chunks),
    }
