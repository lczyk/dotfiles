# global instructions

## style files

- `~/.config/agent-styles/lofi.md` -- voice rules for all generated prose. claude, codex and copilot inject it at session start; if it isn't in your context (opencode, hax), read it before writing prose.
- `~/.config/agent-styles/lofi-extras.md` -- optional expressive markers; read when writing chat-style notes or PR comments.
- `~/.config/agent-styles/makefile-style.md` -- read when writing makefiles.
- `~/.config/agent-styles/shellscript-style.md` -- read when writing shell scripts.
- `~/.config/agent-styles/config-style.md` -- read when writing config files (toml, yaml, json, ...).

## git and `gh` permissions

three tiers; only the middle one is a judgement call.

- **reads: free** `status`, `log`, `diff`, `show`, `blame`, `gh pr view`, `gh api` GET and the like. a prompt naming an issue / PR / ci run is invitation enough to read it.
- **commits: yours, per prompt** `git add <explicit-paths>`, `git commit`, `git commit --amend` of an unpushed HEAD. nothing enforces the per-prompt part but you: commit only when the current prompt says to, and one permission covers one commit -- a follow-up asking for another small edit is not permission to commit again. stage only paths you changed; leave wip, scratch and unrelated edits alone. amending a commit that is already on `@{u}` is rejected by the `prepare-commit-msg` hook -- make a new commit instead.
- **every other write: not yours** push, branch, tag, rebase, merge, revert, history rewrites, `gh pr create`, `gh issue create` and other `gh` writes are blocked by `~/.config/agent-hooks/block-dangerous.sh`. say what you would have run, and stop. two reflexes to resist:
    - **stay on the checked-out branch** no new branches, switches or worktrees -- commit onto whatever is checked out, `main` included. harness advice to "branch first" doesn't apply here. read other branches with `git log` / `git diff` / `git show <ref>`.
    - **never push** commits stay local; the user pushes. (a session launched with `push` is the exception -- see capabilities.)

- **`BLOCKED:` is final** don't rephrase the command, split it up or otherwise route around the fence. report it and stop.
- **`HINT:` is advisory** weigh it and carry on; quoted shell text can trip heuristic hints.
- **capabilities only the user grants** the fences read `AGENT_UNFENCE` (comma-separated) from their own env at launch, e.g. `env AGENT_UNFENCE=branch claude`. prefixing your own command with it reaches the policy as text, not a variable -- you can't grant yourself one.
    - `branch` -- create / switch branches, `git checkout -b`, `git worktree add`. `git branch -D` and push stay blocked.
    - `history` -- `git rebase`, `git cherry-pick`, `git reset --soft`. `reset --hard` / `--mixed` / bare `reset` and force-push are never liftable.
    - `remote` -- `ssh`, `scp`, `autossh`, `kubectl exec`, `gcloud compute ssh`. doesn't reach `git push`.
    - `push` -- `git push` of the current (or a named) branch to a configured remote by name, fast-forward only. never, capability or not: force (`-f`, `--force*`, `+ref`), delete (`-d`, `--delete`, `:ref`), bulk (`--all`, `--tags`, `--mirror`, `--prune`), `--no-verify`, a url or path as the target, or a `-c remote.*` / `-c push.*` / `-c url.*` one-shot. `pre-push` enforces the same line for anything the text fence misses, and refuses tags -- add `--no-follow-tags` if one gets dragged along. pull / merge stay blocked, so local `main` goes stale: base new branches on `origin/main` after `git fetch`.
    - `pr` -- `gh pr create` against the current repo (no `-R`). an inline title takes the conventional prefix; the body (inline or `--body-file <absolute-path>`) is ascii with no attribution. it doesn't reach push: an unpushed branch fails at `pre-push`, so pair it with `push` or push first yourself. push before `gh pr create` (or pass `--head <branch>` literally) so gh never prompts to push or fork. `gh pr edit` of the title / body follows the same rules; labels, reviewers, base, milestone, comment, ready and merge stay user-run.
    - `issue` -- `gh issue create` and `gh issue edit` of the title / body against the current repo (no `-R`); the body rules of `pr`, no title prefix. labels, assignees, comment, close, transfer stay user-run.
    - `meta` -- lifts the hook protection below.

## environment boundaries

