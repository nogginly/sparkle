# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1, its three gaps, CI on Linux and macOS (`macos-26`, for Xcode 26), and `bin/sparkle` with `libponyc` linked in (`src/sparkle/ponyc/`).
- `step2-field-or-method`: step 2, option 1, part 2. A bare `x.name` is a field unless the type checker reports a method, settled by a type-check loop in `Driver.build`; `env.@out` is now `env.out`. Goldens moved into the end-to-end spec. The shim also keeps Crystal's GC signals out of LLVM's crash handlers, which printed a spurious "PLEASE submit a bug report" banner once per multi-build process since in-process compiling began.
- Delegation, four tasks so far: about 36k, 41k, 44k and 45k subagent tokens. Review found one wrong brief, one simplification, a Linux-only path found later, and on the fourth task nothing to change; its report flagged the banner, which turned out to be the GC signal clash.

## What's next

1. Build the AST directly instead of Pony text (spike stage 3, kept at commit `747866f`; see [docs/spike-libponyc.md](docs/spike-libponyc.md)), with token values generated from `token.h`. Then the type-check loop can rewrite nodes instead of re-emitting text.
2. Then the `ponyc` fork for `yield` inlining.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
