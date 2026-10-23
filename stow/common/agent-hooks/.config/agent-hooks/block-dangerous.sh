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
#   - gh pr create / gh issue create and edits of their title, body and
#     labels (liftable, see AGENT_UNFENCE=pr / issue / labels)
#   - any write `gh` op (pr/issue/release comment+edit, api writes)
#   - bypass of commit signing
#   - software / package installs
#   - remote envs (ssh, scp, kubectl exec, ... -- liftable, see AGENT_UNFENCE=remote)
#
# reads are free and commits are the agent's to make (per prompt, checked by
# the git hooks); every other git / gh write is fenced here unless the user
# granted a capability at launch.

# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh" 2>/dev/null ||
    { echo "BLOCKED: agent-hooks lib.sh is missing next to $0" >&2; exit 2; }

INPUT=$(cat)
COMMAND=$(_fold "$(printf '%s' "$INPUT" | jq -r '.command')")

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

# a quoted heredoc ($(cat <<'EOF' ... EOF)) is literal text: nothing in it
# runs, so the command checks skip it. the gh text checks still put its body
# through the attribution and ascii scans, but not the substitution scan --
# markdown code spans want backticks. an unquoted heredoc expands, so only
# its opener is excused (GH_TEXT_HEREDOC_RE). newlines were folded to spaces,
# so the terminator line reads " EOF )".
GH_TEXT_QUOTED_HEREDOC_RE="\\\$\\(cat <<-?('([A-Za-z_]+)'|\"([A-Za-z_]+)\"|\\\\([A-Za-z_]+))"
_strip_quoted_heredocs() {
    local s=$1 open d before rest
    while [[ $s =~ $GH_TEXT_QUOTED_HEREDOC_RE ]]; do
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

# a substitution, subshell or group opens a new command: `$(git push)`,
# `(git reset --hard)` and `` `git tag v1` `` must anchor like a bare `git`.
# the bracket stays outside the inserted `;`, so a substitution is still
# visible in the arguments of the command that holds it. backticks alternate
# open / close; a `(` counts only where a command can start, so a regex group
# in a quoted pattern stays inert. the gh text checks read RAW_COMMAND -- a PR title's `feat(x):`
# must survive intact.
_split_substitutions() {
    local s=$1 out="" open=1
    while [[ "$s" == *'`'* ]]; do
        if ((open)); then out+="${s%%\`*}\` ; "; else out+="${s%%\`*} ; \`"; fi
        s=${s#*\`}
        open=$((!open))
    done
    printf '%s' "$out$s" | sed -E 's/(^|[ ;|&$<>])\(/\1( ; /g; s/\)/ ; )/g; s/  +/ /g'
}
RAW_COMMAND=$COMMAND
COMMAND=$(_split_substitutions "$(_strip_quoted_heredocs "$COMMAND")")

# `-c key=val` / `--config-env` overrides that neutralise the git-hook and
# signing layers, or define a one-shot alias that hides a subcommand from
# every anchor below (`git -c alias.p=push p`). `--exec-path=<dir>` swaps
# the remote helpers git runs. matched pre-strip -- the loop below erases
# exactly the evidence being looked for. -i: config keys are case-insensitive.
# known false positive: `git grep -c <key>` reads as an override.
GIT_CFG_KEYS="core\.hookspath|commit\.gpgsign|tag\.gpgsign|gpg\.program|clean\.requireforce|alias\."
if echo "$COMMAND" | grep -qiE -- "(^|[ ;|&])git [^;|&]*((-c ?|--config-env[= ])[\"']?(${GIT_CFG_KEYS})|--exec-path=)"; then
    echo "BLOCKED: command overrides hook / signing / clean-safety / alias / exec-path config -- ask the user if you really need to" >&2
    exit 2
fi

# the same layers, reached through the environment: config file locations,
# the repo location, the exec path, the ssh / proxy commands git runs, and
# PATH itself when git or gh is on the line (a shadowing git binary).
GIT_ENV_VARS="GIT_CONFIG[A-Z_]*|GIT_DIR|GIT_WORK_TREE|GIT_EXEC_PATH|GIT_SSH|GIT_SSH_COMMAND|GIT_PROXY_COMMAND|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|XDG_CONFIG_HOME|HOME"
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])(${GIT_ENV_VARS})="; then
    echo "BLOCKED: command overrides git's config / repo / exec environment -- ask the user if you really need to" >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])PATH=" && echo "$COMMAND" | grep -qE -- "(^|[ ;|&/])(git|gh)( |$)"; then
    echo "BLOCKED: command rewrites PATH around a git / gh call -- ask the user if you really need to" >&2
    exit 2
