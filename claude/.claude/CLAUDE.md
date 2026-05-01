# Global instructions

## Repo-resident instructions

repo-resident instruction files (`AGENT.md`, `AGENTS.md`, repo-level `CLAUDE.md`, `.cursorrules`, contributor docs the project points at, etc.) generally win over this file for anything that lands in the repo -- code style, naming, comment conventions, commit/PR style, in-repo doc style. respect what the project asks for.

caveats:

- not blind. if a repo rule looks low-quality, internally inconsistent, or conflicts severely with the rules here (e.g. asks for behaviour that would be actively harmful, or demands wildly divergent conventions w/out apparent reason), stop and flag it to me -- ask for resolution rather than just complying.
- scope is committed artefacts only: code, comments, commit messages, PR titles/bodies merged into the repo, in-repo docs. does **not** apply when i ask you to generate natural language *for me* (a PR message i'll paste, an email, a chat reply, etc.) -- those follow this file's style regardless of what repo the cwd happens to be in.
- does **not** override personal-workflow rules (git/`gh` permissions, session conventions, environment boundaries). those always apply.

## Session conventions

- if i send just `.` as a message, treat it as "continue what you were doing" -- sessions sometimes get interrupted, and `.` is my resume signal. pick up where the prior turn left off.
- when prompting from the vscode plugin, the currently open file gets auto-attached as context. it might be relevant, but often isn't -- don't assume relevance just because it's attached. weigh it against the prompt; if the prompt doesn't connect to that file, ignore it.
- when i ask you to generate a piece of natural language (pr comment, message, commit body, email, etc), wrap the output in a fenced code block so i can copy-paste cleanly. does not apply to direct conversational replies.

## Git and `gh` permissions

- **git read-only ops: no permission needed.** `status`, `log`, `diff`, `show`, `blame`, `branch --list`, `remote -v`, etc. -- run freely as part of investigation.
- **`gh` needs permission unless the prompt implies it.** invocations like `gh pr view`, `gh issue view`, `gh api` count as reaching out to a remote; ask first. exception: when the prompt clearly invites it (e.g. *"look at this issue <github-link>"*, *"read the comments on PR 123"*, *"check ci status"*) -- treat that as implicit permission for the read action being requested. write `gh` ops (`gh pr create`, `gh issue create`, `gh pr comment`, etc.) follow the per-prompt explicit-permission rule below.
- **never run write git / `gh` ops without explicit per-prompt permission.** this covers `commit`, `commit --amend`, `revert`, `branch` (create/delete), `cherry-pick`, `tag`, `push`, `reset --hard`, `checkout` of files, `gh pr create`, `gh issue create`, comments / reviews / merges via `gh`, and anything else that mutates local repo state or remote github state. permission is per-prompt: granting it for one turn does *not* carry to follow-up turns -- once the authorised op lands, permission is consumed. if a later prompt asks for a small follow-up edit, stop after the edit; do not commit / amend / revert / push unless explicitly told to in *that* prompt.
- **never run complex / risky git ops at all.** `rebase` (interactive or not), `merge`, `reset` (any mode), `filter-branch`, `filter-repo`, `reflog expire`, `gc --prune`, force-push, branch-rename of in-use branches, history rewrites generally. these need a human; surface what youd do and stop.
- do not create PRs unless explicitly instructed. stop after commits.
- create commits only when explicitly prompted to.
- **commit permission does not carry across prompts.** if i ask you to do some work and commit it, that authorisation is consumed by the commit you make in that turn. once that commit lands, you no longer have permission to commit -- including for follow-up tweaks, fixups, or any further work in later prompts. wait for me to explicitly say "commit" again. this applies even if the next prompt is a small edit ("fix this typo", "add a comment") that feels like part of the same task -- stop after the change; do not commit unless told to.

## Commits and PRs

- do not add yourself (`Co-Authored-By: Claude ...`) as a co-author on commits or in PR bodies.
- when creating PRs (only when asked), use Conventional Commits format for the title (e.g. `feat:`, `fix:`, `docs:`, `bench:`, `refactor:`, `revert:`, `chore:`).
- **conventional-commit suffix markers.** two extensions to the standard prefix:
    - `!:` -- the commit is intentionally broken. signals known-bad state (failing tests, broken build, half-landed migration) committed on purpose -- e.g. tdd's failing tests landed before the impl (`test!:`), or a deliberate mid-refactor checkpoint. distinguishes intentional breakage from accidental.
    - `?:` -- we *think* the commit is valid but cannot fully verify locally; might fail ci, remote tests, or other remote validation. e.g. `fix?:`, `ci?:`. signals "best effort, watch ci".
- **keep commit categories clean.** one category per commit -- a `feat:` commit contains only the feature itself, and any docs changes describing that feature go in a separate `docs:` commit afterwards. same rule for `test:`, `refactor:`, `chore:`, etc. don't mix categories in one commit just because the changes were made together.
- **commit subject lines: bare-minimum reminder, not a description.** the subject is just a memory-jogger for what the commit is vaguely about; details live in the diff and (if needed) the body. principles:
    - **avoid specific identifiers** -- function names, class names, test names, variable names. they bloat the subject and are easily found in the diff. exception: when the identifier *is* the subject (e.g. introducing a single named flag/env var/constant, where naming it conveys the whole change).
    - **skip framing verbs and connective tissue** -- *introduce*, *add support for*, *implement*, *make it so that*, etc. -- when the category prefix (`feat:`, `fix:`, `refactor:`) already conveys the action.
    - **prefer the abstract noun over the concrete instance** -- name the kind of change, not the specific site; unless naming the specific thing is the point (per above).
- **`appease <tool>` for cosmetic-only fix-ups.** when a commit exists solely to satisfy a non-functional convention tool -- formatter, linter, spellchecker, style-only rules -- use the form `appease <tool-name>` (e.g. `appease yamllint`, `appease prettier`, `appease codespell`). only for purely cosmetic conventions; do **not** use for test failures, typechecker errors, or static-analysis findings (those are real bugs and warrant a normal `fix:` with a real subject).
- **revert PRs.** title format: `revert: "<first-line-of-reverted-pr>"` (quote the original subject verbatim). body says this is a PR reverting PR `<hash>`, then `original body: ...` -- include the original body only if there was one; omit the line entirely otherwise. when generating the revert with `git revert`, the default message git produces will *not* match this format -- amend the commit message after `git revert` to bring it into the format above.

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

## Tooling hygiene

- **adding a tool means handling its artefacts too.** when you add a tool to a project (linter, formatter, test runner, type checker, build tool, etc.), also add its cache / output / artefact dirs to `.gitignore` in the same change. e.g. adding `ruff` -> add `.ruff_cache/`; `pytest` -> `.pytest_cache/`; `mypy` -> `.mypy_cache/`; `coverage` -> `.coverage`, `htmlcov/`; `cargo` -> `target/`. don't wait for the cache to show up in `git status` and surprise the user.

## Writing style (non-user-facing prose: comments, commit messages, PR bodies)

- **lowercase by default.** start sentences lowercase. write `i` not `I`. *don't* capitalise generic words just because they start a sentence.
- **only capitalise uncommon acronyms.** common ones stay lowercase: `http`, `json`, `llm`, `ci/cd`, `url`, `cpu`, `ram`, `ai`, `tcp`, `ascii`, `id` (identifier). product names too: `github`, `claude`, `gemini`, `sqlite`, `go`. capitalise when the acronym is genuinely obscure or its capitalisation carries meaning, e.g. `LR(1)` parser, `CASB` (cloud access security broker). exception: `PR` is always capitalised (personal habit, overrides the lowercase-common rule).
- **casual tone.** avoid corporate or marketing voice. specifics:
    - **contractions.** fine in prose. apostrophes are optional for past contractions (`ive`, `dont`, `wasnt`, `youd`). keep the apostrophe when dropping it would create a different word or collide with another token -- `we'll` vs `well`, `we're` vs `were`, `i'd` vs `id` (the latter clashes with `id`, the lowercase form of `ID`/identifier -- always write `i'd` with the apostrophe).
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
        - `ff` -- feel free. note: `ff` is also git jargon for *fast-forward* (`--ff-only`, *ff merge*); disambiguate by context -- in prose around git ops it likely means fast-forward, elsewhere it means feel free.
        - `obv` -- obviously
        - `e2e` -- end-to-end
        - `1-1` -- one-to-one (only for meetings, e.g. *1-1 session*, *1-1 meeting*)
        - `tbd` -- to be discussed (not *to be determined*); often closes a meandering / open-ended thought to signal it's worth talking through rather than decided
        - `tbh` -- to be honest; hedge / softener flagging a candid take, e.g. *tbh i'd just delete the helper*
        - `tdd` -- test-driven development
        - `prod` -- production, in the broad sense of *the main thing* for the project (not necessarily a deployed service -- could be the main binary, main branch, main artefact, etc.)
        - `kinda` / `kindof` -- *kind of*, as a hedge/intensifier. e.g. *this is kinda sus*, *how about `foo(1,2,mode)`, or this kindof thing?*. only as the hedge contraction; do **not** elide the literal phrase *kind of* when it means *type of* (e.g. *this kind of thing is not allowed* stays as written).
        - `recc` -- recommend
        - `repro` -- reproduce / reproduction
        - `repo` -- repository
        - `ppl` -- people
        - `wrt` -- with respect to
        - `afaik` -- as far as i know
        - `imo` -- in my opinion (not `imho`)
        - `idk` -- i don't know
        - `nit` -- nitpick (low-priority review comment)
        - `lgtm` -- looks good to me
        - `wip` -- work in progress
        - `atm` -- at the moment
        - `aka` -- also known as
        - `pls` -- please
        - `2c` -- two cents, as in *my 2c on this*; flags a take as personal opinion rather than a settled view
        - `-ish` suffix -- fuzz marker, e.g. *5ish lines*, *workingish*
        - `-esque` suffix -- approximate-identity marker, for when something acts like X but isn't strictly X. e.g. *singleton-esque* (behaves like a singleton, but technically may not satisfy all the criteria). use sparingly
        - `env` -- environment
        - `cwd` -- current working directory (prefer over `pwd`, which is the shell builtin, not the abbreviation)
        - `re` -- regarding / about, as a topic marker introducing what a thought is *about*. tighter than *regarding* / *with respect to* (`wrt`). usage:
            - **inline, mid-sentence** -- attaches a topic to a noun phrase: *guideline re conventional commits*, *thoughts re rollout plan*, *question re cache invalidation*.
            - **leading, as a topic header** -- opens a thought with the subject before the substance: *re naming: `foo` reads ambiguous*, *re migration: we should backfill first*. especially common inside the colon-chained hierarchy (*unrelated: re phrasing: ...*, *nit: re error wrapping: ...*).
            - **drop articles after `re`.** *re cache invalidation* not *re the cache invalidation*; *re migration* not *re the migration*. exception: when the article is part of a proper noun or specific reference that would be ambiguous w/out it.
            - not a verb -- only a preposition / topic marker. lowercase even at sentence start.
        - `smth` -- something
    - **short forms i do *not* use.** avoid these even though they're common: `dupe` (write *duplicate*), `imho` (use `imo` instead).
    - **inline symbols ok.** `~` for *approx.* (e.g. `~15 lines`); `+` for *also* / *in addition* (e.g. `touches 4 lsh files + all definitions`); spaced `/` for *or* between phrases (e.g. `once / if we have one`, `wire up / remove`) -- the spaces distinguish it from compound forms like `ci/cd`, `w/out`, `b/c` where `/` joins without alternation.
    - **punctuation in abbreviations.** write `e.g.` and `i.e.` with the dots (not `eg` / `ie`); `n/a` stays as-is.
    - **no emoji in generated prose.** PR bodies, comments, commit messages, drafts, etc. -- keep emoji-free regardless of the surrounding tone of the thread.
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
- **backticks** around code, filenames, flags, commands, package names in prose (PR bodies, design notes, docs, chat). **do not** backtick identifiers in code comments -- the comment sits right next to the code, the reader doesn't need scanning aids to tell prose from idents. rare exception: a long prose-like comment block (multiple paragraphs of explanation, far from the thing it names) where backticks genuinely help disambiguate. default: no backticks in comments. do not go through existing comments adding backticks.
- **quote chars.** `"` and `'` for quoting natural language; backticks `` ` `` for quoting code. never backtick-quote natural language, never `"`-quote code.
- **emphasis markers.** use `**...**` for bold and `_..._` for italics. when inline-quoting natural language, italicise it: `and then he said: _"hello there!"_`.
- **bold lead-ins, sparingly.** the `- **label.** body` pattern helps when bullets are long or meant to be skimmed by header. skip it for short single-clause bullets, where the bold prefix is just noise. if a reader could find the right bullet without the lead-in, drop it. **never mix lead-ins and non-lead-ins in the same list** -- a list is either entirely lead-in style or entirely not. this also means: in a non-lead-in list, you cannot embolden the first phrase of a bullet for any other reason (emphasis, calling out a key term, etc.) because it would look like a lead-in and break the pattern. if you really want to emphasise something at the start, rephrase the bullet so the emphasised phrase is not the opening, or convert the whole list to lead-in style.
- **`<>` templating.** for theoretical code or cli snippets, prefer `<>` placeholders, e.g. `git clone <upstream-url> --depth 1`. the inside of `<>` should never contain spaces -- use `-` to join words, and prefer a single word where possible.
- **respectively pattern.** when pairing two lists of items, use *respectively* instead of spelling each pair out, e.g. "the `--build` and `--test` flags wrap `just build` and `just test`, respectively."
- **`alas` for resigned acknowledgement.** drop in mid-sentence to flag that something is an unfortunate but accepted limitation -- not a problem to fix, just a fact. e.g. `` `Package` cannot, alas, really be frozen. ``. signals "i know, but that's how it is".
- **`tbd` to close open-ended thoughts.** when a thought is meandering or genuinely undecided and worth talking through rather than resolved on the spot, end with `tbd` (*to be discussed*). signals it's an open question, not a conclusion.
- **colon-chained hierarchy.** lay out a thought as `topic: subtopic: sub-subtopic: actual-point` -- each colon narrows scope one level, like nested error wrapping. use to flag *what* a thought is about before getting to the substance, especially in chat-style notes / review comments / loose lists where multiple unrelated points share a context. e.g. *unrelated: re phrasing: i often use ...*, *nit: naming: `foo` reads ambiguous*. lowercase throughout. don't force it -- only when there's a genuine hierarchy worth signalling.
- **`tldr;` to open a summary line.** lead a paragraph with `tldr; <one-line gist>` when the bottom line is worth pulling up front before details. lowercase, semicolon, no caps after. use sparingly -- only in shorter / less structured bits like PR descriptions or chat-style notes; not a default. never in code comments.
- **`-//-` for ditto.** means *same as the line above*, repeating the column-aligned text directly above. only valid when `-//-` is column-aligned with the phrase it stands in for -- works well in tables or list items where the repeat is unambiguous. e.g.
    - `migrate the user-service handlers to the new auth middleware`
    - `-//- billing-service`

    = *migrate the billing-service handlers to the new auth middleware*.
- **`^` for pointer-to-above.** unlike `-//-`, does not imply alignment or repetition -- just points at something earlier in the surrounding text, often the previous bullet or sentence. e.g. `the retry path swallows the 503. ^ also masks 504s in staging.` = the retry-path-swallowing behaviour also masks 504s.
- **`!?` vs `?!`.** order matters and conveys different tone:
    - `!?` -- surprised question. the `!` colours the `?` with curiosity / mild incredulity. e.g. *the test passes locally!?*, *that's the whole fix!?*.
    - `?!` -- outraged question, signals indignation / exasperation. avoid -- too charged for technical prose; rephrase plainly instead.
- **`(?)` for implied question.** trailing `(?)` softens a declarative statement into an up-for-discussion soft question -- *"this is what i think / am suggesting, but tell me if i'm off"*. lets the sentence keep declarative shape while flagging it as not-fully-asserted. e.g. *pls have a double check that nothing is missing(?)*, *an alternative approach would be to add a `private:` field and not rely on `_`(?)*. distinct from a full `?` interrogative, which restructures the whole sentence as a direct question.
- **`...` for unfinished / mulling thought.** in-the-moment hedge marking a thought as not-yet-resolved. two flavours:
    - mid-sentence pause -- *probably we want... or dashes*, *unsure about the structure here... maybe split it*.
    - sentence-end open thought -- *unsure about the structure here...*, *don't see a reason why not ...*.
    distinct from `tbd` (a deliberate "let's discuss" marker) -- `...` is thinking-aloud, not a flagged item to revisit. only in chat-style notes / PR comments / loose prose; never in code comments or commit messages.
- **letter-stretching for emphasis.** elongate a vowel or consonant to convey tone -- e.g. *muuuch cleaner code* (intensifier), *too too much back and forth* (repetition variant; same effect). expressive register only -- chat / PR comments; never in code comments, commit messages, or docs.

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
    - greek mu `µ` / `μ` as the *micro-* prefix -> `u` (e.g. `us` for microseconds, `ug` for micrograms)
    - non-breaking spaces and zero-width spaces -> regular space or nothing
- **avoid llm filler phrases.** stock phrases that don't carry information are the giveaway. specifically skip: *moving the needle*, *at the end of the day*, *deep dive*, *the elephant in the room*, *boil the ocean*, *cutting-edge*, *swing for the fences*, *seamless*, *robust* (and *robust solution*), *leverage* (as a verb), *delve into*, *navigate* (as a metaphor), *tapestry*, *vibrant*, *intricate* / *intricacies*, *foster* / *fostering*, *garner*, *showcase* (as verb), *crucial*, *valuable* (as bare praise), *key* (as filler adjective, e.g. *a key part of*). idioms the user actually uses are fine: *low-hanging fruit*, *rule of thumb*, *under the hood*, etc.

---

- **PR bodies open with the description**, no fluff preamble. a one-line lead-in is fine ("this PR adds X. ...").
- **PR template headers** like `## Proposed changes`, `### Forward porting` -- keep as-is when the repo template uses them.
- **don't over-explain.** state what changed and why if non-obvious. skip the *what* when the diff is the answer.
- **be realistic in PR bodies, not falsely positive or negative.** skip generic upbeat closers (*the future looks bright*, *exciting times ahead*, *a major step forward*, *this unlocks...*) and skip self-flagellating ones too. prefer concrete, verifiable signal: tests passing, benchmark numbers, before/after sizes, error counts, profile snapshots. *"reduces p99 from 240ms to 90ms on the `loadtest` bench, 3 runs"* beats *"significant performance improvement"*. if there's no measurable result yet, say so plainly rather than inflating qualitative claims.
- **uppercase tag prefixes for callout comments.** when a code comment exists to flag a specific *kind* of concern -- not just describe the code -- lead with an uppercase tag followed by a colon so it's greppable. the rest of the comment stays lowercase per the usual style. common tags:
    - `PERF:` -- explains a non-obvious choice made for performance reasons (avoiding an alloc, caching a result, picking a less idiomatic shape because the obvious one was hot).
    - `NOTE:` -- a subtle invariant, hidden constraint, or surprising behaviour a future reader should know about.
    - `TODO:` -- deferred work; ideally followed by enough context to act on later.
    - other accepted tags: `FIXME:`, `HACK:`. use sparingly -- only when the tag genuinely adds scanning value over a plain comment.

---

prose that screams "an llm wrote this" has recurring shapes. avoid them:

- **significance inflation.** dont puff up importance with abstract weight. ban: *testament to*, *pivotal moment*, *underscores its importance*, *evolving landscape*, *marks / represents a shift*, *vital role*, *deeply rooted*, *indelible mark*, *setting the stage for*, *a turning point*. state the fact directly; if the significance is real, the reader will see it from the fact itself.
- **copula avoidance.** prefer plain *is / are / has*. dont substitute *serves as*, *stands as*, *functions as*, *acts as*, *boasts*, *features* (as a verb), *represents* (as identity, e.g. *X represents a new approach to Y* -- just say *X is a new approach to Y*). e.g. write *`Cache` is the in-memory store* not *`Cache` serves as the in-memory store*.
- **superficial -ing tails.** dont tack on present-participle clauses to fake depth: *highlighting...*, *underscoring...*, *emphasising...*, *ensuring...*, *reflecting...*, *symbolising...*, *contributing to...*, *fostering...*, *showcasing...*, *encompassing...*. either cut the tail or split into a real sentence with concrete content -- the participle phrase almost never carries information.
- **persuasive-authority tropes.** phrases that pretend to cut through noise to a deeper truth: *the real question is*, *at its core*, *fundamentally*, *what really matters*, *in reality*, *the heart of the matter*, *the deeper issue*. usually the next sentence just restates an ordinary point with extra ceremony. drop the framing; lead with the point.
- **fragmented headers.** dont follow a heading with a one-line restating paragraph before the real content (e.g. `## Performance` then `Speed matters.` then the real text). heading, then content directly.
- **synonym-cycling.** llms rotate synonyms within a paragraph b/c they treat repetition as a style flaw. it isnt -- reusing the same noun/verb across nearby sentences is clearer than swapping in a near-synonym that subtly shifts meaning. if youre talking about a `Cache`, call it the cache every time; dont alternate with *the store*, *the buffer*, *the layer*. same for verbs -- pick one and stick with it. swap only when the meaning genuinely differs.
- **passive-to-hide-actor.** dont reach for the passive when you know who or what is doing the thing. *"it has been decided that..."*, *"the file is processed and the result is returned"*, *"errors are logged"* -- name the actor: *"i decided ..."*, *"`run()` processes the file and returns the result"*, *"`handle_err` logs errors"*. passive is fine when the actor is genuinely unknown, irrelevant, or obvious from context; it's an llm tell when used to dodge specifics.
- **flattering / framing openers.** two related shapes to ban at the start of a response or paragraph:
    - **sycophantic openers** -- *great question*, *thats a really interesting point*, *absolutely*, *what a thoughtful observation*. just answer.
    - **content-free framing prefixes** -- *its worth noting that*, *its important to understand that*, *keep in mind that*, *it should be mentioned that*, *one thing to consider is*. drop the prefix and lead with the actual point. iff the noting/considering really is the point (rare), say so concretely.
- **restraint over enthusiasm.** a dry statement carries more weight than an excited one. write *"this works"* not *"this works beautifully!"*; *"the fix landed"* not *"great news -- the fix landed!"*. exclamation marks are almost never warranted in technical prose. enthusiasm-as-default reads as performative; let the facts be the signal.

---

apply these to: code comments, commit messages, PR titles/bodies, design notes. **do not** apply to user-facing UI text or end-user-facing docs unless the user says so. for docs, judge the style from existing docs in the project -- don't use casual style in docs that aren't already casual. when creating new docs, match the style of other docs in the project. iff the project has no other docs, default to casual style.
