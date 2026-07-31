#!/usr/bin/env bats
# tests for stow/common/agent-hooks/.config/agent-hooks/block-dangerous.sh
# the policy reads a harness-neutral shell request and exits 2 to deny.

setup() {
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
