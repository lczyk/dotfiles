from __future__ import annotations

import argparse
import os
import sys

from . import __version__, _log
from .completions import SHELLS as COMPLETION_SHELLS
from .completions import render as render_completion
from .generate import DEFAULT_EFFORT, DEFAULT_MODEL, GenerateError, generate_message
from .git import (
    GitError,
    add_all,
    commit,
    has_any_remote,
    push,
    staged_binary_files,
    staged_diff_for,
    staged_files,
    staged_name_status,
)

ENV_OPTS = "CLC_DEFAULT_OPTS"
ENV_MODEL = "CLC_MODEL"
ENV_EFFORT = "CLC_EFFORT"
_VALID_OPTS = {"all", "yes", "print", "push"}


def _parse_env_opts() -> dict[str, bool]:
    raw = os.environ.get(ENV_OPTS, "")
    tokens = [t.strip().lower() for t in raw.split(",") if t.strip()]
    opts = {"all": False, "yes": False, "print": False, "push": False}
    for t in tokens:
        if t not in _VALID_OPTS:
            _log.error(f"{ENV_OPTS}: unknown token {t!r} (valid: {sorted(_VALID_OPTS)})")
            raise SystemExit(2)
        opts[t] = True
    if opts["yes"] and opts["print"]:
        _log.error(f"{ENV_OPTS}: 'yes' and 'print' are mutually exclusive")
        raise SystemExit(2)
    if opts["push"] and opts["print"]:
        _log.error(f"{ENV_OPTS}: 'push' and 'print' are mutually exclusive")
        raise SystemExit(2)
    return opts


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="claude-commit",
        description="generate a conventional-commit message for staged changes using a cheap claude model",
        epilog=(
            "env vars:\n"
            f"  {ENV_OPTS}  comma-separated default flags. tokens: all, yes, print, push.\n"
            "                     'yes'/'push' are mutually exclusive with 'print'. cli flags override:\n"
            "                     --staged cancels 'all', --print cancels 'yes'/'push',\n"
            "                     --yes cancels 'print'.\n"
            f"  {ENV_MODEL}           default model id (overridden by --model).\n"
            f"  {ENV_EFFORT}          default effort level (overridden by --effort)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--version", action="version", version=f"claude-commit {__version__}")
    p.add_argument(
        "--model",
        default=os.environ.get(ENV_MODEL, DEFAULT_MODEL),
        help=f"model id (default: {DEFAULT_MODEL}, env: {ENV_MODEL})",
    )
    p.add_argument(
        "--effort",
        default=os.environ.get(ENV_EFFORT, DEFAULT_EFFORT),
        help=f"effort level (default: {DEFAULT_EFFORT}, env: {ENV_EFFORT})",
    )
    p.add_argument(
        "-p",
        "--print",
        action="store_true",
        default=None,
        help=f"print message instead of committing (overrides 'yes'/'push' in {ENV_OPTS})",
    )
    p.add_argument(
        "-y",
        "--yes",
        action="store_true",
        default=None,
        help=f"skip y/n confirmation (overrides 'print' in {ENV_OPTS})",
    )
    p.add_argument(
        "-P",
        "--push",
        action="store_true",
        default=None,
        help="`git push` after committing (cancelled by --print)",
    )
    p.add_argument(
        "-a",
        "--all",
        action="store_true",
        default=None,
        help="stage everything (git add -A) before generating",
    )
    p.add_argument(
        "--staged",
        action="store_true",
        default=None,
        help=f"only use already-staged changes (overrides 'all' in {ENV_OPTS})",
    )
    p.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="-v: info logs, -vv: debug logs (incl. raw model i/o). all to stderr.",
    )
    p.add_argument(
        "--completion",
        choices=COMPLETION_SHELLS,
        metavar="SHELL",
        help=f"print shell completion script and exit (one of: {', '.join(COMPLETION_SHELLS)})",
    )
    return p


def main() -> None:
    args = _build_parser().parse_args()
    _log.setup(verbose=args.verbose)

    if args.completion:
        cmd_name = os.environ.get("CLC_INVOKED_AS") or os.path.basename(sys.argv[0]) or "claude-commit"
        sys.stdout.write(render_completion(args.completion, cmd_name))
        return

    env_opts = _parse_env_opts()

    if args.staged and args.all:
        _log.error("--staged and --all are mutually exclusive")
        raise SystemExit(2)
    if args.print and args.yes:
        _log.error("--print and --yes are mutually exclusive")
        raise SystemExit(2)
    if args.print and args.push:
        _log.error("--print and --push are mutually exclusive")
        raise SystemExit(2)

    do_all = (args.all is True) or (env_opts["all"] and not args.staged)
    if args.print:
        do_print, do_yes = True, False
    elif args.yes:
        do_print, do_yes = False, True
    else:
        do_print, do_yes = env_opts["print"], env_opts["yes"]
    do_push = (args.push is True) or (env_opts["push"] and not do_print)

    _log.info(
        f"resolved: all={do_all} yes={do_yes} print={do_print} push={do_push} model={args.model} effort={args.effort}"
    )

    if do_all:
        try:
            add_all()
        except GitError as e:
            _log.error(str(e))
            raise SystemExit(2) from e

    try:
        files = staged_files()
        binary = staged_binary_files()
        status = staged_name_status()
    except GitError as e:
        _log.error(str(e))
        raise SystemExit(2) from e

    if not files:
        if do_all:
            _log.error("working tree clean; nothing to commit.")
        else:
            _log.error("no staged changes. use `git add` first.")
        raise SystemExit(1)

    if binary:
        _log.warn(f"{len(binary)} binary file(s) staged; only filenames will be sent: " + ", ".join(sorted(binary)))

    if do_push and not has_any_remote():
        _log.warn("no git remote configured; will skip push.")
        do_push = False

    try:
        tag, body = generate_message(
            files,
            staged_diff_for,
            binary=binary,
            status=status,
            model=args.model,
            effort=args.effort,
        )
    except GenerateError as e:
        _log.error(str(e))
        raise SystemExit(1) from e

    # stitch tag prefix onto the first line of the body.
    first, _, rest = body.partition("\n")
    message = f"{tag}: {first}" + (f"\n{rest}" if rest.strip() else "")

    if do_print:
        print(message)
        return

    print(message)
    print()

    if not do_yes:
        try:
            reply = input("commit with this message? [Y/n] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            _log.warn("aborted.")
            raise SystemExit(130) from None
        if reply not in {"", "y", "yes"}:
            _log.warn("aborted.")
            raise SystemExit(1)

    try:
        commit(message)
    except GitError as e:
        _log.error(str(e))
        raise SystemExit(2) from e
    _log.info("committed.")

    if do_push:
        try:
            push()
        except GitError as e:
            _log.error(str(e))
            raise SystemExit(2) from e
        _log.info("pushed.")


if __name__ == "__main__":
    main()
    sys.exit(0)
