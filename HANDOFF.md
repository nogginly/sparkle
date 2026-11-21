# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps, CI on Linux and macOS (`macos-26`, for Xcode 26), `bin/sparkle` with `libponyc` linked in (`src/sparkle/ponyc/`), and the field-or-method loop (`env.out`, no `@`). `spike/` is deleted; its findings are in [docs/spike-libponyc.md](docs/spike-libponyc.md).
- Building ponyc's AST directly, in four stages (`DESIGN.md`, "One binary"). Stage 1 is on `main`: `Ponyc::Tree`, `Ponyc.compile_tree`, generated `Ponyc::Tk`. `step2-ast-lowering` starts stage 2: `Lowerer`, used when `SPARKLE_AST=1`, lowers `fields`, `counter`, `fizzbuzz`, `handoff`, `shapes`, `ring` and `traffic`, which completes stage 2; anything else raises "the AST path does not lower … yet" at its position.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, four tasks so far: about 36k to 45k subagent tokens each. Review found one wrong brief, one simplification, a Linux-only path found later, and nothing on the fourth.

## What's next

1. Enum predicates are implemented: `red?` on each member (`is_red`), and `when .red?` as the member's type pattern when exactly one enum in the package has it, on both the text and AST paths (`examples/traffic` uses both).
2. Stage 3, parity: run the fixtures (`spec/fixtures/`) and every example through the AST path in the e2e spec, with errors reported at the same Sparkle positions as the text path. Known gaps in `Lowerer`, each raising "does not lower … yet": string escapes, `if` with `else`/`elsif`, `and`/`or`, `begin` without `rescue` or with `ensure`, negative enum values.
3. Stage 4 (switch, retire the emitter and source map), then the `ponyc` fork for `yield` inlining.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
