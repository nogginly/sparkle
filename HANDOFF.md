# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step1-gaps`, `step2-libponyc-spike`), cut from `main`. No pull request unless asked.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- `step1-gaps` holds three step 1 additions, each a spec commit followed by an implementation commit:
  1. An assignment used as a value gives the new value (`(y = 5; y)`).
  2. Named arguments are primed across the package when their parameter is.
  3. `enum`: a primitive per member and a union type, with `value`, `string`, `eq` and `ne`; members in `case` patterns are matched by type. Example: `examples/traffic`.
- Build, 118 specs (none pending), lint and format all pass.
- Delegation, three tasks so far: about 36k, 41k and 44k subagent tokens, 2 to 2½ minutes each. Review needed one correction (a wrong brief), one simplification, and nothing on the third.

## What's next

1. Merge `step1-gaps`.
2. The `libponyc` spike from `DESIGN.md` "One binary": link `libponyc` from Crystal and build a trivial AST through its C API. Step 2 depends on it, and it is untested. It is exploratory, so it stays in the main session.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types.
