# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step1-gaps`, `step2-libponyc-spike`), cut from `main`. No pull request unless asked.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `main` has step 1 plus three gaps: assignment value, primed named arguments and `enum`. 118 specs, none pending.
- `ci-workflow` adds `.github/workflows/ci.yml` (Linux and macOS; fails on pending specs) and `make ameba`.
- Delegation, three tasks so far: about 36k, 41k and 44k subagent tokens, 2 to 2½ minutes each. Review needed one correction (a wrong brief), one simplification, nothing on the third, and a macOS-only path found later by the user.

## What's next

1. Merge `ci-workflow` once both CI jobs pass.
2. The `libponyc` spike from `DESIGN.md` "One binary": link `libponyc` from Crystal and build a trivial AST through its C API. Step 2 depends on it, and it is untested. It is exploratory, so it stays in the main session.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
