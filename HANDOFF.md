# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`delegation-setup`, `step2-libponyc-spike`), cut from `main`. No pull request unless asked.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis and review stay in the main session.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

- Step 1, the translator, is merged to `main`. Build, specs (97, none pending), lint and format all pass.
- `delegation-setup` adds the delegation guide, the `implementer` agent and this file, makes `make build` create `bin/`, which a fresh clone or worktree lacks, and makes `make clean` keep `bin/ameba`.
- No task has been delegated yet, so the approach is unmeasured.

## What's next

Three step 1 gaps, decided by the user, each on its own branch and starting in `docs/step1-spec.md`:

1. **Assignment value.** Adopt Crystal's: an assignment used as a value gives the new value (`x = (y = 5)` → `x = (y = 5; y)`). Pony's swap idiom `a = b = a` is lost, knowingly.
2. **Named arguments to primed parameters.** The build records, across the package, which methods have a primed parameter, and primes matching named arguments (`Message.new(payload: …)` → `where payload' = …`). Two same-named methods on different types that disagree are left to `ponyc` to report.
3. **`enum`.** One `primitive` per member and a union type, so `case … in` can be exhaustive over it.

Dropped for now, maybe for good: calls without parentheses.

After those, the `libponyc` spike from `DESIGN.md` "One binary": link `libponyc` from Crystal and build a trivial AST through its C API. Step 2 depends on it, and it is untested.
