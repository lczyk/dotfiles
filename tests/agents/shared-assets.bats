#!/usr/bin/env bats
# tests for shared agent sources and harness-specific shims

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    TARGET="$BATS_TEST_TMPDIR/home"
}

@test "canonical shared agent sources exist" {
    for path in \
        "$REPO/stow/common/agent-guidance/.config/agent-guidance/workflow.md" \
        "$REPO/stow/common/agent-styles/.config/agent-styles/lofi.md" \
        "$REPO/stow/common/agent-skills/.config/agent-skills/caveman/SKILL.md" \
        "$REPO/stow/common/agent-modes/.config/agent-modes/ponytail.json"; do
        [ -f "$path" ]
    done
}

@test "claude and codex shims point at canonical shared sources" {
    [ "$(readlink "$REPO/stow/common/claude/.claude/CLAUDE.md")" = "../../agent-guidance/.config/agent-guidance/workflow.md" ]

    for harness in claude codex; do
        for skill in caveman caveman-commit grill-me lofi ponytail; do
            [ "$(readlink "$REPO/stow/common/$harness/.${harness}/skills/$skill")" = "../../../agent-skills/.config/agent-skills/$skill" ]
        done
    done
}

@test "stow resolves cross-package agent links" {
    mkdir -p "$TARGET"
    run make -C "$REPO" stow STOW_TARGET="$TARGET"
    [ "$status" -eq 0 ]

    for path in \
        "$TARGET/.claude/CLAUDE.md" \
        "$TARGET/.claude/styles/lofi.md" \
        "$TARGET/.claude/skills/caveman/SKILL.md" \
        "$TARGET/.codex/skills/caveman/SKILL.md"; do
        [ -r "$path" ]
    done
}

@test "adapters use shared sources and state" {
    run rg -F '$HOME/.config/agent-guidance/workflow.md' "$REPO/stow/common/codex/.codex/hooks.json"
    [ "$status" -eq 0 ]

    run rg -F 'agent-styles/lofi' "$REPO/stow/common/claude/.claude/settings.json" "$REPO/stow/common/codex/.codex/hooks.json"
    [ "$status" -eq 0 ]

    run rg -F 'agent-state' \
        "$REPO/stow/common/claude/.claude/hooks" \
        "$REPO/stow/common/claude/.claude/statusline.d" \
        "$REPO/stow/common/opencode/.config/opencode/plugin/caveman.ts"
    [ "$status" -eq 0 ]

    run rg -F '.claude' "$REPO/stow/common/opencode/.config/opencode/plugin/caveman.ts"
    [ "$status" -ne 0 ]
}

@test "claude mode adapters resolve the shared config and state paths" {
    config_home="$BATS_TEST_TMPDIR/config"
    state_dir="$BATS_TEST_TMPDIR/state"
    mkdir -p "$config_home/agent-modes"
    printf '{"defaultMode":"lite"}\n' > "$config_home/agent-modes/caveman.json"
    printf '{"defaultMode":"ultra"}\n' > "$config_home/agent-modes/ponytail.json"

    run env XDG_CONFIG_HOME="$config_home" AGENT_STATE_DIR="$state_dir" node -e '
        const caveman = require(process.argv[1]);
        const ponytail = require(process.argv[2]);
        console.log(caveman.getDefaultMode());
        console.log(caveman.getStatePath());
        console.log(ponytail.getDefaultMode());
        console.log(ponytail.getStatePath());
    ' \
        "$REPO/stow/common/claude/.claude/hooks/caveman-config.js" \
        "$REPO/stow/common/claude/.claude/hooks/ponytail-config.js"
    [ "$status" -eq 0 ]
    [ "$output" = $'lite\n'"$state_dir"$'/caveman-active\nultra\n'"$state_dir"'/ponytail-active' ]
}
