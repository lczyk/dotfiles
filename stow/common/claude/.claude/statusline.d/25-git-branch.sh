#!/usr/bin/env bash
# git branch badge. prints [<repo>/<subpath>/<branch>] for the cwd of the
# claude session, or [...(N)] when N > 0 changed files (staged + unstaged
# combined). <repo> is the repo-root dir name; <subpath> is the path within
# the repo (omitted at the root). silent outside a git repo or w/out git.

# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

INPUT=$(cat)

if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
cwd="${cwd:-$PWD}"

command -v git >/dev/null 2>&1 || exit 0

branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
[ -z "$branch" ] && exit 0

branch=$(printf '%s' "$branch" | tr -cd 'A-Za-z0-9/_.-' | head -c 40)
[ -z "$branch" ] && exit 0

# show the repo-root dir name plus the path within the repo, so a subdir
# still reads as <root>/<subpath> rather than just the leaf basename.
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$root" ]; then
    prefix=$(git -C "$cwd" rev-parse --show-prefix 2>/dev/null)
    prefix=${prefix%/}
    pwd_name="$(basename "$root")${prefix:+/$prefix}"
else
    pwd_name=$(basename "$cwd")
fi
pwd_name=$(printf '%s' "$pwd_name" | tr -cd 'A-Za-z0-9/_.-')
# fish-style abbreviation: keep the first (repo root) and last (current dir)
# components full, shorten each middle one to its first char (preserving a
# leading dot, like fish). e.g. dotfiles/stow/common/claude/.claude -> dotfiles/s/c/c/.claude
IFS=/ read -ra _parts <<< "$pwd_name"
_n=${#_parts[@]}
pwd_name=""
for ((_i = 0; _i < _n; _i++)); do
    _p=${_parts[_i]}
    if ((_i > 0 && _i < _n - 1)); then
        case $_p in
            .*) _p=".${_p:1:1}" ;;
            *)  _p=${_p:0:1} ;;
        esac
    fi
    pwd_name="${pwd_name:+$pwd_name/}$_p"
done

dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c '^')

if [ "$dirty" -gt 0 ]; then
    sl_paint '5;139' "[$pwd_name/$branch($dirty)]"
else
    sl_paint '5;139' "[$pwd_name/$branch]"
fi
