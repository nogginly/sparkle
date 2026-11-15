# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps (assignment value, primed named arguments, `enum`), CI with cached `ponyc` and `ameba`, and `make ameba`.
- `step2-libponyc-spike` holds the spike: Crystal links `libponyc-standalone.a`, builds an AST, compiles it in-process to a running binary, and gets errors at `.spk` lines. Findings, costs and gaps are in [docs/spike-libponyc.md](docs/spike-libponyc.md); the code is in `spike/libponyc/`, Linux x86-64 only.
- Delegation, three tasks so far: about 36k, 41k and 44k subagent tokens, 2 to 2½ minutes each. Review found one wrong brief, one simplification, and later a Linux-only path.

## What's next

1. **Decision** for the user: how step 2 starts. The spike suggests type-dependent rules might first be written in Crystal against the typed AST after `PASS_EXPR`, before any `ponyc` fork. Untested: reading types back, macOS, multiple modules.
2. Then plan step 2 (`yield` inlining) in `DESIGN.md`.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
