#!/usr/bin/env bash
# model-name badge. prints [<model-display-name>] from the json payload claude
# code pipes on stdin. silent when stdin is empty or the field is missing.

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if command -v jq >/dev/null 2>&1; then
    name=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // empty' 2>/dev/null)
else
    name=$(printf '%s' "$INPUT" \
        | tr '\n' ' ' \
        | sed -n 's/.*"model"[^{]*{[^}]*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# whitelist + length cap. blocks ansi-escape injection if a future claude build
# ever surfaces user-controlled strings in the model field.
name=$(printf '%s' "$name" | tr -cd 'A-Za-z0-9 ._-' | head -c 32)
[ -z "$name" ] && exit 0

printf '\033[38;5;39m[%s]\033[0m' "$name"
