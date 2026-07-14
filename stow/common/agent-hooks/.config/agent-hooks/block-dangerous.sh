#!/usr/bin/env bash
# Shell-command policy. blocks dangerous / out-of-bounds operations per the
# rules in ~/.config/agent-guidance/workflow.md. exit 2 means policy denial;
# evaluate.sh translates that into a harness-neutral verdict.
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
COMMAND=$(printf '%s' "$INPUT" | jq -r '.command')

# normalise before matching, so `git <subcommand>` anchors can't be dodged:
#   - `\git push` (backslash escape) -> `git push`
#   - `git -C <path> push` / `-c k=v` / `--git-dir=<p>` etc -- strip the
#     global options that sit between `git` and the subcommand. loop handles
#     several in a row.
#
# TODO(lczyk): evasions that would need real shell parsing: env-prefix
# (GIT_DIR=x git ...), $VAR / $(...) command construction, `git${IFS}push`,
# quoted 'git', read-flag-first flag soup (git branch -v -f main).
COMMAND=${COMMAND//\\git/git}
while :; do
    STRIPPED=$(printf '%s' "$COMMAND" | sed -E 's/(^|[ ;|&])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace)[= ][^[:space:]]+|--no-pager|-P)[[:space:]]+/\1git /')
    [[ "$STRIPPED" == "$COMMAND" ]] && break
    COMMAND=$STRIPPED
done

# destructive / history-rewriting git ops. not recoverable.
GIT_PATTERNS=(
    "git reset( |$)"
    # force / interactive clean deletes untracked files; -n / -nd dry-runs stay allowed.
    "git clean ((-[A-Za-z]*[fi])|--force|--interactive)"
    "git branch -D"
    "push --force"
    "git rebase"
    "git merge( |$)"
    # pull = fetch + merge (or rebase) into the current branch
    "(^|[ ;|&])git pull( |$)"
    "git filter-branch"
    "git filter-repo"
    "git reflog (expire|delete)"
    "git gc --prune"
    # ref plumbing -- create / move / delete branch pointers directly
    "(^|[ ;|&])git update-ref( |$)"
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
    # (--cached) and dry-run forms allowed for patch staging.
    "(^|[ ;|&])git stash (drop|clear)"
    "(^|[ ;|&])git config (--add|--unset|--global|--system|--replace-all|--remove-section)"
    # `git config <key> <value>` (local write, no flag needed). the read form
    # `git config <key>` has no trailing value token and doesn't match.
    "(^|[ ;|&])git config (set|unset|rename-section|remove-section)"
    "(^|[ ;|&])git config (--[a-z-]+ )*[A-Za-z][^ ]* [^-&|;<>[:space:]]"
    # remote config writes -- set-url could silently redirect the user's own
    # future pushes.
    "(^|[ ;|&])git remote (add|remove|rm|rename|set-url|set-head|set-branches|prune)"
)
GIT_WRITE_REASON="these git ops are user-run -- commits on the current branch ARE allowed, but run push / tag / cherry-pick / etc yourself or disable the hook"

# branch / worktree creation+switching. the agent works ON the currently
# checked-out branch -- it must not create or switch branches / worktrees.
# committing on the current branch is fine (with per-prompt permission).
# `git checkout` handled by a special-case below -- the explicit-path
# discard form `checkout -- <paths>` is allowed (same power as the Write
# tool), branch switching / `-b` stay blocked. reading other branches goes
# via log / diff / show.
BRANCH_PATTERNS=(
    # short create/copy/move/delete/force/track/upstream flags (first arg,
    # combined forms like -fD included) or a bare non-flag arg (create).
    "(^|[ ;|&])git branch -[cCmMdDftu]"
    "(^|[ ;|&])git branch [^-]"
    # long write flags anywhere in the branch invocation. reads like --list /
    # --show-current / --contains / --merged / -vv stay allowed.
    "(^|[ ;|&])git branch [^;|&]*--(track|copy|move|delete|force|set-upstream-to|unset-upstream|create-reflog)"
    "(^|[ ;|&])git switch( |$)"
    "(^|[ ;|&])git worktree (add|remove|move|prune)"
    # symbolic-ref rewrites HEAD = branch switch w/out checkout. blocks the
    # read form too -- use git branch --show-current instead.
    "(^|[ ;|&])git symbolic-ref( |$)"
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
    # `-X ?` also catches the glued form `-XPOST`
    "gh api .*(-X ?|--method[ =])(POST|PUT|PATCH|DELETE)"
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
if ! echo "$COMMAND" | grep -qE -- "(-X ?|--method[ =])GET"; then
    check "$GH_API_FIELD_REASON" "${GH_API_FIELD_PATTERNS[@]}"
fi
# explicit-path discard (`git restore <file>`, `git checkout -- <file>`) is
# allowed: the agent can already overwrite any single file via the Write
# tool, so blocking it only forces a noisier `git show > tmp` + Write
# workaround. what stays blocked is anything broader than named files:
# `.` / `..`, globs, pathspec magic (:/ etc), shell expansions, directories,
# and unknown flags (e.g. --source) -- fail safe on all of them.
#
# NOTE: word-splitting heuristic, not a shell parser. quoted paths with
# spaces split into odd tokens but still land in the concrete branch. the
# -d directory check is cwd-dependent (best effort).
paths_concrete() {
    local n=0 tok toks
    # read -ra (not bare $1 expansion) so glob tokens are inspected
    # literally instead of being pathname-expanded by the shell.
    read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        case "$tok" in
            --) ;;
            -S|-W|--staged|--worktree) ;;              # restore's own flags
            -*) return 1 ;;                            # unknown flag -- fail safe
            .|..) return 1 ;;                          # cwd sweep
            "~"*) return 1 ;;                          # tilde -- shell expands to home
            :*) return 1 ;;                            # pathspec magic
            *'*'*|*'?'*|*'['*|*'$'*|*'`'*) return 1 ;; # glob / expansion
            */) return 1 ;;                            # explicit dir
            *) [[ -d "$tok" ]] && return 1             # dir sweep (best effort)
               ((n++)) ;;
        esac
    done
    ((n > 0))                                          # at least one real path
}

