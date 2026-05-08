#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/10-caveman.sh

setup() {
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/10-caveman.sh"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
    mkdir -p "$CLAUDE_CONFIG_DIR"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# helpers
write_settings() {
    cat > "$CLAUDE_CONFIG_DIR/settings.json"
}
write_flag() {
    mkdir -p "$(dirname "$CLAUDE_CONFIG_DIR/.caveman-active")"
    printf '%s' "$1" > "$CLAUDE_CONFIG_DIR/.caveman-active"
}

@test "[x] when settings.json is absent and flag is missing" {
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x]" ]
}

@test "[x] when plugin missing from settings.json" {
    write_settings <<<'{"enabledPlugins":{}}'
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x]" ]
}

@test "[-] when plugin explicitly disabled" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":false}}'
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[-]" ]
}

@test "[x] when plugin enabled but flag is missing" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x]" ]
}

@test "[C] when plugin enabled and flag is full" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "full"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[C]" ]
}

@test "[C] when flag is empty (defaults to full)" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag ""
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[C]" ]
}

@test "[c] when flag is lite" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "lite"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[c]" ]
}

@test "[C!] when flag is ultra" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "ultra"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[C!]" ]
}

@test "[w] when flag is wenyan-lite" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "wenyan-lite"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[w]" ]
}

@test "[W] when flag is wenyan" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "wenyan"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[W]" ]
}

@test "[W!] when flag is wenyan-ultra" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "wenyan-ultra"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[W!]" ]
}

@test "[x] when flag is off" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "off"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x]" ]
}

@test "[Cc] when flag is commit" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "commit"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[Cc]" ]
}

@test "[Cr] when flag is review" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "review"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[Cr]" ]
}

@test "[Cp] when flag is compress" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "compress"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[Cp]" ]
}

@test "refuses symlink flag" {
    write_settings <<<'{"enabledPlugins":{"caveman@caveman":true}}'
    write_flag "full"
    mv "$CLAUDE_CONFIG_DIR/.caveman-active" "$CLAUDE_CONFIG_DIR/.caveman-real"
    ln -s "$CLAUDE_CONFIG_DIR/.caveman-real" "$CLAUDE_CONFIG_DIR/.caveman-active"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x]" ]
}

@test "[C] when plugin entry absent but settings.json exists with other keys" {
    write_settings <<<'{"enabledPlugins":{"other@plugin":true}}'
    write_flag "full"
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x]" ]
}
