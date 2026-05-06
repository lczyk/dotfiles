#!/usr/bin/env bash
# git branch badge. prints [<pwd>/<branch>] for the cwd of the claude session,
# or [<pwd>/<branch>(N)] when N > 0 changed files (staged + unstaged combined).
# silent when not in a git repo or when git is unavailable.

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

pwd_name=$(basename "$cwd")
pwd_name=$(printf '%s' "$pwd_name" | tr -cd 'A-Za-z0-9/_.-' | head -c 40)

dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c '^')

if [ "$dirty" -gt 0 ]; then
    printf '\033[38;5;139m[%s/%s(%d)]\033[0m' "$pwd_name" "$branch" "$dirty"
else
    printf '\033[38;5;139m[%s/%s]\033[0m' "$pwd_name" "$branch"
fi
