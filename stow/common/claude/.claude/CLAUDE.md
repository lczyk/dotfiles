# global instructions

## repo-resident instructions

repo-resident instruction files (`AGENT.md`, `AGENTS.md`, repo-level `CLAUDE.md`, `.cursorrules`, contributor docs the project points at, etc.) generally win over this file for anything that lands in the repo -- code style, naming, comment conventions, commit/PR style, in-repo doc style. respect what the project asks for.

caveats:

- not blind. if a repo rule looks low-quality, internally inconsistent, or conflicts severely with the rules here (e.g. asks for behaviour that would be actively harmful, or demands wildly divergent conventions w/out apparent reason), stop and flag it to the user -- ask for resolution rather than just complying.
- scope is committed artefacts only: code, comments, commit messages, PR titles/bodies merged into the repo, in-repo docs. does **not** apply when the user asks you to generate natural language _for them_ (a PR message they'll paste, an email, a chat reply, etc.) -- those follow this file's style regardless of what repo the cwd happens to be in.
- does **not** override personal-workflow rules (git/`gh` permissions, session conventions, environment boundaries). those always apply.

## session conventions

- if the user sends just `.` as a message, treat it as "continue what you were doing" -- sessions sometimes get interrupted, and `.` is the user's resume signal. pick up where the prior turn left off.
- when prompting from the vscode plugin, the currently open file gets auto-attached as context. it might be relevant, but often isn't -- don't assume relevance just because it's attached. weigh it against the prompt; if the prompt doesn't connect to that file, ignore it.
- when the user asks you to generate a piece of natural language (PR comment, message, commit body, email, etc), wrap the output in a fenced code block so it can be copy-pasted cleanly. does not apply to direct conversational replies.
- after you make a suggestion or ask a question, the next message authorises action only if it contains an explicit go-signal: an affirmative (_yes_ / _do it_ / _go_ / _ok_ / _sgtm_), a direct instruction (_add X_ / _change Y_), or `.` (per above). anything else -- new info, clarifications, follow-up questions, refinements, half-thoughts -- is discussion. respond in text, do not write code.

## git and `gh` permissions

- **git read-only ops: no permission needed** `status`, `log`, `diff`, `show`, `blame`, `branch --list`, `remote -v`, etc. -- run freely as part of investigation.
- **`gh` needs permission unless the prompt implies it** invocations like `gh pr view`, `gh issue view`, `gh api` count as reaching out to a remote; ask first. exception: when the prompt clearly invites it (e.g. _"look at this issue <github-link>"_, _"read the comments on PR 123"_, _"check ci status"_) -- treat that as implicit permission for the read action being requested. write `gh` ops (`gh pr create`, `gh issue create`, `gh pr comment`, etc.) follow the per-prompt explicit-permission rule below.
- **never run write git / `gh` ops without explicit per-prompt permission** this covers `commit`, `commit --amend`, `revert`, `branch` (create/delete), `cherry-pick`, `tag`, `push`, `reset --hard`, `checkout` of files, `gh pr create`, `gh issue create`, comments / reviews / merges via `gh`, and anything else that mutates local repo state or remote github state. permission is per-prompt: granting it for one turn does _not_ carry to follow-up turns -- once the authorised op lands, permission is consumed. if a later prompt asks for a small follow-up edit, stop after the edit; do not commit / amend / revert / push unless explicitly told to in _that_ prompt.
- **never run complex / risky git ops at all** `rebase` (interactive or not), `merge`, `reset` (any mode), `filter-branch`, `filter-repo`, `reflog expire`, `gc --prune`, force-push, branch-rename of in-use branches, history rewrites generally. these need a human; surface what youd do and stop.
- do not create PRs unless explicitly instructed. stop after commits.
- create commits only when explicitly prompted to.
- **commit permission does not carry across prompts** if the user asks for some work and a commit, that authorisation is consumed by the commit made in that turn. once that commit lands, you no longer have permission to commit -- including for follow-up tweaks, fixups, or any further work in later prompts. wait for the user to explicitly say "commit" again. this applies even if the next prompt is a small edit ("fix this typo", "add a comment") that feels like part of the same task -- stop after the change; do not commit unless told to.

## commits and PRs

- do not add yourself (`Co-Authored-By: Claude ...`) as a co-author on commits or in PR bodies.
- when creating PRs (only when asked), use Conventional Commits format for the title (e.g. `feat:`, `fix:`, `docs:`, `bench:`, `refactor:`, `revert:`, `chore:`).
- **conventional-commit suffix markers** two extensions to the standard prefix:
    - `!:` -- the commit is intentionally broken. signals known-bad state (failing tests, broken build, half-landed migration) committed on purpose -- e.g. tdd's failing tests landed before the impl (`test!:`), or a deliberate mid-refactor checkpoint. distinguishes intentional breakage from accidental.
    - `?:` -- we _think_ the commit is valid but cannot fully verify locally; might fail ci, remote tests, or other remote validation. e.g. `fix?:`, `ci?:`. signals "best effort, watch ci".
- **keep commit categories clean** one category per commit -- a `feat:` commit contains only the feature itself, and any docs changes describing that feature go in a separate `docs:` commit afterwards. same rule for `test:`, `refactor:`, `chore:`, etc. don't mix categories in one commit just because the changes were made together.
- **commit subject lines: bare-minimum reminder, not a description** the subject is just a memory-jogger for what the commit is vaguely about; details live in the diff and (if needed) the body. principles:
    - **avoid specific identifiers** -- function names, class names, test names, variable names. they bloat the subject and are easily found in the diff. exception: when the identifier _is_ the subject (e.g. introducing a single named flag/env var/constant, where naming it conveys the whole change).
    - **skip framing verbs and connective tissue** -- _introduce_, _add support for_, _implement_, _make it so that_, etc. -- when the category prefix (`feat:`, `fix:`, `refactor:`) already conveys the action.
    - **prefer the abstract noun over the concrete instance** -- name the kind of change, not the specific site; unless naming the specific thing is the point (per above).
- **`appease <tool>` for cosmetic-only fix-ups** when a commit exists solely to satisfy a non-functional convention tool -- formatter, linter, spellchecker, style-only rules -- use the form `chore: appease <tool-name>` (e.g. `chore: appease yamllint`, `chore: appease prettier`, `chore: appease codespell`). still conventional commits format -- the `chore:` prefix stays; `appease <tool>` is only the subject. only for purely cosmetic conventions; do **not** use for test failures, typechecker errors, or static-analysis findings (those are real bugs and warrant a normal `fix:` with a real subject).
- **revert PRs** title format: `revert: "<first-line-of-reverted-pr>"` (quote the original subject verbatim). body says this is a PR reverting PR `<hash>`, then `original body: ...` -- include the original body only if there was one; omit the line entirely otherwise. when generating the revert with `git revert`, the default message git produces will _not_ match this format -- amend the commit message after `git revert` to bring it into the format above.

## finding repo automation

most repos have a task runner -- `make`, `just`, `task`, `npm`/`pnpm`/`yarn` scripts, `uv` scripts, etc. before guessing at commands, find what's there.

detect with explicit `ls` at repo root, not globs (fish errors on unmatched globs, and case varies):

```
ls Makefile makefile justfile Justfile Taskfile.yml taskfile.yml package.json pyproject.toml 2>/dev/null
```

once detected, list targets before invoking -- a `lint` target may chain tools (`nilaway`, `golangci-lint`) you wouldn't have invoked otherwise:

- `make` -- `make help` iff defined; otherwise read the `Makefile`
- `just` -- `just --list`
- `task` -- `task --list`
- `npm` / `pnpm` / `yarn` -- `npm run` / `pnpm run` / `yarn run`
- `uv` -- `uv run --list`

## makefile style

iff a repo has no automation and the user has explicitly asked to add some, prefer a `makefile` (lowercase filename -- both `make` and the user prefer it; some of the user's older repos still use `Makefile`, leave those alone). style:

- **`.SUFFIXES:` at the top** disables built-in implicit rules; everything in the makefile is then explicit.
- **`help` is the default target** sits first, prints all public targets. self-documenting via a trailing `## description` on each public target rule, rendered with a `grep` + `awk` one-liner. internal targets (helpers, intermediate steps) omit the `## ` so they don't show up.
- **`.PHONY:` per target, inline** declare `.PHONY: foo` on the line directly above the `foo:` rule, not batched at the top of the file. keeps the declaration next to the thing it describes.
- **file targets list real deps** rules that produce a file (e.g. `./bin/foo:`) name every input that should trigger a rebuild -- source globs, the `makefile` itself, package/lockfiles (`go.mod`, `go.sum`, `package-lock.json`, `uv.lock`). including the `makefile` and the package files means a change to the build recipe or to declared deps invalidates the cached artefact, just like a source-file edit would.
- **`mkdir -p` before writes** any rule that produces a file in a directory creates the directory first.
- **optional tools are soft** wrap with `command -v <tool> >/dev/null 2>&1` and either fall back (e.g. `gotest` -> `go test`) or skip with a message. don't hard-fail on a missing nice-to-have.
- **overridable knobs use `$(or $(VAR),<default>)`** lets the caller pass `BENCH=...` / `PKG=...` w/out touching the makefile, with a sensible default baked in.
- **aggregate gate target** a `verify` (or similar) target that chains `lint test spellcheck ...` -- one entry point for "is this commit healthy".
- **internal targets skip the `## ` doc** only public, user-invokable targets get the trailing `## description`. helpers and intermediate file rules stay undocumented so they don't clutter `make help`.
- **kebab-case target names** `cover-open`, `generate-version`, not `cover_open` or `coverOpen`.

## testing before commits

before any commit, every check that should pass for a healthy commit must pass -- test, lint, typecheck, format-check, spellcheck, etc. (only the ones that exist; don't invent them). one exception: tdd (see below).

find the right commands in this order:

1. **pre-written automation in the repo** -- see [finding repo automation](#finding-repo-automation). run every relevant target, not just the test one.
2. **ci/pipeline config** -- if no local automation, mirror what ci runs on pr/push. check `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`.
3. **language defaults** -- only if neither exists. e.g. `go test ./...`, `cargo test`, `uvx pytest`. in this fallback, just run tests; don't guess at lint/spellcheck commands.

- **prefer `uv` / `uvx` for python** runs in an isolated venv, doesn't pollute the system or project env.
- **tdd exception** if doing test-driven development, write the failing tests first. if asked to commit them before the implementation lands, use `test!:` (with the `!`) to mark the commit as intentionally not passing -- this signals the failing-tests-on-purpose case and distinguishes it from a normal `test:` commit.
- **coverage as guide, not target** use coverage to find untested branches / edge cases worth exercising -- not to chase a number. don't write tests for code whose correctness is already guaranteed by something else (autogenerated `String()` on an enum, trivial getters, framework-provided behaviour, etc.) just to lift the percentage. if a test only exists to satisfy coverage on something already guaranteed, it's noise. when a test _is_ legitimately driven by coverage (exercising a specific branch that would otherwise go untested), mark it with a `COVER:` comment so future readers know why it's shaped the way it is.
- **long-running tests / benchmarks** ff to run tests, benchmarks, or other checks expected to finish in a reasonable amount of time (~10min ceiling as a rough rule of thumb). for runs expected to take longer -- e.g. nn training, big sweeps, slow integration suites -- stop, hand the user the exact command(s) to run, and wait for them to come back. if the run naturally produces a giant log, redirect to a file and point at which file / which lines / which summary line to look at -- don't ask the user to paste the whole thing.

## environment boundaries

- **shell may be bash or fish** don't assume bash -- the user runs both interchangeably (and the active shell when you're invoked may be either). main pitfalls:
    - **unmatched globs** fish aborts the command if a glob matches nothing; bash returns the literal. for file detection, list explicit names rather than `Taskfile*` etc.
    - **env vars** `export FOO=bar` is bash-only. fish uses `set -x FOO bar`. for one-shot use prefer `env FOO=bar <cmd>` -- works in both.
    - **command substitution** `$(...)` works in both; avoid backticks.
    - **`&&` / `||` / `;`** all work in modern fish (3.x+) and bash, so chaining is fine.
- **never install software or packages** not via `apt`, `brew`, `pip install`, `npm install -g`, `cargo install`, `go install`, etc. if a tool is missing, stop and prompt the user; suggest the command they could run, but do not run it yourself. this applies even if the install seems trivial or clearly needed to finish the task. also applies regardless of guards (`command -v X ||`, `which X >/dev/null ||`, `[ -x ... ] ||`, etc.) -- if the fallback path installs, it's an install.
    - n/a for project-local dependency resolution that's part of normal build flow (e.g. `npm ci` / `uv sync` / `cargo build` pulling declared deps into the project's own lockfile-managed env) -- those are fine.
    - writes to user-global tool dirs (`~/.local/bin`, `~/go/bin` / `$GOPATH/bin`, `~/.cargo/bin`, `~/.npm-global`, `~/.local/share/...`, homebrew prefix, etc.) count as installs even though they don't need sudo. "user-only" or "no root needed" is not a green light -- the test is whether the artefact persists outside the current project tree, not whether root was involved.
- **never ssh or work in remote environments** unless explicitly instructed to. no `ssh`, no `scp`, no remote `kubectl exec`, no connecting to remote shells. heads-up the user and ask before doing anything that crosses the local boundary.

## tooling hygiene

- **adding a tool means handling its artefacts too** when you add a tool to a project (linter, formatter, test runner, type checker, build tool, etc.), also add its cache / output / artefact dirs to `.gitignore` in the same change. e.g. adding `ruff` -> add `.ruff_cache/`; `pytest` -> `.pytest_cache/`; `mypy` -> `.mypy_cache/`; `coverage` -> `.coverage`, `htmlcov/`; `cargo` -> `target/`. don't wait for the cache to show up in `git status` and surprise the user.

## config-file style (toml, yaml, json, etc.)

- **multi-item lists stay multiline** in config files (`pyproject.toml`, `tox.ini` arrays, `package.json` arrays, ci yaml lists, etc.), put each item on its own line. one-item-per-line keeps git diffs minimal (a line touched is a line changed) and makes it trivial to comment out / re-enable individual entries without rebalancing brackets or commas.
- **trailing `# ` sentinel to lock multiline shape** end the list with a bare `# ` line (just a hash, optional empty trailing comment) before the closing bracket. this anchors the multiline form against autoformatters that would otherwise collapse a single-item list onto one line, and gives a stable place to drop a `# "FOO",` commented-out entry. e.g.
    ```toml
    dependencies = [
        "torch",
        "numpy",
        # 
    ]
    ```
    apply consistently even to short lists -- the rule is "every list, every time", not "lists above N entries".
- **inline `# what-it-is` after opaque short tokens** when list entries are terse codes whose meaning isn't obvious from the token alone (ruff/flake8 codes like `E` / `F` / `B` / `SIM`, mypy plugin names, ci job ids, etc.), append an inline comment naming what each token expands to. align the comments at a consistent column so the file scans as a two-column table. e.g.
    ```toml
    select = [
        "E",   # pycodestyle
        "F",   # pyflakes
        "B",   # flake8-bugbear
        "SIM", # flake8-simplify
        # "PL",  # pylint -- enable later
    ]
    ```
    skip the inline comment when the token is self-describing (a package name, a file path, a human-readable identifier). the rule kicks in only when the token is a code or shorthand a future reader would have to look up.

!import writing-style.md
