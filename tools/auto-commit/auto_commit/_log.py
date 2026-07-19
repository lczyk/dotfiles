"""tiny logging helpers w/ ansi colour."""

from __future__ import annotations

import logging
import sys

_COLOUR: dict[str, str] = {
    "cyan": "\033[36m",
    "blue": "\033[34m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "reset": "\033[0m",
}

_log = logging.getLogger("auto-commit")


def setup(verbose: int = 0) -> None:
    """verbose: 0 = warnings+errors, 1 = info, 2 = debug."""
    if not _log.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(logging.Formatter("%(message)s"))
        _log.addHandler(handler)
        _log.propagate = False

    level = logging.WARNING
    if verbose >= 2:
        level = logging.DEBUG
    elif verbose >= 1:
        level = logging.INFO
    _log.setLevel(level)


def debug(msg: str) -> None:
    _log.debug("%s%s%s", _COLOUR["cyan"], msg, _COLOUR["reset"])


def info(msg: str) -> None:
    _log.info("%s%s%s", _COLOUR["green"], msg, _COLOUR["reset"])


def warn(msg: str) -> None:
    _log.warning("%s%s%s", _COLOUR["yellow"], msg, _COLOUR["reset"])


def error(msg: str) -> None:
    _log.error("%s%s%s", _COLOUR["red"], msg, _COLOUR["reset"])
