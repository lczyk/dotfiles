---
name: fizzbee
description: analyse a component, protocol, state machine or feature with FizzBee formal modelling -- requirements in ears form, a small executable spec, the model checker (fizz cli or docker), counterexamples read as requirement gaps, properties mutation-tested, spec kept next to the docs. use for `/fizzbee <target>`, and whenever the user wants to model, formally specify, prove, model-check or "reason about" a design, invariants, liveness, races, caches, retries, reload or watch loops, or asks what a fizzbee / tla+ style spec would catch -- even if they never say "fizzbee". not for pure functions or parsers (table tests) and not for crashes (plain tests).
---

# fizzbee

formal analysis as a working step, not a paper: write down what the thing must do, model it small, let the checker argue, keep the spec where the next reader finds it. the method is from blog.fizzbee.ai ("your .md file is not a specification") plus what the edit repo's viewer / cli specs taught.

`/fizzbee <target>` -- `<target>` is a component, file, feature or sentence. figure out the system boundary from it (below), then run the whole process. with no target, ask what to model in one line.

## when it earns its keep

a fizz model pays off when behaviour depends on **interleaving or time**: several actors or events (user, timer, disk, network, retries), a cache that must agree with the truth, a mode switch, a lifecycle. the checker enumerates orderings no test author would.

skip it, and say so, when:

- the thing is a **pure function** (parser, formatter, arg rewrite): the model would restate the code. write an exhaustive table / bounded test against the real function instead. a model is still fine for _reasoning through_ a rule set if the user wants that; say which you're doing.
- the bug is a **crash or panic**: a plain test is the oracle.
- the invariant would restate one line of code.

## process

### 1. boundary

read the code before modelling. decide:

- **the system**: the component under analysis. its state is what it stores across steps; its actions are its chokepoints (the tick, the reload, the handler, the publish point), not every function.
- **the environment**: everything that can change under it -- file on disk, command output, clock, peer, user keys. each becomes an action that nondeterministically does what it may do. a spec permits any behaviour it does not forbid, so write the environment's freedom down explicitly.
- **roles** only when identity matters (two customers, n workers). one actor type -> plain global state, no role.
- **abstraction**: values become small versions (a monotonic version number for "file content", `None` for "unavailable", a 3-state lexer for "the highlighter"). pick the smallest domain that still exercises every branch of the rule: lengths 1 / 5 / 3 rather than real sizes.

### 2. requirements first

before the model, a numbered list in ears form, in the spec file's header comment:

```
# R1:  THE SYSTEM SHALL load the source once at startup.
# R3:  WHILE -w is given, WHEN the poll interval elapses and the source
#      differs from the buffer, THE SYSTEM SHALL load the source.
# R3b: WHILE -w is given, WHEN the poll interval elapses and the source
#      equals the buffer, THE SYSTEM SHALL NOT touch the buffer.
# R7:  IF the source is unavailable, THEN THE SYSTEM SHALL keep the
#      previous buffer and show an "error" marker.
```

`WHILE` = state, `WHEN` = event, `IF ... THEN` = unwanted condition. separate **invariants** (hold in every state, not directly testable) from **testable pre / postconditions** (what one action does). phrase in observable behaviour, not the mechanism you're about to model, so the requirement outlives a refactor. tag each spec line and assertion with its id (`# R6`). a counterexample later is a gap in this list as often as a bug in the code.

### 3. model

one file, `<component>.fizz`. shape:

```
---
# frontmatter only when needed: per-action bounds, options
action_options:
  PressR:
    max_actions: 2
---

# header: what this models, how to run it, the requirements, the
# decisions the model forced.

MAX_VERSION = 3                     # constants, small
Marker = enum('NONE', 'MODIFIED', 'ERROR')

action Init:
    live = oneof [False, True]      # a config dimension: one spec, both modes
    disk = 1
    buf = 0

atomic action SourceChange:         # environment
    require disk != None and disk < MAX_VERSION
    disk += 1

atomic fair action Tick:            # the system's chokepoint
    ...

atomic func load():                 # shared mechanism, called from actions
    ...

always assertion TopInsideBuffer:   # R8
    return 0 <= top and top < LEN[buf]
```