fi
# unsetting HOME / XDG_CONFIG_HOME drops git's global config (and its
# core.hooksPath) for a child -- the same layer the assignment check guards.
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])(env ([^;|&]* )?(-u ?|--unset[ =])|unset ([^;|&]* )?)(HOME|XDG_CONFIG_HOME)( |$)"; then
    echo "BLOCKED: command unsets HOME / XDG_CONFIG_HOME, dropping git's global config -- ask the user if you really need to" >&2
    exit 2
fi

# one-shot config that redirects or widens a push: remote.<r>.pushurl,
# url.<base>.pushInsteadOf, push.default=matching, branch.<b>.pushRemote.
# remotes are fixed for the agent (git remote / git config writes are fenced),
# so this stays fenced under every capability. matched pre-strip, same reason.
PUSH_CFG_KEYS="remote\.|url\.|push\.|branch\."
if echo "$COMMAND" | grep -qiE -- "(^|[ ;|&])git [^;|&]*(-c ?|--config-env[= ])[\"']?(${PUSH_CFG_KEYS})[^;|&]* push( |$)"; then
    echo "BLOCKED: command pushes under a one-shot remote / push config -- not liftable; push to a configured remote by name" >&2
    exit 2
fi

# glued forms included (-C/path, -ckey=val) -- a spaced-only strip would
# leave them sitting between `git` and the subcommand, dodging every anchor.
while :; do
    STRIPPED=$(printf '%s' "$COMMAND" | sed -E 's/(^|[ ;|&])git[[:space:]]+(-C[[:space:]]*[^[:space:]]+|-c[[:space:]]*[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path|config-env)[= ][^[:space:]]+|--no-pager|-P)[[:space:]]+/\1git /')
    [[ "$STRIPPED" == "$COMMAND" ]] && break
    COMMAND=$STRIPPED
done

# every `git <sub>` command on the line, one per output line, from `git` to
# the end of its `;` / `|` / `&` segment. <sub> is an ERE alternation; the
# word has to end after it, so `git checkout` never matches checkout-index.
_git_cmds() {
    _segments "$COMMAND" | grep -oE -- "(^| )git ($1)( .*|$)" | sed -E 's/^ //'
}

