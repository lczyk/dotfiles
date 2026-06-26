#!/usr/bin/env bash
# tests for enforce-tmp-claude.sh. run directly:
#   bash enforce-tmp-claude.test.sh
#
# each case is "expected_exit|channel|value". expected_exit is 0 (allowed) or
# 2 (blocked). channel is 'f' (Write/Edit file_path) or 'c' (Bash command).
# the hook blocks claude scratch in /tmp (and the /private/tmp alias) unless it
# lives under /tmp/claude/.

set -u
HOOK="$(dirname "$0")/enforce-tmp-claude.sh"

CASES=(
    # --- file_path: allowed (under claude, or not in /tmp at all) ---
    "0|f|/tmp/claude/foo.py"
    "0|f|/tmp/claude/log/x.log"
    "0|f|/private/tmp/claude/foo.py"
    "0|f|/private/tmp/claude/sub/dir/x"
    "0|f|/Users/marcin/dotfiles/x.py"
    "0|f|/home/user/scratch.txt"
    "0|f|relative/path.py"

    # --- file_path: blocked (in /tmp but not under claude) ---
    "2|f|/tmp/foo.py"
    "2|f|/tmp/scratch/x.py"
    "2|f|/tmp/claudette/x.py"
    "2|f|/private/tmp/foo.py"
    "2|f|/private/tmp/claude-501/x/scratchpad/chisel_tree.py"
    "2|f|/private/tmp/claudette/x.py"

    # --- bash redirect / tee: allowed ---
    "0|c|echo hi > /tmp/claude/x.log"
    "0|c|echo hi >> /tmp/claude/log/x.log"
    "0|c|cmd 2>&1 | tee /tmp/claude/log/x.log"
    "0|c|echo hi > /private/tmp/claude/x.log"
    "0|c|cmd | tee /private/tmp/claude/log/x.log"
    "0|c|echo hi > /var/log/x.log"
    "0|c|ls -la"
    "0|c|cat /tmp/claude/log/x.log"

    # --- bash redirect / tee: blocked ---
    "2|c|echo hi > /tmp/foo.log"
    "2|c|echo hi >/tmp/foo.log"
    "2|c|echo hi >> /tmp/foo.log"
    "2|c|cmd 2>&1 | tee /tmp/other.log"
    "2|c|echo hi > /private/tmp/foo.log"
    "2|c|cmd | tee /private/tmp/other.log"

    # --- mktemp: allowed only when targeting /tmp/claude ---
    "0|c|mktemp -p /tmp/claude"
    "0|c|mktemp -p /tmp/claude/sub"
    "2|c|mktemp"
    "2|c|mktemp -d"
    "2|c|f=\$(mktemp)"
)

pass=0; fail=0; failures=()
for case in "${CASES[@]}"; do
    expected="${case%%|*}"
    rest="${case#*|}"
    chan="${rest%%|*}"
    val="${rest#*|}"
    if [[ "$chan" == "f" ]]; then
        payload=$(jq -nc --arg v "$val" '{tool_input: {file_path: $v}}')
    else
        payload=$(jq -nc --arg v "$val" '{tool_input: {command: $v}}')
    fi
    actual=0
    out=$(printf '%s' "$payload" | bash "$HOOK" 2>&1) || actual=$?
    if [[ "$actual" == "$expected" ]]; then
        ((pass++))
    else
        ((fail++))
        failures+=("expected=$expected actual=$actual chan=$chan val='$val' out='$out'")
    fi
done

printf '%d passed, %d failed (of %d)\n' "$pass" "$fail" $((pass+fail))
if ((fail)); then
    for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
