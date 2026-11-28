# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step3-contracts`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has steps 1 to 3: the translator lowering straight to ponyc's AST, `yield` inlined in Sparkle, and runtime contracts (`expects`, `guarantees`, `maintains`; `src/sparkle/contracts.cr`). Also `make install`, `sparkle check`, the language skill, literal defaults, one compiler session for the field-or-method loop, debug builds unless `--release`, and interpolated strings evaluated left to right.
- `main` also has message handlers (#38). `on` declares one; callers post the message with `recv <~ name(args)`, which is required both ways; `be` is an error. "Behaviour" is Pony's word only. The type-check rounds record which calls reach a handler (`beref` after the expression pass, `Ponyc::Session#check`), and `Driver.posts_match?` reports mismatches once the last round is clean.
- `main` also evaluates calls left to right (#39). Pony evaluates arguments before the receiver, so the lowerer (`ordered`) binds a receiver that may change to `let spk_r<n>` and reads it back with `consume` when an argument may have an effect. Fields stay unbound, because an `iso` field cannot be aliased; that is the one gap, in the spec and `limits.md`.
- `main` also has packages (#40, #41): `require "./x"` and `require "name"`, each package lowered into its own in-memory Pony package keyed `spk_<name>`, public `spk_yf_` accessors, `spk_` reserved, and a library (`$SPARKLE_LIB`, `share/sparkle/stdlib`, or `stdlib/`) whose `prelude` every package requires. The library has no packages yet.
- `step4-design`: `docs/enumerable-design.md` proposes Enumerable as inline-only methods in `stdlib/prelude`, over Pony's `Array` and collections. A spike (`spike/enumerable/probe.cr`) showed a type-check round can read a block's value type from a probe local, which gives `map`'s `B`. Four decisions are open: reopening Pony types, clashing names, `forall B`, and the first set of methods.
- Left in step 2: `return` with a value in a yielding method, and `next` or `break` where the call's value is used.
- Left in step 3: clauses on yielding, abstract and `tag` methods; `maintains` in traits, interfaces and primitives; an `old` type error points its note at the generated primitive.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.

## What's next

1. The user answers the four decisions in `docs/enumerable-design.md`.
2. Step 4 in the order of its *Building it*.
3. Optional: compiling in the loop's session (about 2.5 s a build with `collections`), and a faster docs spec.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars, field-level invariants, constrained types.
