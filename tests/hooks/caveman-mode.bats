#!/usr/bin/env bats
# tests for stow/common/claude/.claude/hooks/caveman-{mode-tracker,activate}.js
# the tracker reads UserPromptSubmit payloads and toggles the shared mode flag;
# the activation hook seeds it at SessionStart without clobbering a mid-session
# choice when claude code re-fires on resume / clear / compaction.

setup() {
    HOOKS="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/hooks"
    TRACKER="$HOOKS/caveman-mode-tracker.js"
    ACTIVATE="$HOOKS/caveman-activate.js"

    export AGENT_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
    unset CAVEMAN_DEFAULT_MODE
    mkdir -p "$AGENT_STATE_DIR" "$XDG_CONFIG_HOME" "$CLAUDE_CONFIG_DIR"

    FLAG="$AGENT_STATE_DIR/caveman-active"
}

# fire the tracker with a raw prompt string.
fire() {
    printf '{"prompt":%s}' "$(printf '%s' "$1" | jq -Rs .)" | node "$TRACKER"
}

# fire the tracker with the slash-command envelope claude code actually sends.
fire_command() {
    fire "$(printf '<command-message>caveman</command-message>\n<command-name>%s</command-name>\n<command-args>%s</command-args>' "$1" "$2")"
}

# fire the SessionStart hook for a given payload source.
activate() {
    printf '{"source":"%s"}' "$1" | node "$ACTIVATE"
}

flag() {
    cat "$FLAG" 2>/dev/null || echo "(none)"
}

# -- tracker: literal slash commands --------------------------------

@test "literal /caveman <level> sets the flag" {
    fire "/caveman ultra" >/dev/null
    [ "$(flag)" = "ultra" ]
}

@test "literal bare /caveman falls back to the configured default" {
    fire "/caveman" >/dev/null
    [ "$(flag)" = "full" ]
}

@test "unknown level leaves an existing flag untouched" {
    fire "/caveman lite" >/dev/null
    fire "/caveman sideways" >/dev/null
    [ "$(flag)" = "lite" ]
}

# -- tracker: slash-command envelope --------------------------------

@test "envelope /caveman <level> sets the flag" {
    fire_command "/caveman" "lite" >/dev/null
    [ "$(flag)" = "lite" ]
}

@test "envelope /caveman with empty args uses the default" {
    fire_command "/caveman" "" >/dev/null
    [ "$(flag)" = "full" ]
}

@test "envelope /caveman off clears the flag" {
    fire "/caveman ultra" >/dev/null
    fire_command "/caveman" "off" >/dev/null
    [ "$(flag)" = "(none)" ]
}

@test "a foreign command's args cannot trip deactivation" {
    fire "/caveman ultra" >/dev/null
    fire_command "/review" "stop caveman" >/dev/null
    [ "$(flag)" = "ultra" ]
}

# -- tracker: deactivation phrasing ---------------------------------

@test "whole-message stop caveman clears the flag" {
    fire "/caveman ultra" >/dev/null
    fire "stop caveman" >/dev/null
    [ "$(flag)" = "(none)" ]
}

@test "trailing newlines do not defeat the whole-message match" {
    fire "/caveman ultra" >/dev/null
    fire "$(printf 'stop caveman\n\n')" >/dev/null
    [ "$(flag)" = "(none)" ]
}

@test "a mid-sentence mention does not clear the flag" {
    fire "/caveman ultra" >/dev/null
    fire "the docs say stop caveman turns it off -- where is that handled?" >/dev/null
    [ "$(flag)" = "ultra" ]
}

# -- tracker: reinforcement and scheduled tasks ---------------------

@test "an ordinary turn re-emits the reinforcement while active" {
    fire "/caveman ultra" >/dev/null
    run fire "what does this function do?"
    [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" != "null" ]
}

@test "no reinforcement when no mode is active" {
    run fire "what does this function do?"
    [ -z "$output" ]
}

@test "scheduled-task runs get no reinforcement and no flag change" {
    fire "/caveman ultra" >/dev/null
    run fire "<scheduled-task id=\"1\">check the deploy</scheduled-task>"
    [ -z "$output" ]
    [ "$(flag)" = "ultra" ]
}

# -- activation: sessionstart re-fires ------------------------------

@test "startup seeds the configured default" {
    activate startup >/dev/null
    [ "$(flag)" = "full" ]
}

@test "resume preserves a mode chosen mid-session" {
    activate startup >/dev/null
    fire "/caveman ultra" >/dev/null
    activate resume >/dev/null
    [ "$(flag)" = "ultra" ]
}

@test "compaction preserves a mode chosen mid-session" {
    activate startup >/dev/null
    fire "/caveman lite" >/dev/null
    activate compact >/dev/null
    [ "$(flag)" = "lite" ]
}

@test "clear preserves a mid-session deactivation" {
    activate startup >/dev/null
    fire "/caveman off" >/dev/null
    run activate clear
    [ "$output" = "OK" ]
    [ "$(flag)" = "(none)" ]
}

@test "a later true startup restores the default after deactivation" {
    fire "/caveman off" >/dev/null
    activate startup >/dev/null
    [ "$(flag)" = "full" ]
}

@test "the emitted ruleset names the active level" {
    fire "/caveman ultra" >/dev/null
    run activate resume
    [[ "$output" == *"caveman mode active -- level: ultra"* ]]
}
