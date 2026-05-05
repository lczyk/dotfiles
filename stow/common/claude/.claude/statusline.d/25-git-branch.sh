#!/usr/bin/env bash
# git branch badge. prints [<branch>] for the cwd of the claude session.
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

printf '\033[38;5;139m[%s]\033[0m' "$branch"
