@AGENTS.md

## Claude-specific

- **Delegate coding to a subagent on a lower-power model**, chosen by judgement for the task. Keep design, review and verification in the main session, and re-run the checks yourself before committing.
- **Use the `sparkle` cloud environment** for cloud sessions. Its setup script installs Crystal, the prebuilt `ponyc` and `ameba`.
