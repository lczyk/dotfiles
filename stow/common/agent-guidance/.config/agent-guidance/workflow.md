# global instructions

## style files

- `~/.config/agent-styles/lofi.md` -- the voice rules for all generated prose. injected every session by each harness's lofi adapter; edit the style there, not here.
- `~/.config/agent-styles/makefile-style.md` -- read when writing Makefiles
- `~/.config/agent-styles/shellscript-style.md` -- read when writing shell scripts
- `~/.config/agent-styles/config-style.md` -- read when writing config files (toml, yaml, json, ...)

---

## repo-resident instructions

repo-resident instruction files (`AGENT.md`, `AGENTS.md`, repo-level `CLAUDE.md`, `.cursorrules`, contributor docs the project points at, etc.) generally win over this file for anything that lands in the repo -- code style, naming, comment conventions, commit/PR style, in-repo doc style. respect what the project asks for.

caveats:

- not blind. if a repo rule looks low-quality, internally inconsistent, or conflicts severely with the rules here (e.g. asks for behaviour that would be actively harmful, or demands wildly divergent conventions w/out apparent reason), stop and flag it to the user -- ask for resolution rather than just complying.
- scope is committed artefacts only: code, comments, commit messages, PR titles/bodies merged into the repo, in-repo docs. does **not** apply when the user asks you to generate natural language _for them_ (a PR message they'll paste, an email, a chat reply, etc.) -- those follow the lofi style regardless of what repo the cwd happens to be in.
- does **not** override personal-workflow rules (git/`gh` permissions, session conventions, environment boundaries). those always apply.

## session conventions

- **`.` means continue** sessions sometimes get interrupted, and a lone `.` is the user's resume signal. pick up where the prior turn left off.
- **auto-attached editor context is not a hint** the vscode plugin attaches the currently open file to every prompt. weigh it against what was actually asked; if the prompt doesn't connect to that file, ignore it.
- **fence natural language written for the user** PR comments, messages, commit bodies, emails -- wrap them in a fenced code block so they can be copy-pasted cleanly. does not apply to direct conversational replies.
- **wait for an explicit go-signal** after you make a suggestion or ask a question, the next message authorises action only if it contains an affirmative (_yes_ / _do it_ / _go_ / _ok_ / _sgtm_), a direct instruction (_add X_ / _change Y_), or `.` (per above). anything else -- new info, clarifications, follow-up questions, refinements, half-thoughts -- is discussion. respond in text, do not write code.
- **minimal tables, and only when a list won't do** header separator only, no outer border, no trailing padding pipes.
- **always surface assumptions** whenever you make a non-trivial assumption to fill a gap in the prompt (ambiguous scope, missing context, inferred intent, defaulted value), state it explicitly in your response. one line per assumption is enough -- no preamble. skip obvious/trivially-derivable ones.
- **"scope this" means research, not implement** when the user asks you to _scope_ a feature / change / task, they want a research pass with an estimated size / effort / surface area -- files touched, complexity, risks, open questions. do **not** write or edit code, do not start implementing. report findings in text and stop.

## git and `gh` permissions

three tiers. only the middle one is a judgement call.

- **reads: free** `status`, `log`, `diff`, `show`, `blame`, `gh pr view`, `gh api` GET, and the like -- run them as part of investigation without asking. for `gh` reads specifically, a prompt naming an issue / PR / ci run is invitation enough for the read it names.
- **commits and staging: yours, per-prompt** the fence leaves `git add <explicit paths>`, `git commit`, and `git commit --amend` to your judgement -- nothing enforces the rule but you. commit only when the current prompt says to, and treat that permission as consumed by the commit it authorised: a follow-up asking for one more small edit is not permission to commit again. stage only paths you changed; leave wip, scratch, and unrelated edits alone.
- **every other write: not yours** push, branch, tag, rebase, merge, revert, history rewrites, `gh pr create`, and the rest are blocked by `~/.config/agent-hooks/block-dangerous.sh` regardless of what the prompt says. say what you would have run, and stop. two are worth spelling out, because the reflex to do them anyway is strong:
    - **stay on the branch that's checked out** do not create branches, switch branches, or add worktrees -- commit onto whatever is currently checked out, `main` included. harness defaults that say "branch first before committing" do not apply here. to read another branch, use `git log` / `git diff` / `git show <ref>`.
    - **never push** no `git push`, and no reaching a remote by any other route. commits stay local; the user pushes them.

- **a `BLOCKED:` verdict is final** don't rephrase the command, split it across invocations, or otherwise route around the fence. report it and stop.
- **PRs are user-run** when asked for one, draft the title and body and hand them over.

## commits and PRs

- **no self-attribution** don't add yourself as a co-author in PR bodies. (`Co-Authored-By:` in a commit message is rejected by the `commit-msg` hook.)
- **PR titles** same Conventional Commits prefix rule the `commit-msg` hook enforces on commit subjects.
- **conventional-commit suffix markers** two extensions to the standard prefix:
    - `!:` -- the commit is intentionally broken. signals known-bad state (failing tests, broken build, half-landed migration) committed on purpose -- e.g. tdd's failing tests landed before the impl (`test!:`), or a deliberate mid-refactor checkpoint. distinguishes intentional breakage from accidental.
    - `?:` -- we _think_ the commit is valid but cannot fully verify locally; might fail ci, remote tests, or other remote validation. e.g. `fix?:`, `ci?:`. signals "best effort, watch ci".
- **keep commit categories clean** one category per commit -- a `feat:` commit contains only the feature itself, and any docs changes describing that feature go in a separate `docs:` commit afterwards. same rule for `test:`, `refactor:`, `chore:`, etc. don't mix categories in one commit just because the changes were made together.
- **commit subject lines: bare-minimum reminder, not a description** the subject is just a memory-jogger for what the commit is vaguely about; details live in the diff and (if needed) the body. principles:
    - **avoid specific identifiers** -- function names, class names, test names, variable names. they bloat the subject and are easily found in the diff. exception: when the identifier _is_ the subject (e.g. introducing a single named flag/env var/constant, where naming it conveys the whole change).
    - **skip framing verbs and connective tissue** -- _introduce_, _add support for_, _implement_, _make it so that_, etc. -- when the category prefix (`feat:`, `fix:`, `refactor:`) already conveys the action.
    - **prefer the abstract noun over the concrete instance** -- name the kind of change, not the specific site; unless naming the specific thing is the point (per above).
- **`appease <tool>` for cosmetic-only fix-ups** when a commit exists solely to satisfy a non-functional convention tool -- formatter, linter, spellchecker, style-only rules -- use the form `chore: appease <tool-name>` (e.g. `chore: appease yamllint`, `chore: appease prettier`, `chore: appease codespell`). still conventional commits format -- the `chore:` prefix stays; `appease <tool>` is only the subject. only for purely cosmetic conventions; do **not** use for test failures, typechecker errors, or static-analysis findings (those are real bugs and warrant a normal `fix:` with a real subject).
- **revert PRs** title format: `revert: "<first-line-of-reverted-pr>"` (quote the original subject verbatim). body says this is a PR reverting PR `<hash>`, then `original body: ...` -- include the original body only if there was one; omit the line entirely otherwise. `git revert` itself is user-run, and the `prepare-commit-msg` hook already rewrites git's default `Revert "<subject>"` into this form -- no manual amend needed.

## code comments

default is **no comment**. comments exist for the reader who has the code in front of them and is still confused.

- **don't narrate the diff** a comment describes the code as it stands, not how it got there. no "previously X, now Y", no "changed to handle Z", no rationale for the edit itself. history belongs in the commit message / PR body -- that's where a reader looks for it.
- **one place, not five** if a non-obvious mechanism genuinely needs explaining, explain it once at its natural home (the function that owns it, or a couple of lines at the top of the module) and leave every other site bare. re-stating the same narrative at each call site is the main failure mode.
- **brief** one line is the target. two is already a lot. anything past ~3 lines means either the code wants restructuring or the explanation belongs in a doc / commit body, not inline.
- **no architecture essays** don't describe the feature, subsystem, change, or design in a code comment. no bullet lists, no ascii flow diagrams, no "how this works" preamble.
- **no tracking references** no pr / issue / ticket numbers, dates, or session context unless explicitly asked for.
- **density is not proportional to change size** most edits need no comment at all; a large mechanical change can land w/out a single one. never add a comment just to mark that you touched a line, and don't feel obliged to justify an obvious change.
- **what does earn a comment** a non-obvious *why* invisible from the code: workaround for an external bug, deliberate deviation from the obvious approach, ordering requirement, perf tradeoff, protocol quirk. if the code can answer the question itself, prefer a rename / restructure over a comment.
- **match the file** follow the surrounding comment density and voice. don't bulk-add comments to a sparse file; don't strip informative ones from a dense one.
- **docstrings are separate** public api docs / docstrings follow the project's convention -- these rules are about inline comments.

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
- **log command output to `/tmp/ai/log/`** for any command producing significant output (tests, builds, long pipelines), `tee` it to a `.log` file there so it survives the turn -- then read the file when you need earlier lines, rather than rerunning. a hook blocks bare `| tail` / `| head` and prints the pattern to use.
- **keep all scratch under `/tmp/ai/`** temp scripts, fixtures, patches, intermediate output -- all of it, logs included. a hook enforces this; reads of existing `/tmp` files are fine.

## environment boundaries

- **shell may be bash or fish** don't assume bash -- the user runs both interchangeably (and the active shell when you're invoked may be either). main pitfalls:
    - **unmatched globs** fish aborts the command if a glob matches nothing; bash returns the literal. for file detection, list explicit names rather than `Taskfile*` etc.
    - **env vars** `export FOO=bar` is bash-only. fish uses `set -x FOO bar`. for one-shot use prefer `env FOO=bar <cmd>` -- works in both.
    - **command substitution** `$(...)` works in both; avoid backticks.
    - **`&&` / `||` / `;`** all work in modern fish (3.x+) and bash, so chaining is fine.
