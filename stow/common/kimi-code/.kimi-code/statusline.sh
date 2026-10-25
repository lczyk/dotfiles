#!/usr/bin/env bash
# Kimi statusline adapter. Normalize the native snapshot to the Claude badge
# contract, then run every executable in statusline.d in lex order and join
# non-empty stdout results with a single space.

CONFIG_DIR="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
BADGE_DIR="$CONFIG_DIR/statusline.d"

RAW_INPUT=$(cat)
[ -z "$RAW_INPUT" ] && exit 0

INPUT=$(printf '%s' "$RAW_INPUT" | jq -ce '
    . as $kimi
    | if ($kimi.model | type) != "string" or ($kimi.cwd | type) != "string"
      then empty
      else
          $kimi + {
              model: {display_name: $kimi.model},
              context_window: (
                  if ($kimi.contextTokens | type) == "number"
                      and ($kimi.maxContextTokens | type) == "number"
                      and $kimi.maxContextTokens > 0
                  then
                      {used_percentage: ($kimi.contextTokens / $kimi.maxContextTokens * 100)}
                  elif ($kimi.contextUsage | type) == "number" then
                      {used_percentage: ($kimi.contextUsage * 100)}
                  else
                      {}
                  end
              )
          }
      end
' 2>/dev/null) || exit 0

function main() {
    [ -d "$BADGE_DIR" ] || return 0

    local first=1
    local script out
    for script in "$BADGE_DIR"/*; do
        [ -f "$script" ] && [ -x "$script" ] || continue
        out=$(printf '%s' "$INPUT" | "$script" 2>/dev/null)
        [ -z "$out" ] && continue
        if [ "$first" -eq 1 ]; then
            first=0
        else
            printf ' '
        fi
        printf '%s' "$out"
    done
}

main "$@"
