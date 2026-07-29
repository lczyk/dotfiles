"""tiny logging helpers w/ ansi colour."""

from __future__ import annotations

import logging
import os
import sys

_COLOUR: dict[str, str] = {
    "magenta": "\033[35m",
    "cyan": "\033[36m",
    "blue": "\033[34m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "reset": "\033[0m",
}

# one below DEBUG: the bulky stuff you only want when chasing what was sent.
TRACE = logging.DEBUG - 5
logging.addLevelName(TRACE, "TRACE")

_BY_LEVEL: dict[int, str] = {
    TRACE: "magenta",
    logging.DEBUG: "cyan",
    logging.INFO: "green",
    logging.WARNING: "yellow",
    logging.ERROR: "red",
}

_log = logging.getLogger("auto-commit")


def _paint(msg: str, colour: str) -> str:
    """colour `msg` iff both streams are ttys and NO_COLOR is unset (presence,
    per no-color.org). one decision for both streams, not one each: `ac | cat`
    should come out plain even though the logs on stderr still face a tty."""
    if os.environ.get("NO_COLOR") or not (sys.stdout.isatty() and sys.stderr.isatty()):
        return msg
    return f"{_COLOUR[colour]}{msg}{_COLOUR['reset']}"


class _ColourFormatter(logging.Formatter):
    """colour by level, so callers just log and never mention a colour."""

    def format(self, record: logging.LogRecord) -> str:
        colour = _BY_LEVEL.get(record.levelno)
        msg = record.getMessage()
        return _paint(msg, colour) if colour else msg


_LEVELS = [logging.WARNING, logging.INFO, logging.DEBUG, TRACE]


def setup(verbose: int = 0) -> None:
    """verbose: 0 = warnings+errors, 1 = info, 2 = + model output, 3 = + what
    we sent. anything past 3 is the same as 3."""
    if not _log.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(_ColourFormatter())
        _log.addHandler(handler)
        _log.propagate = False

    _log.setLevel(_LEVELS[min(verbose, len(_LEVELS) - 1)])


def verbose() -> bool:
    """true from -v upwards."""
    return _log.isEnabledFor(logging.INFO)


def debugging() -> bool:
    """true from -vv upwards."""
    return _log.isEnabledFor(logging.DEBUG)


def trace(msg: str) -> None:
    _log.log(TRACE, msg)


def blue(msg: str) -> str:
    """colourise without logging -- for text written straight to stdout."""
    return _paint(msg, "blue")


debug = _log.debug
info = _log.info
warn = _log.warning
error = _log.error
