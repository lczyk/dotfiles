#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/commit-msg

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/commit-msg"
    MSG="$BATS_TEST_TMPDIR/msg"
    export CLAUDECODE=1
}

write_msg() { printf '%s\n' "$1" > "$MSG"; }

# -- conventional commits prefix: valid forms ---------------------------

@test "accepts feat:" {
    write_msg "feat: add thing"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts fix:" {
    write_msg "fix: a bug"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts docs(claude):" {
    write_msg "docs(claude): tweak style"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts feat(api)!:" {
    write_msg "feat(api)!: breaking change"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts chore(hooks)?:" {
    write_msg "chore(hooks)?: unverified tweak"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts scope w/ digits, dot, dash, underscore" {
    write_msg "feat(my-scope.v2_x): ok"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts revert: with quoted subject" {
    write_msg 'revert: "feat: prior subject"'
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts TODO: subject" {
    write_msg "TODO: things"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts TODO(scope): subject" {
    write_msg "TODO(parser): parse"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts FIXME: subject" {
    write_msg "FIXME: broken"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts FIXME(api): subject" {
    write_msg "FIXME(api): null deref"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts release:" {
    write_msg "release: v1.2.3"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

# -- conventional commits prefix: rejected forms ------------------------

@test "rejects unknown type" {
    write_msg "update: nope"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects missing colon" {
    write_msg "feat add thing"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects missing space after colon" {
    write_msg "feat:nospace"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects uppercase scope" {
    write_msg "feat(API): nope"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects scope with space" {
    write_msg "feat(my scope): nope"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects empty scope" {
    write_msg "feat(): nope"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects bare subject" {
    write_msg "just some words"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

# -- co-author ban ------------------------------------------------------

@test "rejects Co-Authored-By line" {
    printf 'feat: x\n\nCo-Authored-By: Bot <bot@example.com>\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects co-authored-by case-insensitively" {
    printf 'feat: x\n\nco-authored-by: bot\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

# -- ?! ban -------------------------------------------------------------

@test "rejects ?! in body" {
    printf 'feat: x\n\nwhat?!\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "accepts !? (surprised question)" {
    printf 'feat: x\n\nreally!?\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

# -- ascii only ---------------------------------------------------------

@test "rejects em-dash" {
    printf 'feat: x \xe2\x80\x94 nope\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects smart quote" {
    printf 'feat: x \xe2\x80\x9cwat\xe2\x80\x9d\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects emoji" {
    printf 'feat: x \xf0\x9f\x9a\x80\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -ne 0 ]
}

# -- CLAUDECODE gating --------------------------------------------------

@test "non-claude run warns but exits 0 on bad subject" {
    unset CLAUDECODE
    write_msg "update: nope"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}

@test "non-claude run still exits 0 on co-author" {
    unset CLAUDECODE
    printf 'feat: x\n\nCo-Authored-By: bot\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
}
