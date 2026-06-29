# 🧭 Decision Log

> **Append-only.** Record technical/architectural decisions so a future agent (or human)
> never has to re-litigate or reverse-engineer *why* something is the way it is.
> Newest entries on top. Never delete an entry — supersede it with a new one.

<!--
Template for each entry:

## YYYY-MM-DD — <short title>
- **Decision:** what was decided.
- **Why:** the reasoning / the problem it solves.
- **Alternatives considered:** what was rejected and why.
- **By:** which agent / who.
- **Supersedes:** (optional) link/title of an earlier decision this replaces.
-->

## {{DATE}} — Adopt Continuum for cross-agent continuity
- **Decision:** Keep a portable project memory in `.aicontext/` that every AI agent reads and writes.
- **Why:** Switching between agents (Codex → Claude → Antigravity …) or hitting usage limits loses all context. A repo-local ledger makes context survive the switch.
- **Alternatives considered:** Relying on each agent's native history (siloed, not portable); a cloud service (added dependency, privacy).
- **By:** installer
