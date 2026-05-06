#!/usr/bin/env bash
# usage badge. shows [N%] with progressive green->red gradient (rate-limit %
# or context-window %), falling back to [$N.NN] session cost when no % is
# available (e.g. some non-Anthropic providers).

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if command -v jq >/dev/null 2>&1; then
    pct=$(printf '%s' "$INPUT" | jq -r '
        .rate_limits.five_hour.used_percentage //
        .context_window.used_percentage   //
        empty
    ' 2>/dev/null)
    cost=$(printf '%s' "$INPUT" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
else
    pct=$(printf '%s' "$INPUT" \
        | tr '\n' ' ' \
        | sed -n 's/.*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    cost=$(printf '%s' "$INPUT" \
        | tr '\n' ' ' \
        | sed -n 's/.*"total_cost_usd"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p')
fi

# -- percentage path: progressive green->yellow->red (0%=green, 50%=yellow, 100%=red)
case "$pct" in
    ''|*[!0-9.]) ;;
    *)
        pct=${pct%%.*}
        if [ -n "$pct" ]; then
            [ "$pct" -gt 100 ] && pct=100

            if [ "$pct" -le 50 ]; then
                r=$(( pct * 255 / 50 ))
                g=255
            else
                r=255
                g=$(( (100 - pct) * 255 / 50 ))
            fi
            b=0
            printf '\033[38;2;%d;%d;%dm[%d%%]\033[0m' "$r" "$g" "$b" "$pct"
            exit 0
        fi
        ;;
esac

# -- cost fallback: fixed colour, 2 decimal places
case "$cost" in
    ''|*[!0-9.]*) exit 0 ;;
esac

printf -v cost_fmt '%.2f' "$cost" 2>/dev/null || cost_fmt="$cost"
[ -z "$cost_fmt" ] && exit 0

printf '\033[38;5;71m[$%s]\033[0m' "$cost_fmt"
