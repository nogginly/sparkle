# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps (assignment value, primed named arguments, `enum`), CI with cached `ponyc` and `ameba`, `make ameba`, and both stages of the `libponyc` spike ([docs/spike-libponyc.md](docs/spike-libponyc.md)).
- `step2-inprocess-ponyc`: step 2, option 1, part 1. `bin/sparkle` links `libponyc-standalone.a` and compiles the generated Pony in-process (`src/sparkle/ponyc/`); nothing else changes. `make ponyc` is now a build prerequisite, and the binary is about 160 MB.
- Delegation, three tasks so far: about 36k, 41k and 44k subagent tokens, 2 to 2½ minutes each. Review found one wrong brief, one simplification, and later a Linux-only path.

## What's next

1. Part 2 of option 1: the field-or-method loop from spike stage 4, which retires `env.@out`. It starts with the rule in `docs/step1-spec.md`: a bare `x.name` is a field read unless the type checker says it is a method.
2. Later: build the AST directly instead of Pony text (spike stage 3), with token values generated from `token.h`; then the `ponyc` fork for `yield` inlining.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
