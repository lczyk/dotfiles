"""shell out to the `claude` cli for a conventional-commit message."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import threading
import time
from collections.abc import Callable, Iterable
from tempfile import TemporaryFile
from typing import NamedTuple

from . import _log

DEFAULT_MODEL = "claude-haiku-4-5"
DEFAULT_VARIANT = "none"

# cap any single diff payload sent to the model.
MAX_DIFF_CHARS = 50_000

# kill the cli if a single invocation runs longer than this.
CLAUDE_TIMEOUT = 120

# mirrors the HEADERS list in the commit-msg hook, in the same order -- a tag
# this doesn't accept is a commit the hook will bounce. the glosses go into the
# prompt; without them the model gets the bare words and has to guess.
TAG_GLOSS: dict[str, str] = {
    "feat": "new capability someone could use",
    "fix": "corrects behaviour that was wrong",
    "docs": "documentation or comments only",
    "test": "tests only",
    "refactor": "restructures code without changing what it does",
    "chore": "anything else -- deps, tooling, config, formatting, build files",
    "bench": "benchmarks only",
    "revert": "undoes an earlier commit",
    "ci": "ci config, pipelines, workflows",
    "perf": "same behaviour, measurably faster or lighter",
    "release": "version bump or release prep, nothing else",
}

VALID_TAGS = tuple(TAG_GLOSS)

COMMIT_SCHEMA = {
    "type": "object",
    "properties": {
        "tag": {"type": "string", "enum": list(VALID_TAGS)},
        "message": {"type": "string"},
    },
    "required": ["tag", "message"],
    "additionalProperties": False,
}

# general conventional-commit rules -- sensible for anyone.
_RULES_COMMON = (
    "tag: exactly one of --\n"
    + "".join(f"  {tag}: {gloss}\n" for tag, gloss in TAG_GLOSS.items())
    + "pick the narrowest one that covers the whole diff; `chore` is the fallback "
    "when nothing narrower fits, not a tie-breaker. "
    "message: `<subject>` or `<subject>\\n\\n<body>`. "
    "subject: imperative, no trailing period, <= 72 chars. a terse reminder of what the "
    "change is about, not a description -- don't name specific functions/classes/variables, "
    "and don't pad with framing verbs (add, implement, introduce, support for) the tag "
    "already implies. "
    "body: include only when the why isn't obvious from the diff; explain why, not what; "
    "wrap ~72 chars. "
    "avoid filler/marketing words (robust, seamless, leverage, crucial) and tacked-on "
    "'-ing' clauses (ensuring..., highlighting..., reflecting...). no emoji. "
    "ascii only (write -- not an em-dash, -> not an arrow)."
)

# personal voice/locale -- edit (or empty) to taste; concatenated onto the common rules.
_RULES_STYLE = "write lowercase and casual, in british english."

_RULES = _RULES_COMMON + " " + _RULES_STYLE

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


# the cli is invoked with --tools "", so the only tool it should report is the
# one the schema itself installs. bypassPermissions is only defensible while
# that holds -- anything else in the list can be escalated into.
ALLOWED_TOOLS = frozenset({"StructuredOutput"})


class Stream(NamedTuple):
    """what a single cli invocation told us about itself."""

    result: dict | None
    chars: int
    init: dict | None = None
    thinking_tokens: int = 0


class GenerateError(RuntimeError):
    pass


class GenerateCancelled(GenerateError):
    pass


def _kill(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is None:
        try:
            proc.kill()
        except ProcessLookupError:
            return


def _reap(proc: subprocess.Popen[str], *, kill: bool) -> bool:
    """stop and reap child; return true when ctrl+c interrupted cleanup."""
    interrupted = False
    if kill:
        _kill(proc)
    while True:
        try:
            proc.wait()
            return interrupted
        except KeyboardInterrupt:
            interrupted = True
            _kill(proc)


def _truncate(text: str, limit: int) -> str:
    """keep the head, cut on a line boundary, say what was dropped."""
    if len(text) <= limit:
        return text
    head = text[:limit].rsplit("\n", 1)[0]
    return head + f"\n... [truncated, {len(text) - len(head)} chars omitted]\n"


def _split_by_file(diff: str) -> list[str]:
    """one chunk per file, header included. only a header sits at column 0 with
    `diff --git `; body lines always carry a ' ', '+' or '-' prefix, so this
    can't be fooled by a diff of a diff."""
    chunks: list[list[str]] = []
    for line in diff.splitlines(keepends=True):
        if line.startswith("diff --git ") or not chunks:
            chunks.append([])
        chunks[-1].append(line)
    return ["".join(c) for c in chunks]


