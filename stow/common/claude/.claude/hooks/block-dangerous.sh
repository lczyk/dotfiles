#!/usr/bin/env bash
# PreToolUse hook for the Bash tool. blocks dangerous / out-of-bounds
# operations per the rules in ~/.claude/CLAUDE.md. exit 2 to block.
#
# categories:
#   - destructive / history-rewriting git
#   - any write git op (commit, tag, branch creation, cherry-pick, ...)
#   - any write `gh` op (pr/issue/release create+comment+edit, api writes)
#   - bypass of commit signing
#   - software / package installs
#   - remote envs (ssh, scp, kubectl exec, ...)
#
# the agent is fenced to read-only git/gh by default. when the user
# wants a commit / push / PR, they run it themselves or temporarily
# disable this hook.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# destructive / history-rewriting git ops. not recoverable.
GIT_PATTERNS=(
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
    "git reflog expire"
    "git gc --prune"
    "gh pr merge"
)
GIT_REASON="user prevents destructive / history-rewriting git ops"

# any write git op. agent is read-only by default. user runs commits etc.
# themselves, or disables this hook for the turn.
GIT_WRITE_PATTERNS=(
    # NOTE: `git commit` intentionally allowed -- per CLAUDE.md, commits
    # need explicit per-prompt permission, but the model is trusted to
    # follow that rule rather than being hard-fenced.
    "(^|[ ;|&])git push( |$)"
    "(^|[ ;|&])git tag( -[adfsmu]| [^-])"
    "(^|[ ;|&])git cherry-pick( |$)"
    "(^|[ ;|&])git revert( |$)"
    "(^|[ ;|&])git branch( -[cCmMdD]| [^-])"
    "(^|[ ;|&])git am( |$)"
    "(^|[ ;|&])git apply( |$)"
    "(^|[ ;|&])git worktree (add|remove|move|prune)"
    "(^|[ ;|&])git stash (drop|clear)"
    "(^|[ ;|&])git config (--add|--unset|--global|--system|--replace-all|--remove-section)"
)
GIT_WRITE_REASON="agent is fenced to read-only git -- run write ops yourself or disable the hook"

# any write `gh` op. read ops (view/list/status/api GET) are fine.
GH_WRITE_PATTERNS=(
    "(^|[ ;|&])gh pr (create|comment|edit|review|close|reopen|ready|checkout|lock|unlock|update-branch)"
    "(^|[ ;|&])gh issue (create|comment|edit|close|reopen|lock|unlock|delete|develop|pin|unpin|transfer)"
    "(^|[ ;|&])gh release (create|edit|delete|upload)"
    "(^|[ ;|&])gh repo (create|delete|edit|archive|unarchive|fork|rename|sync|deploy-key)"
    "(^|[ ;|&])gh gist (create|edit|delete|clone)"
    "(^|[ ;|&])gh workflow (run|disable|enable)"
    "(^|[ ;|&])gh run (cancel|delete|rerun)"
    "(^|[ ;|&])gh label (create|delete|edit|clone)"
    "(^|[ ;|&])gh secret (set|delete)"
    "(^|[ ;|&])gh variable (set|delete)"
    "(^|[ ;|&])gh ruleset (create|edit|delete)"
    "gh api .*(-X|--method)[ =](POST|PUT|PATCH|DELETE)"
)
GH_WRITE_REASON="agent is fenced to read-only gh -- run write ops yourself or disable the hook"

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

check "$GIT_REASON"       "${GIT_PATTERNS[@]}"
check "$GIT_WRITE_REASON" "${GIT_WRITE_PATTERNS[@]}"
check "$GH_WRITE_REASON"  "${GH_WRITE_PATTERNS[@]}"
check "$GPG_REASON"       "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON"   "${INSTALL_PATTERNS[@]}"
check "$REMOTE_REASON"    "${REMOTE_PATTERNS[@]}"

exit 0
