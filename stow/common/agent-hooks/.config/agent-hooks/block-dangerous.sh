#!/usr/bin/env bash
# Shell-command policy. blocks dangerous / out-of-bounds operations per the
# rules in ~/.config/agent-guidance/workflow.md. exit 2 means policy denial;
# evaluate.sh translates that into a harness-neutral verdict.
#
# categories:
#   - destructive git (reset, force-push, filter-branch, ...)
#   - history-mutating git (rebase, cherry-pick, reset --soft -- liftable, see AGENT_UNFENCE=history)
#   - git push (liftable, see AGENT_UNFENCE=push; force / delete / bulk forms never)
#   - any write git op (tag, revert, config, ...)
#   - gh pr create / gh issue create (liftable, see AGENT_UNFENCE=pr / issue)
#   - any write `gh` op (pr/issue/release comment+edit, api writes)
#   - bypass of commit signing
#   - software / package installs
#   - remote envs (ssh, scp, kubectl exec, ... -- liftable, see AGENT_UNFENCE=remote)
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

# `-c key=val` / `--config-env` overrides that neutralise the git-hook and
# signing layers, or define a one-shot alias that hides a subcommand from
# every anchor below (`git -c alias.p=push p`). `--exec-path=<dir>` swaps
# the remote helpers git runs. matched pre-strip -- the loop below erases
# exactly the evidence being looked for. -i: config keys are case-insensitive.
# known false positive: `git grep -c <key>` reads as an override.
GIT_CFG_KEYS="core\.hookspath|commit\.gpgsign|tag\.gpgsign|gpg\.program|alias\."
if echo "$COMMAND" | grep -qiE -- "(^|[ ;|&])git [^;|&]*((-c ?|--config-env[= ])[\"']?(${GIT_CFG_KEYS})|--exec-path=)"; then
    echo "BLOCKED: '${COMMAND:0:120}' overrides hook / signing / alias / exec-path config -- ask the user if you really need to" >&2
    exit 2
fi

# the same layers, reached through the environment: config file locations,
# the repo location, the exec path, the ssh / proxy commands git runs, and
# PATH itself when git or gh is on the line (a shadowing git binary).
GIT_ENV_VARS="GIT_CONFIG[A-Z_]*|GIT_DIR|GIT_WORK_TREE|GIT_EXEC_PATH|GIT_SSH|GIT_SSH_COMMAND|GIT_PROXY_COMMAND|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|XDG_CONFIG_HOME|HOME"
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])((env|export) [^;|&]*)?(${GIT_ENV_VARS})="; then
    echo "BLOCKED: '${COMMAND:0:120}' overrides git's config / repo / exec environment -- ask the user if you really need to" >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])((env|export) [^;|&]*)?PATH=" && echo "$COMMAND" | grep -qE -- "(^|[ ;|&/])(git|gh)( |$)"; then
    echo "BLOCKED: '${COMMAND:0:120}' rewrites PATH around a git / gh call -- ask the user if you really need to" >&2
    exit 2
fi

# one-shot config that redirects or widens a push: remote.<r>.pushurl,
# url.<base>.pushInsteadOf, push.default=matching, branch.<b>.pushRemote.
# remotes are fixed for the agent (git remote / git config writes are fenced),
# so this stays fenced under every capability. matched pre-strip, same reason.
PUSH_CFG_KEYS="remote\.|url\.|push\.|branch\."
if echo "$COMMAND" | grep -qiE -- "(^|[ ;|&])git [^;|&]*(-c ?|--config-env[= ])[\"']?(${PUSH_CFG_KEYS})[^;|&]* push( |$)"; then
    echo "BLOCKED: '${COMMAND:0:120}' pushes under a one-shot remote / push config -- not liftable; push to a configured remote by name" >&2
    exit 2
fi

# glued forms included (-C/path, -ckey=val) -- a spaced-only strip would
# leave them sitting between `git` and the subcommand, dodging every anchor.
while :; do
    STRIPPED=$(printf '%s' "$COMMAND" | sed -E 's/(^|[ ;|&])git[[:space:]]+(-C[[:space:]]*[^[:space:]]+|-c[[:space:]]*[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path|config-env)[= ][^[:space:]]+|--no-pager|-P)[[:space:]]+/\1git /')
    [[ "$STRIPPED" == "$COMMAND" ]] && break
    COMMAND=$STRIPPED
