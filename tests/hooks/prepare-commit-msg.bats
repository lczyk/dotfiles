#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/prepare-commit-msg

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/prepare-commit-msg"
    MSG="$BATS_TEST_TMPDIR/msg"
    # the suite runs from inside an agent session -- clear every marker so the
    # human-path tests below aren't testing the agent path by accident.
    unset CLAUDECODE AGENT_SESSION OPENCODE_PID
    # fixture repos must not pick up the user's hooksPath / gpgsign.
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

write_msg() { printf '%s\n' "$@" > "$MSG"; }

# a clone of a bare remote, one commit, main tracking origin/main. cwd moves
# into it.
tracking_repo() {
    local remote="$BATS_TEST_TMPDIR/remote.git" repo="$BATS_TEST_TMPDIR/repo"
    git init -q --bare -b main "$remote"
    git init -q -b main "$repo"
    cd "$repo" || return 1
    git commit -q --allow-empty -m "first"
    git remote add origin "$remote"
    git push -q -u origin main
}

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

# -- amend of a pushed commit ----------------------------------------------
# git passes `commit HEAD` as $2 $3 for --amend (and -c / -C HEAD).

@test "agent: rejects amend when HEAD is pushed" {
    tracking_repo
    write_msg "first"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -ne 0 ]
    [[ "$output" == *"rejected"* ]]
    [[ "$output" == *"pushed"* ]]
}

@test "agent: rejects amend under AGENT_SESSION" {
    tracking_repo
    write_msg "first"
    AGENT_SESSION=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -ne 0 ]
}

@test "agent: rejects amend when upstream is ahead of HEAD" {
    tracking_repo
    git commit -q --allow-empty -m "second"
    git push -q origin main
    git reset -q --hard HEAD~1
    write_msg "first"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -ne 0 ]
}

@test "agent: allows amend of an unpushed commit" {
    tracking_repo
    git commit -q --allow-empty -m "local only"
    write_msg "local only"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -eq 0 ]
}

@test "agent: allows amend with no upstream" {
    git init -q -b main "$BATS_TEST_TMPDIR/repo"
    cd "$BATS_TEST_TMPDIR/repo"
    git commit -q --allow-empty -m "first"
    write_msg "first"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -eq 0 ]
}

@test "agent: allows amend on detached HEAD" {
    tracking_repo
    git checkout -q --detach
    write_msg "first"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -eq 0 ]
}

@test "agent: allows a normal commit on top of a pushed HEAD" {
    tracking_repo
    write_msg "feat: new thing"
    CLAUDECODE=1 run "$HOOK" "$MSG" message
    [ "$status" -eq 0 ]
}

@test "agent: allows -C of a non-HEAD commit on a pushed branch" {
    tracking_repo
    git commit -q --allow-empty -m "second"
    git push -q origin main
    write_msg "first"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD~1
    [ "$status" -eq 0 ]
}

@test "human: allows amend when HEAD is pushed" {
    tracking_repo
    write_msg "first"
    run "$HOOK" "$MSG" commit HEAD
    [ "$status" -eq 0 ]
}

@test "outside a repo: amend args do not error" {
    cd "$BATS_TEST_TMPDIR"
    write_msg "first"
    CLAUDECODE=1 run "$HOOK" "$MSG" commit HEAD
    [ "$status" -eq 0 ]
}
