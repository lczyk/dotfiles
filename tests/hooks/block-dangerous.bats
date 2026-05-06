#!/usr/bin/env bats
# tests for stow/common/claude/.claude/hooks/block-dangerous.sh
# the hook reads claude-code's PreToolUse JSON on stdin and exits 2 to block.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/hooks/block-dangerous.sh"
}

# pipe a fake PreToolUse payload with the given Bash command.
fire() {
    local cmd="$1"
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# -- destructive git ----------------------------------------------------

@test "blocks git push" {
    run fire "git push origin main"
    [ "$status" -eq 2 ]
}

@test "blocks git push --force" {
    run fire "git push --force"
    [ "$status" -eq 2 ]
}

@test "blocks git reset --hard" {
    run fire "git reset --hard HEAD"
    [ "$status" -eq 2 ]
}

@test "blocks bare git reset" {
    run fire "git reset"
    [ "$status" -eq 2 ]
}

@test "blocks git rebase" {
    run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "blocks git merge" {
    run fire "git merge feature"
    [ "$status" -eq 2 ]
}

@test "blocks git filter-branch" {
    run fire "git filter-branch --tree-filter rm a"
    [ "$status" -eq 2 ]
}

@test "blocks gh pr merge" {
    run fire "gh pr merge 123"
    [ "$status" -eq 2 ]
}

@test "blocks git checkout ." {
    run fire "git checkout ."
    [ "$status" -eq 2 ]
}

@test "blocks git clean -fd" {
    run fire "git clean -fd"
    [ "$status" -eq 2 ]
}

@test "allows git status" {
    run fire "git status"
    [ "$status" -eq 0 ]
}

@test "allows git log" {
    run fire "git log --oneline -10"
    [ "$status" -eq 0 ]
}

@test "allows git diff" {
    run fire "git diff --cached"
    [ "$status" -eq 0 ]
}

# -- gpg bypass ---------------------------------------------------------

@test "blocks --no-gpg-sign" {
    run fire "git commit --no-gpg-sign -m x"
    [ "$status" -eq 2 ]
}

# -- installs -----------------------------------------------------------

@test "blocks brew install" {
    run fire "brew install jq"
    [ "$status" -eq 2 ]
}

@test "blocks pip install" {
    run fire "pip install requests"
    [ "$status" -eq 2 ]
}

@test "blocks pipx install" {
    run fire "pipx install black"
    [ "$status" -eq 2 ]
}

@test "blocks uv pip install" {
    run fire "uv pip install foo"
    [ "$status" -eq 2 ]
}

@test "blocks uv tool install" {
    run fire "uv tool install ruff"
    [ "$status" -eq 2 ]
}

@test "blocks npm install -g" {
    run fire "npm install -g typescript"
    [ "$status" -eq 2 ]
}

@test "blocks npm i -g" {
    run fire "npm i -g typescript"
    [ "$status" -eq 2 ]
}

@test "blocks cargo install" {
    run fire "cargo install ripgrep"
    [ "$status" -eq 2 ]
}

@test "blocks go install" {
    run fire "go install github.com/x/y@latest"
    [ "$status" -eq 2 ]
}

@test "blocks apt install" {
    run fire "sudo apt install ripgrep"
    [ "$status" -eq 2 ]
}

@test "blocks apt-get install" {
    run fire "sudo apt-get install ripgrep"
    [ "$status" -eq 2 ]
}

@test "blocks pip install when chained after another command" {
    run fire "cd /tmp && pip install foo"
    [ "$status" -eq 2 ]
}

@test "allows project-local npm ci" {
    run fire "npm ci"
    [ "$status" -eq 0 ]
}

@test "allows project-local uv sync" {
    run fire "uv sync"
    [ "$status" -eq 0 ]
}

@test "allows cargo build" {
    run fire "cargo build --release"
    [ "$status" -eq 0 ]
}

@test "allows npm install (project-local, no -g)" {
    run fire "npm install"
    [ "$status" -eq 0 ]
}

# -- remote ops ---------------------------------------------------------

@test "blocks ssh" {
    run fire "ssh host whoami"
    [ "$status" -eq 2 ]
}

@test "blocks scp" {
    run fire "scp file host:/tmp/"
    [ "$status" -eq 2 ]
}

@test "blocks kubectl exec" {
    run fire "kubectl exec pod -- ls"
    [ "$status" -eq 2 ]
}

@test "blocks gcloud compute ssh" {
    run fire "gcloud compute ssh my-vm"
    [ "$status" -eq 2 ]
}

@test "allows kubectl get" {
    run fire "kubectl get pods"
    [ "$status" -eq 0 ]
}

@test "allows ssh-keygen (not the ssh command itself)" {
    run fire "ssh-keygen -y -f key"
    [ "$status" -eq 0 ]
}

# -- benign commands ----------------------------------------------------

@test "allows ls" {
    run fire "ls -la"
    [ "$status" -eq 0 ]
}

@test "allows echo" {
    run fire "echo hello"
    [ "$status" -eq 0 ]
}