# `git restore` -- allow index-only (--staged w/out --worktree, worktree
# untouched) and explicit-path discard; block broad forms.
while IFS= read -r seg; do
    args="${seg#*git restore}"
    if [[ "$args" == *--staged* && "$args" != *--worktree* ]]; then
        continue
    fi
    if ! paths_concrete "$args"; then
        echo "BLOCKED: '$COMMAND' discards more than named files. \`git restore <explicit-file-paths>\` is allowed -- no \`.\`, globs, dirs, or --source." >&2
        exit 2
    fi
done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])git restore[^;|&]*")

# `git checkout` -- ONLY the explicit-path discard form `checkout -- <paths>`
# is allowed. branch switching, `-b`, `checkout <ref> -- <path>`, and bare
# `checkout .` stay blocked.
while IFS= read -r seg; do
    args="${seg#*git checkout}"
    if [[ "$args" != " -- "* ]] || ! paths_concrete "${args# -- }"; then
        echo "BLOCKED: '$COMMAND' -- only \`git checkout -- <explicit-file-paths>\` is allowed (no branch switching, \`.\`, globs, or dirs). $BRANCH_REASON" >&2
        exit 2
    fi
done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])git checkout[^;|&]*")

# `git rm <path>` deletes the worktree copy. allow `--cached` (index-only) and
# `-n` / `--dry-run` (preview).
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git rm "; then
    if ! echo "$COMMAND" | grep -qE -- "(--cached|-n |--dry-run)"; then
        echo "BLOCKED: '$COMMAND' deletes worktree files. $GIT_REASON" >&2
        exit 2
    fi
fi

# `git apply` mutates the worktree by default. allow the index-only form
# (--cached; NOTE: --index applies to index AND worktree, so it stays
# blocked) and dry-run inspection (--check/--stat/--numstat/--summary).
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git apply "; then
    if ! echo "$COMMAND" | grep -qE -- "--(cached|check|stat|numstat|summary)"; then
        echo "BLOCKED: '$COMMAND' mutates worktree. $GIT_WRITE_REASON" >&2
        exit 2
    fi
fi

check "$GPG_REASON"       "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON"   "${INSTALL_PATTERNS[@]}"
check "$REMOTE_REASON"    "${REMOTE_PATTERNS[@]}"

exit 0
