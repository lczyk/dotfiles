"""tests for auto_commit.generate. plain asserts -- run directly with
`python tests/test_generate.py` or via `pytest`. no fixtures, no framework."""

from __future__ import annotations

import json

from auto_commit import generate
from auto_commit.generate import (
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
    stream = _consume(lines)
    assert stream.result is not None
    assert stream.result["structured_output"] == {"tag": "fix", "message": "x"}
    assert stream.chars == len("hello") + len("abc")


def test_consume_no_result_returns_none():
    stream = _consume([_line({"type": "stream_event", "event": {"type": "message_start"}})])
    assert stream.result is None
    assert stream.chars == 0


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


def test_consume_captures_init_and_thinking_tokens():
    lines = [
        _line({"type": "system", "subtype": "init", "tools": ["StructuredOutput"], "model": "m"}),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "message_delta", "usage": {"output_tokens_details": {"thinking_tokens": 228}}},
            }
        ),
        # the result event reports it as null; that must not clobber the count.
        _line({"type": "result", "usage": {"output_tokens_details": None}}),
    ]
    stream = _consume(lines)
    assert stream.init is not None
    assert stream.init["tools"] == ["StructuredOutput"]
    assert stream.thinking_tokens == 228


def test_consume_emits_completed_blocks():
    blocks: list[tuple[str, str]] = []
    lines = [
        _line(
            {"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "thinking"}}}
        ),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "content_block_delta", "delta": {"type": "thinking_delta", "thinking": "hmm"}},
            }
        ),
        _line({"type": "stream_event", "event": {"type": "content_block_stop"}}),
        _line({"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "text"}}}),
        _line(
            {
                "type": "stream_event",
                "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "answer"}},
            }
        ),
        # no trailing stop -- the last block still has to be flushed.
    ]
    _consume(lines, on_block=lambda k, t: blocks.append((k, t)))
    assert blocks == [("thinking", "hmm"), ("text", "answer")]


# --- _check_sandbox -------------------------------------------------------


def test_check_sandbox_accepts_the_expected_tool():
    generate._check_sandbox({"tools": ["StructuredOutput"], "model": "m"})


def test_check_sandbox_rejects_an_unexpected_tool():
    try:
        generate._check_sandbox({"tools": ["StructuredOutput", "Bash"], "model": "m"})
    except GenerateError as e:
        assert "Bash" in str(e)
    else:
        raise AssertionError("expected GenerateError on an unexpected tool")


class _InterruptingStream:
    def __iter__(self):
        raise KeyboardInterrupt


class _FakeProc:
    stdout = _InterruptingStream()
    stderr = iter(())

    def __init__(self):
        self.returncode = None

    def poll(self):
        return self.returncode

    def kill(self):
        self.returncode = -9

    def wait(self):
        return self.returncode


def test_claude_ctrl_c_is_cancelled_without_traceback():
    real_popen = generate.subprocess.Popen
    real_which = generate.shutil.which
    generate.subprocess.Popen = lambda *args, **kwargs: _FakeProc()
    generate.shutil.which = lambda name: "/usr/bin/claude"
    try:
        try:
            generate._claude("prompt", generate.COMMIT_SCHEMA, model="model", variant="none")
        except generate.GenerateCancelled:
            pass
        else:
            raise AssertionError("expected GenerateCancelled")
    finally:
        generate.subprocess.Popen = real_popen
        generate.shutil.which = real_which


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
    assert _truncate("abc", 10) == "abc"
    out = _truncate("aaaa\nbbbb\ncccc\n", 12)
    assert out.startswith("aaaa\nbbbb")
    assert "cccc" not in out  # cut on a line boundary, no half lines
    assert "truncated" in out


def _chunk(path: str, body_lines: int) -> str:
    body = "".join(f"+line {i}\n" for i in range(body_lines))
    return f"diff --git c/{path} i/{path}\n--- c/{path}\n+++ i/{path}\n@@ -0,0 +1 @@\n{body}"


def test_split_by_file_is_not_fooled_by_a_diff_of_a_diff():
    # a staged patch file contains `diff --git` lines, but prefixed with +.
    inner = _chunk("a.txt", 1) + "diff --git c/b.txt i/b.txt\n+++ b\n"
    nested = "".join("+" + line + "\n" for line in inner.splitlines())
    combined = f"diff --git c/p.patch i/p.patch\n{nested}" + _chunk("real.txt", 1)
    chunks = generate._split_by_file(combined)
    assert len(chunks) == 2
    assert chunks[0].startswith("diff --git c/p.patch")
    assert chunks[1].startswith("diff --git c/real.txt")


def test_label_matches_paths_with_spaces_and_shared_suffixes():
    paths = ["a.py", "xa.py", "my file.txt"]
    assert generate._label("diff --git c/xa.py i/xa.py\nbody", paths) == "xa.py"
    assert generate._label("diff --git c/a.py i/a.py\nbody", paths) == "a.py"
    assert generate._label("diff --git c/my file.txt i/my file.txt", paths) == "my file.txt"
    assert generate._label("diff --git c/z i/z", paths) == "diff --git c/z i/z"


def test_allocate_is_max_min_fair():
    # one greedy file, three small: the small ones are satisfied in full and
    # their unused share flows to the big one.
    assert generate._allocate([1000, 10, 10, 10], 400) == [370, 10, 10, 10]
    # everyone fits -> everyone whole, budget left over.
    assert generate._allocate([5, 5], 100) == [5, 5]
    # nobody fits -> equal split.
    assert generate._allocate([100, 100], 50) == [25, 25]


def test_fit_keeps_every_file_represented():
    diff = _chunk("big.py", 400) + _chunk("small.py", 2)
    assert len(diff) > 1000
    out = generate._fit(diff, ["big.py", "small.py"], budget=1000)
    assert len(out) <= 1000 + 200  # truncation markers add a little back
    # the whole point: the small file survives instead of being chopped off.
    assert "diff --git c/small.py" in out
    assert "diff --git c/big.py" in out
    assert "truncated" in out


def test_fit_leaves_a_diff_under_budget_alone():
    diff = _chunk("a.py", 2)
    assert generate._fit(diff, ["a.py"], budget=10_000) == diff


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

    def __call__(self, prompt, schema, *, model, variant):
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


def test_generate_large_diff_stays_one_call_and_keeps_every_file():
    # one huge file next to a tiny one, well over the cap between them.
    diff = _chunk("big.py", generate.MAX_DIFF_CHARS // 8) + _chunk("small.py", 1)
    assert len(diff) > generate.MAX_DIFF_CHARS
    fake = _FakeClaude({"tag": "refactor", "message": "split module"})
    real = _patch(fake)
    try:
        tag, msg = generate_message(["big.py", "small.py"], lambda paths: diff)
    finally:
        generate._claude = real
    assert (tag, msg) == ("refactor", "split module")
    assert len(fake.calls) == 1  # no pick round trip, ever
    prompt = fake.calls[0][0]
    assert "diff --git c/big.py" in prompt
    assert "diff --git c/small.py" in prompt  # not chopped off the tail
    assert "truncated" in prompt


_TESTS = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]

if __name__ == "__main__":
    for t in _TESTS:
        t()
        print(f"ok {t.__name__}")
    print(f"\n{len(_TESTS)} passed")
