#!/usr/bin/env bash
# Shell/write policy. the agent safety hooks -- and the harness config that
# wires them in -- are not agent-editable: a fence the agent can rewrite is not
# a fence. exit 2 means policy denial; evaluate.sh translates that into a
# harness-neutral verdict.
#
# request channels:
#   - write: normalized destination paths supplied in write_paths.
#   - shell: any `;|&` segment naming a protected path that is not a plain
#            read (redirects and non-allowlisted commands both deny).
#
# opt out with the `meta` capability -- see _unfenced.
#
# TODO(lczyk): the shell side is a read-allowlist over crude segments, not a
# shell parser. still walks past it:
#   - $VAR-built or $(...)-built paths
#   - cd ~/.claude/hooks then a relative edit
#   - writes from inside an interpreter (python3 -c "open(...,'w')")
#   - `git -C <path> diff <hook>` -- global options before a read subcommand
#     read as unknown and deny (fail-safe, but noisy)

INPUT=$(cat)
OPERATION=$(printf '%s' "$INPUT" | jq -r '.operation')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.command // empty')

# fold line wraps and whitespace runs -- same fold as the sibling policies,
# kept inline so a missing helper can't turn this into a no-op.
COMMAND=$(printf '%s' "$COMMAND" | sed -E 's/\\$//' | tr '\n\t' '  ' | sed -E 's/  +/ /g')