- **the hooks are not yours** `~/.config/agent-hooks/`, `~/.claude/hooks/`, `~/.codex/hooks*`, `~/.copilot/hooks/`, `~/.config/git/hooks/`, `~/.claude/settings*.json`, any repo's `.claude/settings*.json` (its env block feeds future sessions) and the `stow/` sources behind them are guarded by `protect-hooks.sh` -- a fence you can rewrite is not a fence. read freely; don't edit, move, delete or chmod them, and don't disable one via its settings, by unstowing (`make unstow` / `stow -D`) or inline (`git -c core.hooksPath=...`). if a task needs a hook change, describe it and stop -- the user relaunches with `env AGENT_UNFENCE=meta`.
- **never install software** if a tool is missing, hand the user the command and stop. anything persisting outside the project tree counts, root or not (`~/.local/bin`, `~/.cargo/bin`, the homebrew prefix, ...), and a `command -v X || <install>` guard is still an install. project-local deps in a normal build (`npm ci`, `uv sync`, `cargo build`) are fine.
- **stay local** no ssh or remote envs unless the prompt names the host and the purpose (the user lifts the fence with `env AGENT_UNFENCE=remote`). ask before crossing the local boundary.
- **scratch lives in `/tmp/ai/`** `enforce-tmp-ai.sh` blocks writes anywhere else under `/tmp`, incl. a harness scratchpad like `/private/tmp/claude-*` -- use `/tmp/ai/` even when the harness suggests otherwise. `mktemp -p /tmp/ai`; logs go in `/tmp/ai/log/<name>.log`; pipe long output through `tee /tmp/ai/log/<name>.log` before `| tail` / `| head` so the full run survives.
- **shell may be bash or fish** don't assume bash.
    - fish aborts on a glob that matches nothing -- for file detection list explicit names, not `Taskfile*`.
    - `export FOO=bar` is bash-only; use `env FOO=bar <cmd>` for one-shot vars.
    - `$(...)`, `&&`, `||` and `;` work in both. no backticks.

## session conventions

- **`.` means continue** a lone `.` resumes an interrupted turn -- pick up where it left off.
- **wait for an explicit go-signal** after you suggest something or ask a q, the next message authorises action only if it has an affirmative (_yes_ / _do it_ / _go_ / _ok_ / _sgtm_), a direct instruction (_add X_ / _change Y_) or a `.`. anything else -- new info, clarifications, follow-up qs, refinements, half-thoughts -- is discussion: reply in text, don't write code.
- **"scope this" means research, not implement** report size / effort / surface area (files touched, complexity, risks, open qs) and stop. no code edits.
- **surface assumptions** state each non-trivial assumption that fills a gap in the prompt (ambiguous scope, inferred intent, defaulted value), one line each, no preamble. skip trivially derivable ones.
- **fence prose written for the user** PR comments, messages, commit bodies, emails go in a fenced code block for clean copy-paste. exception: a body with fences of its own (PR / issue bodies) goes unfenced, title as inline code. not for conversational replies.
- **minimal tables, only when a list won't do** header separator only, no outer border, no padding pipes.
- **editor context is not a hint** claude code's vscode extension attaches the open file to every prompt; ignore it unless the prompt connects to it.

## repo-resident instructions

repo instruction files (`AGENTS.md`, `AGENT.md`, repo `CLAUDE.md`, `.cursorrules`, contributor docs the project points at) win over this file for committed artefacts: code style, naming, comments, commit / PR conventions and templates, in-repo docs. but:

