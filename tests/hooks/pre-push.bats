#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/pre-push

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/pre-push"
    SHIMDIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$SHIMDIR"
    export PATH="$SHIMDIR:$PATH"
    # the suite runs from inside an agent session -- clear every marker and
    # capability so the human-path tests below aren't testing the agent path
    # by accident.
    unset CLAUDECODE AGENT_SESSION OPENCODE_PID AGENT_UNFENCE
}

# fake git: control merge-base --is-ancestor via arg (0=is-ancestor=ff, 1=non-ff).
fake_git() {
    local ancestor="${1:-0}"
    cat > "$SHIMDIR/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "merge-base" ] && [ "\$2" = "--is-ancestor" ]; then
    exit $ancestor
fi
exit 0
EOF
    chmod +x "$SHIMDIR/git"
}

Z=0000000000000000000000000000000000000000

# -- agent block --

@test "blocks push under CLAUDECODE=1" {
    CLAUDECODE=1 run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "blocks push under AGENT_SESSION" {
    AGENT_SESSION=1 run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "blocks push under OPENCODE_PID" {
    OPENCODE_PID=4242 run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "passes when CLAUDECODE unset and no input" {
    run "$HOOK" </dev/null
    [ "$status" -eq 0 ]
}

@test "passes when CLAUDECODE is empty" {
    CLAUDECODE="" run "$HOOK" </dev/null
    [ "$status" -eq 0 ]
}

@test "passes when CLAUDECODE is some other value" {
    CLAUDECODE=0 run "$HOOK" </dev/null
    [ "$status" -eq 0 ]
}

# -- protected-branch ff guard --

@test "ff push to main passes" {
    fake_git 0
    run bash -c "echo 'refs/heads/main abc refs/heads/main def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "non-ff push to main rejected" {
    fake_git 1
    run bash -c "echo 'refs/heads/main abc refs/heads/main def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "non-ff push to master rejected" {
    fake_git 1
    run bash -c "echo 'refs/heads/master abc refs/heads/master def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "non-ff push to trunk rejected" {
    fake_git 1
    run bash -c "echo 'refs/heads/trunk abc refs/heads/trunk def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "non-ff push to release/1.2 rejected" {
    fake_git 1
    run bash -c "echo 'refs/heads/release/1.2 abc refs/heads/release/1.2 def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "non-ff push to feature branch allowed" {
    fake_git 1
    run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "delete of main rejected" {
    fake_git 0
    run bash -c "echo 'refs/heads/main $Z refs/heads/main def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "delete of feature allowed" {
    fake_git 0
    run bash -c "echo 'refs/heads/feature $Z refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "new branch push to main (remote sha zero) ff allowed" {
    fake_git 0
    run bash -c "echo 'refs/heads/main abc refs/heads/main $Z' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "non-ff push to feature by a human stays allowed under AGENT_UNFENCE=push" {
    fake_git 1
    AGENT_UNFENCE=push run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

# -- the push capability --------------------------------------------------
# AGENT_UNFENCE=push lifts the outright agent reject. every ref then gets the
# protected-branch rules, whatever the branch, plus no tags.

@test "push: agent ff push to a feature branch passes" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "push: agent ff push to main passes" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/main abc refs/heads/main def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "push: agent push of a new branch passes" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/feature abc refs/heads/feature $Z' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "push: agent push with no refs passes" {
    AGENT_UNFENCE=push CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -eq 0 ]
}

@test "push: lifts under AGENT_SESSION and OPENCODE_PID too" {
    fake_git 0
    AGENT_UNFENCE=push AGENT_SESSION=1 run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=push OPENCODE_PID=4242 run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "push: agent non-ff push to a feature branch rejected" {
    fake_git 1
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-fast-forward"* ]]
}

@test "push: agent non-ff push to main rejected" {
    fake_git 1
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/main abc refs/heads/main def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "push: agent delete of a feature branch rejected" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/feature $Z refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"delete"* ]]
}

@test "push: agent delete of main rejected" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/main $Z refs/heads/main def' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "push: agent tag push rejected, with the follow-tags hint" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/tags/v1.0 abc refs/tags/v1.0 $Z' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--no-follow-tags"* ]]
}

@test "push: agent force invocation rejected even when the push is ff" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x --force"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--force"* ]]
}

@test "push: one bad ref rejects the whole agent push" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "printf 'refs/heads/a abc refs/heads/a def\nrefs/heads/b $Z refs/heads/b def\n' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "push: a tag dragged along by follow-tags rejects the whole agent push" {
    fake_git 0
    AGENT_UNFENCE=push CLAUDECODE=1 run bash -c "printf 'refs/heads/a abc refs/heads/a def\nrefs/tags/v1 abc refs/tags/v1 $Z\n' | '$HOOK' origin git@x"
    [ "$status" -ne 0 ]
}

@test "push: composes with other capabilities" {
    fake_git 0
    AGENT_UNFENCE=branch,push,pr CLAUDECODE=1 run bash -c "echo 'refs/heads/feature abc refs/heads/feature def' | '$HOOK' origin git@x"
    [ "$status" -eq 0 ]
}

@test "pr alone does not lift the agent push block" {
    AGENT_UNFENCE=pr CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
}

@test "an unrelated capability does not lift the agent push block" {
    AGENT_UNFENCE=meta CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
    AGENT_UNFENCE=branch,history,remote CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
}

@test "an empty AGENT_UNFENCE does not lift the agent push block" {
    AGENT_UNFENCE= CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
}

@test "a substring of a capability name does not lift the agent push block" {
    AGENT_UNFENCE=pushy CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
    AGENT_UNFENCE=nopush CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
}

@test "the agent push block names the capability" {
    CLAUDECODE=1 run "$HOOK" origin git@x </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"AGENT_UNFENCE=push"* ]]
}
