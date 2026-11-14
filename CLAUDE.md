@AGENTS.md

## Claude-specific

- **Delegate by judgement** to the `implementer` subagent (`.claude/agents/implementer.md`), following [.claude/delegation.md](.claude/delegation.md). Keep design, review and verification in the main session, and re-run the checks yourself before committing.
- **Read [HANDOFF.md](HANDOFF.md)** at the start of a session, and rewrite it at the end of each piece of work.
- **Use the `sparkle` cloud environment** for cloud sessions. Its setup script installs Crystal, the prebuilt `ponyc` and `ameba`.
