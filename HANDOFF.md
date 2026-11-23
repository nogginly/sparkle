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
- `main` keeps one compiler across the field-or-method loop's rounds (`Ponyc::Session`): `examples/ring` settles in 2.8 s instead of 7 s.
- `debug-by-default`: builds are unoptimised unless `--release` is given, as in Crystal; hello world builds in about 1.4 s instead of 3 s.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, eight tasks so far. Stage 4's used about 55k, 186k (two rounds) and 87k subagent tokens; the reference pages 132k. Reviews sent one back for two gaps, and the docs task found two translator bugs that the tree comparisons had missed.

## What's next

1. Roadmap step 2, `yield` inlining. Before creating a `ponyc` fork, spike doing it in Sparkle, as the field-or-method loop does: a check round gives the receiver's type at each call with a block; when that method is a Sparkle method with `yield`, splice the block into a copy of its body and lower again. A fork means building LLVM from source (about an hour) in CI and rebasing patches each release, so it is the fallback if the spike fails (generic receivers, nested yields). The user will create `nogginly/ponyc` if needed.
2. Compiling in the loop's session would save the standard library's reload in a build, about 2.5 s with `collections` and 0.2 s without. Removed round packages may leave references that code generation trips over, and ponyc here is a release build with its assertions off, so it needs a spike.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars.