# destructive git ops. not recoverable, and not liftable by any capability.
# `git reset` (past --soft) and `git rebase` are handled separately below --
# see the history capability.
GIT_PATTERNS=(
    # force / interactive clean deletes untracked files; -n / -nd dry-runs stay allowed.
    "git clean ([^;|&]* )?(-[A-Za-z]*[fi]|--force|--interactive)"
    "git branch -D"
    "git merge( |$)"
    # pull = fetch + merge (or rebase) into the current branch
    "(^|[ ;|&])git pull( |$)"
    "git filter-branch"
    "git filter-repo"
    "git reflog (expire|delete)"
    # plumbing checkout: overwrites worktree files from the index
    "(^|[ ;|&])git checkout-index( |$)"
    # read-tree -u / --reset discards worktree edits; mv -f overwrites the dest
    "(^|[ ;|&])git read-tree ([^;|&]* )?(-[A-Za-z]*u[A-Za-z]*|--reset)( |$)"
    "(^|[ ;|&])git mv ([^;|&]* )?(--force|-[A-Za-z]*f[A-Za-z]*)( |$)"
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
    # special-case below -- see the push capability. `git tag` and
    # `git config` have read allowlists below.
    "(^|[ ;|&])git revert( |$)"
    "(^|[ ;|&])git am( |$)"
    # NOTE: `git apply` intentionally allowed -- a patch on the worktree is
    # no more than the Write tool, `sed -i` or `patch -p1` can already do,
    # and fencing it only got in the way of patching scratch clones.
    "(^|[ ;|&])git stash (drop|clear)"
    # remote config writes -- set-url could silently redirect the user's own
    # future pushes.
    "(^|[ ;|&])git remote (add|remove|rm|rename|set-url|set-head|set-branches|prune)"
    # commit plumbing: objects and refs written without the commit hooks.
    # `git replace` has its own case below -- its bare and -l forms list.
    "(^|[ ;|&])git commit-tree( |$)"
    "(^|[ ;|&])git notes (--ref[= ][^ ]+ +)*(add|append|copy|edit|merge|prune|remove)( |$)"
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
    # `git branch` has a read allowlist below.
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
# belongs here too but has its own per-command check below (the one `reset`
# form that touches neither index nor worktree), which also blocks every
# other reset under any capability.
HISTORY_PATTERNS=(
    "git rebase"
    "(^|[ ;|&])git cherry-pick( |$)"
)
HISTORY_REASON="git rebase / cherry-pick rewrite or duplicate commits -- user prevents this by default. (the user can lift this for a session with env AGENT_UNFENCE=history.)"

# wide `git add` -- agent must stage explicit paths, not sweep the worktree.
# blocks -A / --all / -u / --update / --no-ignore-removal (and short-flag
# clusters containing A or u, e.g. -Au, -Av), the `.` / `..` / `./` / `../`
# / `*` sweeps and the `:/` `:!` `:^` `:(` pathspec magic, wherever they sit in
# the add. pass file paths explicitly instead.
GIT_ADD_WIDE_RE=" (-[A-Za-z]*[Au][A-Za-z]*|--all|--update|--no-ignore-removal|\\.|\\.\\.|\\.\\.?/|\\*)( |$)| :[/!(^]"
GIT_ADD_REASON="stage explicit paths only -- wide \`git add\` may grab unrelated wip / scratch files"

# any write `gh` op. read ops (view/list/status/api GET) are fine.
GH_WRITE_PATTERNS=(
    # `gh pr create` / `gh pr edit` have their own special-case below -- see
    # the pr capability.
    "(^|[ ;|&])gh pr (comment|review|revert|close|reopen|ready|checkout|lock|unlock|update-branch)"
    # `co` is checkout under both its documented alias and gh's own top-level one
    "(^|[ ;|&])gh (pr )?co( |$)"
    # `gh issue create` / `gh issue edit` have their own special-case below --
    # see the issue capability.
    "(^|[ ;|&])gh issue (comment|close|reopen|lock|unlock|delete|pin|unpin|transfer)"
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

# NOTE: BLOCKED messages never echo the command back. the agent already has
# it, and a truncated echo hid the part that tripped the fence.
check() {
    local reason="$1"
    shift
    for pat in "$@"; do
        if echo "$COMMAND" | grep -qE -- "$pat"; then
            echo "BLOCKED: command matches '$pat'. $reason" >&2
            exit 2
        fi
    done
}

check "$GIT_REASON"       "${GIT_PATTERNS[@]}"
check "$GIT_WRITE_REASON" "${GIT_WRITE_PATTERNS[@]}"
_unfenced branch  || check "$BRANCH_REASON"  "${BRANCH_PATTERNS[@]}"
_unfenced history || check "$HISTORY_REASON" "${HISTORY_PATTERNS[@]}"
while IFS= read -r cmd; do
    args=" ${cmd#git add} "
    printf '%s' "${args//[\"\']/}" | grep -qE -- "$GIT_ADD_WIDE_RE" || continue
    echo "BLOCKED: $GIT_ADD_REASON" >&2
    exit 2
done < <(_git_cmds add)

# tag / branch / config: their read forms are a small closed set and their
# write forms are not, so these allow the known reads and block the rest. a
# read: every flag a known read flag (a value-taking one swallows the next
# token unless that is a flag), and at most <max> positionals -- any number
# once a listing flag is present.
_read_form() {
    local flags=$1 valued=$2 listing=$3 max=$4 tok toks want=0 skip=0 list=0 n=0
    read -ra toks <<< "$5"
    for tok in "${toks[@]}"; do
        tok=${tok//[\"\']/}
        if ((skip)); then
            skip=0
            continue
        fi
        # a redirect (`2>/dev/null`, `> f`) is the shell's, not an argument;
        # a bare operator takes the next token as its target.
        if [[ "$tok" =~ ^[0-9]*[\<\>] ]]; then
            [[ "$tok" =~ ^[0-9]*[\<\>]+$ ]] && skip=1
            continue
        fi
        if ((want)); then
            want=0
            [[ "$tok" == -* ]] || continue
        fi
        if [[ "$tok" == *"\$("* || "$tok" == *"\`"* ]]; then
            # a substitution expands to any number of arguments
            n=$((max + 1))
        elif [[ "$tok" != -* ]]; then
            ((n++))
        elif [[ "$tok" =~ ^($listing)$ ]]; then
            list=1
        elif [[ "$tok" =~ ^($valued)$ ]]; then
            want=1
        elif ! [[ "$tok" =~ ^($flags)$ ]]; then
            return 1
        fi
    done
    ((list || n <= max))
}

READ_LISTING_FLAGS="-i|--ignore-case|--color|--color=.*|--no-color|--column|--column=.*|--no-column|--omit-empty|--sort=.*|--format=.*|--contains=.*|--no-contains=.*|--merged=.*|--no-merged=.*|--points-at=.*"
READ_LISTING_VALUED="--contains|--no-contains|--merged|--no-merged|--points-at|--sort|--format"

while IFS= read -r cmd; do
    _read_form "-n|-n[0-9]+|$READ_LISTING_FLAGS" "$READ_LISTING_VALUED" "-l|--list|-v|--verify" 0 "${cmd#git tag}" && continue
    echo "BLOCKED: \`git tag\` writes or deletes a tag. $GIT_WRITE_REASON" >&2
    exit 2
done < <(_git_cmds tag)

if ! _unfenced branch; then
    while IFS= read -r cmd; do
        _read_form "-[arvqi]+|--all|--remotes|--verbose|--quiet|--show-current|--abbrev|--abbrev=.*|--no-abbrev|$READ_LISTING_FLAGS" \
            "$READ_LISTING_VALUED" "-l|--list" 0 "${cmd#git branch}" && continue
        echo "BLOCKED: $BRANCH_REASON" >&2
        exit 2
    done < <(_git_cmds branch)
fi

# config: the get / list verbs read and set / unset / rename-section /
# remove-section / edit write; otherwise one positional (a key) reads, two
# write, and a --get / --list style action makes every positional a read.
CONFIG_READ_FLAGS="--global|--system|--local|--worktree|--file=.*|--blob=.*|--type=.*|--default=.*|--bool|--int|--bool-or-int|--path|--expiry-date|-z|--null|--name-only|--show-origin|--show-scope|--includes|--no-includes|--fixed-value"
CONFIG_READ_ACTIONS="--get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|-l|--list"
while IFS= read -r cmd; do
    args=${cmd#git config}
    read -r verb _ <<< "${args//[\"\']/}"
    case "$verb" in
        (get|list) continue ;;
        (set|unset|rename-section|remove-section|edit) ;;
        (*) _read_form "$CONFIG_READ_FLAGS" "-f|--file|--blob|--type|--default" "$CONFIG_READ_ACTIONS" 1 "$args" && continue ;;
    esac
    echo "BLOCKED: \`git config\` writes config. $GIT_WRITE_REASON" >&2
    exit 2
done < <(_git_cmds config)

check "$GH_WRITE_REASON"  "${GH_WRITE_PATTERNS[@]}"

# `gh issue develop` creates a linked branch, but `--list` / `-l` only reads
# the existing ones. the flag has to sit in the same segment to count.
if echo "$COMMAND" | grep -qE -- "(^|[ ;|&])gh issue develop"; then
    if ! echo "$COMMAND" | grep -qE -- "gh issue develop[^;|&]* (--list|-l)( |$)"; then
        echo "BLOCKED: \`gh issue develop\` creates a branch. $GH_WRITE_REASON" >&2
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
    echo "BLOCKED: $GH_API_FIELD_REASON" >&2
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
_expands() {
    case "$1" in
        "~"*) return 0 ;;                          # tilde -- shell expands to home
        *'*'*|*'?'*|*'['*|*'$'*|*'`'*) return 0 ;; # glob / expansion
    esac
    return 1
}

_concrete_path() {
    _expands "$1" && return 1
    case "$1" in
        .|..) return 1 ;;                          # cwd sweep
        :*) return 1 ;;                            # pathspec magic
        */) return 1 ;;                            # explicit dir
    esac
    [[ ! -d "$1" ]]                                # dir sweep (best effort)
}