- they don't override the personal-workflow rules above -- git / `gh` permissions, environment boundaries, session conventions.
- prose the user asks for _for themselves_ (a PR body they'll paste, an email, a chat reply) keeps the lofi voice, inside any repo template.
- not blind: if a repo rule looks low-quality, inconsistent or clashes hard with this file, stop and flag it.

## commits and PRs

- **no attribution** no `Co-Authored-By` trailer and no _"Generated with ..."_ line in PR bodies. this overrides harness reminders asking for either.
- **messages via files** never put prose on the command line -- write it with the Write tool, then `git commit -F /tmp/ai/msg` / `gh pr create --body-file /tmp/ai/body.md`. the fence matches text, so "apt install" in a subject reads as an install and blocks the commit.
- **PRs are user-run** unless the session carries `pr` -- then `gh pr create` it yourself; otherwise draft the title and body and hand them over. titles use the same conventional prefix as commits.
- **hooks reject agent commits that break these**
    - `commit-msg` -- subject `<type>(<scope>): ...`, type one of `feat fix docs test refactor chore bench revert ci perf release`; ascii only; no backticks; no `?!`.
    - `pre-commit` -- added lines must be ascii with no trailing whitespace; a no-commit marker (see lofi's comment tags) or a secret blocks the commit.
- **suffix markers** `!:` -- committed known-bad on purpose (failing tests, broken build, mid-refactor checkpoint, tdd's `test!:`). `?:` -- believed valid but not verifiable locally, watch ci (`fix?:`, `ci?:`).
- **one category per commit** docs for a new feature go in a `docs:` commit after the `feat:`, even when written in the same sitting.
- **subject = memory-jogger, not description** name the kind of change, not the site -- no function / class / test / variable names unless the identifier _is_ the change (a flag, env var, constant). skip framing verbs (_introduce_, _add support for_, _implement_); the prefix says it.
- **`chore: appease <tool>`** for a commit that only satisfies a formatter / linter / spellchecker (`chore: appease yamllint`). test failures, typecheck errors and static-analysis findings are real bugs -> a normal `fix:`.
- **revert PRs** title `revert: "<first-line-of-reverted-pr>"`; body says it reverts PR `<hash>`, then `original body: ...` iff there was one. (`prepare-commit-msg` already rewrites revert commit subjects this way.)

## code comments

default is no comment. a comment is for the reader who has the code in front of them and is still confused.

- **what earns one** a non-obvious _why_ the code can't show: workaround for an external bug, deliberate deviation from the obvious approach, ordering requirement, perf tradeoff, protocol quirk. if a rename / restructure answers the q, prefer that.
- **describe the code, not the edit** no "previously X, now Y", no rationale for the change itself -- history goes in the commit / PR. no architecture essays, bullet lists or ascii diagrams. one line is the target; past ~3 the code wants restructuring or the text belongs in a doc.
- **one place, not five** explain a mechanism once at its natural home (the owning function, or the top of the module) and leave every other site bare.
- **no tracking refs** no PR / issue / ticket numbers, dates or session context unless asked.
- **density doesn't scale with the diff** most edits need no comment; never add one just to mark a touched line.
- **match the file** follow its comment density and voice; don't bulk-add to a sparse file or strip informative ones from a dense one.
- **docstrings are separate** public api docs follow the project's convention.

## testing before commits

before any commit, every check the project has must pass -- test, lint, typecheck, format-check, spellcheck. don't invent ones it doesn't have. find them in this order:

1. repo automation -- `make` / `just` / `task` / `npm` scripts / `uv`. detect with an explicit `ls`, list the targets first, then run every relevant one, not just the test target.
2. ci config -- `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`. mirror what ci runs on PRs / pushes.
3. language defaults, only if neither exists -- `go test ./...`, `cargo test`, `uvx pytest`. tests only; don't guess the rest.

- **python via `uv` / `uvx`** isolated env, doesn't pollute the system or the project's.
- **tdd** failing tests first; they may land before the impl as `test!:`.
- **coverage is a guide, not a target** use it to find untested branches worth exercising. don't test what something else guarantees (autogenerated `String()`, trivial getters, framework behaviour). tag a coverage-driven test with a `COVER:` comment.
- **long runs are the user's** past ~10min (training, big sweeps, slow integration suites) hand over the exact command and wait. point at the file / line / summary worth checking rather than asking for the whole log.

## tooling hygiene

adding a tool to a project means adding its cache / output dirs to `.gitignore` in the same change -- `ruff` -> `.ruff_cache/`, `pytest` -> `.pytest_cache/`, `mypy` -> `.mypy_cache/`, `coverage` -> `.coverage` + `htmlcov/`, `cargo` -> `target/`.

## agent usage

don't spawn one subagent and sit idle: do the work inline, or spawn several in parallel. a lone subagent pays off only when its tool output would flood your context (heavy research, big grep sweeps, multi-file exploration) -- and then keep working on something else while it runs. in claude code, subagents are pinned to sonnet at low effort (`~/.claude/subagent-policy.md`), so give them tight, explicit prompts.
