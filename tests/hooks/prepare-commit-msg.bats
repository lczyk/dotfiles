#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/prepare-commit-msg

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/prepare-commit-msg"
    MSG="$BATS_TEST_TMPDIR/msg"
}

write_msg() { printf '%s\n' "$@" > "$MSG"; }

# -- revert rewriting ------------------------------------------------------

@test "rewrites default revert to conventional format" {
    write_msg 'Revert "feat: prior subject"'
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$MSG")" = 'revert: "feat: prior subject"' ]
}

@test "rewrites revert with plain subject" {
    write_msg 'Revert "add login page"'
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$MSG")" = 'revert: "add login page"' ]
}

@test "preserves body after rewrite" {
    printf 'Revert "feat: thing"\n\nThis reverts commit abc123.\n' > "$MSG"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$MSG")" = 'revert: "feat: thing"' ]
    [ "$(sed -n '3p' "$MSG")" = "This reverts commit abc123." ]
}

# -- no-op cases -----------------------------------------------------------

@test "leaves non-revert subject alone" {
    write_msg "feat: add thing"
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$MSG")" = "feat: add thing" ]
}

@test "leaves already-conventional revert alone" {
    write_msg 'revert: "feat: prior subject"'
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$MSG")" = 'revert: "feat: prior subject"' ]
}

@test "leaves subject containing Revert mid-line alone" {
    write_msg 'fix: Revert "broken thing"'
    run "$HOOK" "$MSG"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$MSG")" = 'fix: Revert "broken thing"' ]
}
