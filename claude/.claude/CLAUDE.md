# Global instructions

## Session conventions

- if i send just `.` as a message, treat it as "continue what you were doing" -- sessions sometimes get interrupted, and `.` is my resume signal. pick up where the prior turn left off.
- when prompting from the vscode plugin, the currently open file gets auto-attached as context. it might be relevant, but often isn't -- don't assume relevance just because it's attached. weigh it against the prompt; if the prompt doesn't connect to that file, ignore it.
- when i ask you to generate a piece of natural language (pr comment, message, commit body, email, etc), wrap the output in a fenced code block so i can copy-paste cleanly. does not apply to direct conversational replies.

## Commits and PRs

- do not create PRs unless explicitly instructed. stop after commits.
- do not add yourself (`Co-Authored-By: Claude ...`) as a co-author on commits or in PR bodies.
- create commits only when explicitly prompted to.
- **commit permission does not carry across prompts.** if i ask you to do some work and commit it, that authorisation is consumed by the commit you make in that turn. once that commit lands, you no longer have permission to commit -- including for follow-up tweaks, fixups, or any further work in later prompts. wait for me to explicitly say "commit" again. this applies even if the next prompt is a small edit ("fix this typo", "add a comment") that feels like part of the same task -- stop after the change; do not commit unless told to.
- when creating PRs (only when asked), use Conventional Commits format for the title (e.g. `feat:`, `fix:`, `docs:`, `bench:`, `refactor:`, `revert:`, `chore:`).
- **keep commit categories clean.** one category per commit -- a `feat:` commit contains only the feature itself, and any docs changes describing that feature go in a separate `docs:` commit afterwards. same rule for `test:`, `refactor:`, `chore:`, etc. don't mix categories in one commit just because the changes were made together.
- **revert PRs.** title format: `revert: "<first-line-of-reverted-pr>"` (quote the original subject verbatim). body says this is a PR reverting PR `<hash>`, then `original body: ...` -- include the original body only if there was one; omit the line entirely otherwise.

## Finding repo automation

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

## Testing before commits

before any commit, every check that should pass for a healthy commit must pass -- test, lint, typecheck, format-check, spellcheck, etc. (only the ones that exist; don't invent them). one exception: tdd (see below).

find the right commands in this order:

1. **pre-written automation in the repo** -- see [finding repo automation](#finding-repo-automation). run every relevant target, not just the test one.
2. **ci/pipeline config** -- if no local automation, mirror what ci runs on pr/push. check `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`.
3. **language defaults** -- only if neither exists. e.g. `go test ./...`, `cargo test`, `uvx pytest`. in this fallback, just run tests; don't guess at lint/spellcheck commands.

- **prefer `uv` / `uvx` for python.** runs in an isolated venv, doesn't pollute the system or project env.
- **tdd exception.** if doing test-driven development, write the failing tests first. if asked to commit them before the implementation lands, use `test!:` (with the `!`) to mark the commit as intentionally not passing -- this signals the failing-tests-on-purpose case and distinguishes it from a normal `test:` commit.

## Environment boundaries

- **shell may be bash or fish.** don't assume bash -- the user runs both interchangeably (and the active shell when you're invoked may be either). main pitfalls:
    - **unmatched globs.** fish aborts the command if a glob matches nothing; bash returns the literal. for file detection, list explicit names rather than `Taskfile*` etc.
    - **env vars.** `export FOO=bar` is bash-only. fish uses `set -x FOO bar`. for one-shot use prefer `env FOO=bar <cmd>` -- works in both.
    - **command substitution.** `$(...)` works in both; avoid backticks.
    - **`&&` / `||` / `;`** all work in modern fish (3.x+) and bash, so chaining is fine.
- **never install software or packages.** not via `apt`, `brew`, `pip install`, `npm install -g`, `cargo install`, etc. if a tool is missing, stop and prompt the user; suggest the command they could run, but do not run it yourself. this applies even if the install seems trivial or clearly needed to finish the task.
    - n/a for project-local dependency resolution that's part of normal build flow (e.g. `npm ci` / `uv sync` / `cargo build` pulling declared deps into the project's own lockfile-managed env) -- those are fine.
- **never ssh or work in remote environments** unless explicitly instructed to. no `ssh`, no `scp`, no remote `kubectl exec`, no connecting to remote shells. heads-up the user and ask before doing anything that crosses the local boundary.

## Writing style (non-user-facing prose: comments, commit messages, PR bodies)

