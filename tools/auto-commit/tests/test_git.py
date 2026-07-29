"""tests for staged git reads from nested working directories."""

from __future__ import annotations

import subprocess
from contextlib import chdir
from pathlib import Path
from tempfile import TemporaryDirectory

from auto_commit.git import (
    add_all,
    preview_index,
    staged_binary_files,
    staged_diff_for,
    staged_files,
    staged_name_status,
    worktree_dirty,
)


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def _commit(repo: Path, subject: str) -> None:
    _git(
        repo,
        "-c",
        "user.email=t@t",
        "-c",
        "user.name=t",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-qm",
        subject,
    )


def test_staged_diff_for_handles_repo_subdirectory():
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        _git(repo, "init", "-q")
        (repo / "file.txt").write_text("staged content\n")
        _git(repo, "add", "--", "file.txt")
        nested = repo / "nested"
        nested.mkdir()

        with chdir(nested):
            files = staged_files()
            assert files == ["file.txt"]
            assert "staged content" in staged_diff_for(files)


def test_non_ascii_paths_are_not_quoted():
    # escaped rather than literal so this file stays ascii; the path git sees
    # is still non-ascii, which is the whole point of the test.
    name = "caf\u00e9.txt"
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        _git(repo, "init", "-q")
        (repo / name).write_text("staged content\n")
        _git(repo, "add", "--", name)

        with chdir(repo):
            files = staged_files()
            assert files == [name]
            assert "staged content" in staged_diff_for(files)
            assert staged_name_status() == {name: "A"}


def test_worktree_dirty_distinguishes_empty_index_cases():
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        _git(repo, "init", "-q")
        (repo / "file.txt").write_text("committed\n")
        _git(repo, "add", "--", "file.txt")
        _commit(repo, "chore: init")

        with chdir(repo):
            assert staged_files() == []
            assert not worktree_dirty()

            (repo / "file.txt").write_text("edited\n")
            assert not staged_files()
            assert worktree_dirty()

            (repo / "file.txt").write_text("committed\n")
            (repo / "untracked.txt").write_text("new\n")
            assert worktree_dirty()


def _porcelain(repo: Path) -> str:
    return subprocess.run(["git", "status", "--porcelain"], cwd=repo, check=True, capture_output=True, text=True).stdout


def test_preview_index_does_not_touch_the_real_index():
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        _git(repo, "init", "-q")
        (repo / "tracked.txt").write_text("committed\n")
        _git(repo, "add", "--", "tracked.txt")
        _commit(repo, "chore: init")
        (repo / "tracked.txt").write_text("edited\n")
        (repo / "untracked.txt").write_text("new\n")
        before = _porcelain(repo)

        with chdir(repo):
            with preview_index():
                add_all()
                assert set(staged_files()) == {"tracked.txt", "untracked.txt"}
            assert staged_files() == []

        assert _porcelain(repo) == before


def test_preview_index_survives_a_repo_with_no_index_file():
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        _git(repo, "init", "-q")
        (repo / "first.txt").write_text("new\n")
        assert not (repo / ".git" / "index").exists()

        with chdir(repo):
            with preview_index():
                add_all()
                assert staged_files() == ["first.txt"]
            assert staged_files() == []

        assert not (repo / ".git" / "index").exists()


def test_rename_and_binary_are_parsed():
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        _git(repo, "init", "-q")
        (repo / "old.txt").write_text("x\n")
        _git(repo, "add", "--", "old.txt")
        _commit(repo, "chore: init")
        _git(repo, "mv", "old.txt", "new.txt")
        (repo / "blob.dat").write_bytes(b"\x00\x01\x02")
        _git(repo, "add", "--", "blob.dat")

        with chdir(repo):
            assert staged_binary_files() == {"blob.dat"}
            assert staged_name_status() == {"new.txt": "R", "blob.dat": "A"}
