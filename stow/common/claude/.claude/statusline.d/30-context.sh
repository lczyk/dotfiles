#!/usr/bin/env bash
# context-window usage badge. prints [ctx N%] coloured by usage level.
# silent before first api call or when context_window data is absent.

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if command -v jq >/dev/null 2>&1; then
    used=$(printf '%s' "$INPUT" | jq -r '
        .context_window.used_percentage //
        if (.context_window.current_usage.input_tokens != null
            and .context_window.context_window_size != null)
        then
            ((.context_window.current_usage.input_tokens
              + (.context_window.current_usage.cache_creation_input_tokens // 0)
              + (.context_window.current_usage.cache_read_input_tokens // 0))
             / .context_window.context_window_size * 100) | floor
        else empty
        end // empty
    ' 2>/dev/null)
else
    used=$(printf '%s' "$INPUT" \
        | tr '\n' ' ' \
        | sed -n 's/.*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
fi

case "$used" in
    ''|*[!0-9.]*) exit 0 ;;
esac
used=${used%%.*}
[ -z "$used" ] && exit 0

if [ "$used" -ge 80 ]; then
    colour='\033[38;5;196m'
elif [ "$used" -ge 50 ]; then
    colour='\033[38;5;214m'
else
    colour='\033[38;5;71m'
fi

printf "${colour}[ctx %d%%]\033[0m" "$used"
