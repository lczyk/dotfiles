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

# NOTE: gnu stat (linux) uses -c '%Y'; bsd stat (mac/*bsd) uses -f '%m'. can't
# chain them with || -- gnu stat accepts -f too (filesystem status), so a
# bsd-first try succeeds with non-numeric garbage on linux. detect by uname.
case "$(uname -s)" in
    Darwin|*BSD) stat_mtime() { stat -f '%m' "$1"; } ;;
    *)           stat_mtime() { stat -c '%Y' "$1"; } ;;
esac

latest=""
latest_mtime=0
for path in "${candidates[@]}"; do
    [ -f "$path" ] || continue
    mtime=$(stat_mtime "$path" 2>/dev/null)
    [ -z "$mtime" ] && continue
    if [ "$mtime" -gt "$latest_mtime" ]; then
        latest_mtime=$mtime
        latest=$path
    fi
done

[ -z "$latest" ] && exit 0
[ -x "$latest" ] || [ -r "$latest" ] || exit 0

# upstream prints [CAVEMAN] / [CAVEMAN:<mode>] (+ optional savings suffix).
# we only care whether caveman is active; collapse any non-empty output to [C].
out=$(bash "$latest")
[ -z "$out" ] && exit 0
printf '\033[38;5;172m[C]\033[0m'