- **lowercase by default.** start sentences lowercase. write `i` not `I`. *don't* capitalise generic words just because they start a sentence.
- **only capitalise uncommon acronyms.** common ones stay lowercase: `pr`, `http`, `json`, `llm`, `ci/cd`, `url`, `cpu`, `ram`, `ai`, `tcp`, `ascii`. product names too: `github`, `claude`, `gemini`, `sqlite`, `go`. capitalise when the acronym is genuinely obscure or its capitalisation carries meaning, e.g. `LR(1)` parser, `CASB` (cloud access security broker).
- **casual tone.** avoid corporate or marketing voice. specifics:
    - **contractions.** fine in prose. apostrophes are optional for past contractions (`ive`, `dont`, `wasnt`, `youd`). keep the apostrophe when dropping it would create a different word -- `we'll` vs `well`, `i'd` vs `id`.
    - **short forms welcome.** examples:
        - `w/out` -- without
        - `b/c` -- because
        - `v simple` -- very simple
        - `n/a` -- not applicable
        - `heads-up`
        - `ofc` -- of course
        - `tldr` -- too long; didn't read
        - `noop` (not `no-op`)
        - `tradeoff` (not `trade-off`)
        - `vs` (no dot)
        - `approx` (not `approximately`)
        - `iff` -- if and only if
        - `ff` -- feel free
        - `obv` -- obviously
        - `e2e` -- end-to-end
        - `1-1` -- one-to-one (only for meetings, e.g. *1-1 session*, *1-1 meeting*)
        - `tbd` -- to be discussed (not *to be determined*); often closes a meandering / open-ended thought to signal it's worth talking through rather than decided
        - `tdd` -- test-driven development
        - `prod` -- production, in the broad sense of *the main thing* for the project (not necessarily a deployed service -- could be the main binary, main branch, main artefact, etc.)
        - `kinda` / `kindof` -- *kind of*, as a hedge/intensifier. e.g. *this is kinda sus*, *how about `foo(1,2,mode)`, or this kindof thing?*. only as the hedge contraction; do **not** elide the literal phrase *kind of* when it means *type of* (e.g. *this kind of thing is not allowed* stays as written).
        - `recc` -- recommend
        - `repro` -- reproduce / reproduction
        - `repo` -- repository
        - `wrt` -- with respect to
        - `afaik` -- as far as i know
        - `imo` -- in my opinion (not `imho`)
        - `idk` -- i don't know
        - `nit` -- nitpick (low-priority review comment)
        - `lgtm` -- looks good to me
        - `wip` -- work in progress
        - `-ish` suffix -- fuzz marker, e.g. *5ish lines*, *workingish*
    - **short forms i do *not* use.** avoid these even though they're common: `dupe` (write *duplicate*), `imho` (use `imo` instead).
    - **inline symbols ok.** `~` for *approx.* (e.g. `~15 lines`); `+` for *also* / *in addition* (e.g. `touches 4 lsh files + all definitions`); spaced `/` for *or* between phrases (e.g. `once / if we have one`, `wire up / remove`) -- the spaces distinguish it from compound forms like `ci/cd`, `w/out`, `b/c` where `/` joins without alternation.
    - **punctuation in abbreviations.** write `e.g.` and `i.e.` with the dots (not `eg` / `ie`); `n/a` stays as-is.
- **british english.** write prose in `en-GB`. common differences:
    - `-ise` not `-ize` (`synthesise`, `optimise`, `organise`, `recognise`); but `analyse` (note the `s`).
    - `-our` not `-or` (`colour`, `behaviour`, `favour`).
    - `-re` not `-er` (`centre`, `metre`, `fibre`).
    - `-ence` for nouns where en-US uses `-ense` (`defence`, `offence`, `licence` (noun) / `license` (verb)).
    - `-ogue` not `-og` (`catalogue`, `dialogue`).
    - double-l on inflections (`travelled`, `modelling`, `cancelled`).

    identifiers in code keep their original spelling -- never rewrite `Color` to `Colour`, `Optimize` to `Optimise`, or `Serializer` to `Serialiser`. same for filenames, third-party API names, and standard-library symbols. if prose references such an identifier, quote it in backticks and leave it alone.

---

