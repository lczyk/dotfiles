#!/usr/bin/env bash
# caveman-badge wrapper. finds the latest installed caveman plugin cache and
# execs its statusline script. silent no-op when caveman isn't installed.
#
# the plugin cache path is versioned (.../caveman/caveman/<hash>/...) and the
# hash changes on plugin upgrade. picking newest-mtime here means we don't
# need a settings.json edit when caveman updates.

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_GLOB="$CONFIG_DIR/plugins/cache/caveman/caveman/*/hooks/caveman-statusline.sh"

# find newest matching script. nullglob avoids the literal-glob fallback so we
# bail cleanly when caveman is absent.
shopt -s nullglob
candidates=($CACHE_GLOB)
shopt -u nullglob

[ "${#candidates[@]}" -eq 0 ] && exit 0

latest=""
latest_mtime=0
for path in "${candidates[@]}"; do
    [ -f "$path" ] || continue
    # NOTE: stat -f on bsd/mac, stat -c on gnu. try bsd form first, fall back.
    mtime=$(stat -f '%m' "$path" 2>/dev/null || stat -c '%Y' "$path" 2>/dev/null)
    [ -z "$mtime" ] && continue
    if [ "$mtime" -gt "$latest_mtime" ]; then
        latest_mtime=$mtime
        latest=$path
    fi
done

[ -z "$latest" ] && exit 0
[ -x "$latest" ] || [ -r "$latest" ] || exit 0

exec bash "$latest"
