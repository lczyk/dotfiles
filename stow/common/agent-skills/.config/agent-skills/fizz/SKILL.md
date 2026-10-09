---
name: fizz
description: entry point for fizzbee work. routes a plain-language request to the right fizz skill (fizz-spec, fizz-check, fizz-debug, fizz-mbt), runs the whole model-and-check method for `/fizz <target>`, or prints usage when the intent is unclear. use when the user runs /fizz (with a target, a request, or bare), says "fizz help", or wants to model, formally specify, prove, model-check or "reason about" a design, invariants, liveness, races, caches, retries, reload or watch loops, lifecycles, or asks what a fizzbee / tla+ style spec would catch -- even if they never say "fizzbee". not for pure functions or parsers (table tests) and not for crashes (plain tests).
---

# fizz

entry point for fizzbee work. the four `fizz-*` skills next to this one are vendored from the [fizzbee repo](https://github.com/fizzbee-io/fizzbee) (see `NOTICE-fizz.md`) and own the language, the tool and its failure modes. this one routes to them and carries the method they leave out: the boundary, the requirements, mutation-testing the spec, where the spec lives.

`/fizz` does one of three things:

- **route** -- the request clearly maps to one skill below: load its `SKILL.md` from the sibling directory (e.g. `../fizz-spec/SKILL.md` relative to this file) and follow it, passing the request through as plain language. writing, editing or reviewing a spec -> `fizz-spec`; running the checker or simulator, a guided trace, reading output -> `fizz-check`; a FAILED run, a wrong state count, a timeout -> `fizz-debug`; tests driven from a spec against a real system -> `fizz-mbt`.
- **method** -- `/fizz <target>`, where the target is a component, file, feature or sentence: run the whole process below, loading the skills above as each step needs them.
- **usage** -- no args, "help", or an intent not covered by the above: print the usage block verbatim, then stop. don't guess.

```
fizz -- fizzbee formal modelling

skills:
  /fizz <target>          model a component: requirements, spec, check, mutate, keep
  /fizz-spec <request>    write, edit or review a .fizz spec
  /fizz-check <spec>      run the checker or the simulator, read the output
  /fizz-debug <spec>      a run that fails, is slow or has the wrong state count
  /fizz-mbt <spec>        model-based tests against a real system

usage:
  /fizz src/litescreen    (a component, file, feature or sentence)
  /fizz-check spec.fizz
  or plain language: "model the reload loop", "why does this spec fail"

docs: https://github.com/fizzbee-io/fizzbee (language reference, gotchas, examples)
```

## the method

formal analysis as a working step, not a paper: write down what the thing must do, model it small, let the checker argue, keep the spec where the next reader finds it. method from blog.fizzbee.ai ("your .md file is not a specification"). the language reference is [LANGUAGE_REFERENCE.md](https://github.com/fizzbee-io/fizzbee/blob/main/examples/references/LANGUAGE_REFERENCE.md); `fizz-spec` links the rest.

### when it earns its keep

a model pays off when behaviour depends on **interleaving or time**: several actors or events (user, timer, disk, network, retries, signals), a cache that must agree with the truth, a mode switch, a lifecycle. the checker enumerates orderings no test author would.

skip it, and say so, when:

- the thing is a **pure function** (parser, formatter, arg rewrite): the model would restate the code. write an exhaustive table / bounded test against the real function instead. a model is still fine for _reasoning through_ a rule set if the user wants that; say which you're doing.
- the bug is a **crash or panic**: a plain test is the oracle.
- the invariant would restate one line of code.

### 1. boundary

read the code before modelling. decide:

- **the system**: the component under analysis. its state is what it stores across steps; its actions are its chokepoints (the tick, the reload, the handler, the lock sections of an api call), not every function.
- **the environment**: everything that can change under it -- file on disk, command output, clock, peer, user keys, signals. each becomes an action that nondeterministically does what it may do. a spec permits any behaviour it does not forbid, so write the environment's freedom down explicitly.
- **roles** only when identity matters (two customers, n workers). one actor type -> plain global state, no role.
- **abstraction**: values become small versions (a version number for "file content", `None` for "unavailable", a flag for "a write happened while we held the terminal"). pick the smallest domain that still exercises every branch.

### 2. requirements first

before the model, a numbered list in ears form, in the spec file's header comment:

```
# R1:  THE SYSTEM SHALL load the source once at startup.
# R3:  WHILE -w is given, WHEN the poll interval elapses and the source
#      differs from the buffer, THE SYSTEM SHALL load the source.
# R7:  IF the source is unavailable, THEN THE SYSTEM SHALL keep the
#      previous buffer and show an "error" marker.
```

`WHILE` = state, `WHEN` = event, `IF ... THEN` = unwanted condition. separate **invariants** (hold in every state) from **testable pre / postconditions** (what one action does). phrase in observable behaviour, not the mechanism you're about to model, so the requirement outlives a refactor. tag each assertion with its id (`# R6`). a counterexample later is a gap in this list as often as a bug in the code.

### 3. model

one file, `<component>.fizz`: frontmatter (bounds, options), header comment (what this models, how to run it, the requirements, the decisions the model forced), constants, funcs, `action Init`, actions, assertions. `fizz-spec` has the language; rules that saved time on top of it:

- **bound the environment, not the system**: per-action `max_actions` on user / environment actions, the system's tick unbounded. a global budget gets eaten by environment spam and then the fair tick starves and liveness fails for nothing.
- **terminal states get a successor, deadlock detection stays on** (`atomic action NoOp: pass`). turning detection off hides the state that genuinely cannot move.
- **a mutex section is one `atomic:` block**; a call that drops and retakes a lock is several, with yields between. that is where the races live.
- **the checker injects crashes at yield points by default** (`crash_on_yield`). goroutines and threads don't vanish mid-call: turn it off for in-process models, or every trace carries a `crash` step.
- **a process that died stays dead**: an `alive` flag plus `require alive` at the top of each later block of an in-flight serial action; a failed mid-action `require` parks that thread without a deadlock report.
- **a marker or cache that is a snapshot lags**. put the property on the transition that refreshes it, and write the lag down as a decision.
- **counters for "only via"** (`loads`, `resumes`): `loads <= presses + 1` says "never loads on its own" w/out naming the action.
- nothing in a model is "the code": a transcription of `main()` proves the transcription. say so in the header; the real function gets a test.

### 4. properties

- `always assertion` for invariants.
- `transition assertion Name(before, after)` for what one step may do; return `True` on the stutter / unrelated case first.
- `always eventually` for progress, with `fair` on the action that must keep running; liveness w/out fairness is vacuous or false. weak `fair` by default.
- `exists assertion` as **coverage**: every outcome reachable, every interesting state reached. an `exists` that `Init` already satisfies proves nothing: gate it on a counter of the transition it witnesses.
- the vacuity trap: `[A]p` holds when `A` is disabled. if an action must be possible, assert it (`exists`); if it must be blocked, assert that too.

### 5. run and read

`fizz-check` runs it and reads the output; `fizz-debug` when the run itself is the problem. two things they don't say: a failed `exists` prints `FAILED: Expected states never reached` then `Invariant 0: <Name>` (no colon after the word), and every run drops an `out/` tree plus a `<spec>.json` sidecar next to the spec.

first run is almost always red; triage each counterexample as one of:

- **property wrong** -- it said more than the requirement. fix the property, note why.
- **model wrong** -- the spec does what the code doesn't. fix the model.
- **real finding** -- the requirement list has a hole or the code has a bug. each one is a decision: put it in front of the user with the trace in two lines and the options, record the decision in the header.

iterate until green. a `max_actions` budget running out looks like a liveness failure with a `stutter` at the end: bound differently, don't weaken the property.

### 6. mutation-test the spec

a green spec may be vacuous. for each property, break the model on purpose in a copy (drop the clamp, skip the lock, make the tick load, make it unfair), rerun, confirm the intended property is the one that fails. a mutant that passes means a property is missing or too weak; one property catching every mutant means it is too coarse to name the defect.

hygiene: mutants live in a scratch dir, never next to the spec, since each run litters `out/` and a `.json` beside whatever file it ran. shape:

```sh
mkdir -p <scratch>/fizz-mut && cd <scratch>/fizz-mut
python3 - <<'EOF'
s = open('/path/to/spec.fizz').read()
open('mut_no_clamp.fizz', 'w').write(s.replace("    top = min(top, N)", "    pass"))
EOF
fizz mut_no_clamp.fizz 2>&1 | grep -E '^(PASSED|FAILED|Invariant)'
```

report the table: mutant -> property that caught it.

### 7. keep it

- the spec lives with the docs (`doc/spec/<name>.fizz` or the repo's equivalent); for a package headed for extraction, inside the package dir so it travels. header first: purpose, run line, requirements, decisions.
- gitignore `out/` and `*.json` in the spec dir; a make / just target wrapping the run; a one-line pointer from the component's doc.
- the properties map onto tests: an `always` becomes a sanity check at the chokepoint, a `transition` a test case, a race finding a test that injects the interleaving. prove each fails on the unfixed code first.
- commit the spec on its own (`docs(<scope>): fizzbee model of ...`), the fixes it found separately.

### what to hand back

- the spec file path and the run result (states, pass / fail).
- the findings as decisions, each: what the trace showed, the options, your recc.
- the mutation table.
- what the model does not cover (startup, torn reads, anything abstracted away) in one list.
