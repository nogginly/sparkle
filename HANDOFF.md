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
- `packages-design` (#40): `docs/packages-design.md`, with the user's decisions: `require` (`use` is an error), a `prelude` in scope without `require`, no qualified names yet, `spk_` reserved.
- `packages` (stacked on #40): built. `PackageSet` (`src/sparkle/packages.cr`) finds, parses and orders the packages a build requires; `Ponyc::Packages` adds each to the program in memory, keyed `spk_<name>`, in the type-check session and in the compile. Yielding methods read fields through public `spk_yf_` accessors, so they inline across packages. The library is `$SPARKLE_LIB`, `share/sparkle/stdlib` installed, or `stdlib/` in the repository (not `lib/`, which holds the shards); it does not exist yet, so the prelude is a mechanism without contents. `examples/packages` covers a yielding method, a contract and a message handler across packages.
- Left in step 2: `return` with a value in a yielding method, and `next` or `break` where the call's value is used.
- Left in step 3: clauses on yielding, abstract and `tag` methods; `maintains` in traits, interfaces and primitives; an `old` type error points its note at the generated primitive.
- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.

## What's next

1. The user reviews #40 and `packages`.
2. Step 4, Enumerable and Array as yielding methods over Pony's collections, in the Sparkle library.
3. Optional: compiling in the loop's session (about 2.5 s a build with `collections`), and a faster docs spec.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment, a default type for chars, field-level invariants, constrained types.
