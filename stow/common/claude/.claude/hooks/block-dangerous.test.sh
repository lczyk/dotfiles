#!/usr/bin/env bash
# tests for block-dangerous.sh. run directly: bash block-dangerous.test.sh
#
# each case is "expected_exit|command". expected_exit is 0 (allowed) or
# 2 (blocked). commands containing literal blocked tokens use placeholders
# (P0ST, DEL, P_USH, etc.) that are unmunged before being fed to the hook
# -- otherwise the parent claude-code session running the test would itself
# trip the hook on the test command.

set -u
HOOK="$(dirname "$0")/block-dangerous.sh"

# (placeholder, real) pairs -- expanded inside each case before invocation.
declare -a SUBS=(
    "P0ST"   "POST"
    "P_UT"   "PUT"
    "PATCH_" "PATCH"
    "DEL"    "DELETE"
    "C0MMIT" "commit"
    "P_USH"  "push"
    "RE5ET"  "reset"
    "REB4SE" "rebase"
    "MERG3"  "merge"
)

unmunge() {
    local s="$1" i k v
    for ((i=0; i<${#SUBS[@]}; i+=2)); do
        k="${SUBS[i]}"; v="${SUBS[i+1]}"
        s="${s//$k/$v}"
    done
    printf '%s' "$s"
}

# format: "expected|munged-command"
CASES=(
    # --- blocked: destructive / history-rewriting ---
    "2|git RE5ET --hard"
    "2|git clean -fd"
    "2|git branch -D feature"
    "2|git checkout ."
    "2|git restore ."
    "2|git P_USH --force origin main"
    "2|git REB4SE -i HEAD~3"
    "2|git MERG3 main"
    "2|git filter-branch --tree-filter rm"
    "2|git filter-repo --path foo"
    "2|gh pr merge 123"

    # --- blocked: write git ops ---
    "2|git P_USH origin main"
    "2|git tag v1.0.0"
    "2|git tag -a v1 -m msg"
    "2|git cherry-pick abc123"
    "2|git revert HEAD"
    "2|git branch newfeat"
    "2|git branch -m oldname newname"
    "2|git am patch.mbox"
    "2|git apply patch.diff"
    "2|git worktree add ../wt main"
    "2|git stash drop"
    "2|git config --global user.name foo"

    # --- blocked: write gh ops ---
    "2|gh pr create --title foo"
    "2|gh pr comment 1 -b hi"
    "2|gh pr edit 1 --title bar"
    "2|gh pr close 1"
    "2|gh pr review 1 --approve"
    "2|gh issue create --title foo"
    "2|gh issue comment 1 -b hi"
    "2|gh issue close 1"
    "2|gh release create v1"
    "2|gh repo create foo/bar"
    "2|gh repo delete foo/bar"
    "2|gh gist create file.txt"
    "2|gh workflow run ci.yml"
    "2|gh run cancel 123"
    "2|gh label create bug"
    "2|gh secret set TOKEN"
    "2|gh variable set FOO"
    "2|gh api -X P0ST /repos/x/y/issues"
    "2|gh api --method DEL /repos/x/y"
    "2|gh api -X PATCH_ /x"
    "2|gh api repos/x/y --method P_UT"

    # --- blocked: gpg / installs / remote ---
    "2|git C0MMIT --no-gpg-sign -m foo"

    # --- allowed: commits (trusted to claude per CLAUDE.md per-prompt rule) ---
    "0|git C0MMIT -m hello"
    "0|git C0MMIT --amend --no-edit"
    "0|git C0MMIT -am quick"
    "2|brew install jq"
    "2|pip install requests"
    "2|npm install -g typescript"
    "2|cargo install ripgrep"
    "2|ssh user@host"
    "2|scp f host:/"
    "2|kubectl exec -it pod -- sh"

    # --- allowed: read-only git ---
    "0|git status"
    "0|git log --oneline -5"
    "0|git diff HEAD"
    "0|git show abc"
    "0|git blame file.txt"
    "0|git branch --list"
    "0|git branch -l"
    "0|git tag -l"
    "0|git tag --list"
    "0|git remote -v"
    "0|git stash list"
    "0|git config --get user.name"
    "0|git worktree list"

    # --- allowed: read-only gh ---
    "0|gh pr view 1"
    "0|gh pr list"
    "0|gh pr status"
    "0|gh pr diff 1"
    "0|gh pr checks 1"
    "0|gh issue view 1"
    "0|gh issue list"
    "0|gh release list"
    "0|gh release view v1"
    "0|gh repo view"
    "0|gh run list"
    "0|gh run view 1"
    "0|gh api repos/x/y"
    "0|gh api -X GET /user"
    "0|gh workflow list"
    "0|gh workflow view ci.yml"

    # --- allowed: misc ---
    "0|ls -la"
    "0|cat README.md"
    "0|rg foo"
    "0|npm ci"
    "0|uv sync"
    "0|cargo build"
)

pass=0; fail=0; failures=()
for case in "${CASES[@]}"; do
    expected="${case%%|*}"
    munged="${case#*|}"
    cmd=$(unmunge "$munged")
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
