# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has the step 1 translator lowering straight to ponyc's AST, `make install`, `sparkle check`, the language skill in `skills/sparkle/` (every example compiled by `spec/docs_spec.cr`), Crystal's literal defaults, one compiler session across the field-or-method loop, unoptimised builds unless `--release`, and the `yield` spike (`docs/spike-yield.md`).
- Step 2, `yield` inlining, as stacked PRs:
  1. `step2-yield-inlining`: the spec rule, the `yield` keyword, `src/sparkle/inliner.cr` folded into the field-or-method loop, field accessors, synthetic positions mapped back in errors, `examples/yield`, `spec/inliner_spec.cr`. `each` on a Sparkle type is inlined, `each` on Pony's types stays a loop, by receiver type.
  2. `step2-yield-control`, stacked on it: `yield` as a value, calls used as values, `next` (each block run is a `repeat … until true`), `break` and a bare `return` in the method (a flag local, with the rest of the copy guarded), `return` in the block. `examples/yield_control`.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation: eight tasks so far; none in step 2 yet, which has been design work.

## What's next

1. Left in step 2: `return` with a value in a yielding method (a result local beside the flag), and `next` or `break` where the call's value is used.
2. Roadmap step 3: Enumerable and Array rewritten on `yield`. Settle the standard-library question in `DESIGN.md` first.
3. Compiling in the loop's session would save the standard library's reload in a build, about 2.5 s with `collections`. It needs a spike: removed round packages may leave references that code generation trips over.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars.
