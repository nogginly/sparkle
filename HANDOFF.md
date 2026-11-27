# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step3-contracts`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has steps 1 to 3: the translator lowering straight to ponyc's AST, `yield` inlined in Sparkle, and runtime contracts (`expects`, `guarantees`, `maintains`; `src/sparkle/contracts.cr`). Also `make install`, `sparkle check`, the language skill, literal defaults, one compiler session for the field-or-method loop, debug builds unless `--release`, and interpolated strings evaluated left to right.
- `on-and-post`: Pony's behaviours are Sparkle's message handlers, declared with `on`; callers post the message with `recv <~ name(args)`; `be` is an error. "Behaviour" is Pony's word only: docs and errors say message and handler. The type-check rounds record which calls reach a handler (`beref` after the expression pass, `Ponyc::Session#check`), and `Driver.posts_match?` reports a behaviour called with `.` or a `<~` that reaches a method, once the last round is clean. Every example, fixture, skill page and the README now use `<~`, `env.out <~ print(...)` included. The docs call `<~` "post"; the user may rename it.
- Left in step 2: `return` with a value in a yielding method, and `next` or `break` where the call's value is used.
- Left in step 3: clauses on yielding, abstract and `tag` methods; `maintains` in traits, interfaces and primitives; an `old` type error points its note at the generated primitive.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.

## What's next

1. The user reviews `on-and-post`.
2. Evaluation order: Pony evaluates a call's arguments before its receiver; the user wants Ruby and Crystal's left-to-right order everywhere, not only in interpolation. Bind receivers with effects to locals first, as interpolation does.
3. Step 4, Enumerable and Array as inline-only methods on Pony's collections. It needs Sparkle packages beyond one (`use` of a Sparkle package) first.
4. Optional: compiling in the loop's session (about 2.5 s a build with `collections`), and a faster docs spec.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars, field-level invariants, constrained types.
