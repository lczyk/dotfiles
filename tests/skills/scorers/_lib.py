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
    "NA",
    "OUT",
    "TASK",
    "emit",
    "lofi_prose",
    "lofi_raw",
    "penalty",
    "report",
    "transcript",
]

# tasks whose chat reply and commit messages should be lofi.
_LOFI_TASKS = {"lofi-explain", "lofi-pr-body", "lofi-commit", "lofi-docs-match"}

_FENCE = re.compile(r"^\s*(```|~~~)")
_INLINE_CODE = re.compile(r"`[^`]*`")
_URL = re.compile(r"https?://\S+")
_DQUOTED = re.compile(r'"[^"\n]*"')

OUT = Path(os.environ["PATS_OUTPUT_DIR"])
TASK = os.environ.get("PATS_TASK_ID", "")

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


def lofi_raw() -> str:
    """the lofi text under test, as written: the agent's own output plus the
    messages of any commits it made. NA outside the lofi prose tasks."""
    if TASK not in _LOFI_TASKS:
        raise NA
    parts = list(transcript()["texts"])
    commits = OUT / "new-commits.txt"
    if commits.exists():
        parts.append(commits.read_text(encoding="utf-8", errors="replace"))
    text = "\n".join(parts).strip()
    if not text:
        raise NA
    return text


def lofi_prose() -> list[str]:
    """lofi_raw() as prose lines: no fenced blocks, and inline code, urls and
    double-quoted text cut out, since those keep their source spelling."""
    lines = []
    in_fence = False
    for line in lofi_raw().splitlines():
        if _FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        line = _DQUOTED.sub(" ", _URL.sub(" ", _INLINE_CODE.sub(" ", line)))
        if line.strip():
            lines.append(line)
    return lines


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
