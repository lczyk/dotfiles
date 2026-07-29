"""thin wrappers over `git` for the bits we need."""

from __future__ import annotations

import os
import shutil
import subprocess
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from pathlib import Path
from tempfile import TemporaryDirectory


class GitError(RuntimeError):
    pass


# set by preview_index(); every git call reads and writes this index instead of
# the repo's own while it is in effect.
_index_file: ContextVar[str | None] = ContextVar("git_index_file", default=None)


def _run(args: list[str], *, cwd: str | None = None) -> str:
    index = _index_file.get()
    env = {**os.environ, "GIT_INDEX_FILE": index} if index else None
    try:
        out = subprocess.run(
            # quotePath=false keeps non-ascii paths readable in diff headers; the
            # machine-read listings below use -z and don't depend on it.
            ["git", "-c", "core.quotePath=false", *args],
            check=True,
            capture_output=True,
            text=True,
            errors="replace",
            cwd=cwd,
            env=env,
        )
    except FileNotFoundError as e:
        raise GitError("git not found on PATH") from e
    except subprocess.CalledProcessError as e:
        raise GitError(f"git {' '.join(args)} failed: {e.stderr.strip()}") from e
    return out.stdout


def staged_diff_for(paths: list[str]) -> str:
    if not paths:
        return ""
    repo_root = _run(["rev-parse", "--show-toplevel"]).strip()
    return _run(["diff", "--cached", "--", *paths], cwd=repo_root)


# the listings below all pass -z: without it git quotes any path with non-ascii
# or special characters, and the quoted form is useless as a pathspec later.
def _nul_fields(args: list[str]) -> list[str]:
    return _run([*args, "-z"]).split("\0")


def staged_files() -> list[str]:
    return [p for p in _nul_fields(["diff", "--cached", "--name-only"]) if p]


def staged_binary_files() -> set[str]:
    """paths whose staged diff is binary (numstat reports `-` for both counts).
    under -z a record is `<add>\t<del>\t<path>`, except renames/copies which
    leave the path empty and follow with `old` and `new` as separate fields."""
    fields = _nul_fields(["diff", "--cached", "--numstat"])
    out: set[str] = set()
    i = 0
    while i < len(fields) and fields[i]:
        parts = fields[i].split("\t")
        if len(parts) != 3:
            break
        added, deleted, path = parts
        if path:
            i += 1
        else:
            if i + 2 >= len(fields):
                break
            path = fields[i + 2]
            i += 3
        if added == "-" and deleted == "-":
            out.add(path)
    return out


def staged_name_status() -> dict[str, str]:
    """path -> single-letter change kind (A/M/D/R/C/T). renames/copies carry
    both paths, and the new one keys the entry (matches what --name-only
    reports)."""
    fields = _nul_fields(["diff", "--cached", "--name-status"])
    out: dict[str, str] = {}
    i = 0
    while i < len(fields) and fields[i]:
        status = fields[i]
        n = 2 if status[0] in "RC" else 1
        if i + n >= len(fields):
            break
        out[fields[i + n]] = status[0]
        i += n + 1
    return out


def worktree_dirty() -> bool:
    """any unstaged edit or untracked file. only ask this when nothing is
    staged -- `git status` counts staged entries too."""
    return bool(_run(["status", "--porcelain", "-z"]))


def commit(message: str) -> None:
    _run(["commit", "-m", message])


def add_all() -> None:
    _run(["add", "-A"])


@contextmanager
def preview_index() -> Iterator[None]:
    """run the enclosed git calls against a throwaway copy of the index, so
    `add_all()` can be previewed without touching the repo. leaving the block
    discards the copy -- an abort at any point stages nothing."""
    real = Path(_run(["rev-parse", "--git-path", "index"]).strip()).resolve()
    with TemporaryDirectory(prefix="auto-commit-") as tmpdir:
        # a fresh repo has no index file yet; leaving the copy absent is how git
        # spells "empty index", whereas a zero-length file is a parse error.
        copy = Path(tmpdir) / "index"
        if real.exists():
            shutil.copyfile(real, copy)
        token = _index_file.set(str(copy))
        try:
            yield
        finally:
            _index_file.reset(token)