done

# destructive git ops. not recoverable, and not liftable by any capability.
# `git reset` (past --soft) and `git rebase` are handled separately below --
# see the history capability.
GIT_PATTERNS=(
    # force / interactive clean deletes untracked files; -n / -nd dry-runs stay allowed.
    "git clean ((-[A-Za-z]*[fi])|--force|--interactive)"
    "git branch -D"
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
    # follow that rule rather than being hard-fenced. `git push` has its own
    # special-case below -- see the push capability.
    "(^|[ ;|&])git tag( -[adfsmu]| [^-])"
    "(^|[ ;|&])git revert( |$)"
    "(^|[ ;|&])git am( |$)"
    # NOTE: `git apply` handled by a special-case below -- index-only
    # (--cached) and dry-run forms allowed for patch staging.
    "(^|[ ;|&])git stash (drop|clear)"
    "(^|[ ;|&])git config (--add|--unset|--global|--system|--replace-all|--remove-section)"
    # `git config <key> <value>` (local write, no flag needed). the read form
    # `git config <key>` has no trailing value token and doesn't match; the
    # key token stops at segment separators so a chained command after a read
    # (`git config --get k; echo x`) isn't misread as the value.
    "(^|[ ;|&])git config (set|unset|rename-section|remove-section)"
    "(^|[ ;|&])git config (--[a-z-]+ )*[A-Za-z][^ ;|&]* [^-&|;<>[:space:]]"
    # remote config writes -- set-url could silently redirect the user's own
    # future pushes.
    "(^|[ ;|&])git remote (add|remove|rm|rename|set-url|set-head|set-branches|prune)"
)
GIT_WRITE_REASON="these git ops are user-run -- commits on the current branch ARE allowed, but run push / tag / etc yourself or disable the hook"

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

# history-mutating git ops -- rewrite or duplicate commits, distinct risk
# class from branch nav (which never loses work). reflog-recoverable but
# real risk: conflicts, duplicate commits, wrong base. `git reset --soft`
# belongs here too but is handled as a special case below (it's the one
# `reset` form that touches neither index nor worktree); --hard / --mixed /
# bare `reset` stay in GIT_PATTERNS, ungated by any capability.
HISTORY_PATTERNS=(
    "git rebase"
    "(^|[ ;|&])git cherry-pick( |$)"
)
HISTORY_REASON="git rebase / cherry-pick rewrite or duplicate commits -- user prevents this by default. (the user can lift this for a session with env AGENT_UNFENCE=history.)"

# wide `git add` -- agent must stage explicit paths, not sweep the worktree.
# blocks -A / --all / -u / --update / `.` / `*` (and combined short flags
# containing A or u, e.g. -Au, -Av). pass file paths explicitly instead.
GIT_ADD_PATTERNS=(
    "(^|[ ;|&])git add (-[A-Za-z]*[Au][A-Za-z]*|--all|--update|\\.|\\*)( |$)"
)
GIT_ADD_REASON="stage explicit paths only -- wide \`git add\` may grab unrelated wip / scratch files"

