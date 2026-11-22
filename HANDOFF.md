# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps, CI on Linux and macOS (`macos-26`, for Xcode 26), and `bin/sparkle` with `libponyc` linked in (`src/sparkle/ponyc/`). `spike/` is deleted; its findings are in [docs/spike-libponyc.md](docs/spike-libponyc.md).
- Stage 4 of "One binary" (`DESIGN.md`) is four stacked PRs, each based on the one before. Merge them in order:
  1. `step4-ast-default`, nogginly/sparkle#22: the AST path is the default, `sparkle translate` prints the lowered tree, and each example has `expected.ast`.
  2. `step4-lower-every-rule`, nogginly/sparkle#23: the lowerer covers every construct the emitter's specs covered, chars included, and each spec checks both paths against the same Pony.
  3. `step4-retire-emitter`, nogginly/sparkle#24: the emitter, source map, text path, `SPARKLE_TEXT` and `expected.pony` are gone. Shared rules live in `Sparkle::Rules`, and the rule specs are `spec/rules_spec.cr`.
  4. `step4-docs`: `DESIGN.md`, `docs/step1-spec.md`, README, AGENTS and the spike doc describe a translator that builds ponyc's AST.
- Still not lowered: a NUL escape in a string (ponyc's string nodes cannot hold the byte), and statements after a jump in the same block (unreachable, and rejected by ponyc either way).
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, seven tasks so far. The first four used about 36k to 45k subagent tokens each. Stage 4's took about 55k, 186k over two rounds (closing every lowering gap), and 87k. Review sent one back for two gaps: chars, and a negative literal as a receiver.

## What's next

1. Roadmap step 2: the `ponyc` fork for `yield` inlining. Read the spike doc's "Not tested" first.
2. The field-or-method loop is slow with `use "collections"`: each round reloads every package, about 2.4 s, so `examples/ring` spends 7 s in three rounds (about 0.2 s a round with `builtin` alone). Rewriting nodes in place would not help; keeping packages loaded between rounds might. Measure before changing.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