def _label(header: str, paths: list[str]) -> str:
    """match a chunk back to the path that produced it. the header's last field
    is `<prefix>/<path>` (the new name, for renames), so an exact suffix match
    on `/<path>` survives spaces in filenames and near-identical names."""
    first = header.partition("\n")[0]
    return next((p for p in paths if first.endswith("/" + p)), first)


def _allocate(sizes: list[int], budget: int) -> list[int]:
    """max-min fair share: an equal slice each, and whatever a small file
    doesn't need is handed back to be split among the ones still short."""
    out = [0] * len(sizes)
    remaining, left = budget, len(sizes)
    for i in sorted(range(len(sizes)), key=lambda i: sizes[i]):
        take = min(sizes[i], remaining // left)
        out[i] = take
        remaining -= take
        left -= 1
    return out


def _fit(diff: str, paths: list[str], budget: int = MAX_DIFF_CHARS) -> str:
    """trim a combined diff to `budget` chars by giving every file a fair share
    of it. breadth over depth -- a commit subject summarises the whole change,
    so every file should be represented even if none is represented fully."""
    if len(diff) <= budget:
        return diff
    chunks = _split_by_file(diff)
    allowances = _allocate([len(c) for c in chunks], budget)
    kept = []
    for chunk, allowance in zip(chunks, allowances, strict=True):
        if len(chunk) > allowance:
            _log.debug(f"trimmed {_label(chunk, paths)}: {len(chunk)} -> {allowance} chars")
        kept.append(_truncate(chunk, allowance))
    return "".join(kept)


def _render_status(phase: str, chars: int, started: float) -> None:
    """redraw the single-line live status in place."""
    elapsed = time.time() - started
    msg = f"[claude] {phase} ({elapsed:.0f}s"
    if chars:
        msg += f", {chars} chars"
    msg += ")"
    # \r + clear-to-eol, then write. flush so it shows up immediately.
    sys.stderr.write("\r\x1b[2K" + msg)
    sys.stderr.flush()


def _clear_status() -> None:
    sys.stderr.write("\r\x1b[2K")
    sys.stderr.flush()


def _consume(
    lines: Iterable[str],
    on_phase: Callable[[str, int], None] | None = None,
    on_block: Callable[[str, str], None] | None = None,
) -> Stream:
    """parse the cli's stream-json event lines.
    `on_phase(phase, chars)` fires once per parsed line for live status.
    `on_block(kind, text)` fires once per completed thinking/text block -- the
    deltas are only buffered when it's supplied. pure apart from the callbacks
    -- feed it canned lines to test the state machine."""
    phase = "connecting"
    chars = 0
    final: dict | None = None
    init: dict | None = None
    thinking_tokens = 0
    kind = ""
    buf: list[str] = []

    def _flush() -> None:
        if buf and on_block:
            on_block(kind, "".join(buf))
        buf.clear()

    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            ev = json.loads(raw)
        except json.JSONDecodeError:
            continue

        # mapping patterns ignore keys we don't name, which is what you want
        # against a stream whose events carry plenty we don't care about.
        match ev:
            case {"type": "system", "subtype": "init"}:
                init = ev
            case {"type": "system", "subtype": "status", "status": "requesting"}:
                phase = "waiting for first token"
            case {"type": "result"}:
                final = ev
                phase = "done"
            case {"type": "stream_event", "event": dict(evt)}:
                match evt:
                    case {"type": "message_start"}:
                        phase = "thinking"
                    case {"type": "content_block_start", "content_block": {"type": "thinking"}}:
                        phase = kind = "thinking"
                    case {"type": "content_block_start", "content_block": {"type": "text"}}:
                        phase, kind = "responding", "text"
                    case {"type": "content_block_start", "content_block": {"type": "tool_use", **cb}}:
                        phase, kind = f"calling {cb.get('name', 'tool')}", ""
                    case {"type": "content_block_stop"}:
                        _flush()
                    case {"type": "content_block_delta", "delta": {"type": "thinking_delta", "thinking": str(s)}}:
                        chars += len(s)
                        if on_block:
                            buf.append(s)
                    case {"type": "content_block_delta", "delta": {"type": "text_delta", "text": str(s)}}:
                        chars += len(s)
                        if on_block:
                            buf.append(s)
                    case {"type": "content_block_delta", "delta": {"type": "input_json_delta", "partial_json": str(s)}}:
                        # the tool call carries the structured output, which gets
                        # logged whole once it's parsed. no point buffering it.
                        chars += len(s)
                    case {"type": "message_delta", "usage": {"output_tokens_details": {"thinking_tokens": int(n)}}}:
                        # only lives here -- the result event reports it as null.
                        thinking_tokens += n

        if on_phase:
            on_phase(phase, chars)
    _flush()
    return Stream(final, chars, init, thinking_tokens)


def _check_sandbox(init: dict | None) -> None:
    """the init event is the cli reporting the sandbox it actually built. a tool
    we didn't ask for means --tools "" stopped working, which is what makes
    bypassPermissions safe -- so that's a hard failure, not a warning."""
    if init is None:
        return
    tools = init.get("tools") or []
    _log.trace(
        f"[claude sandbox] model={init.get('model')} tools={tools} "
        f"mcp={init.get('mcp_servers')} permissions={init.get('permissionMode')}"
    )
    if extra := sorted(set(tools) - ALLOWED_TOOLS):
        raise GenerateError(
            f"claude cli exposed unexpected tools despite --tools '': {', '.join(extra)}. "
            "refusing to continue under --permission-mode bypassPermissions."
        )


def _claude(prompt: str, schema: dict, *, model: str, variant: str) -> dict:
    if shutil.which("claude") is None:
        raise GenerateError("`claude` cli not found on PATH")

    cmd = [
        "claude",
        "--print",
        "--model",
        model,
    ]
    # the cli spells this --effort; `variant` is our generic name for the knob.
    # asking for a variant and pinning thinking off contradict each other, so
    # the default-off setting below is only applied when no variant is asked for.
    wants_variant = bool(variant) and variant != "none"
    if wants_variant:
        cmd += ["--effort", variant]
    else:
        cmd += ["--settings", '{"alwaysThinkingEnabled": false}']
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

    _log.debug(f"running: claude --model {model} --effort {variant} ...")
    _log.trace(f"prompt ({len(prompt)} chars):\n{prompt}")

    # the in-place status line would trample the phase logs, so under -v the
    # phases are logged instead, one line each.
    live = sys.stderr.isatty() and not _log.verbose()
    started = time.time()

    with TemporaryFile() as errf:
        # stderr goes to a file rather than a pipe: nothing to drain, so a
        # chatty child can't fill a buffer and deadlock the stdout read loop.
        proc = subprocess.Popen(
            cmd,
            # the prompt is an argv item, so the child needs no stdin -- and
            # letting it inherit ours lets it swallow the y/n answer typed after.
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=errf,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        if live:
            _render_status("connecting", 0, started)

        timed_out = threading.Event()
        watchdog = threading.Timer(CLAUDE_TIMEOUT, lambda: (timed_out.set(), proc.kill()))
        watchdog.start()

        last_phase_logged: str | None = None

        def _on_phase(phase: str, chars: int) -> None:
            nonlocal last_phase_logged
            if live:
                _render_status(phase, chars, started)
            elif phase != last_phase_logged:
                _log.info(f"[claude] {phase}")
                last_phase_logged = phase

        def _on_block(kind: str, text: str) -> None:
            _log.debug(f"[claude {kind}]\n{text.strip()}")

        interrupted = False
        stream = Stream(None, 0)
        try:
            stream = _consume(proc.stdout, _on_phase, _on_block if _log.debugging() else None)
        except KeyboardInterrupt:
            interrupted = True
        finally:
            watchdog.cancel()
            interrupted = _reap(proc, kill=interrupted) or interrupted
            if live:
                _clear_status()

        if interrupted:
            raise GenerateCancelled("aborted") from None

        if timed_out.is_set():
            raise GenerateError(f"claude cli timed out after {CLAUDE_TIMEOUT}s")

        errf.seek(0)
        stderr = errf.read().decode(errors="replace").strip()

        if proc.returncode != 0:
            raise GenerateError(f"claude cli failed (rc={proc.returncode}): {stderr}")

        if stderr:
            _log.trace(f"[claude stderr]\n{stderr}")

    final = stream.result
    _check_sandbox(stream.init)

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

    stop = final.get("stop_reason")
    if stop == "max_tokens":
        # visible without -v: it's the likeliest cause of whatever fails next.
        _log.warn("[claude] output hit the token cap; the message may be truncated")
    if _log.debugging():
        used = final.get("modelUsage") or {}
        bits = [f"stop={stop}", f"resolved={', '.join(used) or '?'}"]
        if (cost := final.get("total_cost_usd")) is not None:
            bits.append(f"cost=${cost:.5f}")
        if stream.thinking_tokens:
            bits.append(f"thinking={stream.thinking_tokens} tok")
        for key, label in (("ttft_ms", "ttft"), ("duration_api_ms", "api")):
            if (ms := final.get(key)) is not None:
                bits.append(f"{label}={ms}ms")
        _log.debug("[claude] " + " ".join(bits))
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


_STATUS_WORD = {"A": "added", "M": "modified", "D": "deleted", "R": "renamed", "C": "copied", "T": "type changed"}


def _fmt_file(p: str, binary: set[str], status: dict[str, str]) -> str:
    """`  <path> (<kind>, binary)` -- annotate with the change kind (added /
    modified / ...) so the model doesn't assume an edit is a fresh add, and flag
    binary files whose diff content is withheld."""
    tags = []
    word = _STATUS_WORD.get(status.get(p, ""))
    if word:
        tags.append(word)
    if p in binary:
        tags.append("binary")
    return f"  {p} ({', '.join(tags)})" if tags else f"  {p}"


def _write_commit(
    chosen: list[str],
    diff: str,
    *,
    binary: set[str],
    status: dict[str, str],
    model: str,
    variant: str,
) -> tuple[str, str]:
    """final step: send the chosen files + their (already-fetched) diff and get
    back the commit message."""
    binary_chosen = [p for p in chosen if p in binary]
    binary_note = (
        "\nnote: binary files above have no diff content; only filenames were sent.\n" if binary_chosen else ""
    )
    commit_prompt = PROMPT_MULTI.format(
        rules=_RULES,
        files="\n".join(_fmt_file(f, binary, status) for f in chosen),
        binary_note=binary_note,
        diff=diff or "(no text-file diffs)",
    )
    obj = _claude(commit_prompt, COMMIT_SCHEMA, model=model, variant=variant)
    return _parse_commit(obj)


def generate_message(
    files: list[str],
    diff_for: Callable[[list[str]], str],
    *,
    binary: set[str] | None = None,
    status: dict[str, str] | None = None,
    model: str = DEFAULT_MODEL,
    variant: str = DEFAULT_VARIANT,
) -> tuple[str, str]:
    """returns (tag, message). `diff_for(paths)` is a callback to fetch the
    staged diff for a given list of paths. `binary` lists paths whose diff
    content should not be sent (filename only). `status` maps path -> change
    kind letter (A/M/D/...) for the file annotations."""
    if not files:
        raise GenerateError("no staged files")
    binary = binary or set()
    status = status or {}

    text_files = [p for p in files if p not in binary]
    full_diff = diff_for(text_files) if text_files else ""
    diff = _fit(full_diff, text_files)
    if len(diff) < len(full_diff):
        _log.info(f"{len(files)} files, diff {len(full_diff)} chars > {MAX_DIFF_CHARS} -> trimmed to {len(diff)}")
    else:
        _log.info(f"{len(files)} files, diff {len(full_diff)} chars, sent whole")

    return _write_commit(files, diff, binary=binary, status=status, model=model, variant=variant)