# any write `gh` op. read ops (view/list/status/api GET) are fine.
GH_WRITE_PATTERNS=(
    # `gh pr create` has its own special-case below -- see the pr capability.
    "(^|[ ;|&])gh pr (comment|edit|review|revert|close|reopen|ready|checkout|lock|unlock|update-branch)"
    # `co` is checkout under both its documented alias and gh's own top-level one
    "(^|[ ;|&])gh (pr )?co( |$)"
    # `gh issue create` has its own special-case below -- see the issue capability.
    "(^|[ ;|&])gh issue (comment|edit|close|reopen|lock|unlock|delete|pin|unpin|transfer)"
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

# crossing the local boundary into remote envs. lifted as one category by
# the remote capability; git push is its own category and stays fenced.
REMOTE_PATTERNS=(
    "(^|[ ;|&])ssh "
    "(^|[ ;|&])autossh "
    "(^|[ ;|&])scp "
    "kubectl exec"
    "gcloud compute ssh"
)
REMOTE_REASON="do not work in remote envs without explicit permission. (the user can lift this for a session with env AGENT_UNFENCE=remote.)"

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
_unfenced branch  || check "$BRANCH_REASON"  "${BRANCH_PATTERNS[@]}"
_unfenced history || check "$HISTORY_REASON" "${HISTORY_PATTERNS[@]}"
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

# `git reset` -- ONLY `--soft` is conditionally allowed (under the history
# capability): it moves the branch pointer but leaves index and worktree
# untouched, fully reflog-recoverable. `--hard`, `--mixed`, and bare
# `git reset` stay blocked always, capability or not -- they touch the
# index and/or worktree and are a different risk class.
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git reset( |$)"; then
    if ! { _unfenced history && echo "$COMMAND" | grep -qE -- "(^|[ ;|&])git reset --soft( |$)"; }; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' -- \`git reset\` is destructive past --soft. $GIT_REASON. (\`--soft\` alone is liftable with env AGENT_UNFENCE=history.)" >&2
        exit 2
    fi
fi

# `git push` -- liftable with the push capability, minus the forms that rewrite
# or delete remote refs, skip the pre-push hook, push in bulk, or name a url or
# path instead of a configured remote. those stay fenced under every capability
# (pre-push draws the same line for aliases and scripts the text match misses).
# git takes any unambiguous prefix of a long option, so each flag is matched
# from its shortest accepted spelling: --force-w(ith-lease), --force-i(f-includes),
# --de(lete), --m(irror), --pru(ne), --al(l), --b(ranches), --ta(gs),
# --no-veri(fy), --rece(ive-pack), --e(xec), --rep(o). --for[a-z-]* also
# swallows the ambiguous --for / --forc, which git rejects anyway.
PUSH_HARD_FLAG_RE=" --(for[a-z-]*|de[a-z]*|m[a-z]*|pru[a-z]*|al[a-z]*|b[a-z]*|ta[a-z]*|no-veri[a-z]*|rece[a-z-]*|e[a-z]*|rep[a-z]*)(=[^ ]*)?( |$)"
PUSH_HARD_SHORT_RE=" -[A-Za-z]*[fd][A-Za-z]*( |$)"
# `+ref` forces one refspec, a leading `:` deletes the remote ref, and a bare
# `:` is the old push-everything-matching form.
PUSH_HARD_REFSPEC_RE=" (\+[^ ]+|:[^ ]*)( |$)"
# a substituted or variable target could be anything, a url included; git
# push origin HEAD names the current branch without one.
PUSH_SUBST_RE='\$\(|`|\$\{|\$[A-Za-z_]|\$'"'"
PUSH_HARD_REASON="force / delete / bulk / hook-skipping pushes and url targets are user-run under every capability"
PUSH_REASON="git push is user-run. (the user can lift fast-forward pushes to a configured remote for a session with env AGENT_UNFENCE=push.)"

# plumbing that pushes without running pre-push, and the transport helpers
# `git push` drives underneath.
PUSH_PLUMBING_PATTERNS=(
    "(^|[ ;|&])git (send-pack|http-push)( |$)"
    "(^|[ ;|&])git(-| )remote-[a-z]+( |$)"
)
PUSH_PLUMBING_REASON="push plumbing bypasses the pre-push hook -- push through git push"

# the git hooks read the agent markers from the environment; unsetting or
# rewriting them for a child would hand the hooks a human session.
MARKER_PATTERNS=(
    "(CLAUDECODE|AGENT_SESSION|OPENCODE_PID)="
    "(^|[ ;|&])unset [^;|&]*(CLAUDECODE|AGENT_SESSION|OPENCODE_PID)"
    "(-u|--unset)[ =](CLAUDECODE|AGENT_SESSION|OPENCODE_PID)"
    "(^|[ ;|&])env( [^;|&]*)? (-i|--ignore-environment)( |$)"
)
MARKER_REASON="agent session markers are not yours to unset or rewrite -- the git hooks read them"

# a url or path where a remote name belongs. remotes are fixed for the agent
# (git remote / git config writes are fenced), so a literal target is the only
# way left to push somewhere the user did not configure. redirect targets are
# files, not remotes -- skipped.
_push_names_url() {
    local tok toks skip=0
    read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        if ((skip)); then skip=0; continue; fi
        case "$tok" in
            (\>|\>\>|[0-9]\>|[0-9]\>\>|\<|[0-9]\<) skip=1; continue ;;
            (*\>*|\<*) continue ;;
            (*://*|*@*:*|/*|./*|../*|"~"*|*.git) return 0 ;;
        esac
    done
    return 1
}

check "$PUSH_PLUMBING_REASON" "${PUSH_PLUMBING_PATTERNS[@]}"
check "$MARKER_REASON"        "${MARKER_PATTERNS[@]}"

while IFS= read -r seg; do
    args="${seg#*git push}"
    if echo "$args" | grep -qE -- "${PUSH_HARD_FLAG_RE}|${PUSH_HARD_SHORT_RE}|${PUSH_HARD_REFSPEC_RE}" || _push_names_url "$args"; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' -- $PUSH_HARD_REASON" >&2
        exit 2
    fi
    if ! _unfenced push; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' -- $PUSH_REASON" >&2
        exit 2
    fi
    if echo "$args" | grep -qE -- "$PUSH_SUBST_RE"; then
        echo "BLOCKED: '$(_abbrev "$COMMAND")' -- git push arguments must be literal (no \$(...), backticks or variables); git push origin HEAD names the current branch" >&2
        exit 2
    fi
done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])git push( [^;|&]*|$)")

