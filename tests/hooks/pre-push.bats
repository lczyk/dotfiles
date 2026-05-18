#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/pre-push

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/pre-push"
    SHIMDIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$SHIMDIR"
    export PATH="$SHIMDIR:$PATH"
    unset CLAUDECODE
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

# -- CLAUDECODE block (preserved from original) --

@test "blocks push under CLAUDECODE=1" {
    CLAUDECODE=1 run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "passes when CLAUDECODE unset and no input" {
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "passes when CLAUDECODE is empty" {
    CLAUDECODE="" run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "passes when CLAUDECODE is some other value" {
    CLAUDECODE=0 run "$HOOK"
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
