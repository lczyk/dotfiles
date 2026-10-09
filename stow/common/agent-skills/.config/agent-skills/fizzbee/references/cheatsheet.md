# fizzbee cheat sheet

the parts of the language and the tool a spec in the style of `SKILL.md` needs. the full reference is `LANGUAGE_REFERENCE.md` in the fizzbee repo (`examples/references/`), installed locally as `~/.claude/skills/fizzbee-docs/` by `fizz install-skills`, which also adds the upstream `fizz-spec`, `fizz-check`, `fizz-debug` and `fizz-mbt` skills. use those for anything not here (roles, channels, symmetry, fault injection, model-based testing).

## running

```sh
# cli, if installed (homebrew tap fizzbee-io/fizzbee, formula fizzbee)
fizz spec.fizz

# docker, from the spec's directory (the mount is the working dir)
docker run --rm -v "$PWD":/workspace ghcr.io/fizzbee-io/fizzbee:latest spec.fizz
```

- verdict is the `PASSED:` / `FAILED:` line. grep the run: `grep -E '^(PASSED|FAILED|Invariant|panic|Nodes:|Valid)'`.
- a counterexample prints as `------` separated blocks: action name (`Any:live=True` is a nondeterministic pick, `stutter` is the run going nowhere), then `state: {...}`. the first block is `Init`.
- output lands in `out/run_<timestamp>/` next to the spec: `graph.dot` (small graphs), on failure `error-graph.dot`, `error-graph.json`, `error-states.html`. a `<spec>.json` sidecar appears next to the spec too. gitignore `out/` and `*.json` in the spec dir.
- a runtime error is a go panic: `Error evaluating expr: spec.fizz:75:8: undefined: disk` then a stack. the useful line is the first `E...` / `panic:` one.
- a parse error is `line 133:22 mismatched input 'exec' expecting {...}` then a python traceback.
- simulation (random walks, no exhaustiveness): `fizz -x --max_runs 200 --seed 1 spec.fizz`. `exists` assertions are off in simulation.
- `--no-symmetry-reduction`, `--output-dir DIR`, `--preinit-hook 'N = 2'` to override a constant for a small config.

## file shape

frontmatter (optional) between `---` lines, then constants, enums, funcs, roles, `action Init`, actions, assertions.

```
---
options:
  max_actions: 40            # global step budget; default 100
  max_concurrent_actions: 2
action_options:
  Scroll:
    max_actions: 2           # per-action budget: bound the environment here
deadlock_detection: true     # default; keep it, give terminal states a no-op
liveness: strict             # default
---
```

## state, actions, nondeterminism

```
MAX = 3                                  # constant
Mode = enum('OPTS', 'POS')               # Mode.OPTS
LEN = {0: 1, 1: 5}                       # dict; list [] ; set() ; bag()

action Init:                             # assignments here become global state
    tty = oneof [False, True]            # nondeterministic init = config dimension
    files = []

atomic action Feed:                      # atomic = one step; serial (default) yields between statements
    require not done                     # guard: disables the action, never fails
    t = oneof ALPHABET                   # pick; oneof on an empty list disables the action
    consume(t)                           # func call must be a bare statement, or `x = f()`

atomic fair action Tick:                 # fair = weak fairness; fair<strong> exists. order: flow then fairness
    pass                                 # pass alone enables an action; a bare if/require does not

atomic action Finished:                  # terminal state's successor, keeps deadlock detection honest
    require done
    pass

atomic func load():                      # reads/writes globals from an action
    if disk == None:
        return
    buf = disk
```

- starlark, not python: integers only, no `is` (`== None`), no `del`, no try / except, no classes, no imports, no tuple unpacking in `for`, no `list.count` (use `len([x for x in xs if x == v])`), no multi-line comprehensions. `exec` is reserved.
- a top-level func called from the global `Init` does not see the globals yet: inline the startup load. a role's `Init` cannot see a global assigned after it in the enclosing `Init`.
- funcs can't be called from assertions: inline the expression (`opts = argv[0:argv.index('--')] if '--' in argv else argv`).
- `self.x = role.fn()` crashes; `tmp = role.fn()` then assign.
- an unassigned variable keeps its value across a step (no frame axioms).
- roles: `role Node:` with `action Init:` setting `self.*`; `self.__id__` is the identity; `symmetric role` + `bag()` for interchangeable instances.

## assertions

```
always assertion TopInsideBuffer:                        # every state
    return 0 <= top and top < LEN[buf]

transition assertion LoadKeepsViewport(before, after):   # every step; first line handles the stutter / unrelated case
    if after.loads == before.loads:
        return True
    return after.top == min(before.top, max(0, LEN[after.buf] - BODY))

always eventually assertion LiveCatchesUp:               # liveness: needs a fair action to drive it
    return not live or disk == None or buf == disk

eventually always assertion Stabilises:                  # eventually true and stays true
    return done

exists assertion ReachesUsage:                           # coverage: at least one state
    return outcome == Outcome.USAGE
```

- temporal operators don't nest. assertions sit at top level and read role state via the role variables.
- comparing role objects across `before` / `after` is always false; compare `__id__`.

## sizes that work

a spec with 5-8 state variables, 4-6 actions, versions bounded at 3, user / environment actions capped at 2 each: hundreds to low tens of thousands of states, seconds to check. 20k states with liveness took ~8s in docker. if it takes minutes, shrink a constant or a bound, don't drop a property.

## mutation run, one-liner shape

```sh
run() { docker run --rm -v "$PWD":/workspace ghcr.io/fizzbee-io/fizzbee:latest "$1" 2>&1 | grep -E '^(PASSED|FAILED|Invariant:)' | head -2; }
python3 - <<'EOF'
s=open('spec.fizz').read()
open('mut_no_clamp.fizz','w').write(s.replace("    top = min(top, max(0, LEN[buf] - BODY))", "    pass"))
EOF
run mut_no_clamp.fizz; rm -f mut_no_clamp.fizz mut_no_clamp.json
```

each mutant should fail on the property that was written for it; a passing mutant is a missing property.
