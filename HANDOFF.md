# Handoff

Where the work stands, for the next session. Rewritten, not appended, at the end of each piece of work. What belongs in another document lives there instead.

## How we work

- One branch per piece of work, named for it (`step2-libponyc-spike`), cut from `main`, with a pull request opened when its work is ready.
- Mechanical, checkable tasks go to the `implementer` subagent on a cheaper model, following [.claude/delegation.md](.claude/delegation.md). Design, diagnosis, spikes and review stay in the main session. A language change is specified, and its Pony forms compiled by hand, before the brief is written.
- CI (`.github/workflows/ci.yml`) runs the checks on Linux and macOS for every PR and fails on pending specs.
- Questions and decisions put to the user are labelled (**Question**, **Decision**).

## Where things stand

Seven stacked PRs, each based on the one before. Merge in order:

1. `step4-ast-default`, nogginly/sparkle#22: the AST path is the default; `sparkle translate` prints the lowered tree; `expected.ast` goldens.
2. `step4-lower-every-rule`, nogginly/sparkle#23: the lowerer covers every construct the emitter's specs covered.
3. `step4-retire-emitter`, nogginly/sparkle#24: the emitter, source map, text path and `expected.pony` are gone; `Sparkle::Rules`, `spec/rules_spec.cr`.
4. `step4-docs`, nogginly/sparkle#25: the design docs describe a translator that builds ponyc's AST.
5. `install-target`, nogginly/sparkle#26: `make install` / `make uninstall` into one directory, `~/.local/sparkle` by default.
6. `lowering-gaps`, nogginly/sparkle#27: lambdas get ponyc's `AST_FLAG_PRESERVE` (they crashed `ponyc` before), printed trees list preserved nodes, and tuple, `&`, `->`, `Proc` and bare-capability types lower.
7. `language-docs`: `skills/sparkle/` (skill and reference, every example compiled by `spec/docs_spec.cr`), `sparkle check`, and the skill installed under `share/sparkle/skills/`.

- Still not lowered: a NUL escape in a string, and statements after a jump in the same block.
- Open question for the user, in `DESIGN.md`: what happens to Pony's standard library after step 6. Settle before step 3.
- Delegation, eight tasks so far. Stage 4's used about 55k, 186k (two rounds) and 87k subagent tokens; the reference pages 132k. Reviews sent one back for two gaps, and the docs task found two translator bugs that the tree comparisons had missed.

## What's next

1. Decisions for the user, found while writing the docs (see `skills/sparkle/reference/limits.md`): literals with no type of their own, such as `[1, 2, 3]`, `'a'`, `x = c ? 1 : 2` and `"#{1 + 2}"`, fail with "could not infer literal type". Crystal's rule would give them `Int32`, as `x = 0` already does.
2. The field-or-method loop is slow with `use "collections"`: each round reloads every package, about 2.4 s, so `examples/ring` spends 7 s in three rounds (about 0.2 s a round with `builtin` alone). Keeping packages loaded between rounds might fix it; rewriting nodes in place would not. Measure before changing.
3. `spec/docs_spec.cr` takes about 3.5 minutes, because most examples are built and run. Fewer output blocks, or a faster loop (item 2), would cut it.
4. Roadmap step 2: the `ponyc` fork for `yield` inlining. Read the spike doc's "Not tested" first.

Dropped for now, maybe for good: calls without parentheses. Deferred: methods inside an `enum`, flag enums, enum base types, destructuring assignment.
