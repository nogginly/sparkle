# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step3-contracts`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has steps 1 and 2 (the translator, lowering straight to ponyc's AST, and `yield` inlined in Sparkle), `make install`, `sparkle check`, the language skill, literal defaults, one compiler session for the field-or-method loop, debug builds unless `--release`, and the contracts design with every decision settled (`docs/contracts-design.md`).
- `step3-contracts`: runtime contracts. `src/sparkle/contracts.cr` rewrites `expects`, `guarantees` and `maintains` into plain methods before lowering: a wrapper that checks around the body (renamed `_spk_name`), checks inside constructors, and a `box` method `_spk_maintains`. Conditions read `self` and the arguments through `box` aliases, so ponyc rejects state changes. Failure goes through a generated primitive `_SpkContract` with FFI to `fprintf` and `exit`. `--release` keeps `expects` only; `--contracts=all` keeps all. Rules in `docs/step1-spec.md`, *Contracts (step 3)*; user page `skills/sparkle/reference/contracts.md`; example `examples/contracts`.
- Found on the way, not fixed: an interpolated string runs its parts from the right, because Pony evaluates a method call's arguments before its receiver and `String`'s `+` is a method. Recorded in the spec's known gaps and in `limits.md`. Fixing it means lowering interpolation so each part is evaluated into a local, left to right.
- Left in step 2: `return` with a value in a yielding method, and `next` or `break` where the call's value is used.
- Left in step 3: clauses on yielding, abstract and `tag` methods; `maintains` in traits, interfaces and primitives; an `old` type error points its note at the generated primitive.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.

## What's next

1. The user reviews `step3-contracts`.
2. **Decision** for the user: fix the interpolation order now, or later.
3. Step 4, Enumerable and Array as inline-only methods on Pony's collections. It needs Sparkle packages beyond one (`use` of a Sparkle package) first.
4. Optional: compiling in the loop's session (about 2.5 s a build with `collections`), and a faster docs spec.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars, field-level invariants, constrained types.
