"""thin wrappers over `git` for the bits we need."""

from __future__ import annotations

import subprocess


class GitError(RuntimeError):
    pass


def _run(args: list[str], *, cwd: str | None = None) -> str:
    try:
        out = subprocess.run(
            ["git", *args],
            check=True,
            capture_output=True,
            text=True,
            errors="replace",
            cwd=cwd,
        )
    except FileNotFoundError as e:
        raise GitError("git not found on PATH") from e
    except subprocess.CalledProcessError as e:
        raise GitError(f"git {' '.join(args)} failed: {e.stderr.strip()}") from e
    return out.stdout


def staged_diff() -> str:
    return _run(["diff", "--cached"])


def staged_diff_for(paths: list[str]) -> str:
    if not paths:
        return ""
    repo_root = _run(["rev-parse", "--show-toplevel"]).strip()
    return _run(["diff", "--cached", "--", *paths], cwd=repo_root)


def staged_blob(path: str) -> str:
    """staged content of a single file (`:path` blob). empty for deletions."""
    try:
        return _run(["show", f":{path}"])
    except GitError:
        return ""


def staged_files() -> list[str]:
    raw = _run(["diff", "--cached", "--name-only"])
    return [line for line in raw.splitlines() if line]


def staged_binary_files() -> set[str]:
    """paths whose staged diff is binary (numstat reports `-\t-\t<path>`)."""
    raw = _run(["diff", "--cached", "--numstat"])
    out: set[str] = set()
    for line in raw.splitlines():
        parts = line.split("\t", 2)
        if len(parts) == 3 and parts[0] == "-" and parts[1] == "-":
            out.add(parts[2])
    return out


def staged_name_status() -> dict[str, str]:
    """path -> single-letter change kind (A/M/D/R/C/T). for renames/copies the
    line is `R100\told\tnew`, so the new path keys the entry (matches what
    --name-only reports)."""
    raw = _run(["diff", "--cached", "--name-status"])
    out: dict[str, str] = {}
    for line in raw.splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or not parts[0]:
            continue
        out[parts[-1]] = parts[0][0]
    return out


def commit(message: str) -> None:
    _run(["commit", "-m", message])


def add_all() -> None:
    _run(["add", "-A"])