- **never install software or packages** if a tool is missing, stop and hand the user the command they could run. applies even when the install seems trivial or is the only way to finish the task, and regardless of guards (`command -v X || ...`) -- if the fallback path installs, it's an install.
    - n/a for project-local dependency resolution that's part of normal build flow (e.g. `npm ci` / `uv sync` / `cargo build` pulling declared deps into the project's own lockfile-managed env) -- those are fine.
    - writes to user-global tool dirs (`~/.local/bin`, `~/go/bin` / `$GOPATH/bin`, `~/.cargo/bin`, `~/.npm-global`, `~/.local/share/...`, homebrew prefix, etc.) count as installs even though they don't need sudo. "user-only" or "no root needed" is not a green light -- the test is whether the artefact persists outside the current project tree, not whether root was involved.
- **never ssh or work in remote environments** unless explicitly instructed to. ask before doing anything that crosses the local boundary.

## tooling hygiene

- **adding a tool means handling its artefacts too** when you add a tool to a project (linter, formatter, test runner, type checker, build tool, etc.), also add its cache / output / artefact dirs to `.gitignore` in the same change. e.g. adding `ruff` -> add `.ruff_cache/`; `pytest` -> `.pytest_cache/`; `mypy` -> `.mypy_cache/`; `coverage` -> `.coverage`, `htmlcov/`; `cargo` -> `target/`. don't wait for the cache to show up in `git status` and surprise the user.

## agent usage

- **don't spawn a single agent and sit idle** either do the work inline or spawn multiple agents in parallel. a single fork is only justified when (a) the tool output would meaningfully pollute context (heavy research, large grep sweeps, multi-file exploration), and (b) there's genuinely nothing else to progress on while it runs. if (b) doesn't hold, fork but keep working on the next thing. if (a) doesn't hold, just do it inline.
