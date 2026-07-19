"""shell completion templates."""

from __future__ import annotations

from importlib.resources import files

PLACEHOLDER = "__AC_CMD__"
SHELLS = ("fish",)


def render(shell: str, cmd_name: str) -> str:
    if shell not in SHELLS:
        raise ValueError(f"invalid shell {shell!r}, must be one of: {', '.join(SHELLS)}")
    template = files(__package__).joinpath(f"auto-commit.{shell}").read_text()
    return template.replace(PLACEHOLDER, cmd_name)
