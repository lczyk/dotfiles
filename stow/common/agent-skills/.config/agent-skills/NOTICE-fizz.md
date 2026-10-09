vendored from https://github.com/fizzbee-io/fizzbee (Apache-2.0), commit `579328a5778169d5bda37b1c9fb95c4f5d28621e`, path `.claude/skills/`. see `LICENSE-fizz`.

vendored files:
- `skills/fizz-spec/` -- writing, editing or reviewing a `.fizz` spec
- `skills/fizz-check/` -- running the model checker or the simulator, reading its output
- `skills/fizz-debug/` -- a failing, slow or wrong-sized model check
- `skills/fizz-mbt/` -- model-based tests from a spec against a real system

local modifications:
- `name:` added to each frontmatter, so the skill is found by name in every harness
- references to files that `fizz install-skills` would put under the local skills dir point at the same files in the fizzbee repo instead
- ascii only: em-dashes, arrows, check marks and maths signs replaced with their ascii forms
