# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has the step 1 translator, lowering straight to ponyc's AST with no text path (stage 4 done), `make install`, `sparkle check`, and the language skill in `skills/sparkle/`, every example of which `spec/docs_spec.cr` compiles.
- `main` also has Crystal's `Int32`/`Float64` defaults for literals nothing else types (spec, *Literal defaults*; chars get none), and `.claude/skills/sparkle` links the skill for this repository's agents. DESIGN.md records two decisions: `Int32` stays the default, and an OS is assumed.
- `faster-field-loop`: `Ponyc::Session` keeps one compiler across the field-or-method loop's rounds, so the standard library is loaded once. `examples/ring` settles in 2.8 s instead of 7 s; `sparkle check` on it takes 2.9 s instead of 10 s, `sparkle run` 8.8 s instead of 13 s, and `make test` 4:35 instead of 5:42.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, eight tasks so far. Stage 4's used about 55k, 186k (two rounds) and 87k subagent tokens; the reference pages 132k. Reviews sent one back for two gaps, and the docs task found two translator bugs that the tree comparisons had missed.

## What's next

1. `spec/docs_spec.cr` takes about 3 minutes, because most examples are built and run, and each build still starts a fresh `ponyc` to generate code (about 2 s with `collections`). Fewer output blocks, or compiling in the loop's session, would cut it.
2. Roadmap step 2: the `ponyc` fork for `yield` inlining. Read the spike doc's "Not tested" first.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars.
