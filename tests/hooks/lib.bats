#!/usr/bin/env bats
# drift guards for stow/common/agent-hooks/.config/agent-hooks/lib.sh: one
# definition of each shared helper, the badge reading AGENT_UNFENCE the way
# the fences do, and every user of the lib failing closed without it.

setup() {
    unset AGENT_UNFENCE
    REPO=$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)
    AH="$REPO/stow/common/agent-hooks/.config/agent-hooks"
    GH="$REPO/stow/common/git/.config/git/hooks"
    BADGE="$REPO/stow/common/claude/.claude/statusline.d/14-unfence.sh"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

@test "only lib.sh defines the shared helpers" {
    run grep -lE '^(function )?(_fold|_segments|_unfenced|_unfence_tokens|is_agent) ?\(\)' \
        "$AH"/*.sh "$GH"/* "$REPO"/stow/common/claude/.claude/hooks/*.sh \
        "$REPO"/stow/common/codex/.codex/hooks/*.sh "$REPO"/stow/common/claude/.claude/statusline.d/*.sh
    [ "$output" = "$AH/lib.sh" ]
}

@test "only lib.sh folds commands" {
    run grep -lF "tr '\n\t' '  '" "$AH"/*.sh "$GH"/*
    [ "$output" = "$AH/lib.sh" ]
}

@test "the badge lists exactly the capabilities the fences honour" {
    for value in "branch" "branch,meta" "branch, meta" " meta" "meta " ",,push,," "Meta" \
        'branch;$(rm x),meta' "brnach,pr" "" "history,remote,issue,labels"; do
        shown=$(AGENT_UNFENCE="$value" bash "$BADGE" </dev/null | strip_ansi)
        for cap in branch history remote push pr issue labels meta; do
            honoured=0
            AGENT_UNFENCE="$value" bash -c '. "$1"; _unfenced "$2"' _ "$AH/lib.sh" "$cap" && honoured=1
            listed=0
            [[ "$shown" =~ [:,]$cap[],] ]] && listed=1
            [ "$honoured" = "$listed" ] ||
                { echo "AGENT_UNFENCE=[$value] cap=$cap honoured=$honoured badge=$shown"; false; }
        done
    done
}

@test "a policy without lib.sh denies" {
    for policy in block-dangerous protect-hooks enforce-tmp-ai discourage-bare-tail; do
        cp "$AH/$policy.sh" "$BATS_TEST_TMPDIR/"
        run bash -c 'printf %s "{\"version\":1,\"operation\":\"shell\",\"command\":\"ls\"}" | bash "$1"' \
            _ "$BATS_TEST_TMPDIR/$policy.sh"
        [ "$status" -eq 2 ] || { echo "$policy: $status $output"; false; }
        [[ "$output" == *"lib.sh is missing"* ]]
    done
}

@test "a git hook without lib.sh rejects" {
    printf 'feat: x\n' > "$BATS_TEST_TMPDIR/msg"
    for hook in pre-commit commit-msg prepare-commit-msg pre-push; do
        cp "$GH/$hook" "$BATS_TEST_TMPDIR/$hook"
        HOME="$BATS_TEST_TMPDIR" run bash "$BATS_TEST_TMPDIR/$hook" "$BATS_TEST_TMPDIR/msg" </dev/null
        [ "$status" -eq 1 ] || { echo "$hook: $status $output"; false; }
        [[ "$output" == *"lib.sh not found"* ]]
    done
}

@test "an adapter without the shared adapter denies" {
    mkdir -p "$BATS_TEST_TMPDIR/hooks"
    for adapter in "$REPO/stow/common/claude/.claude/hooks/safety-adapter.sh" "$REPO/stow/common/codex/.codex/hooks/safety-adapter.sh"; do
        cp "$adapter" "$BATS_TEST_TMPDIR/hooks/safety-adapter.sh"
        HOME="$BATS_TEST_TMPDIR" run bash "$BATS_TEST_TMPDIR/hooks/safety-adapter.sh" shell <<<'{"tool_input":{"command":"ls"}}'
        [ "$status" -eq 2 ]
        [[ "$output" == *"adapter.sh not found"* ]]
    done
}

@test "the badge says it cannot tell when the lib is missing" {
    mkdir -p "$BATS_TEST_TMPDIR/statusline.d"
    cp "$BADGE" "$BATS_TEST_TMPDIR/statusline.d/"
    cp "$REPO/stow/common/claude/.claude/statusline-colour.sh" "$BATS_TEST_TMPDIR/"
    HOME="$BATS_TEST_TMPDIR" run bash "$BATS_TEST_TMPDIR/statusline.d/14-unfence.sh" </dev/null
    [ "$(printf '%s' "$output" | strip_ansi)" = "[U:?]" ]
}