- **bullets with `-`** (not `*`). short, often fragments.
- **backticks** around code, filenames, flags, commands, package names. use sparingly in comments -- only where they aid scanning.
- **quote chars.** `"` and `'` for quoting natural language; backticks `` ` `` for quoting code. never backtick-quote natural language, never `"`-quote code.
- **emphasis markers.** use `**...**` for bold and `_..._` for italics. when inline-quoting natural language, italicise it: `and then he said: _"hello there!"_`.
- **bold lead-ins, sparingly.** the `- **label.** body` pattern helps when bullets are long or meant to be skimmed by header. skip it for short single-clause bullets, where the bold prefix is just noise. if a reader could find the right bullet without the lead-in, drop it. **never mix lead-ins and non-lead-ins in the same list** -- a list is either entirely lead-in style or entirely not. this also means: in a non-lead-in list, you cannot embolden the first phrase of a bullet for any other reason (emphasis, calling out a key term, etc.) because it would look like a lead-in and break the pattern. if you really want to emphasise something at the start, rephrase the bullet so the emphasised phrase is not the opening, or convert the whole list to lead-in style.
- **`<>` templating.** for theoretical code or cli snippets, prefer `<>` placeholders, e.g. `git clone <upstream-url> --depth 1`. the inside of `<>` should never contain spaces -- use `-` to join words, and prefer a single word where possible.
- **respectively pattern.** when pairing two lists of items, use *respectively* instead of spelling each pair out, e.g. "the `--build` and `--test` flags wrap `just build` and `just test`, respectively."
- **`alas` for resigned acknowledgement.** drop in mid-sentence to flag that something is an unfortunate but accepted limitation -- not a problem to fix, just a fact. e.g. `` `Package` cannot, alas, really be frozen. ``. signals "i know, but that's how it is".
- **`tbd` to close open-ended thoughts.** when a thought is meandering or genuinely undecided and worth talking through rather than resolved on the spot, end with `tbd` (*to be discussed*). signals it's an open question, not a conclusion.
- **`tldr;` to open a summary line.** lead a paragraph with `tldr; <one-line gist>` when the bottom line is worth pulling up front before details. lowercase, semicolon, no caps after. use sparingly -- only in shorter / less structured bits like PR descriptions or chat-style notes; not a default. never in code comments.

---

- **ASCII only -- no unicode tells.** hard rule. these characters must never appear in prose; use the ASCII equivalent instead:
    - em-dash `—` -> `--`
    - en-dash `–` -> `-`
    - ellipsis `…` -> `...`
    - smart/curly quotes `“ ” ‘ ’` -> `"` and `'`
    - arrows `→ ← ⇒ ⇐` -> `->`, `<-`, `=>`, `<=`
    - bullet glyph `•` -> `-`
    - check/cross marks `✓ ✗` -> `[x]`, `[ ]` or words
    - math operators `≥ ≤ ≠ × ÷` -> `>=`, `<=`, `!=`, `x`, `/`
    - `™ © ®` -> drop entirely
    - non-breaking spaces and zero-width spaces -> regular space or nothing
- **avoid llm filler phrases.** stock phrases that don't carry information are the giveaway. specifically skip: *moving the needle*, *at the end of the day*, *deep dive*, *the elephant in the room*, *boil the ocean*, *cutting-edge*, *swing for the fences*, *seamless*, *robust solution*, *leverage* (as a verb), *delve into*, *navigate* (as a metaphor). idioms the user actually uses are fine: *low-hanging fruit*, *rule of thumb*, *under the hood*, etc.

---

- **PR bodies open with the description**, no fluff preamble. a one-line lead-in is fine ("this PR adds X. ...").
- **PR template headers** like `## Proposed changes`, `### Forward porting` -- keep as-is when the repo template uses them.
- **don't over-explain.** state what changed and why if non-obvious. skip the *what* when the diff is the answer.
- **uppercase tag prefixes for callout comments.** when a code comment exists to flag a specific *kind* of concern -- not just describe the code -- lead with an uppercase tag followed by a colon so it's greppable. the rest of the comment stays lowercase per the usual style. common tags:
    - `PERF:` -- explains a non-obvious choice made for performance reasons (avoiding an alloc, caching a result, picking a less idiomatic shape because the obvious one was hot).
    - `NOTE:` -- a subtle invariant, hidden constraint, or surprising behaviour a future reader should know about.
    - `TODO:` -- deferred work; ideally followed by enough context to act on later.
    - other accepted tags: `FIXME:`, `HACK:`. use sparingly -- only when the tag genuinely adds scanning value over a plain comment.

---

apply these to: code comments, commit messages, PR titles/bodies, design notes. **do not** apply to user-facing UI text or end-user-facing docs unless the user says so. for docs, judge the style from existing docs in the project -- don't use casual style in docs that aren't already casual. when creating new docs, match the style of other docs in the project. iff the project has no other docs, default to casual style.
