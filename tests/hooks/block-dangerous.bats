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
