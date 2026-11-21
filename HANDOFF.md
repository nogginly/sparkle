# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps, CI on Linux and macOS (`macos-26`, for Xcode 26), `bin/sparkle` with `libponyc` linked in (`src/sparkle/ponyc/`), and the field-or-method loop (`env.out`, no `@`). `spike/` is deleted; its findings are in [docs/spike-libponyc.md](docs/spike-libponyc.md).
- Building ponyc's AST directly, in four stages (`DESIGN.md`, "One binary"). Stage 1 is on `main`: `Ponyc::Tree`, `Ponyc.compile_tree`, generated `Ponyc::Tk`. `step2-ast-lowering` starts stage 2: `Lowerer`, used when `SPARKLE_AST=1`, lowers `fields`, `counter`, `fizzbuzz`, `handoff`, `shapes` and `ring`; anything else raises "the AST path does not lower … yet" at its position.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, four tasks so far: about 36k to 45k subagent tokens each. Review found one wrong brief, one simplification, a Linux-only path found later, and nothing on the fourth.

## What's next

1. Stage 2, one example per task, smallest first: `traffic` is the last. Add each name to `LOWERED` in `spec/lowerer_spec.cr`; the spec demands a tree that prints identically to ponyc's parse of `expected.pony`, which makes these tasks delegable. Print the target with `ponyc --pass=parse --astmodule`. Known gaps in `Lowerer`: string escapes, `if` with `else`/`elsif`, `and`/`or`, `case` forms other than a tuple, an empty array literal, `begin` without `rescue` or with `ensure`; each raises "does not lower … yet".
2. Stages 3 and 4, then the `ponyc` fork for `yield` inlining.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