paths_concrete() {
    local n=0 tok toks
    # read -ra (not bare $1 expansion) so glob tokens are inspected
    # literally instead of being pathname-expanded by the shell.
    read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        case "$tok" in
            --|-S|-W|--staged|--worktree|-q|--quiet) continue ;;   # restore's own flags, and quiet
            -*) return 1 ;;                                        # unknown flag -- fail safe
        esac
        _concrete_path "$tok" || return 1
        ((n++))
    done
    ((n > 0))                                                      # at least one real path
}

# `git restore` -- allow index-only (--staged w/out --worktree, worktree
# untouched) and explicit-path discard; block broad forms.
while IFS= read -r seg; do
    args="${seg#git restore}"
    if [[ "$args" == *--staged* && "$args" != *--worktree* ]]; then
        continue
    fi
    if ! paths_concrete "$args"; then
        echo "BLOCKED: \`git restore\` discards more than named files. \`git restore <explicit-file-paths>\` is allowed -- no \`.\`, globs, dirs, or --source." >&2
        exit 2
    fi
done < <(_git_cmds restore)

# `git checkout` -- ONLY the explicit-path discard form `checkout [-q] -- <paths>`
# is allowed; -q changes nothing about what gets overwritten. branch switching,
# `-b`, `checkout <ref> -- <path>`, any other flag, and bare `checkout .` stay
# blocked. a refused line with ` -- ` in it was a path checkout, so it gets the
# path reason rather than the branch one.
CHECKOUT_PATH_REASON="a path checkout must be \`git checkout [-q] -- <explicit-file-paths>\` -- no other flags, no ref, no \`.\`, globs or dirs"
BRANCH_LIFT_REASON="the branch capability covers creating and switching branches only -- deleting, forcing or moving a branch, a forced or sweeping checkout, and removing a worktree stay user-run"
BRANCH_EXPANSION_REASON="expands at run time. checkout / switch take literal names only"

