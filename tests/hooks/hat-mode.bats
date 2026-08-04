#!/usr/bin/env bats
# tests for stow/common/claude/.claude/hooks/hat-{tracker,activate,session-end,config}.js
#
# unlike caveman's single global flag, hat state is one file per session_id
# under $AGENT_STATE_DIR/hats -- these tests exercise that isolation directly,
# plus the staleness sweep and session-end cleanup that keep the directory
# from growing forever.

setup() {
    HOOKS="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/hooks"
    TRACKER="$HOOKS/hat-tracker.js"
    ACTIVATE="$HOOKS/hat-activate.js"
    SESSION_END="$HOOKS/hat-session-end.js"

    export AGENT_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    mkdir -p "$AGENT_STATE_DIR" "$XDG_CONFIG_HOME"

    HATS_DIR="$AGENT_STATE_DIR/hats"
    S1="session-aaaa"
    S2="session-bbbb"
}

# fire the tracker with a session id and a raw prompt string.
fire() {
    printf '{"session_id":"%s","prompt":%s}' "$1" "$(printf '%s' "$2" | jq -Rs .)" | node "$TRACKER"
}

# fire the tracker with the slash-command envelope claude code actually sends.
fire_command() {
    fire "$1" "$(printf '<command-message>hat</command-message>\n<command-name>%s</command-name>\n<command-args>%s</command-args>' "$2" "$3")"
}

# fire the SessionStart hook for a given session id / payload source.
activate() {
    printf '{"session_id":"%s","source":"%s"}' "$1" "$2" | node "$ACTIVATE"
}

session_end() {
    printf '{"session_id":"%s"}' "$1" | node "$SESSION_END"
}

flag() {
    cat "$HATS_DIR/$1" 2>/dev/null || echo "(none)"
}

# -- tracker: setting and clearing --------------------------------

@test "/hat yolo sets this session's flag" {
    fire "$S1" "/hat yolo" >/dev/null
    [ "$(flag "$S1")" = "yolo" ]
}

@test "/hat default clears this session's flag" {
    fire "$S1" "/hat yolo" >/dev/null
    fire "$S1" "/hat default" >/dev/null
    [ "$(flag "$S1")" = "(none)" ]
}

@test "unknown arg leaves an existing flag untouched" {
    fire "$S1" "/hat yolo" >/dev/null
    fire "$S1" "/hat sideways" >/dev/null
    [ "$(flag "$S1")" = "yolo" ]
}

@test "bare /hat does not change the flag" {
    fire "$S1" "/hat yolo" >/dev/null
    fire "$S1" "/hat" >/dev/null
    [ "$(flag "$S1")" = "yolo" ]
}

@test "envelope /hat <arg> sets the flag" {
    fire_command "$S1" "/hat" "yolo" >/dev/null
    [ "$(flag "$S1")" = "yolo" ]
}

@test "a foreign command's args cannot trip /hat parsing" {
    fire "$S1" "/hat yolo" >/dev/null
    fire_command "$S1" "/review" "hat default" >/dev/null
    [ "$(flag "$S1")" = "yolo" ]
}

# -- tracker: per-session isolation --------------------------------

@test "two concurrent sessions never share a flag" {
    fire "$S1" "/hat yolo" >/dev/null
    [ "$(flag "$S1")" = "yolo" ]
    [ "$(flag "$S2")" = "(none)" ]

    fire "$S2" "/hat yolo" >/dev/null
    fire "$S1" "/hat default" >/dev/null
    [ "$(flag "$S1")" = "(none)" ]
    [ "$(flag "$S2")" = "yolo" ]
}

@test "a session_id with path traversal chars stays sandboxed to the hats dir" {
    fire "../../etc/evil" "/hat yolo" >/dev/null
    found=$(find "$HATS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
    [ "$found" = "1" ]
    [ "$(cat "$HATS_DIR"/*)" = "yolo" ]
}

@test "missing session_id is a silent no-op" {
    run bash -c "printf '{\"prompt\":\"/hat yolo\"}' | node '$TRACKER'"
    [ -z "$output" ]
}

# -- tracker: status query -------------------------------------------

@test "bare /hat reports the active hat via additionalContext" {
    fire "$S1" "/hat yolo" >/dev/null
    run fire "$S1" "/hat"
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"yolo"* ]]
}

@test "bare /hat also lists the valid options" {
    fire "$S1" "/hat yolo" >/dev/null
    run fire "$S1" "/hat"
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"default"* ]]
    [[ "$ctx" == *"yolo"* ]]
}

@test "bare /hat reports default when no flag is set" {
    run fire "$S1" "/hat"
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"default"* ]]
}

# -- tracker: reinforcement and scheduled tasks ---------------------

@test "an ordinary turn re-emits the reinforcement while yolo" {
    fire "$S1" "/hat yolo" >/dev/null
    run fire "$S1" "what does this function do?"
    [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" != "null" ]
}

@test "no reinforcement while on default" {
    run fire "$S1" "what does this function do?"
    [ -z "$output" ]
}

@test "scheduled-task runs get no reinforcement and no flag change" {
    fire "$S1" "/hat yolo" >/dev/null
    run fire "$S1" "<scheduled-task id=\"1\">check the deploy</scheduled-task>"
    [ -z "$output" ]
    [ "$(flag "$S1")" = "yolo" ]
}

@test "an ordinary turn refreshes mtime while yolo (liveness, not just value changes)" {
    fire "$S1" "/hat yolo" >/dev/null
    # pin both the flag and a comparison marker to the same old date, so the
    # post-touch assertion doesn't race sub-second clock resolution -- it only
    # has to detect "years newer", not "a moment newer".
    marker="$BATS_TEST_TMPDIR/marker"
    touch -t 202001010000 "$HATS_DIR/$S1" "$marker"
    fire "$S1" "some other question" >/dev/null
    [ "$HATS_DIR/$S1" -nt "$marker" ]
}

# -- activation: sessionstart re-fires ------------------------------

@test "startup for a session with no flag emits OK only" {
    run activate "$S1" startup
    [ "$output" = "OK" ]
}

@test "resume re-emits the ruleset when this session is yolo" {
    fire "$S1" "/hat yolo" >/dev/null
    run activate "$S1" resume
    [[ "$output" == *"HAT ACTIVE -- yolo"* ]]
}

@test "resume emits OK only when this session is on default" {
    run activate "$S1" startup
    [ "$output" = "OK" ]
}

@test "startup sweep prunes flags older than 7 days" {
    mkdir -p "$HATS_DIR"
    printf 'yolo' > "$HATS_DIR/stale-session"
    touch -t 202001010000 "$HATS_DIR/stale-session"
    printf 'yolo' > "$HATS_DIR/fresh-session"
    activate "$S1" startup >/dev/null
    [ ! -f "$HATS_DIR/stale-session" ]
    [ -f "$HATS_DIR/fresh-session" ]
}

# -- session-end: cleanup --------------------------------------------

@test "session-end deletes only its own session's flag" {
    fire "$S1" "/hat yolo" >/dev/null
    fire "$S2" "/hat yolo" >/dev/null
    session_end "$S1" >/dev/null
    [ "$(flag "$S1")" = "(none)" ]
    [ "$(flag "$S2")" = "yolo" ]
}

@test "session-end on a session with no flag is a silent no-op" {
    run session_end "$S1"
    [ "$output" = "OK" ]
}
