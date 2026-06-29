#!/usr/bin/env bash
# tests for discourage-bare-tail.sh. run directly:
#   bash discourage-bare-tail.test.sh
#
# each case is "expected_exit|command". expected_exit is 0 (allowed) or
# 2 (blocked). the hook blocks bare `| tail` patterns and allows commands
# that tee through /tmp/ai/log/ first (so the full log persists).

set -u
HOOK="$(dirname "$0")/discourage-bare-tail.sh"

CASES=(
    # --- blocked: bare `| tail` w/out tee to /tmp/ai/log/ ---
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

    # --- allowed: tee to /tmp/ai/log/ before tail ---
    "0|cmd 2>&1 | tee /tmp/ai/log/foo.log | tail -50"
    "0|cmd 2>&1 | tee /tmp/ai/log/foo.log | tail -n 50"
    "0|ls /tmp 2>&1 | tee /tmp/ai/log/lstest.log | tail -3"
    "0|cmd | tee  /tmp/ai/log/x.log | tail -10"

    # --- allowed: tee to /tmp/ai/log/ without tail at all ---
    "0|cmd 2>&1 | tee /tmp/ai/log/foo.log"
    "0|cmd > /tmp/ai/log/foo.log 2>&1"

    # --- allowed: no tail at all ---
    "0|ls -la"
    "0|cat README.md"
    "0|git status"
    "0|grep foo file.txt"
    "0|find . -name foo"

    # --- allowed: bare tail (reading a file, not piped from another cmd) ---
    "0|tail -50 /var/log/syslog"
    "0|tail -f /var/log/foo.log"
    "0|tail /tmp/ai/log/foo.log"

    # --- allowed: words that start with 'tail' but aren't tail ---
    "0|ls | tailscale up"
    "0|cmd | tailor --fit"

    # --- blocked (false negative fix): `head` equivalents ---
    "2|ls /tmp | head"
    "2|ls /tmp | head -5"
    "2|ls /tmp | head -50"
    "2|ls /tmp | head -n 50"
    "2|ls /tmp | head -n50"
    "2|cat huge.log | head -100"
    "2|cmd 2>&1 | head -50"
    "2|find . -name foo | grep bar | head -10"

    # --- allowed: words that start with 'head' but aren't head ---
    "0|cmd | header --format=json"
    "0|cmd | heading --level 2"

    # --- allowed: bare head reading a file (not piped) ---
    "0|head -50 /var/log/syslog"
    "0|head /etc/passwd"

    # --- blocked (false negative fix): long-form tail/head flags ---
    "2|cmd | tail --lines=50"
    "2|cmd | tail --bytes=1024"
    "2|cmd | tail --follow"
    "2|cmd | tail -c 100"
    "2|cmd | tail -F"
    "2|cmd | head --lines=50"
    "2|cmd | head --bytes=1024"
    "2|cmd | head -c 100"

    # --- blocked (false negative fix): process substitution ---
    "2|tail -5 <(ls /tmp)"
    "2|tail -n 50 <(some-cmd)"
    "2|head -5 <(ls /tmp)"
    "2|head -n 50 <(some-cmd)"

    # --- allowed (false positive fix): tee -a (append) to log dir ---
    "0|cmd 2>&1 | tee -a /tmp/ai/log/foo.log | tail -5"
    "0|cmd 2>&1 | tee --append /tmp/ai/log/foo.log | tail -5"

    # --- allowed (false positive fix): quoted log path ---
    "0|cmd 2>&1 | tee \"/tmp/ai/log/foo.log\" | tail -5"
    "0|cmd 2>&1 | tee '/tmp/ai/log/foo.log' | tail -5"
    "0|cmd 2>&1 | tee -a \"/tmp/ai/log/foo.log\" | tail -5"

    # --- allowed (false positive fix): tee multi-file w/ log dir not first ---
    "0|cmd | tee /tmp/other.log /tmp/ai/log/x.log | tail -5"
    "0|cmd | tee /tmp/a.log /tmp/b.log /tmp/ai/log/x.log | tail -5"
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
    for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