# expand the two home shorthands so `~/.claude/hooks/x` and `$HOME/.claude/...`
# compare against the absolute globs below.
COMMAND=${COMMAND//\$HOME/$HOME}
COMMAND=${COMMAND//\{HOME\}/$HOME}
COMMAND=${COMMAND//\~\//$HOME/}

# capability opt-outs, comma-separated, read from this process's OWN
# environment (`env AGENT_UNFENCE=meta claude`). an agent cannot grant itself
# one: a command's env-prefix reaches this policy as text on stdin, never as
# an actual variable. kept inline in each policy for the same reason as the
# fold above.
function _unfenced() {
    case ",${AGENT_UNFENCE}," in
        (*",$1,"*) return 0 ;;
    esac
    return 1
}

_unfenced meta && exit 0

# installed locations first, then their dotfiles sources. both families are
# needed: an installed path is a symlink into the source tree, but a file that
# does not exist yet resolves to nothing, so it only ever matches the
# installed form. source globs are anchored on the stow package layout rather
# than an absolute prefix, so a second clone or a worktree is covered too.
PROTECTED_GLOBS=(
    "$HOME/.config/agent-hooks"
    "$HOME/.config/agent-hooks/*"
    "$HOME/.config/git/hooks"
    "$HOME/.config/git/hooks/*"
    "$HOME/.claude/hooks"
    "$HOME/.claude/hooks/*"
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
    # project-level claude settings, any repo: their env block feeds future
    # sessions, so a persisted AGENT_UNFENCE there would be a self-grant.
    # relative forms cover shell tokens when cwd is the repo root.
    '*/.claude/settings.json'
    '*/.claude/settings.local.json'
    '.claude/settings.json'
    '.claude/settings.local.json'
    "$HOME/.codex/hooks"
    "$HOME/.codex/hooks/*"
    "$HOME/.codex/hooks.json"
    "$HOME/.copilot/hooks"
    "$HOME/.copilot/hooks/*"
    '*/stow/common/agent-hooks/.config/agent-hooks'
    '*/stow/common/agent-hooks/.config/agent-hooks/*'
    '*/stow/common/git/.config/git/hooks'
    '*/stow/common/git/.config/git/hooks/*'
    '*/stow/common/claude/.claude/hooks'
    '*/stow/common/claude/.claude/hooks/*'
    '*/stow/common/claude/.claude/settings.json'
    '*/stow/common/codex/.codex/hooks'
    '*/stow/common/codex/.codex/hooks/*'
    '*/stow/common/codex/.codex/hooks.json'
    '*/stow/common/copilot/.copilot/hooks'
    '*/stow/common/copilot/.copilot/hooks/*'
)

# commands that cannot modify their arguments. deliberately excludes the ones
# that can write to a path they were only "reading": sed (-i), awk (print >),
# and every interpreter. find sits in its own branch below -- a read until
# -delete / -exec and friends make it a write.
READ_CMDS="ls|cat|bat|head|tail|less|more|grep|rg|egrep|fgrep|wc|stat|file|diff|cmp|readlink|realpath|dirname|basename|shellcheck|shfmt|bats|shasum|md5|md5sum|sha256sum"
GIT_READ_SUBCMDS="diff|show|log|blame|status|ls-files|grep|cat-file|rev-parse"
FIND_WRITE_RE="(^| )-(delete|exec|execdir|ok|okdir|fls|fprint0?|fprintf)( |$)"

bad=()
excused=()

function _protected() {
    local path="$1" glob
    [[ -z "$path" ]] && return 1
    for glob in "${PROTECTED_GLOBS[@]}"; do
        # shellcheck disable=SC2254  # $glob is a pattern; quoting would kill it
        case "$path" in ($glob) return 0 ;; esac
    done
    return 1
}

# a path may arrive as the symlink in $HOME or as the file in the dotfiles
# checkout. resolve when we can, and judge both forms -- readlink -f prints
# nothing for a path that does not exist yet, which is exactly the create-a-
# new-hook case the raw form has to cover.
function _protected_either() {
    local path="$1" resolved
    _protected "$path" && return 0
    resolved=$(readlink -f "$path" 2>/dev/null)
    [[ -n "$resolved" ]] && _protected "$resolved"
}

# -- normalized write destinations --------------------------------------
if [[ "$OPERATION" == write ]]; then
    while IFS= read -r path; do
        _protected_either "$path" && bad+=("$path")
    done < <(printf '%s' "$INPUT" | jq -r '.write_paths[]')
fi

# strip a glued redirect and any surrounding quotes, then judge the token.
function _bare_token() {
    local tok="$1"
    tok=${tok##*>}
    tok=${tok#[\"\']}
    tok=${tok%[\"\']}
    printf '%s' "${tok%/}"
}

# the first token that is neither an env assignment nor a wrapper nor a flag,
# reduced to its basename so /usr/bin/cat reads as cat.
function _leading_cmd() {
    local seg="$1" tok toks
    read -ra toks <<< "$seg"
    for tok in "${toks[@]}"; do
        case "$tok" in
            (*=*) ;;
            (sudo | command | env | exec | time | nohup | builtin) ;;
            (-*) ;;
            (*) printf '%s' "${tok##*/}"; return ;;
        esac
    done
}

# -- shell command -------------------------------------------------------
# allowlist, not blocklist: an unrecognised command touching a hook denies.
if [[ "$OPERATION" == shell && -n "$COMMAND" ]]; then
    # unstow removes the fence's symlinks without naming a protected path,
    # so the token checks below never see it. restow and plain stow re-link
    # the same tree and stay allowed.
    if printf '%s' "$COMMAND" |
        grep -qE -- "(^|[ ;|&])(make [^;|&]*unstow|stow[^;|&]*( -[a-zA-Z]*D|--delete))"; then
        bad+=("unstow (removes the fence symlinks)")
    fi

    # shellcheck disable=SC2020  # a char-set mapping is the intent
    SEGMENTS=$(printf '%s' "$COMMAND" | tr ';|&' '\n\n\n')

    while IFS= read -r seg; do
        hits=()
        read -ra toks <<< "$seg"
        for tok in "${toks[@]}"; do
            tok=$(_bare_token "$tok")
            # only path-shaped tokens. without this, readlink resolves every
            # bare word against the cwd, and `ls` run from inside a protected
            # directory would deny itself.
            [[ "$tok" == */* ]] || continue
            _protected_either "$tok" && hits+=("$tok")
        done
        ((${#hits[@]})) || continue

        # a redirect anywhere in the segment outweighs any allowlisted
        # command leading it -- `cat x > <hook>` is a write.
        if [[ "$seg" != *">"* ]]; then
            leading=$(_leading_cmd "$seg")
            if [[ "$leading" == git ]]; then
                if printf '%s' "$seg" |
                    grep -qE -- "(^| )git +(${GIT_READ_SUBCMDS})( |$)"; then
                    excused+=("${hits[@]}")
                    continue
                fi
            elif [[ "$leading" == find ]]; then
                if ! printf '%s' "$seg" | grep -qE -- "$FIND_WRITE_RE"; then
                    excused+=("${hits[@]}")
                    continue
                fi
            elif printf '%s' "$leading" | grep -qE -- "^(${READ_CMDS})$"; then
                excused+=("${hits[@]}")
                continue
            fi
        fi
        bad+=("${hits[@]}")
    done <<< "$SEGMENTS"

    # a read's excuse doesn't survive piping into a command runner -- the
    # protected path crosses the pipe as text and comes back as an argument
    # (`ls <dir> | xargs rm`).
    if ((${#excused[@]})) &&
        printf '%s' "$COMMAND" | grep -qE -- "(^|[ ;|&])(xargs|parallel)( |$)"; then
        bad+=("${excused[@]}")
    fi
fi

if ((${#bad[@]})); then
    {
        printf 'BLOCKED: agent safety hooks are not agent-editable:\n\n'
        for t in "${bad[@]}"; do printf '    %s\n' "$t"; done
        printf '\na fence the agent can rewrite is not a fence -- this covers the policy\n'
        printf 'scripts, the harness adapters, the git hooks, and the settings that wire\n'
        printf 'them in, in both ~/ and the dotfiles checkout.\n\n'
        printf 'if the user asked for a hook change, they relaunch with the meta\n'
        printf 'capability: env AGENT_UNFENCE=meta <agent>. until then, say what you\n'
        printf 'would have changed and stop. reads via the Read tool are unaffected.\n'
    } >&2
    exit 2
fi

exit 0
