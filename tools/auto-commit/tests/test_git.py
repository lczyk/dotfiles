"""tests for staged git reads from nested working directories."""

from __future__ import annotations

import subprocess
from contextlib import chdir
from pathlib import Path
from tempfile import TemporaryDirectory

from auto_commit.git import staged_diff_for, staged_files


def test_staged_diff_for_handles_repo_subdirectory():
    with TemporaryDirectory() as temp:
        repo = Path(temp)
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        (repo / "file.txt").write_text("staged content\n")
        subprocess.run(["git", "add", "--", "file.txt"], cwd=repo, check=True)
        nested = repo / "nested"
        nested.mkdir()

        with chdir(nested):
            files = staged_files()
            assert files == ["file.txt"]
            assert "staged content" in staged_diff_for(files)