# `gh pr create` / `gh issue create` -- liftable with the pr / issue
# capability. the target is the current repo (no -R / --repo, no GH_REPO), a
# PR's inline title carries a conventional commits prefix, and the body --
# inline or a file -- is ascii with no agent attribution: the line commit-msg
# draws, drawn here because no git hook sees a PR or issue body. text reaches
# gh only as literal command text or as an absolute regular file this policy
# can read too -- a substitution or a variable would hand gh content it never
# saw. the inline heredoc is the one allowed substitution, since its text is
# in the command.
#
# gh's short flags glue their value (-tfoo) and stack behind the booleans
# (-dwt foo), hence -[<bools>]* before each one; the booleans differ per
# command (pr: -d -f -w, issue: -w -e).
GH_CREATE_TYPES="feat|fix|docs|test|refactor|chore|bench|revert|ci|perf|release"
GH_CREATE_ATTRIBUTION_RE="co-authored-by|generated with"
GH_CREATE_NON_ASCII_RE=$'[^\t -~]'
GH_CREATE_HEREDOC_RE='\$\(cat <<-?["'"'"']?[A-Za-z_]+["'"'"']?'
# $'...' is in the list: its escapes rebuild a banned string byte by byte.
GH_CREATE_SUBST_RE='\$\(|`|\$\{|\$[A-Za-z_]|\$'"'"
GH_CREATE_ENV_RE="GH_(REPO|HOST|TOKEN|ENTERPRISE_TOKEN|CONFIG_DIR)="
GH_CREATE_QUOTED_HEREDOC_RE="\\\$\\(cat <<-?('([A-Za-z_]+)'|\"([A-Za-z_]+)\"|\\\\([A-Za-z_]+))"

_gh_create_block() {
    echo "BLOCKED: '$(_abbrev "$COMMAND")' -- $1" >&2
    exit 2
}

