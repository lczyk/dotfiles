#!/usr/bin/env bash
# PreToolUse hook for the Bash tool. blocks dangerous / out-of-bounds
# operations per the rules in ~/.claude/CLAUDE.md. exit 2 to block.
#
# categories:
#   - destructive / history-rewriting git
#   - bypass of commit signing
#   - software / package installs
#   - remote envs (ssh, scp, kubectl exec, ...)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# git ops the user does not want agents running. covers the existing
# destructive list plus the "complex / risky" ops from CLAUDE.md
# (rebase, merge, reset, filter-branch, gh pr merge).
GIT_PATTERNS=(
    "git push"
    "git reset( |$)"
    "git clean -fd?"
    "git branch -D"
    "git checkout \\."
    "git restore \\."
    "push --force"
    "git rebase"
    "git merge( |$)"
    "git filter-branch"
    "git filter-repo"
    "gh pr merge"
)
GIT_REASON="user prevents destructive / history-rewriting git ops"

# bypassing commit signing.
GPG_PATTERNS=(
    "--no-gpg-sign"
)
GPG_REASON="do not bypass commit signing -- ask user if you really need to"

# installing software / packages globally. project-local dep resolution
# (npm ci, uv sync, cargo build) is fine and not matched here.
INSTALL_PATTERNS=(
    "(^|[ ;|&])brew install"
    "(^|[ ;|&])apt(-get)? install"
    "(^|[ ;|&])pip install"
    "(^|[ ;|&])pipx install"
    "(^|[ ;|&])uv pip install"
    "(^|[ ;|&])uv tool install"
    "(^|[ ;|&])npm install -g"
    "(^|[ ;|&])npm i -g"
    "(^|[ ;|&])pnpm add -g"
    "(^|[ ;|&])yarn global add"
    "(^|[ ;|&])cargo install"
    "(^|[ ;|&])go install"
)
INSTALL_REASON="user does not allow installing software / packages"

# crossing the local boundary into remote envs.
REMOTE_PATTERNS=(
    "(^|[ ;|&])ssh "
    "(^|[ ;|&])scp "
    "kubectl exec"
    "gcloud compute ssh"
)
REMOTE_REASON="do not work in remote envs without explicit permission"

check() {
    local reason="$1"
    shift
    for pat in "$@"; do
        if echo "$COMMAND" | grep -qE -- "$pat"; then
            echo "BLOCKED: '$COMMAND' matches '$pat'. $reason" >&2
            exit 2
        fi
    done
}

check "$GIT_REASON"     "${GIT_PATTERNS[@]}"
check "$GPG_REASON"     "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON" "${INSTALL_PATTERNS[@]}"
check "$REMOTE_REASON"  "${REMOTE_PATTERNS[@]}"

exit 0
