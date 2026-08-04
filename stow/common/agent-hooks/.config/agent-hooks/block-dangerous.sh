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

# capability opt-outs, comma-separated, read from this process's OWN
# environment (`env AGENT_UNFENCE=branch claude`). an agent cannot grant
# itself one: a command's env-prefix reaches this policy as text on stdin,
# never as an actual variable. kept inline for the same reason as the fold
# below -- a policy that can't find a helper file must not degrade into
# allowing everything.
_unfenced() {
    case ",${AGENT_UNFENCE}," in
        (*",$1,"*) return 0 ;;
    esac
    return 1
}

# fold line wraps and whitespace runs before matching. every pattern below is
# a line-based grep with literal spaces in it, so a wrapped `git \<newline>
# push` or a stray `git  push` would otherwise walk straight past the fence.
# folding only joins what the shell would join anyway -- it can widen a
# pattern's reach, never narrow it. (kept inline, not sourced: a policy that
# can't find a helper file must not degrade into allowing everything.)
COMMAND=$(printf '%s' "$COMMAND" | sed -E 's/\\$//' | tr '\n\t' '  ' | sed -E 's/  +/ /g')

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
    STRIPPED=$(printf '%s' "$COMMAND" | sed -E 's/(^|[ ;|&])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path)[= ][^[:space:]]+|--no-pager|-P)[[:space:]]+/\1git /')
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
    # NOTE: `git commit` intentionally allowed -- per workflow.md, commits
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
BRANCH_REASON="stay on the current branch -- don't create or switch branches / worktrees. you CAN commit on this branch (commits aren't blocked); just don't branch off it. to read other branches use git log / diff / show <ref>. (the user can lift this for a session with env AGENT_UNFENCE=branch.)"

# wide `git add` -- agent must stage explicit paths, not sweep the worktree.
# blocks -A / --all / -u / --update / `.` / `*` (and combined short flags
# containing A or u, e.g. -Au, -Av). pass file paths explicitly instead.
GIT_ADD_PATTERNS=(
    "(^|[ ;|&])git add (-[A-Za-z]*[Au][A-Za-z]*|--all|--update|\\.|\\*)( |$)"
)
GIT_ADD_REASON="stage explicit paths only -- wide \`git add\` may grab unrelated wip / scratch files"

# any write `gh` op. read ops (view/list/status/api GET) are fine.
GH_WRITE_PATTERNS=(
    "(^|[ ;|&])gh pr (create|comment|edit|review|revert|close|reopen|ready|checkout|lock|unlock|update-branch)"
    # `co` is checkout under both its documented alias and gh's own top-level one
    "(^|[ ;|&])gh (pr )?co( |$)"
    "(^|[ ;|&])gh issue (create|comment|edit|close|reopen|lock|unlock|delete|pin|unpin|transfer)"
    "(^|[ ;|&])gh release (create|edit|delete|upload)"
    # deploy-key is a group, not a leaf -- `list` under it is a read
    "(^|[ ;|&])gh repo (create|delete|edit|archive|unarchive|fork|rename|sync|deploy-key (add|delete))"
    "(^|[ ;|&])gh gist (create|edit|delete)"
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
# forces a POST even w/out an explicit -X, so it's a write. matched per
# segment (see the loop below), and glued as well as spaced -- `-fbody=x`,
# `--field=body=x` and `--input=f.json` are the same write as their spaced
# forms.
GH_API_FIELD_RE="(^| )(-[A-Za-z]*[fF]([ =]|[A-Za-z])|--(field|raw-field|input)([ =]|$))"
# an explicit GET keeps it a read -- fields become query params.
GH_API_GET_RE="(-X ?|--method[ =])GET"
# graphql has no GET form: the v4 endpoint is POST-only and the query rides
# in a field, so fencing on method alone blocks reads that have no REST
# equivalent (review-thread isResolved, say). let it through iff the query is
# inline and mutation-free. `graphql` must be the endpoint, i.e. the first
# token -- further along the line it is as likely a repo name or a string.
GH_API_GRAPHQL_RE="gh api (https?://[^ ]+/)?/?graphql( |$)"
# query the hook can't read (@file, stdin, request body) or mustn't allow.
# matched against the whole command, not the segment: segments split on
# separators, so a quoted `|` inside the query would otherwise cut a mutation
# out of the text being inspected while the shell still sends it. the keyword
# is the only way to write a mutation (there is no shorthand form the way
# there is for a query), so a `mutation` glued to more word characters --
# mutationType, clientMutationId, a repo called mutation-testing -- is a name
# and stays readable.
GH_API_OPAQUE_RE="(^|[^A-Za-z-])mutation[ ({]|--input|=@"
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
    "(^|[ ;|&])npm (install|i) (-g|--global)"
    "(^|[ ;|&])pnpm add (-g|--global)"
    "(^|[ ;|&])yarn global add"
    "(^|[ ;|&])cargo install"
    "(^|[ ;|&])go install"
)
INSTALL_REASON="user does not allow installing software / packages"

