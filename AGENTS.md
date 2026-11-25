# Working on Sparkle

Guidance for coding agents, and for anyone new to the repository. Sparkle is an experimental language: Crystal's syntax on Pony's capabilities and actors. Today it is a translator that lowers `.spk` source to ponyc's AST.

## Read first

| Document | Read it for |
|---|---|
| [README.md](README.md) | What Sparkle is and why |
| [DESIGN.md](DESIGN.md) | Layers, decisions, roadmap, what is not built |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Build, test, lint, and the workflow for a change |
| [docs/step1-spec.md](docs/step1-spec.md) | Every translation rule and known gap |
| [skills/sparkle/SKILL.md](skills/sparkle/SKILL.md) | The language as a user writes it |
| [HANDOFF.md](HANDOFF.md) | Where the work stands and what's next |

## Before you call a change done

1. `make build` finishes with no warnings.
2. `make test` passes with **no pending specs**. Pending means `ponyc` was not found and the generated Pony was never compiled; run `make ponyc` first.
3. `make lint` is clean.
4. `crystal tool format --check src spec` is clean.
5. If a golden file changed, you have read its diff. `UPDATE_GOLDEN=1` accepts whatever the lowerer builds.

## Rules

- **A language change starts in the spec.** Add the rule to `docs/step1-spec.md` first, then follow the workflow in `DEVELOPMENT.md`, which ends with the user reference in `skills/sparkle/`.
- **Do not work around the type system by editing an example.** If reasonable Sparkle fails to compile, fix the translator. Change the example only when Pony genuinely forbids the program, and say so.
- **`vendor/ponyc` stays unmodified**, pinned to a release tag. Sparkle builds ponyc's AST and patches nothing; a rule that needs types is done by type-check rounds, as `yield` inlining can be (docs/spike-yield.md).
- **No lint suppressions.** No inline `ameba:disable`, no excluded files. Fix the code, or raise a threshold in `.ameba.yml` with a reason.
- **Keep the documents current** in the same change. `DEVELOPMENT.md` lists which document owns what.
- **Report results as they are.** If a spec is pending, a step was skipped, or something is untested, say so.

## Git

- Name a branch for the work it holds, such as `step1-translator` or `step2-yield-inlining`.
- One commit per coherent change. The message says what changed and why.
- Open a pull request for each branch when its work is ready; that is how changes are reviewed and reach `main`.

## Code style

- Keep comments to a minimum.
- A comment documents how to use an API, or describes the outcome of a type, entity or function.
- Inside a function, a comment describes the steps or algorithm, and only where needed.
- No change history in comments: nothing about what the code used to do or how it got here. That belongs in the commit message, or in `DESIGN.md` when it matters to a future contributor.

## Document style

- Documents are Markdown files.
- Diagrams are Mermaid, embedded in the document. Use hexagons (`{{condition}}`) for decisions, and a coloured border, not a fill, for emphasis.
- Plain, brief language. Prefer an example to a description.

## Things that will bite you

- **`make ponyc-source` takes about an hour** and downloads Google Benchmark and GoogleTest from `github.com`. On a restricted network the download fails; `make ponyc` (the prebuilt compiler) is the normal route.
- **The translator has no type information.** Many odd rules (`<<` as `push`, ranges fixed at `USize`) follow from that; the one rule that needs types, whether a bare `x.name` is a field or a method, is settled by asking the linked-in compiler. Check `docs/step1-spec.md` before treating one as a bug.
- **Actors run concurrently.** An example whose output order depends on message timing will fail intermittently.

## What comes next

Step 3 of the roadmap in `DESIGN.md`: runtime contracts. Read the proposal, [docs/contracts-design.md](docs/contracts-design.md), and the user's answers to its decisions before starting.
