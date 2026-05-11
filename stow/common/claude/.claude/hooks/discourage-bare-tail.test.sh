#!/usr/bin/env bash
# tests for discourage-bare-tail.sh. run directly:
#   bash discourage-bare-tail.test.sh
#
# each case is "expected_exit|command". expected_exit is 0 (allowed) or
# 2 (blocked). the hook blocks bare `| tail` patterns and allows commands
# that tee through /tmp/claude/log/ first (so the full log persists).

set -u
HOOK="$(dirname "$0")/discourage-bare-tail.sh"

CASES=(
    # --- blocked: bare `| tail` w/out tee to /tmp/claude/log/ ---
    "2|ls /tmp | tail"
    "2|ls /tmp | tail -5"
    "2|ls /tmp | tail -50"
    "2|ls /tmp | tail -n 50"
    "2|ls /tmp | tail -n50"
    "2|ls /tmp | tail -f"
    "2|ls /tmp | tail -q file"
    "2|cmd 2>&1 | tail -50"
    "2|cmd 2>&1 |tail -50"
    "2|cmd 2>&1 |    tail -50"
    "2|find . -name foo | grep bar | tail -10"
    "2|cmd | tee /tmp/other.log | tail -5"
    "2|cmd | tee /var/log/x.log | tail -5"
    "2|cat huge.log | tail -100"

    # --- allowed: tee to /tmp/claude/log/ before tail ---
    "0|cmd 2>&1 | tee /tmp/claude/log/foo.log | tail -50"
    "0|cmd 2>&1 | tee /tmp/claude/log/foo.log | tail -n 50"
    "0|ls /tmp 2>&1 | tee /tmp/claude/log/lstest.log | tail -3"
    "0|cmd | tee  /tmp/claude/log/x.log | tail -10"

    # --- allowed: tee to /tmp/claude/log/ without tail at all ---
    "0|cmd 2>&1 | tee /tmp/claude/log/foo.log"
    "0|cmd > /tmp/claude/log/foo.log 2>&1"

    # --- allowed: no tail at all ---
    "0|ls -la"
    "0|cat README.md"
    "0|git status"
    "0|grep foo file.txt"
    "0|find . -name foo"

    # --- allowed: bare tail (reading a file, not piped from another cmd) ---
    "0|tail -50 /var/log/syslog"
    "0|tail -f /var/log/foo.log"
    "0|tail /tmp/claude/log/foo.log"

    # --- allowed: words that start with 'tail' but aren't tail ---
    "0|ls | tailscale up"
    "0|cmd | tailor --fit"
)

pass=0; fail=0; failures=()
for case in "${CASES[@]}"; do
    expected="${case%%|*}"
    cmd="${case#*|}"
    payload=$(jq -nc --arg c "$cmd" '{tool_input: {command: $c}}')
    actual=0
    out=$(printf '%s' "$payload" | bash "$HOOK" 2>&1) || actual=$?
    if [[ "$actual" == "$expected" ]]; then
        ((pass++))
    else
        ((fail++))
        failures+=("expected=$expected actual=$actual cmd='$cmd' out='$out'")
    fi
done

printf '%d passed, %d failed (of %d)\n' "$pass" "$fail" $((pass+fail))
if ((fail)); then
    printf '\nfailures:\n'
    for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