rules that saved time:

- **bound the environment, not the system**: give user / environment actions `max_actions` in `action_options`, keep the system's tick unbounded. a global `max_actions` gets eaten by spam (nine `PressR`s) and then the fair tick starves and liveness fails for nothing.
- **terminal states get a successor, deadlock detection stays on**. a finished run is `atomic action Finished: require done` + `pass`, or `atomic action NoOp: if done: pass`. turning `deadlock_detection` off hides the state that genuinely cannot move.
- **a marker or cache that is a snapshot lags**. "the marker never lies" fails one tick after the world changes. put the property on the transition that refreshes it (`transition assertion ... if after.last == Act.TICK`), and write the lag down as a decision.
- **last-action register**: `last = Act.TICK` in every action makes transition assertions readable (`after.last in [PRESS_R, TICK]`).
- **counters for "only via"**: `loads`, `r_presses` -- then `loads <= r_presses + 1` says "static mode never loads on its own" w/out naming the action that did it.
- nothing in a model is "the code": `dispatch()` transcribing the real `main()` is a transcription, and the model then proves the transcription. say so in the header; the real function gets a test.

### 4. properties

- `always assertion` for invariants (R-lines with SHALL ENSURE).
- `transition assertion Name(before, after)` for what one step may do; return `True` on the stutter / unrelated case first.
- `always eventually` for progress with `fair` on the action that must keep running; liveness w/out fairness is vacuous or false. use weak `fair` by default, `fair<strong>` only when weak provably can't.
- `exists assertion` as **coverage**: every outcome reachable, every interesting state reached. a green run with an unreachable branch proves nothing about that branch.
- state the vacuity trap: `[A]p` holds when `A` is disabled. if an action must be possible, assert it (`exists`), and if it must be blocked, assert that too.

### 5. run and read

see `references/cheatsheet.md` for the exact commands (fizz cli if installed, the docker one-liner otherwise), output paths and the error shapes. first run is almost always red; triage each counterexample as one of:

- **property wrong** -- it said more than the requirement (e.g. demanded equality where `<=` was meant). fix the property, note why.
- **model wrong** -- the spec does what the code doesn't. fix the model.
- **real finding** -- the requirement list has a hole or the code has a bug. this is the point of the exercise: each one is a decision (block / cascade / flag -> a product call), so put it in front of the user with the trace in two lines and the options, and record the decision in the header under "decisions the model forced".

iterate until green. a `max_actions` budget running out looks like a liveness failure w/ a `stutter` at the end: bound differently, don't weaken the property.

### 6. mutation-test the spec

a green spec may be vacuous. for each property, break the model on purpose (drop the clamp, make the static tick load, blank the buffer on error, make the tick unfair) in a copy, rerun, and confirm the intended property is the one that fails. a mutant that passes means a property is missing or too weak. report the table.

### 7. keep it

- the spec lives with the docs (`doc/spec/<name>.fizz` or the repo's equivalent), header first: purpose, run line, requirements, decisions. the checker's `out/` dir and `.json` sidecar go in `.gitignore`.
- a make / just target wrapping the run; a one-line pointer from the component's doc page.
- the properties map onto tests: an `always` becomes a sanity check at the chokepoint, a `transition` becomes a test case. do that next, and prove the test fails on the unfixed code first.
- commit the spec on its own (`docs(<scope>): fizzbee model of ...`), the fixes it found separately.

## what to hand back

- the spec file path and the run result (states, pass / fail).
- the findings as decisions, each: what the trace showed, the options, your recc.
- the mutation table.
- what the model does not cover (startup, torn reads, anything abstracted away) in one list.
