agent-config behaviour tests using [`pats`](https://github.com/lczyk/pats). each pair runs a real agent in docker with its HOME seeded from this repo's stow packages (instructions, styles, skills, hooks), then scores what it did.

needs pats >= 0.7.3 and docker. claude runs keyless off `~/.claude/.credentials.json`.

```sh
go install github.com/lczyk/pats/cmd/pats@latest
cd tests/skills
pats run      # slow, live, billed against the subscription
pats score    # offline, scores the latest run
```

not part of `make test`.

- `tasks/_lib.sh` -- copies the tracked files of the stow packages into `$PATS_AGENT_HOME`, patches the copied `settings.json` (host-only keys out, commit signing off, canary marker hooks in), and runs git the way the sandbox does.
- `tasks/prepare_<id>.sh` -- one per task: seed the HOME, lay down the fixture repo.
- `tasks/collect.sh` -- canary markers and the fixture repo's git state, for every task.
- `scorers/scorer_<id>.py` -- uv scripts, shared helpers in `scorers/_lib.py`.

run the `canary` suite first after changing the hooks or the seeding. if it scores under 1, the other results don't mean anything.
