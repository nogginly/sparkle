# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps, CI on Linux and macOS (`macos-26`, for Xcode 26), `bin/sparkle` with `libponyc` linked in (`src/sparkle/ponyc/`), and the field-or-method loop (`env.out`, no `@`). `spike/` is deleted; its findings are in [docs/spike-libponyc.md](docs/spike-libponyc.md).
- `step2-ast-foundation`: stage 1 of 4 of building ponyc's AST directly (the stages are in `DESIGN.md`, "One binary"). `Ponyc::Tree`, `Ponyc.compile_tree` and generated `Ponyc::Tk` token ids, with a spec that compiles and runs a hand-built program and checks an error position. Nothing uses it yet.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, four tasks so far: about 36k to 45k subagent tokens each. Review found one wrong brief, one simplification, a Linux-only path found later, and nothing on the fourth.

## What's next

1. Stage 2: the lowering from Sparkle's AST to ponyc's, behind an opt-in switch, one example at a time, starting with the smallest (`examples/fields`, then `counter`). Compare against `ponyc --pass=parse --astmodule` on each example's `expected.pony`.
2. Stages 3 and 4, then the `ponyc` fork for `yield` inlining.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
