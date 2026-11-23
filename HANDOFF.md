# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has the step 1 translator, lowering straight to ponyc's AST with no text path (stage 4 done), `make install`, `sparkle check`, and the language skill in `skills/sparkle/`, every example of which `spec/docs_spec.cr` compiles.
- `literal-defaults`: literals with nothing to type them get Crystal's `Int32` or `Float64` (spec, *Literal defaults*): `[1, 2]`, `c ? 1 : 2`, `{1, "a"}`, `7.string`, `"#{1 + 2}"`. Chars get none. Also links `.claude/skills/sparkle` to the skill, so this repository's own agents load it.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, eight tasks so far. Stage 4's used about 55k, 186k (two rounds) and 87k subagent tokens; the reference pages 132k. Reviews sent one back for two gaps, and the docs task found two translator bugs that the tree comparisons had missed.

## What's next

1. The field-or-method loop is slow with `use "collections"`: each round reloads every package, about 2.4 s, so `examples/ring` spends 7 s in three rounds (about 0.2 s a round with `builtin` alone). Keeping packages loaded between rounds might fix it; rewriting nodes in place would not. Measure before changing.
2. `spec/docs_spec.cr` takes about 3.5 minutes, because most examples are built and run. Fewer output blocks, or a faster loop (item 1), would cut it.
3. Roadmap step 2: the `ponyc` fork for `yield` inlining. Read the spike doc's "Not tested" first.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars.
