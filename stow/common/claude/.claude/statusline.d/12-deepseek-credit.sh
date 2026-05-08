#!/usr/bin/env bash
# deepseek credit badge. calls /user/balance, caches for 120s. silent for
# non-deepseek models or when ANTHROPIC_AUTH_TOKEN is unset.
#
# cache file: $XDG_CACHE_HOME/claude-deepseek-balance (falls back to /tmp)

# only when deepseek is configured via env vars
[ -z "$ANTHROPIC_AUTH_TOKEN" ] && exit 0
case "${ANTHROPIC_BASE_URL:-}" in
    *deepseek*) ;;
    *) case "${ANTHROPIC_MODEL:-}" in
           deepseek*) ;;
           *) exit 0 ;;
       esac ;;
esac

# alt: detect from the statusline json payload instead of env vars. lets you
# show credit even when ANTHROPIC_BASE_URL / ANTHROPIC_MODEL aren't exported
# (the model id in the payload still reflects the active provider).
#
# INPUT=$(cat)
# if command -v jq >/dev/null 2>&1; then
#     model_id=$(printf '%s' "$INPUT" | jq -r '.model.id // empty' 2>/dev/null)
# else
#     model_id=$(printf '%s' "$INPUT" | tr '\n' ' ' \
#         | sed -n 's/.*"model"[^{]*{[^}]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# fi
# case "$model_id" in
#     deepseek*) ;;
#     *) exit 0 ;;
# esac

CACHE_DIR="${XDG_CACHE_HOME:-/tmp}"
CACHE_FILE="$CACHE_DIR/claude-deepseek-balance"
CACHE_TTL=120

now=$(date +%s)

balance=""
if [ -f "$CACHE_FILE" ]; then
    cache_ts=$(stat -f '%m' "$CACHE_FILE" 2>/dev/null || stat -c '%Y' "$CACHE_FILE" 2>/dev/null)
    if [ -n "$cache_ts" ] && [ "$(( now - cache_ts ))" -lt "$CACHE_TTL" ]; then
        balance=$(cat "$CACHE_FILE" 2>/dev/null)
    fi
fi

if [ -z "$balance" ]; then
    resp=$(curl -s --max-time 5 "https://api.deepseek.com/user/balance" \
        -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" 2>/dev/null)
    if command -v jq >/dev/null 2>&1; then
        balance=$(printf '%s' "$resp" | jq -r '
            .balance_infos[0].total_balance // empty
        ' 2>/dev/null)
    else
        balance=$(printf '%s' "$resp" \
            | sed -n 's/.*"total_balance"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi
    if [ -n "$balance" ]; then
        printf '%s' "$balance" > "$CACHE_FILE"
    fi
fi

case "$balance" in
    ''|*[!0-9.]*) exit 0 ;;
esac

# colour: green >= 5, yellow >= 1, red < 1
if [ "$(printf '%.0f' "$balance" 2>/dev/null || echo 0)" -ge 5 ]; then
    printf '\033[38;5;71m[$%s]\033[0m' "$balance"
elif [ "$(printf '%.0f' "$balance" 2>/dev/null || echo 0)" -ge 1 ]; then
    printf '\033[38;5;214m[$%s]\033[0m' "$balance"
else
    printf '\033[38;5;196m[$%s]\033[0m' "$balance"
fi
