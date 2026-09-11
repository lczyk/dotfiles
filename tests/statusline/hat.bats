#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/13-hat.sh
#
# unlike caveman/lofi's single shared flag, hat state is per-session, so the
# badge has to pull session_id out of its own stdin payload -- these tests
# exercise that correlation directly (a badge invoked with session A's id
# must never show session B's hat).

setup() {
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/13-hat.sh"
    export AGENT_STATE_DIR="$BATS_TEST_TMPDIR/agent-state"
    HATS_DIR="$AGENT_STATE_DIR/hats"
    mkdir -p "$HATS_DIR"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

fire() { printf '{"session_id":"%s"}' "$1" | "$BADGE"; }

write_flag() {
    mkdir -p "$HATS_DIR"
    printf '%s' "$2" > "$HATS_DIR/$1"
}

@test "silent when stdin has no session_id" {
    run bash -c "echo '{}' | '$BADGE'"
    [ -z "$output" ]
}

@test "[h] plain when session_id has no flag file" {
    run fire "session-aaaa"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[h]" ]
    [ "$output" = "[h]" ]
}

@test "[H:yolo] when this session's flag is yolo" {
    write_flag "session-aaaa" "yolo"
    run fire "session-aaaa"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[H:yolo]" ]
}

@test "[h] plain when the flag says default" {
    write_flag "session-aaaa" "default"
    run fire "session-aaaa"
    [ "$output" = "[h]" ]
}

@test "a different session's yolo flag never leaks into this session's badge" {
    write_flag "session-aaaa" "yolo"
    run fire "session-bbbb"
    [ "$output" = "[h]" ]
}

@test "a symlinked flag is refused and falls back to plain [h]" {
    write_flag "session-aaaa" "yolo"
    mv "$HATS_DIR/session-aaaa" "$HATS_DIR/session-real"
    ln -s "$HATS_DIR/session-real" "$HATS_DIR/session-aaaa"
    run fire "session-aaaa"
    [ "$output" = "[h]" ]
}

@test "session_id with path traversal chars is sanitized before lookup" {
    write_flag "etcevil" "yolo"
    run fire "../../etc/evil"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[H:yolo]" ]
}