# crossing the local boundary into remote envs.
REMOTE_PATTERNS=(
    "(^|[ ;|&])ssh "
    "(^|[ ;|&])autossh "
    "(^|[ ;|&])scp "
    "kubectl exec"
    "gcloud compute ssh"
)
REMOTE_REASON="do not work in remote envs without explicit permission"

# display-only truncation for BLOCKED messages -- matching always runs
# against the full (untruncated) $COMMAND above.
CMD_ABBREV_LEN=120
_abbrev() {
    local cmd="$1"
    if [ "${#cmd}" -gt "$CMD_ABBREV_LEN" ]; then
        printf '%s...' "${cmd:0:$CMD_ABBREV_LEN}"
    else
        printf '%s' "$cmd"
    fi
}

check() {
    local reason="$1"
    shift
    for pat in "$@"; do
        if echo "$COMMAND" | grep -qE -- "$pat"; then
            echo "BLOCKED: '$(_abbrev "$COMMAND")' matches '$pat'. $reason" >&2
            exit 2
        fi
    done
}

check "$GIT_REASON"       "${GIT_PATTERNS[@]}"
check "$GIT_WRITE_REASON" "${GIT_WRITE_PATTERNS[@]}"
_unfenced branch || check "$BRANCH_REASON" "${BRANCH_PATTERNS[@]}"
check "$GIT_ADD_REASON"   "${GIT_ADD_PATTERNS[@]}"
check "$GH_WRITE_REASON"  "${GH_WRITE_PATTERNS[@]}"

# `gh issue develop` creates a linked branch, but `--list` / `-l` only reads
# the existing ones. the flag has to sit in the same segment to count.
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])gh issue develop"; then
    if ! echo "$COMMAND" | grep -qE -- "gh issue develop[^;|&]* (--list|-l)( |$)"; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' creates a branch. $GH_WRITE_REASON" >&2
        exit 2
    fi
fi

# field-flag writes. per segment, not per command: a GET or a graphql read
# earlier on the line must not vouch for a write later on it. each `gh api`
# opens a segment of its own -- newlines were folded to spaces above, so a
# separator is not guaranteed between two of them.
while IFS= read -r seg; do
    echo "$seg" | grep -qE -- "$GH_API_GET_RE" && continue
    echo "$seg" | grep -qE -- "$GH_API_FIELD_RE" || continue
    if echo "$seg" | grep -qE -- "$GH_API_GRAPHQL_RE" &&
        ! echo "$COMMAND" | grep -qiE -- "$GH_API_OPAQUE_RE"; then
        continue
    fi
    echo "BLOCKED: '$(_abbrev "$seg")' writes. $GH_API_FIELD_REASON" >&2
    exit 2
done < <(printf '%s' "$COMMAND" | sed -E 's/gh api/;gh api/g' | grep -oE -- "(^|[ ;|&])gh api[^;|&]*")
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
        echo "BLOCKED: '$(_abbrev "$COMMAND")' discards more than named files. \`git restore <explicit-file-paths>\` is allowed -- no \`.\`, globs, dirs, or --source." >&2
        exit 2
    fi
done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])git restore[^;|&]*")

# `git checkout` -- ONLY the explicit-path discard form `checkout -- <paths>`
# is allowed. branch switching, `-b`, `checkout <ref> -- <path>`, and bare
# `checkout .` stay blocked.
while IFS= read -r seg; do
    _unfenced branch && break
    args="${seg#*git checkout}"
    if [[ "$args" != " -- "* ]] || ! paths_concrete "${args# -- }"; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' -- only \`git checkout -- <explicit-file-paths>\` is allowed (no branch switching, \`.\`, globs, or dirs). $BRANCH_REASON" >&2
        exit 2
    fi
done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])git checkout[^;|&]*")

# `git rm <path>` deletes the worktree copy. allow `--cached` (index-only) and
# `-n` / `--dry-run` (preview).
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git rm "; then
    if ! echo "$COMMAND" | grep -qE -- "(--cached|-n |--dry-run)"; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' deletes worktree files. $GIT_REASON" >&2
        exit 2
    fi
fi

# `git apply` mutates the worktree by default. allow the index-only form
# (--cached; NOTE: --index applies to index AND worktree, so it stays
# blocked) and dry-run inspection (--check/--stat/--numstat/--summary).
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git apply "; then
    if ! echo "$COMMAND" | grep -qE -- "--(cached|check|stat|numstat|summary)"; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' mutates worktree. $GIT_WRITE_REASON" >&2
        exit 2
    fi
fi

check "$GPG_REASON"       "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON"   "${INSTALL_PATTERNS[@]}"
check "$REMOTE_REASON"    "${REMOTE_PATTERNS[@]}"

exit 0
