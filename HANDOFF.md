# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has steps 1 and 2: the translator lowering straight to ponyc's AST, and `yield` inlined in Sparkle (`src/sparkle/inliner.cr`), with values, `next`, `break` and `return`. Also `make install`, `sparkle check`, the language skill (`skills/sparkle/`), Crystal's literal defaults, one compiler session across the field-or-method loop, and unoptimised builds unless `--release`.
- `contracts-design`: DESIGN.md records the user's decisions: wrap Pony's standard library (option C); Crystal's idiom unless it breaks capabilities or contracts; contracts first (step 3); arenas deferred, so Pony's GC and the upstream `ponyc` stay. `docs/contracts-design.md` proposes how contracts look and lower, with four decisions for the user.
- Left in step 2: `return` with a value in a yielding method, and `next` or `break` where the call's value is used.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.

## What's next

1. The user answers the four decisions in `docs/contracts-design.md`: syntax, what `--release` keeps, invariants before `ref` methods, and how a failure behaves.
2. Step 3, runtime contracts, in the order the proposal's *Building it* gives: the spec section first.
3. Step 4, Enumerable and Array as inline-only methods on Pony's collections. It needs Sparkle packages beyond one (`use` of a Sparkle package) first.
4. Optional: compiling in the loop's session (about 2.5 s a build with `collections`), and a faster docs spec.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars.
