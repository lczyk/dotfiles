"""shell out to the `claude` cli for a conventional-commit message."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from collections.abc import Callable

from . import _log
from .git import staged_blob

DEFAULT_MODEL = "claude-haiku-4-5"
DEFAULT_EFFORT = "none"

# cap any single diff payload sent to the model.
MAX_DIFF_CHARS = 50_000

VALID_TAGS = (
    "feat",
    "fix",
    "docs",
    "style",
    "refactor",
    "perf",
    "test",
    "build",
    "ci",
    "chore",
    "revert",
)

COMMIT_SCHEMA = {
    "type": "object",
    "properties": {
        "tag": {"type": "string", "enum": list(VALID_TAGS)},
        "message": {"type": "string"},
    },
    "required": ["tag", "message"],
    "additionalProperties": False,
}

FILES_SCHEMA = {
    "type": "object",
    "properties": {
        "files": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["files"],
    "additionalProperties": False,
}

_RULES = (
    "tag: one of " + "|".join(VALID_TAGS) + ". "
    "message: `<subject>` or `<subject>\\n\\n<body>`. "
    "subject is lowercase, imperative, no trailing period, <= 72 chars. "
    "body (optional) explains *why*, wrapped ~72 chars."
)

PROMPT_SINGLE = """\
write a conventional-commit message for a single staged file.
{rules}

file: {file}
"""

PROMPT_PICK_FILES = """\
the following files are staged. pick the subset whose diffs you need to read
to write a meaningful commit message. return them as json
{{"files": [...]}}. if all of them matter, return all. paths must be exact.
files marked `(binary)` will not have their diff content sent in the next
step -- only the path. pick them if their name alone is signal.

files:
{files}
"""

PROMPT_MULTI = """\
write a commit message for the staged diff below.
{rules}

