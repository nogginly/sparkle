# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps, CI on Linux and macOS (`macos-26`, for Xcode 26), `bin/sparkle` with `libponyc` linked in (`src/sparkle/ponyc/`), and the field-or-method loop (`env.out`, no `@`). `spike/` is deleted; its findings are in [docs/spike-libponyc.md](docs/spike-libponyc.md).
- Building ponyc's AST directly, in four stages (`DESIGN.md`, "One binary"). Stage 1 is on `main`: `Ponyc::Tree`, `Ponyc.compile_tree`, generated `Ponyc::Tk`. `step2-ast-lowering` starts stage 2: `Lowerer` lowers `fields`, `counter`, `fizzbuzz`, `handoff`, `shapes`, `ring`, `traffic` and `control`, which completes stage 2; anything else raises "the AST path does not lower … yet" at its position.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, four tasks so far: about 36k to 45k subagent tokens each. Review found one wrong brief, one simplification, a Linux-only path found later, and nothing on the fourth.

## What's next

1. Enum predicates are implemented: `red?` on each member (`is_red`), and `when .red?` as the member's type pattern when exactly one enum in the package has it, on both the text and AST paths (`examples/traffic` uses both).
2. Stage 3, parity, is done. Every example in `examples/` must lower (`spec/lowerer_spec.cr` lists them from the directory, so a new example cannot skip the AST path), and every fixture must give identical errors on both paths (`spec/e2e_spec.cr`). Escapes ponyc's strings cannot hold (NUL) still raise "does not lower … yet".
3. Stage 4, in four PRs. PR 1, default (`step4-ast-default`): the AST path is the default, the text path stays behind `SPARKLE_TEXT=1`, `sparkle translate` prints the lowered tree, and each example has `expected.ast` beside `expected.pony`. PR 2, lower every rule (`step4-lower-every-rule`): the lowerer handles every construct the emitter's unit specs cover, and each of those specs pins both paths to the same Pony. PR 3, retire the emitter: the emitter, the source map, the text path, `SPARKLE_TEXT`, `expected.pony` and the diagnostics' location mapping go, and the lowerer's shared rules move out of `Emitter`. PR 4, docs. Then the field-or-method loop rewriting nodes instead of re-lowering, and the `ponyc` fork for `yield` inlining.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
