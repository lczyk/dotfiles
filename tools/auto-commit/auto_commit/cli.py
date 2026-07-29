from __future__ import annotations

import argparse
import os
import sys
from contextlib import nullcontext
from pathlib import Path

from . import __version__, _log
from .completions import SHELLS as COMPLETION_SHELLS
from .completions import render as render_completion
from .generate import DEFAULT_MODEL, DEFAULT_VARIANT, GenerateCancelled, GenerateError, generate_message
from .git import (
    GitError,
    add_all,
    commit,
    preview_index,
    staged_binary_files,
    staged_diff_for,
    staged_files,
    staged_name_status,
    worktree_dirty,
)


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="auto-commit",
        description="generate a conventional-commit message for staged changes using a cheap claude model",
    )
    p.add_argument("--version", action="version", version=f"auto-commit {__version__}")
    p.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"model id (default: {DEFAULT_MODEL})",
    )
    p.add_argument(
        "--variant",
        default=DEFAULT_VARIANT,
        help=f"model variant (default: {DEFAULT_VARIANT})",
    )
    disposition = p.add_mutually_exclusive_group()
    disposition.add_argument(
        "-p",
        "--print",
        action="store_true",
        help="print message instead of committing",
    )
    disposition.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="skip y/n confirmation",
    )
    p.add_argument(
        "-a",
        "--all",
        action="store_true",
        help="stage everything (git add -A) before generating",
    )
    p.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="repeatable, all to stderr. -v: progress, -vv: + model output, -vvv: + what we sent.",
    )
    p.add_argument(
        "--completion",
        choices=COMPLETION_SHELLS,
        metavar="SHELL",
        help=f"print shell completion script and exit (one of: {', '.join(COMPLETION_SHELLS)})",
    )
    return p


def _compose(*, do_all: bool, model: str, variant: str) -> str:
    """stage (if asked), read the index, and return the commit message."""
    try:
        if do_all:
            add_all()
        files = staged_files()
        binary = staged_binary_files()
        status = staged_name_status()
    except GitError as e:
        _log.error(str(e))
        raise SystemExit(2) from e

    if not files:
        if not do_all and worktree_dirty():
            _log.error("nothing staged. `git add` what you want committed, or pass -a to stage everything.")
        else:
            _log.error("working tree clean; nothing to commit.")
        raise SystemExit(1)

    if binary:
        _log.warn(f"{len(binary)} binary file(s) staged; only filenames will be sent: " + ", ".join(sorted(binary)))

    try:
        tag, body = generate_message(
            files,
            staged_diff_for,
            binary=binary,
            status=status,
            model=model,
            variant=variant,
        )
    except GenerateCancelled:
        print()
        _log.warn("aborted.")
        raise SystemExit(130) from None
    except GenerateError as e:
        _log.error(str(e))
        raise SystemExit(1) from e

    # stitch tag prefix onto the first line of the body.
    first, _, rest = body.partition("\n")
    return f"{tag}: {first}" + (f"\n{rest}" if rest.strip() else "")


def main() -> None:
    args = _build_parser().parse_args()
    _log.setup(verbose=args.verbose)

    if args.completion:
        cmd_name = os.environ.get("AC_INVOKED_AS") or Path(sys.argv[0]).name or "auto-commit"
        sys.stdout.write(render_completion(args.completion, cmd_name))
        return

    do_all, do_print, do_yes = args.all, args.print, args.yes
    _log.info(f"resolved: all={do_all} yes={do_yes} print={do_print} model={args.model} variant={args.variant}")

    # -a is previewed against a copy of the index, so an abort anywhere below
    # leaves the repo exactly as it was; the real staging happens post-confirm.
    with preview_index() if do_all else nullcontext():
        message = _compose(do_all=do_all, model=args.model, variant=args.variant)

    if do_print:
        print(message)
        return

    print(message)
    print()

    if not do_yes:
        try:
            reply = input(_log.blue("commit with this message? [Y/n]") + " ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            _log.warn("aborted.")
            raise SystemExit(130) from None
        if reply not in {"", "y", "yes"}:
            _log.warn("aborted.")
            raise SystemExit(1)

    try:
        if do_all:
            add_all()
        commit(message)
    except GitError as e:
        _log.error(str(e))
        raise SystemExit(2) from e
    _log.info("committed.")


if __name__ == "__main__":
    main()
    sys.exit(0)