# the arguments of a checkout / switch the branch capability lifts: create
# and switch flags, branch names and named files. anything that forces,
# discards or sweeps (-B, -C, -f, --discard-changes, --ours, `.`, globs,
# dirs) or any unknown flag fails it, printing the offending token.
_switch_ok() {
    local tok toks dashdash=0
    read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        tok=${tok//[\"\']/}
        if ((!dashdash)); then
            case "$tok" in
                --) dashdash=1; continue ;;
                -|-b|-c|--create|-q|--quiet|-t|--track|--no-track|--detach|-d|-m|--merge|--orphan|--guess|--no-guess|-l) continue ;;
                -*) printf '%s' "$tok"; return 1 ;;
            esac
        fi
        _concrete_path "$tok" || { printf '%s' "$tok"; return 1; }
    done
    return 0
}

if _unfenced branch; then
    while IFS= read -r cmd; do
        bad=$(printf '%s' " ${cmd#git branch} " | grep -oE -- " (-[A-Za-z]*[dDfmMC][A-Za-z]*|--(delete|force|move))( |=)" | head -n1)
        if [[ -n "$bad" ]]; then
            bad=${bad# }
            echo "BLOCKED: \`git branch ${bad%[ =]}\`: $BRANCH_LIFT_REASON" >&2
            exit 2
        fi
    done < <(_git_cmds branch)
    while IFS= read -r cmd; do
        verb=checkout
        [[ "$cmd" == "git switch"* ]] && verb=switch
        bad=$(_switch_ok "${cmd#git "$verb"}") && continue
        if _expands "$bad"; then
            echo "BLOCKED: \`$bad\` $BRANCH_EXPANSION_REASON" >&2
        else
            echo "BLOCKED: \`git $verb $bad\`: $BRANCH_LIFT_REASON" >&2
        fi
        exit 2
    done < <(_git_cmds 'checkout|switch')
    bad=$(_git_cmds worktree | grep -oE -- "^git worktree (remove|move|prune)( |$)" | head -n1)
    if [[ -n "$bad" ]]; then
        echo "BLOCKED: \`${bad% }\`: $BRANCH_LIFT_REASON" >&2
        exit 2
    fi
fi

while IFS= read -r seg; do
    _unfenced branch && break
    args=$(printf '%s' "${seg#git checkout}" | sed -E 's/^( (-q|--quiet))+( |$)/ /')
    [[ "$args" == " -- "* ]] && paths_concrete "${args# -- }" && continue
    if [[ "$args" == *" -- "* ]]; then
        echo "BLOCKED: $CHECKOUT_PATH_REASON" >&2
    else
        echo "BLOCKED: $BRANCH_REASON" >&2
    fi
    exit 2
done < <(_git_cmds checkout)

# `git replace` with no arguments, -l or --list only lists; anything else
# rewrites what an object resolves to.
while IFS= read -r cmd; do
    args="${cmd#git replace}"
    [[ -z "${args// /}" ]] && continue
    printf '%s' "$args" | grep -qE -- "^ (-l|--list|--format=[^ ]*)( |$)" && continue
    echo "BLOCKED: \`git replace\` rewrites what objects resolve to. $GIT_WRITE_REASON" >&2
    exit 2
done < <(_git_cmds replace)

# `git rm` -- allow `--cached` (index-only), `-n` / `--dry-run` (preview) and
# named files: without -f git refuses a file whose content differs from HEAD,
# so what it deletes is recoverable. -f, -r and anything broader than named
# files stay blocked. flags count on that rm, not anywhere on the line.
while IFS= read -r cmd; do
    args=" ${cmd#git rm} "
    printf '%s' "$args" | grep -qE -- " (--cached|-n|--dry-run) " && continue
    paths_concrete "$args" && continue
    echo "BLOCKED: \`git rm\` past named files deletes local edits or sweeps a tree. \`git rm <explicit-file-paths>\` is allowed -- no -f, -r, \`.\`, globs or dirs." >&2
    exit 2
done < <(_git_cmds rm)

# `git reset` -- ONLY `--soft` is conditionally allowed (under the history
# capability): it moves the branch pointer but leaves index and worktree
# untouched, fully reflog-recoverable. `--hard`, `--mixed`, and bare
# `git reset` stay blocked always, capability or not -- they touch the
# index and/or worktree and are a different risk class.
# each reset is judged on its own: a --soft on one can't vouch for another,
# or for a --hard on the same line.
while IFS= read -r cmd; do
    args=" ${cmd#git reset} "
    args=${args//[\"\']/}
    if _unfenced history && [[ "$args" == *" --soft "* ]] &&
        ! printf '%s' "$args" | grep -qE -- " --(hard|mixed|merge|keep) "; then
        continue
    fi
    echo "BLOCKED: \`git reset\` is destructive past --soft. $GIT_REASON. (\`--soft\` alone is liftable with env AGENT_UNFENCE=history.)" >&2
    exit 2
done < <(_git_cmds reset)

# `git push` -- liftable with the push capability, minus the forms that rewrite
# or delete remote refs, skip the pre-push hook, push in bulk, or name a url or
# path instead of a configured remote. those stay fenced under every capability.
# the git pre-push hook draws the same line on the refs a push really sends,
# for the aliases and scripts this text match misses -- keep the two in step.
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
    "(CLAUDECODE|AGENT_SESSION|COPILOT_CLI|OPENCODE_PID)="
    "(^|[ ;|&])unset [^;|&]*(CLAUDECODE|AGENT_SESSION|COPILOT_CLI|OPENCODE_PID)"
    "(-u ?|--unset[ =])(CLAUDECODE|AGENT_SESSION|COPILOT_CLI|OPENCODE_PID)"
    # -i, a bare -, or -i inside a short-flag cluster: an emptied environment.
    "(^|[ ;|&])env( [^;|&]*)? (-[A-Za-z0-9]*i[A-Za-z0-9]*|-|--ignore-environment)( |$)"
    # export -n drops the export attribute; fish `set -e` / --erase erases it.
    "(^|[ ;|&])export -n [^;|&]*(CLAUDECODE|AGENT_SESSION|COPILOT_CLI|OPENCODE_PID)"
    "(^|[ ;|&])set ([^;|&]* )?(-[A-Za-z]*e[A-Za-z]*|--erase) [^;|&]*(CLAUDECODE|AGENT_SESSION|COPILOT_CLI|OPENCODE_PID)"
)
MARKER_REASON="agent session markers are not yours to unset or rewrite -- the git hooks read them"

# a url or path where a remote name belongs. remotes are fixed for the agent
# (git remote / git config writes are fenced), so a literal target is the only
# way left to push somewhere the user did not configure. an unambiguous url or
# scp-style host:path is never a remote wherever it sits (so a second push
# folded into the segment is still caught); the first positional is the remote,
# where a bare relative path or host:colon also disqualifies it, while the
# refspecs that follow keep their own colons and slashes. redirect targets and
# the value of -o are files, not remotes -- skipped.
_push_names_url() {
    local tok toks skip=0 seen_remote=0
    read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        if ((skip)); then skip=0; continue; fi
        case "$tok" in
            (\>|\>\>|[0-9]\>|[0-9]\>\>|\<|[0-9]\<) skip=1; continue ;;
            (*\>*|\<*) continue ;;
            # -o / --push-option take a value; -o may end a short cluster (-uo)
            (-o|-[A-Za-z]*o|--push-option|--receive-pack|--exec|--repo) skip=1; continue ;;
            (-*) continue ;;
            # @{u} / @{upstream} is a reflog ref, not a user@host:path url
            (*@\{*) ;;
            (*://*|*@*:*) return 0 ;;
        esac
        if ((!seen_remote)); then
            seen_remote=1
            # the remote slot: a path, a url, an scp host:path, a .git repo or a
            # bare . / .. is not a configured remote name
            case "$tok" in (*:*|*/*|"~"*|*.git|.|..) return 0 ;; esac
        fi
    done
    return 1
}

check "$PUSH_PLUMBING_REASON" "${PUSH_PLUMBING_PATTERNS[@]}"
check "$MARKER_REASON"        "${MARKER_PATTERNS[@]}"

while IFS= read -r seg; do
    args="${seg#*git push}"
    plain=${args//[\"\']/}
    if echo "$plain" | grep -qE -- "${PUSH_HARD_FLAG_RE}|${PUSH_HARD_SHORT_RE}|${PUSH_HARD_REFSPEC_RE}" || _push_names_url "$plain"; then
        echo "BLOCKED: $PUSH_HARD_REASON" >&2
        exit 2
    fi
    if ! _unfenced push; then
        echo "BLOCKED: $PUSH_REASON" >&2
        exit 2
    fi
    if echo "$args" | grep -qE -- "$PUSH_SUBST_RE"; then
        echo "BLOCKED: git push arguments must be literal (no \$(...), backticks or variables); git push origin HEAD names the current branch" >&2
        exit 2
    fi
done < <(_git_cmds push)

# `gh pr create` / `gh issue create`, and `gh pr edit` / `gh issue edit` of
# the title and body -- liftable with the pr / issue capability. the target
# is the current repo (no -R / --repo, no GH_REPO), a PR's title (inline, or
# the first line of a heredoc) opens with a conventional commits prefix, and
# the body -- inline or a file -- is ascii with no agent attribution: the
# line commit-msg draws, drawn here
# because no git hook sees a PR or issue body. text reaches gh only as literal
# command text or as an absolute regular file this policy can read too -- a
# substitution or a variable would hand gh content it never saw. the inline
# heredoc is the one allowed substitution, since its text is in the command.
# an edit touches the title and body (the pr / issue capability) and the
# labels (the labels capability, or pr for a PR): reviewers, assignees,
# milestone and the base branch stay user-run.
#
# gh's short flags glue their value (-tfoo) and stack behind the booleans
# (-dwt foo), hence -[<bools>]* before each one; the booleans differ per
# command (pr create: -d -f -w, issue create: -w -e, edit: none).
GH_TEXT_TYPES="feat|fix|docs|test|refactor|chore|bench|revert|ci|perf|release"
GH_TEXT_ATTRIBUTION_RE="co-authored-by|generated with"
GH_TEXT_NON_ASCII_RE=$'[^\t -~]'
GH_TEXT_HEREDOC_RE='\$\(cat <<-?["'"'"']?[A-Za-z_]+["'"'"']?'
# $'...' is in the list: its escapes rebuild a banned string byte by byte.
GH_TEXT_SUBST_RE='\$\(|`|\$\{|\$[A-Za-z_]|\$'"'"
GH_TEXT_ENV_RE="(^|[^A-Za-z0-9_])GH_(REPO|HOST|TOKEN|ENTERPRISE_TOKEN|CONFIG_DIR)="
GH_TEXT_QUOTED_RE="\"[^\"]*\"|'[^']*'"

_gh_text_block() {
    echo "BLOCKED: $1" >&2
    exit 2
}

# _gh_text <what: pr|issue> <sub: create|edit> <bool-shorts> <conventional-title: 0|1> <strict-flags: 0|1>
# the capability named after <what> covers the text; labels on an edit come
# from the labels capability, or from pr for a PR.
_gh_text() {
    local what=$1 sub=$2 bools=$3 conventional=$4 strict=$5 seg bodyfile sp tok toks
    local COMMAND=$RAW_COMMAND
    local seg_re="(^|[ ;|&(\`])gh $what $sub( [^;|&]*|$)"
    local text_ok=0 labels_ok=0
    if [ -n "$bools" ]; then sp="-[$bools]*"; else sp="-"; fi
    local title_re="(^| )(${sp}t[ =]?|--title[= ])[\"']?(${GH_TEXT_HEREDOC_RE} )?(${GH_TEXT_TYPES})(\([a-z0-9._-]+\))?(!|\?)?: "
    echo "$COMMAND" | grep -qE -- "$seg_re" || return 0
    _unfenced "$what" && text_ok=1
    _unfenced labels && labels_ok=1
    [ "$what" = pr ] && [ "$text_ok" = 1 ] && labels_ok=1
    if [ "$sub" = create ]; then
        [ "$text_ok" = 1 ] || _gh_text_block "gh $what create is user-run. (the user can lift it for a session with env AGENT_UNFENCE=$what.)"
    else
        [ "$text_ok" = 1 ] || [ "$labels_ok" = 1 ] || _gh_text_block "gh $what edit is user-run. (the user can lift it for a session with env AGENT_UNFENCE=$what for the title and body, or AGENT_UNFENCE=labels for labels.)"
    fi
    while IFS= read -r seg; do
        if echo "$seg" | grep -qE -- " (${sp}R|--repo)"; then
            _gh_text_block "gh $what $sub targets the current repo -- no -R / --repo"
        fi
        if echo "$seg" | grep -qE -- " --recover"; then
            _gh_text_block "--recover replays a title and body this policy cannot read -- pass them explicitly"
        fi
        if [ "$conventional" = 1 ] && echo "$seg" | grep -qE -- " (${sp}t|--title)" && ! echo "$seg" | grep -qE -- "$title_re"; then
            _gh_text_block "PR title must open with a lowercase conventional commits prefix (feat:, fix:, docs:, ...) -- inline, or on the first line of a quoted heredoc"
        fi
        if echo "$seg" | grep -qE -- " (${sp}F|--body-file)"; then
            bodyfile=$(printf '%s' "$seg" | sed -E "s/.* (${sp}F|--body-file)[= ]?[\"']?([^\"' ]*).*/\2/")
            [[ "$bodyfile" == /* && -f "$bodyfile" && -r "$bodyfile" ]] || _gh_text_block "body file must be an absolute path to a readable regular file (got '${bodyfile}')"
            grep -qiE -- "$GH_TEXT_ATTRIBUTION_RE" "$bodyfile" && _gh_text_block "body file carries agent attribution (Co-Authored-By / Generated with) -- drop it"
            LC_ALL=C grep -qE -- "$GH_TEXT_NON_ASCII_RE" "$bodyfile" && _gh_text_block "body file must be ascii only"
        fi
    done < <(printf '%s' "$COMMAND" | grep -oE -- "$seg_re")
    # title, body and labels only, each behind its capability: with the
    # quoted text gone (a quoted span is one argument to gh, whatever it
    # contains), every flag left must be one of those. a lone - or -- is
    # markdown, not a flag.
    if [ "$strict" = 1 ]; then
        while IFS= read -r seg; do
            read -ra toks <<< "${seg#*gh "$what" "$sub"}"
            for tok in "${toks[@]}"; do
                case "$tok" in
                    (-|--) ;;
                    (-t*|--title|--title=*|-b*|--body|--body=*|-F*|--body-file|--body-file=*)
                        [ "$text_ok" = 1 ] || _gh_text_block "the title and body of a $what need AGENT_UNFENCE=$what -- labels alone does not cover $tok" ;;
                    (--add-label|--add-label=*|--remove-label|--remove-label=*)
                        [ "$labels_ok" = 1 ] || _gh_text_block "labels need AGENT_UNFENCE=labels (or pr, for a PR) -- $what alone does not cover $tok" ;;
                    (-*) _gh_text_block "gh $what $sub changes the title, body and labels only -- not $tok" ;;
                esac
            done
        done < <(_strip_quoted_heredocs "$COMMAND" | sed -E "s/${GH_TEXT_QUOTED_RE}//g" | grep -oE -- "$seg_re")
    fi
    printf '%s' "$COMMAND" | grep -qE -- "$GH_TEXT_ENV_RE" && _gh_text_block "gh env overrides (GH_REPO, GH_HOST, GH_TOKEN, ...) are not yours"
    _strip_quoted_heredocs "$COMMAND" | sed -E "s/${GH_TEXT_HEREDOC_RE}//g" | grep -qE -- "$GH_TEXT_SUBST_RE" && _gh_text_block "gh $what $sub text must be literal -- no \$(...), backticks or variables; put the title or body in a quoted heredoc (\$(cat <<'EOF' ... EOF)), where backticks and \$ are plain text"
    printf '%s' "$COMMAND" | grep -qiE -- "$GH_TEXT_ATTRIBUTION_RE" && _gh_text_block "text carries agent attribution (Co-Authored-By / Generated with) -- drop it"
    printf '%s' "$COMMAND" | LC_ALL=C grep -qE -- "$GH_TEXT_NON_ASCII_RE" && _gh_text_block "text must be ascii only (no emoji, em-dash, smart quotes)"
}

_gh_text pr    create dfw 1 0
_gh_text pr    edit   ""  1 1
_gh_text issue create we  0 0
_gh_text issue edit   ""  0 1

check "$GPG_REASON"       "${GPG_PATTERNS[@]}"
check "$INSTALL_REASON"   "${INSTALL_PATTERNS[@]}"
_unfenced remote  || check "$REMOTE_REASON"  "${REMOTE_PATTERNS[@]}"

exit 0