files:
{files}
{binary_note}
diff:
```
{diff}
```
"""


class GenerateError(RuntimeError):
    pass


def _truncate(diff: str) -> str:
    if len(diff) <= MAX_DIFF_CHARS:
        return diff
    head = diff[:MAX_DIFF_CHARS]
    return head + f"\n... [truncated, {len(diff) - MAX_DIFF_CHARS} chars omitted]"


def _render_status(phase: str, chars: int, started: float, is_tty: bool) -> None:
    """live single-line status on a tty; noop otherwise."""
    if not is_tty:
        return
    elapsed = time.time() - started
    msg = f"[claude] {phase} ({elapsed:.0f}s"
    if chars:
        msg += f", {chars} chars"
    msg += ")"
    # \r + clear-to-eol, then write. flush so it shows up immediately.
    sys.stderr.write("\r\x1b[2K" + msg)
    sys.stderr.flush()


def _clear_status(is_tty: bool) -> None:
    if is_tty:
        sys.stderr.write("\r\x1b[2K")
        sys.stderr.flush()


def _claude(prompt: str, schema: dict, *, model: str, effort: str) -> dict:
    if shutil.which("claude") is None:
        raise GenerateError("`claude` cli not found on PATH")

    cmd = [
        "claude",
        "--print",
        "--model",
        model,
    ]
    if effort and effort != "none":
        cmd += ["--effort", effort]
    # NOTE: these flags sandbox the model to a pure json producer: --tools ""
    # (no tools to run), empty+strict mcp, no slash-commands, no session
    # persistence. bypassPermissions is safe *because* --tools "" leaves nothing
    # to escalate into -- it's only here to stop interactive permission prompts
    # hanging a non-interactive run. re-enabling tools means dropping it.
    cmd += [
        "--system-prompt",
        "you are a json producer. respond only with json matching the provided schema.",
        "--tools",
        "",
        "--strict-mcp-config",
        "--mcp-config",
        '{"mcpServers": {}}',
        "--disable-slash-commands",
        "--setting-sources",
        "project",
        "--settings",
        '{"alwaysThinkingEnabled": false}',
        "--no-session-persistence",
        "--permission-mode",
        "bypassPermissions",
        "--output-format",
        "stream-json",
        "--include-partial-messages",
        "--verbose",
        "--json-schema",
        json.dumps(schema),
        prompt,
    ]

    _log.debug(f"prompt ({len(prompt)} chars):\n{prompt}")
    _log.debug(f"running: claude --model {model} --effort {effort} ...")

    is_tty = sys.stderr.isatty()
    started = time.time()
    phase = "connecting"
    last_phase_logged: str | None = None
    chars = 0
    final: dict | None = None

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None
    _render_status(phase, chars, started, is_tty)

    try:
        for raw in proc.stdout:
            raw = raw.strip()
            if not raw:
                continue
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue

            t = ev.get("type")
            if t == "system" and ev.get("subtype") == "status":
                status = ev.get("status")
                if status == "requesting":
                    phase = "waiting for first token"
            elif t == "stream_event":
                evt = ev.get("event") or {}
                et = evt.get("type")
                if et == "message_start":
                    phase = "thinking"
                elif et == "content_block_start":
                    cb = evt.get("content_block") or {}
                    cbt = cb.get("type")
                    if cbt == "thinking":
                        phase = "thinking"
                    elif cbt == "text":
                        phase = "responding"
                    elif cbt == "tool_use":
                        phase = f"calling {cb.get('name', 'tool')}"
                elif et == "content_block_delta":
                    delta = evt.get("delta") or {}
                    dt = delta.get("type")
                    if dt == "thinking_delta":
                        chars += len(delta.get("thinking", ""))
                    elif dt == "text_delta":
                        chars += len(delta.get("text", ""))
                    elif dt == "input_json_delta":
                        chars += len(delta.get("partial_json", ""))
            elif t == "result":
                final = ev
                phase = "done"

            if not is_tty and phase != last_phase_logged:
                _log.info(f"[claude] {phase}")
                last_phase_logged = phase
            _render_status(phase, chars, started, is_tty)
    finally:
        proc.wait()
        _clear_status(is_tty)

    if proc.returncode != 0:
        stderr = (proc.stderr.read() if proc.stderr else "") or ""
        raise GenerateError(f"claude cli failed (rc={proc.returncode}): {stderr.strip()}")

    if final is None:
        raise GenerateError("no result event from claude cli")

    if final.get("is_error"):
        raise GenerateError(f"claude reported error: {final.get('result')!r}")

    structured = final.get("structured_output")
    if not isinstance(structured, dict):
        raise GenerateError(f"missing structured_output in response. raw result: {final.get('result')!r}")

    elapsed = time.time() - started
    usage = final.get("usage") or {}
    fresh = usage.get("input_tokens", 0)
    cache_w = usage.get("cache_creation_input_tokens", 0)
    cache_r = usage.get("cache_read_input_tokens", 0)
    out_tok = usage.get("output_tokens", 0)
    in_tok = fresh + cache_w + cache_r
    parts = [f"{fresh} fresh"]
    if cache_w:
        parts.append(f"{cache_w} cache write")
    if cache_r:
        parts.append(f"{cache_r} cache read")
    _log.info(f"[claude] done in {elapsed:.1f}s ({in_tok} in [{', '.join(parts)}], {out_tok} out)")
    _log.debug(f"structured_output: {json.dumps(structured)}")
    return structured


def _parse_commit(obj: dict) -> tuple[str, str]:
    tag = obj.get("tag")
    message = obj.get("message")
    if tag not in VALID_TAGS:
        raise GenerateError(f"invalid tag from model: {tag!r}")
    if not isinstance(message, str) or not message.strip():
        raise GenerateError("empty message from model")
    return tag, message.strip()


def _fmt_file(p: str, binary: set[str]) -> str:
    return f"  {p} (binary)" if p in binary else f"  {p}"


def _write_commit(
    chosen: list[str],
    diff: str,
    *,
    binary: set[str],
    model: str,
    effort: str,
) -> tuple[str, str]:
    """final step: send the chosen files + their (already-fetched) diff and get
    back the commit message."""
    binary_chosen = [p for p in chosen if p in binary]
    binary_note = (
        "\nnote: binary files above have no diff content; only filenames were sent.\n" if binary_chosen else ""
    )
    commit_prompt = PROMPT_MULTI.format(
        rules=_RULES,
        files="\n".join(_fmt_file(f, binary) for f in chosen),
        binary_note=binary_note,
        diff=diff or "(no text-file diffs)",
    )
    obj = _claude(commit_prompt, COMMIT_SCHEMA, model=model, effort=effort)
    return _parse_commit(obj)


def generate_message(
    files: list[str],
    diff_for: Callable[[list[str]], str],
    *,
    binary: set[str] | None = None,
    model: str = DEFAULT_MODEL,
    effort: str = DEFAULT_EFFORT,
) -> tuple[str, str]:
    """returns (tag, message). `diff_for(paths)` is a callback to fetch the
    staged diff for a given list of paths. `binary` lists paths whose diff
    content should not be sent (filename only)."""
    if not files:
        raise GenerateError("no staged files")
    binary = binary or set()

    if len(files) == 1:
        # single file: filename alone is enough signal. cheaper, faster.
        _log.info(f"single file -> filename-only mode ({files[0]})")
        prompt = PROMPT_SINGLE.format(rules=_RULES, file=files[0])
        obj = _claude(prompt, COMMIT_SCHEMA, model=model, effort=effort)
        return _parse_commit(obj)

    # fetch the whole diff up front. when it fits under the cap, skip the pick
    # step and write the message in a single call -- the pick round-trip only
    # earns its latency when the diff is too big to send whole and needs
    # trimming. so the cap doubles as the skip/trim boundary.
    text_files = [p for p in files if p not in binary]
    full_diff = diff_for(text_files) if text_files else ""

    if len(full_diff) <= MAX_DIFF_CHARS:
        _log.info(f"{len(files)} files, diff {len(full_diff)} chars <= {MAX_DIFF_CHARS} -> single-call mode")
        return _write_commit(files, full_diff, binary=binary, model=model, effort=effort)

    # large diff: 2-step chain. step 1 picks the relevant subset, step 2 writes
    # the commit from just those files' (truncated) diff.
    _log.info(f"{len(files)} files, diff {len(full_diff)} chars > {MAX_DIFF_CHARS} -> picking relevant subset")
    pick_prompt = PROMPT_PICK_FILES.format(files="\n".join(_fmt_file(f, binary) for f in files))
    picked = _claude(pick_prompt, FILES_SCHEMA, model=model, effort=effort)

    requested = picked.get("files") or []
    # sanitise: keep only paths the model is actually allowed to see.
    staged_set = set(files)
    chosen = [p for p in requested if p in staged_set]
    if not chosen:
        # model picked nothing valid -- fall back to all files.
        _log.warn("model picked no valid files; sending all")
        chosen = files
    _log.info(f"chosen ({len(chosen)}/{len(files)}): " + ", ".join(os.path.basename(p) for p in chosen))

    text_chosen = [p for p in chosen if p not in binary]
    binary_chosen = [p for p in chosen if p in binary]
    for p in text_chosen:
        head = "\n".join(staged_blob(p).splitlines()[:10])
        _log.debug(f"--- {p} (head -n10) ---\n{head}")
    if binary_chosen:
        _log.info(f"skipping diff content for {len(binary_chosen)} binary file(s)")

    diff = _truncate(diff_for(text_chosen)) if text_chosen else ""
    return _write_commit(chosen, diff, binary=binary, model=model, effort=effort)
