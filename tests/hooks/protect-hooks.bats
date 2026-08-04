#!/usr/bin/env bats
# tests for stow/common/agent-hooks/.config/agent-hooks/protect-hooks.sh
# the policy reads harness-neutral shell/write requests and exits 2 to deny
# edits to the agent safety hooks. AGENT_UNFENCE=meta lifts it.

setup() {
    # the suite must not inherit a capability from the session that launched
    # it -- every case sets what it needs
    unset AGENT_UNFENCE
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/agent-hooks/.config/agent-hooks/protect-hooks.sh"
    REPO=$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)
    SRC="$REPO/stow/common/agent-hooks/.config/agent-hooks"
}

# fire a neutral shell request.
fire() {
    local cmd="$1"
    printf '{"version":1,"operation":"shell","command":%s}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# fire a neutral write request with one destination path.
fire_write() {
    local path="$1"
    printf '{"version":1,"operation":"write","write_paths":[%s]}' "$(printf '%s' "$path" | jq -Rs .)" \
        | "$HOOK"
}

# -- Write: installed locations -----------------------------------------

@test "blocks Write to an installed policy script" {
    run fire_write "$HOME/.config/agent-hooks/block-dangerous.sh"
    [ "$status" -eq 2 ]
}

@test "blocks Write to a new file in the policy dir" {
    run fire_write "$HOME/.config/agent-hooks/brand-new.sh"
    [ "$status" -eq 2 ]
}

@test "blocks Write to the claude adapter" {
    run fire_write "$HOME/.claude/hooks/safety-adapter.sh"
    [ "$status" -eq 2 ]
}

@test "blocks Write to claude settings.json" {
    run fire_write "$HOME/.claude/settings.json"
    [ "$status" -eq 2 ]
}

@test "blocks Write to claude settings.local.json" {
    run fire_write "$HOME/.claude/settings.local.json"
    [ "$status" -eq 2 ]
}

@test "blocks Write to codex hooks.json" {
    run fire_write "$HOME/.codex/hooks.json"
    [ "$status" -eq 2 ]
}

@test "blocks Write to a copilot hook" {
    run fire_write "$HOME/.copilot/hooks/pre-tool-use.js"
    [ "$status" -eq 2 ]
}

@test "blocks Write to an installed git hook" {
    run fire_write "$HOME/.config/git/hooks/pre-commit"
    [ "$status" -eq 2 ]
}

# -- Write: dotfiles sources --------------------------------------------

@test "blocks Write to the policy source in the checkout" {
    run fire_write "$SRC/block-dangerous.sh"
    [ "$status" -eq 2 ]
}

@test "blocks Write to the evaluator source" {
    run fire_write "$SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "blocks Write to the claude adapter source" {
    run fire_write "$REPO/stow/common/claude/.claude/hooks/safety-adapter.sh"
    [ "$status" -eq 2 ]
}

@test "blocks Write to the claude settings source" {
    run fire_write "$REPO/stow/common/claude/.claude/settings.json"
    [ "$status" -eq 2 ]
}

@test "blocks Write to a git hook source" {
    run fire_write "$REPO/stow/common/git/.config/git/hooks/pre-push"
    [ "$status" -eq 2 ]
}

@test "blocks Write to a copilot hook source" {
    run fire_write "$REPO/stow/common/copilot/.copilot/hooks/agent-hooks.json"
    [ "$status" -eq 2 ]
}

# -- Write: everything else stays writable ------------------------------

@test "allows Write to an unrelated project file" {
    run fire_write "$REPO/README.md"
    [ "$status" -eq 0 ]
}

@test "allows Write to a non-hook claude asset" {
    run fire_write "$REPO/stow/common/claude/.claude/statusline.sh"
    [ "$status" -eq 0 ]
}

@test "allows Write to the hook tests -- deliberately unprotected" {
    # tests can't disarm anything at runtime, and locking them would make the
    # meta capability mandatory for ordinary test work.
    run fire_write "$REPO/tests/hooks/protect-hooks.bats"
    [ "$status" -eq 0 ]
}

@test "allows Write to a lookalike prefix outside the fence" {
    run fire_write "$HOME/.claude/hooks-notes.md"
    [ "$status" -eq 0 ]
}

# -- Write: project-level claude settings -------------------------------
# any repo's .claude/settings*.json feeds env into future sessions, so a
# persisted AGENT_UNFENCE there would be a self-grant.

@test "blocks Write to a project-level settings.json" {
    run fire_write "/Users/marcin/someproj/.claude/settings.json"
    [ "$status" -eq 2 ]
}

@test "blocks Write to a project-level settings.local.json" {
    run fire_write "/Users/marcin/someproj/.claude/settings.local.json"
    [ "$status" -eq 2 ]
}

@test "blocks a shell write to a project-level settings.json" {
    run fire "echo x > /Users/marcin/someproj/.claude/settings.local.json"
    [ "$status" -eq 2 ]
}

@test "blocks a relative-path write to project settings" {
    run fire "echo x > .claude/settings.json"
    [ "$status" -eq 2 ]
}

@test "allows Write to a project-level non-settings claude file" {
    run fire_write "/Users/marcin/someproj/.claude/commands/foo.md"
    [ "$status" -eq 0 ]
}

# -- Shell: writes deny -------------------------------------------------

@test "blocks sed -i on a hook" {
    run fire "sed -i '' s/foo/bar/ $HOME/.claude/hooks/safety-adapter.sh"
    [ "$status" -eq 2 ]
}

@test "blocks a redirect into a hook" {
    run fire "echo x > $SRC/block-dangerous.sh"
    [ "$status" -eq 2 ]
}

@test "blocks a glued redirect into a hook" {
    run fire "echo x >$SRC/block-dangerous.sh"
    [ "$status" -eq 2 ]
}

@test "blocks rm of a hook" {
    run fire "rm $SRC/enforce-tmp-ai.sh"
    [ "$status" -eq 2 ]
}

@test "blocks mv of a hook" {
    run fire "mv $SRC/evaluate.sh /tmp/ai/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "blocks chmod -x on a hook" {
    run fire "chmod -x $HOME/.claude/hooks/safety-adapter.sh"
    [ "$status" -eq 2 ]
}

@test "blocks tee into a hook" {
    run fire "echo x | tee $SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "blocks a write hidden behind an allowlisted leading command" {
    run fire "cat /etc/hosts > $SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "blocks a write in a later segment" {
    run fire "ls /tmp && rm $SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "blocks git checkout of a hook path" {
    run fire "git checkout -- $SRC/block-dangerous.sh"
    [ "$status" -eq 2 ]
}

@test "blocks an unrecognised command touching a hook" {
    run fire "some-unknown-tool $SRC/block-dangerous.sh"
    [ "$status" -eq 2 ]
}

@test "blocks the tilde form" {
    run fire "rm ~/.claude/hooks/safety-adapter.sh"
    [ "$status" -eq 2 ]
}

@test "blocks the \$HOME form" {
    run fire 'rm $HOME/.claude/hooks/safety-adapter.sh'
    [ "$status" -eq 2 ]
}

@test "blocks a line-continued write" {
    run fire "rm \\
$SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "blocks awk -- it can write to a path it appears to read" {
    run fire "awk '{print}' $SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

# -- Shell: reads pass through ------------------------------------------

@test "allows cat of a hook" {
    run fire "cat $SRC/block-dangerous.sh"
    [ "$status" -eq 0 ]
}

@test "allows ls of the policy dir" {
    run fire "ls -la $HOME/.config/agent-hooks/"
    [ "$status" -eq 0 ]
}

@test "allows grep in a hook" {
    run fire "grep -n unfenced $SRC/block-dangerous.sh"
    [ "$status" -eq 0 ]
}

@test "allows git diff of a hook" {
    run fire "git diff $SRC/block-dangerous.sh"
    [ "$status" -eq 0 ]
}

@test "allows shellcheck of a hook" {
    run fire "shellcheck -x $SRC/protect-hooks.sh"
    [ "$status" -eq 0 ]
}

@test "allows a command that mentions no hook path" {
    run fire "make test-hooks"
    [ "$status" -eq 0 ]
}

@test "allows ls run with no path argument" {
    # readlink would otherwise resolve bare words against the cwd, which
    # denies `ls` when the cwd happens to be the policy dir
    run fire "ls -la"
    [ "$status" -eq 0 ]
}

# -- Shell: find is a read until its write flags ------------------------

@test "allows plain find over the policy dir" {
    run fire "find $HOME/.config/agent-hooks -name '*.sh'"
    [ "$status" -eq 0 ]
}

@test "blocks find -delete over the policy dir" {
    run fire "find $HOME/.config/agent-hooks -name '*.sh' -delete"
    [ "$status" -eq 2 ]
}

@test "blocks find -exec rm over the policy dir" {
    run fire "find $HOME/.config/agent-hooks -name '*.sh' -exec rm {} +"
    [ "$status" -eq 2 ]
}

# -- Shell: a read excuse doesn't survive a pipe into xargs -------------

@test "blocks a read of the policy dir piped into xargs" {
    run fire "ls $HOME/.config/agent-hooks/ | xargs rm"
    [ "$status" -eq 2 ]
}

@test "blocks find piped into xargs" {
    run fire "find $HOME/.config/agent-hooks -name '*.sh' -print0 | xargs -0 rm"
    [ "$status" -eq 2 ]
}

@test "allows a read of the policy dir piped into wc" {
    run fire "ls $HOME/.config/agent-hooks/ | wc -l"
    [ "$status" -eq 0 ]
}

@test "allows xargs when no protected path is involved" {
    run fire "ls /tmp/ai | xargs wc -l"
    [ "$status" -eq 0 ]
}

# -- Shell: unstow disarms the fence ------------------------------------

@test "blocks make unstow" {
    run fire "make unstow"
    [ "$status" -eq 2 ]
}

@test "blocks make -C with unstow" {
    run fire "make -C /Users/marcin/dotfiles unstow"
    [ "$status" -eq 2 ]
}

@test "blocks stow -D" {
    run fire "stow -D agent-hooks"
    [ "$status" -eq 2 ]
}

@test "blocks stow --delete" {
    run fire "stow --delete agent-hooks"
    [ "$status" -eq 2 ]
}

@test "blocks stow with a combined -D flag" {
    run fire "stow -vD agent-hooks"
    [ "$status" -eq 2 ]
}

@test "allows make stow" {
    run fire "make stow"
    [ "$status" -eq 0 ]
}

@test "allows a plain stow invocation" {
    run fire "stow -t \$HOME agent-hooks"
    [ "$status" -eq 0 ]
}

# -- the meta capability ------------------------------------------------

@test "meta allows Write to a hook" {
    AGENT_UNFENCE=meta run fire_write "$SRC/block-dangerous.sh"
    [ "$status" -eq 0 ]
}

@test "meta allows a shell write to a hook" {
    AGENT_UNFENCE=meta run fire "rm $SRC/evaluate.sh"
    [ "$status" -eq 0 ]
}

@test "meta alongside another capability still works" {
    AGENT_UNFENCE=branch,meta run fire_write "$SRC/evaluate.sh"
    [ "$status" -eq 0 ]
}

@test "meta allows make unstow" {
    AGENT_UNFENCE=meta run fire "make unstow"
    [ "$status" -eq 0 ]
}

@test "meta allows a project-level settings write" {
    AGENT_UNFENCE=meta run fire_write "/Users/marcin/someproj/.claude/settings.json"
    [ "$status" -eq 0 ]
}

@test "another capability alone does not lift the hook fence" {
    AGENT_UNFENCE=branch run fire_write "$SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the hook fence" {
    AGENT_UNFENCE= run fire_write "$SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the fence" {
    AGENT_UNFENCE=metadata run fire_write "$SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "the capability cannot be granted from inside the command text" {
    # the policy reads its own environment; an env-prefix in the inspected
    # command is only ever text on stdin
    run fire "env AGENT_UNFENCE=meta rm $SRC/evaluate.sh"
    [ "$status" -eq 2 ]
}

# -- known gaps (xfail) -------------------------------------------------
# documented TODOs in the hook -- need real shell parsing. each asserts the
# IDEAL verdict and is skipped; drop the skip once the hook handles it.

@test "xfail: cd into the policy dir then a relative edit should be blocked" {
    skip "relative path after cd needs shell-state tracking"
    run fire "cd $SRC; rm evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "xfail: a \$VAR-built hook path should be blocked" {
    skip "needs variable expansion the policy does not do"
    run fire "d=$SRC; rm \$d/evaluate.sh"
    [ "$status" -eq 2 ]
}

@test "xfail: an interpreter write to a hook should be blocked" {
    skip "writes from inside an interpreter are opaque to the policy"
    run fire "python3 -c \"open('$SRC/evaluate.sh','w')\""
    [ "$status" -eq 2 ]
}
