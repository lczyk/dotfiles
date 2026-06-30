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
    "(^|[ ;|&])git am( |$)"
    # NOTE: `git apply` handled by a special-case below -- index-only
    # (--cached/--index) and dry-run forms allowed for patch staging.
    "(^|[ ;|&])git stash (drop|clear)"
    "(^|[ ;|&])git config (--add|--unset|--global|--system|--replace-all|--remove-section)"
)
GIT_WRITE_REASON="these git ops are user-run -- commits on the current branch ARE allowed, but run push / tag / cherry-pick / etc yourself or disable the hook"

# branch / worktree creation+switching. the agent works ON the currently
# checked-out branch -- it must not create or switch branches / worktrees.
# committing on the current branch is fine (with per-prompt permission).
# `git checkout` also catches `checkout -- <path>` (worktree discard) and
# `checkout -b`. reading other branches goes via log / diff / show.
BRANCH_PATTERNS=(
    "(^|[ ;|&])git branch( -[cCmMdD]| [^-])"
    "(^|[ ;|&])git checkout( |$)"
    "(^|[ ;|&])git switch( |$)"
    "(^|[ ;|&])git worktree (add|remove|move|prune)"
)
BRANCH_REASON="stay on the current branch -- don't create or switch branches / worktrees. you CAN commit on this branch (commits aren't blocked); just don't branch off it. to read other branches use git log / diff / show <ref>."

# wide `git add` -- agent must stage explicit paths, not sweep the worktree.
# blocks -A / --all / -u / --update / `.` / `*` (and combined short flags
# containing A or u, e.g. -Au, -Av). pass file paths explicitly instead.
GIT_ADD_PATTERNS=(
    "(^|[ ;|&])git add (-[A-Za-z]*[Au][A-Za-z]*|--all|--update|\\.|\\*)( |$)"
)
GIT_ADD_REASON="stage explicit paths only -- wide \`git add\` may grab unrelated wip / scratch files"

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
    "(^|[ ;|&])gh auth (login|logout|refresh|setup-git|token)"
    "(^|[ ;|&])gh codespace (create|delete|edit|stop|cp)"
    "(^|[ ;|&])gh project (create|edit|delete|close|copy|link|unlink|mark-template|item-create|item-edit|item-delete|item-add|item-archive|field-create|field-delete)"
    "(^|[ ;|&])gh (ssh-key|gpg-key) (add|delete)"
    "(^|[ ;|&])gh alias (set|delete)"
    "(^|[ ;|&])gh config set"
    "(^|[ ;|&])gh cache delete"
    "(^|[ ;|&])gh extension (install|remove|upgrade)"
    "gh api .*(-X|--method)[ =](POST|PUT|PATCH|DELETE)"
)
GH_WRITE_REASON="agent is fenced to read-only gh -- run write ops yourself or disable the hook"

# `gh api` with a field flag (-f / -F / --field / --raw-field / --input)
# forces a POST even w/out an explicit -X, so it's a write. exception: an
# explicit -X GET / --method GET keeps it a read (fields become query params).
GH_API_FIELD_PATTERNS=(
    "(^|[ ;|&])gh api .*(-f |-F |--field |--raw-field |--input )"
)
GH_API_FIELD_REASON="agent is fenced to read-only gh -- \`gh api\` with field flags writes; run it yourself or disable the hook"

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
check "$BRANCH_REASON"    "${BRANCH_PATTERNS[@]}"
check "$GIT_ADD_REASON"   "${GIT_ADD_PATTERNS[@]}"
check "$GH_WRITE_REASON"  "${GH_WRITE_PATTERNS[@]}"

# field-flag writes, unless an explicit GET method is present.
if ! echo "$COMMAND" | grep -qE -- "(-X|--method)[ =]GET"; then
    check "$GH_API_FIELD_REASON" "${GH_API_FIELD_PATTERNS[@]}"
fi
# `git restore <path>` discards worktree changes. allow `--restore --staged`
# alone (index-only, worktree untouched); block once `--worktree` appears or
# `--staged` is absent.
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git restore "; then
    if echo "$COMMAND" | grep -qE -- "--worktree" || ! echo "$COMMAND" | grep -qE -- "--staged"; then
        echo "BLOCKED: '$COMMAND' discards worktree changes. $GIT_REASON" >&2
        exit 2
    fi
fi

# `git rm <path>` deletes the worktree copy. allow `--cached` (index-only) and
# `-n` / `--dry-run` (preview).
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git rm "; then
    if ! echo "$COMMAND" | grep -qE -- "(--cached|-n |--dry-run)"; then
        echo "BLOCKED: '$COMMAND' deletes worktree files. $GIT_REASON" >&2
        exit 2
    fi
fi

# `git apply` mutates the worktree by default. allow index-only forms
# (--cached/--index, same safety class as the allowed `git commit`) and
# dry-run inspection (--check/--stat/--numstat/--summary) for patch staging.
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git apply "; then
    if ! echo "$COMMAND" | grep -qE -- "--(cached|index|check|stat|numstat|summary)"; then
        echo "BLOCKED: '$COMMAND' mutates worktree. $GIT_WRITE_REASON" >&2
        exit 2
    fi
fi

check "$GPG_REASON"       "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON"   "${INSTALL_PATTERNS[@]}"
check "$REMOTE_REASON"    "${REMOTE_PATTERNS[@]}"

exit 0
