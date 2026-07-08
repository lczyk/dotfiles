#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/pre-commit
# shims `git` on PATH so tests can feed an arbitrary `git diff --cached` output
# w/out building a real repo.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/pre-commit"
    SHIMDIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$SHIMDIR"
    export PATH="$SHIMDIR:$PATH"
    export CLAUDECODE=1
}

# write a fake `git` shim that prints $1 verbatim for `git diff --cached`
fake_diff() {
    local out="$BATS_TEST_TMPDIR/diff.out"
    printf '%s' "$1" > "$out"
    cat > "$SHIMDIR/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "diff" ] && [ "\$2" = "--cached" ]; then
    cat "$out"
    exit 0
fi
exit 0
EOF
    chmod +x "$SHIMDIR/git"
}

@test "passes when diff is empty" {
    fake_diff ""
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "passes on pure ASCII added line" {
    fake_diff $'+hello world\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "rejects em-dash in added line under CLAUDECODE" {
    fake_diff $'+hello \xe2\x80\x94 world\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects smart quote in added line" {
    fake_diff $'+say \xe2\x80\x9chi\xe2\x80\x9d\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects emoji in added line" {
    fake_diff $'+rocket \xf0\x9f\x9a\x80\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores non-ASCII on context lines (only flags + additions)" {
    fake_diff $' old \xe2\x80\x94 line\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores non-ASCII on removed lines" {
    fake_diff $'-removed \xe2\x80\x94 line\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores ++ header lines" {
    fake_diff $'+++ b/file\xe2\x80\x94name\n+ascii content\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "non-claude run warns but exits 0" {
    unset CLAUDECODE
    fake_diff $'+hello \xe2\x80\x94 world\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- nocommit checks (always block, regardless of CLAUDECODE) --

@test "rejects lowercase nocommit in added line" {
    fake_diff $'+print("debug") // nocommit\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects uppercase NOCOMMIT in added line" {
    fake_diff $'+NOCOMMIT: temporary debug dump\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects mixed-case NoCommit in added line" {
    fake_diff $'+// NoCommit remove this\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores nocommit on context lines" {
    fake_diff $' old line // nocommit\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores nocommit on removed lines" {
    fake_diff $'-removed line // nocommit\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "rejects nocommit even in non-claude mode" {
    unset CLAUDECODE
    fake_diff $'+debug print // nocommit\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

# -- trailing whitespace --

@test "rejects trailing space on added line" {
    fake_diff $'+hello   \n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects trailing tab on added line" {
    fake_diff $'+hello\t\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores trailing whitespace on context lines" {
    fake_diff $' old line   \n+clean\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- secret scan --

@test "rejects AWS AKIA key" {
    fake_diff $'+aws_key = "AKIAIOSFODNN7EXAMPLE"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects GitHub PAT (ghp_)" {
    fake_diff $'+token = ghp_abcdefghijklmnopqrstuvwxyz0123456789\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects OpenAI sk- key" {
    fake_diff $'+OPENAI=sk-abcdefghijklmnopqrstuvwxyz0123\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects Anthropic sk-ant- key" {
    fake_diff $'+ANTHROPIC=sk-ant-abcdefghijklmnopqrstuvwxyz0123\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects PEM private key header" {
    fake_diff $'+-----BEGIN RSA PRIVATE KEY-----\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects generic password= literal" {
    fake_diff $'+password = "hunter2hunter2"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects api_key= literal" {
    fake_diff $'+api_key: "abcd1234efgh5678"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores empty password assignment" {
    fake_diff $'+password = ""\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "secrets blocked even in non-claude mode" {
    unset CLAUDECODE
    fake_diff $'+token = ghp_abcdefghijklmnopqrstuvwxyz0123456789\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects OpenAI sk-proj- key (hyphen in body)" {
    fake_diff $'+OPENAI=sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz123456\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects Slack bot token" {
    fake_diff $'+SLACK=xoxb-123456789012-abcdefghijkl\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects unquoted env-file password assignment" {
    fake_diff $'+PASSWORD=hunter2hunter2\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects unquoted exported api key" {
    fake_diff $'+export API_KEY=abcdefgh12345678\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores mid-line kwarg that looks like an assignment" {
    fake_diff $'+result = fetch(token=some_value)\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores spaced assignment from a call expression" {
    fake_diff $'+token = getToken()\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- added lines whose content starts with '+' (regression: ^\+[^+] bypass) --

@test "rejects secret on added line starting with ++" {
    fake_diff $'+++counter; // password="supersecret123"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects non-ASCII on added line starting with ++" {
    fake_diff $'+++counter; // caf\xc3\xa9\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects trailing whitespace on added line starting with ++" {
    fake_diff $'+++counter;   \n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects nocommit on added line starting with ++" {
    fake_diff $'+++counter; // nocommit\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores nocommit in a +++ file header path" {
    fake_diff $'+++ b/nocommit-notes.md\n+clean content\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores trailing whitespace in a +++ file header path" {
    fake_diff $'+++ b/file \n+clean content\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- fallback path (no ripgrep): regression for the fail-open `grep -P` bug --

@test "fallback rejects non-ASCII" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+hello \xe2\x80\x94 world\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "fallback rejects secret" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+token = ghp_abcdefghijklmnopqrstuvwxyz0123456789\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "fallback rejects unquoted env-file password assignment" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+PASSWORD=hunter2hunter2\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "fallback rejects trailing whitespace" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+hello   \n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "fallback rejects trailing tab" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+hello\t\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "fallback rejects nocommit" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+debug print // nocommit\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "fallback passes on clean added line" {
    export PRECOMMIT_NO_RG=1
    fake_diff $'+hello world\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- diff invocation hardening --

@test "requests a plain diff (no ext-diff, color, or textconv)" {
    fake_diff $'+clean\n'
    cat > "$SHIMDIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FLAGS_OUT"
EOF
    chmod +x "$SHIMDIR/git"
    export FLAGS_OUT="$BATS_TEST_TMPDIR/flags"
    run "$HOOK"
    run cat "$FLAGS_OUT"
    [[ "$output" == *"--no-ext-diff"* ]]
    [[ "$output" == *"--no-color"* ]]
    [[ "$output" == *"--no-textconv"* ]]
}
