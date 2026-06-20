"""tests for claude_commit.generate. plain asserts -- run directly with
`python tests/test_generate.py` or via `pytest`. no fixtures, no framework."""

from __future__ import annotations

import json

from claude_commit import generate
from claude_commit.generate import (
    GenerateError,
    _consume,
    _fmt_file,
    _parse_commit,
    _truncate,
    generate_message,
)


def _line(obj: dict) -> str:
    return json.dumps(obj)


# --- _consume: the stream-json state machine ------------------------------


def test_consume_extracts_result_and_counts_chars():
    lines = [
        "",  # blank lines skipped
        "not json",  # decode errors skipped
        _line({"type": "system", "subtype": "status", "status": "requesting"}),
        _line({"type": "stream_event", "event": {"type": "message_start"}}),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "hello"}},
            }
        ),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "content_block_delta", "delta": {"type": "thinking_delta", "thinking": "abc"}},
            }
        ),
        _line({"type": "result", "structured_output": {"tag": "fix", "message": "x"}}),
    ]
    final, chars = _consume(lines)
    assert final is not None
    assert final["structured_output"] == {"tag": "fix", "message": "x"}
    assert chars == len("hello") + len("abc")


def test_consume_no_result_returns_none():
    final, chars = _consume([_line({"type": "stream_event", "event": {"type": "message_start"}})])
    assert final is None
    assert chars == 0


def test_consume_phase_transitions():
    phases: list[str] = []
    lines = [
        _line({"type": "stream_event", "event": {"type": "message_start"}}),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "content_block_start", "content_block": {"type": "text"}},
            }
        ),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "content_block_start", "content_block": {"type": "tool_use", "name": "grep"}},
            }
        ),
        _line({"type": "result"}),
    ]
    _consume(lines, on_phase=lambda p, c: phases.append(p))
    assert phases == ["thinking", "responding", "calling grep", "done"]


# --- pure helpers ---------------------------------------------------------


def test_parse_commit_ok():
    assert _parse_commit({"tag": "feat", "message": "  add thing  "}) == ("feat", "add thing")


def test_parse_commit_bad_tag():
    try:
        _parse_commit({"tag": "nope", "message": "x"})
    except GenerateError:
        pass
    else:
        raise AssertionError("expected GenerateError on bad tag")


def test_parse_commit_empty_message():
    for msg in ("", "   ", None):
        try:
            _parse_commit({"tag": "fix", "message": msg})
        except GenerateError:
            pass
        else:
            raise AssertionError(f"expected GenerateError on message={msg!r}")


def test_truncate():
    assert _truncate("abc") == "abc"
    big = "x" * (generate.MAX_DIFF_CHARS + 100)
    out = _truncate(big)
    assert len(out) < len(big)
    assert "truncated" in out
    assert "100 chars omitted" in out


def test_fmt_file_annotations():
    assert _fmt_file("a.py", set(), {"a.py": "M"}) == "  a.py (modified)"
    assert _fmt_file("a.bin", {"a.bin"}, {"a.bin": "A"}) == "  a.bin (added, binary)"
    assert _fmt_file("a.py", set(), {}) == "  a.py"


# --- generate_message: orchestration branching ----------------------------
#
# COVER: monkeypatch _claude so no real cli runs; assert which prompt/schema
# each branch sends and how picks are sanitised.


class _FakeClaude:
    """records calls and replays scripted responses in order."""

    def __init__(self, *responses: dict):
        self.responses = list(responses)
        self.calls: list[tuple[str, dict]] = []

    def __call__(self, prompt, schema, *, model, effort):
        self.calls.append((prompt, schema))
        return self.responses.pop(0)


def _patch(monkey: _FakeClaude):
    real = generate._claude
    generate._claude = monkey
    return real


def test_generate_empty_files():
    try:
        generate_message([], lambda paths: "")
    except GenerateError:
        pass
    else:
        raise AssertionError("expected GenerateError on no files")


def test_generate_single_file_one_call():
    fake = _FakeClaude({"tag": "fix", "message": "patch bug"})
    real = _patch(fake)
    try:
        tag, msg = generate_message(["a.py"], lambda paths: "diff-a", status={"a.py": "M"})
    finally:
        generate._claude = real
    assert (tag, msg) == ("fix", "patch bug")
    assert len(fake.calls) == 1
    assert "diff-a" in fake.calls[0][0]
    assert fake.calls[0][1] is generate.COMMIT_SCHEMA


def test_generate_small_multi_single_call():
    fake = _FakeClaude({"tag": "feat", "message": "add stuff"})
    real = _patch(fake)
    try:
        tag, msg = generate_message(["a.py", "b.py"], lambda paths: "small diff")
    finally:
        generate._claude = real
    assert (tag, msg) == ("feat", "add stuff")
    assert len(fake.calls) == 1  # under cap -> no pick step


def test_generate_large_diff_two_step():
    big = "x" * (generate.MAX_DIFF_CHARS + 1)

    def diff_for(paths):
        # first call (all text files) is the size probe; later calls fetch chosen
        return big if len(paths) == 2 else "chosen diff"

    fake = _FakeClaude(
        {"files": ["a.py"]},  # pick step
        {"tag": "refactor", "message": "split module"},  # write step
    )
    real = _patch(fake)
    try:
        tag, msg = generate_message(["a.py", "b.py"], diff_for)
    finally:
        generate._claude = real
    assert (tag, msg) == ("refactor", "split module")
    assert len(fake.calls) == 2
    assert fake.calls[0][1] is generate.FILES_SCHEMA
    assert fake.calls[1][1] is generate.COMMIT_SCHEMA


def test_generate_large_diff_bad_picks_fall_back_to_all():
    big = "x" * (generate.MAX_DIFF_CHARS + 1)
    fake = _FakeClaude(
        {"files": ["ghost.py", "also-not-staged.py"]},  # nothing valid
        {"tag": "chore", "message": "cleanup"},
    )
    real = _patch(fake)
    try:
        tag, msg = generate_message(["a.py", "b.py"], lambda paths: big if len(paths) == 2 else "d")
    finally:
        generate._claude = real
    assert (tag, msg) == ("chore", "cleanup")
    # write prompt should mention both files (fell back to all)
    write_prompt = fake.calls[1][0]
    assert "a.py" in write_prompt and "b.py" in write_prompt


_TESTS = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]

if __name__ == "__main__":
    for t in _TESTS:
        t()
        print(f"ok {t.__name__}")
    print(f"\n{len(_TESTS)} passed")