# a quoted heredoc ($(cat <<'EOF' ... EOF)) is literal text: its body still
# gets the attribution and ascii scans with the rest of the command, but not
# the substitution scan -- markdown code spans want backticks. an unquoted
# heredoc expands, so only its opener is excused (GH_CREATE_HEREDOC_RE).
# newlines were folded to spaces, so the terminator line reads " EOF )".
_strip_quoted_heredocs() {
    local s=$1 open d before rest
    while [[ $s =~ $GH_CREATE_QUOTED_HEREDOC_RE ]]; do
        open=${BASH_REMATCH[0]}
        d=${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}
        before=${s%%"$open"*}
        rest=${s#*"$open"}
        [[ $rest == *" $d )"* ]] || break
        rest=${rest#*" $d )"}
        s="$before$rest"
    done
    printf '%s' "$s"
}

# _gh_create <capability> <what> <bool-shorts> <conventional-title: 0|1>
_gh_create() {
    local cap=$1 what=$2 bools=$3 conventional=$4 seg bodyfile
    local seg_re="(^|[ ;|&])gh $what create( [^;|&]*|$)"
    local title_re="(^| )(-[$bools]*t[ =]?|--title[= ])[\"']?(${GH_CREATE_TYPES})(\([a-z0-9._-]+\))?(!|\?)?: "
    echo "$COMMAND" | grep -qE -- "$seg_re" || return 0
    _unfenced "$cap" || _gh_create_block "gh $what create is user-run. (the user can lift it for a session with env AGENT_UNFENCE=$cap.)"
    while IFS= read -r seg; do
        if echo "$seg" | grep -qE -- " (-[$bools]*R|--repo)"; then
            _gh_create_block "gh $what create targets the current repo -- no -R / --repo"
        fi
        if echo "$seg" | grep -qE -- " --recover"; then
            _gh_create_block "--recover replays a title and body this policy cannot read -- pass them explicitly"
        fi
        if [ "$conventional" = 1 ] && echo "$seg" | grep -qE -- " (-[$bools]*t|--title)" && ! echo "$seg" | grep -qE -- "$title_re"; then
            _gh_create_block "PR title must open with a lowercase conventional commits prefix (feat:, fix:, docs:, ...)"
        fi
        if echo "$seg" | grep -qE -- " (-[$bools]*F|--body-file)"; then
            bodyfile=$(printf '%s' "$seg" | sed -E "s/.* (-[$bools]*F|--body-file)[= ]?[\"']?([^\"' ]*).*/\2/")
            [[ "$bodyfile" == /* && -f "$bodyfile" && -r "$bodyfile" ]] || _gh_create_block "body file must be an absolute path to a readable regular file (got '${bodyfile}')"
            grep -qiE -- "$GH_CREATE_ATTRIBUTION_RE" "$bodyfile" && _gh_create_block "body file carries agent attribution (Co-Authored-By / Generated with) -- drop it"
            LC_ALL=C grep -qE -- "$GH_CREATE_NON_ASCII_RE" "$bodyfile" && _gh_create_block "body file must be ascii only"
        fi
    done < <(printf '%s' "$COMMAND" | grep -oE -- "$seg_re")
    printf '%s' "$COMMAND" | grep -qE -- "$GH_CREATE_ENV_RE" && _gh_create_block "gh env overrides (GH_REPO, GH_HOST, GH_TOKEN, ...) are not yours"
    _strip_quoted_heredocs "$COMMAND" | sed -E "s/${GH_CREATE_HEREDOC_RE}//g" | grep -qE -- "$GH_CREATE_SUBST_RE" && _gh_create_block "gh $what create text must be literal -- no \$(...), backticks or variables; put the body in a quoted heredoc (\$(cat <<'EOF' ... EOF)), where backticks and \$ are plain text"
    printf '%s' "$COMMAND" | grep -qiE -- "$GH_CREATE_ATTRIBUTION_RE" && _gh_create_block "text carries agent attribution (Co-Authored-By / Generated with) -- drop it"
    printf '%s' "$COMMAND" | LC_ALL=C grep -qE -- "$GH_CREATE_NON_ASCII_RE" && _gh_create_block "text must be ascii only (no emoji, em-dash, smart quotes)"
}

_gh_create pr    pr    dfw 1
_gh_create issue issue we  0

check "$GPG_REASON"       "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON"   "${INSTALL_PATTERNS[@]}"
_unfenced remote  || check "$REMOTE_REASON"  "${REMOTE_PATTERNS[@]}"

exit 0
