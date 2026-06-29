---
name: continuum
description: >-
  Cross-agent session continuity. Reads and maintains a portable project-memory ledger in
  `.aicontext/` so any AI coding agent (Claude Code, Codex, Antigravity, Windsurf, Gemini)
  can resume exactly where another left off. Use at the START of a coding session to catch up
  on project state; BEFORE ending or handing off a session; when SWITCHING between AI agents
  or recovering from a hit usage limit; when the user asks "where are we", "catch me up",
  "save progress", "checkpoint", or "what were we doing"; or to recover lost context.
---

# Continuum — Cross-Agent Session Continuity

Continuum keeps project context continuous across *any* AI coding agent by storing a small,
structured memory ledger in the repo at **`.aicontext/`**. That folder is the source of truth.
The full spec lives in **`.aicontext/PROTOCOL.md`** — read it if you need detail.

## When this skill applies
- **Starting work** in a project that has a `.aicontext/` folder → catch up first.
- **Ending / handing off / running low on context** → write the handoff.
- **User switched from another agent** (Codex, Antigravity, …) and wants to continue.
- **User asks** "where are we?", "catch me up", "save our progress", "checkpoint this".

## SESSION START — catch up
Do this before acting on the user's first real request:
1. Read `.aicontext/STATE.md`.
2. Skim the top 2–3 entries of `.aicontext/JOURNAL.md` and `IN PROGRESS` in `.aicontext/TASKS.md`.
3. Give a 3–5 line catch-up (what we're building, where we are, the next step), then continue.

If `.aicontext/` doesn't exist, the project isn't initialized — see BOOTSTRAP below.

## BOOTSTRAP — initialize a project that has no `.aicontext/`
If the user wants continuity here and `.aicontext/` is missing, create it yourself (no installer needed):
1. Make `.aicontext/` and create `STATE.md`, `TASKS.md`, `DECISIONS.md`, `JOURNAL.md`, `manifest.json`, `PROTOCOL.md` following the structure in this skill (STATE = living snapshot; JOURNAL/DECISIONS = append-only, newest on top).
2. Seed `STATE.md` from what you already know about this project (skim the repo first) so it's useful immediately.
3. Add `.aicontext/` to `.gitignore` (machine-local by default).
4. Tell the user it's set up. To also wire up other agents (Codex/Antigravity/Windsurf) via `AGENTS.md`/`.windsurfrules`, point them to the Continuum installer (`install.ps1` / `install.sh`).

## DURING WORK — keep it live
- Move items in `.aicontext/TASKS.md` as they progress.
- Append technical decisions to `.aicontext/DECISIONS.md` (decision, why, alternatives).
- Prefer small frequent updates — a session can be cut off at any moment.

## HANDOFF — before you stop (do this proactively if context is filling)
1. **Overwrite the live sections of `.aicontext/STATE.md`**: Current focus, Status, Next steps, Blockers.
2. **Append a `.aicontext/JOURNAL.md` entry** (newest on top): summary, changes, decisions, and a precise *Left off at*.
3. **Update `.aicontext/manifest.json`**: `lastUpdated`, `lastAgent` (set to your tool name), add to `agentsSeen` if new, `sessionCount++`.

## Conventions
- Get real timestamps from the shell (`date` on POSIX, `Get-Date` on PowerShell) — never guess.
- `STATE.md` is living (overwrite to stay current). `DECISIONS.md` / `JOURNAL.md` are append-only (newest on top, supersede — never delete).
- Write for an agent that knows nothing about this session: concrete file paths, commands, exact next step.
- Keep entries tight — a briefing, not a transcript.

## Catch-up output shape
When catching the user up, keep it scannable:

```
📍 Caught up from .aicontext/ (last touched <date> by <agent>):
• Building: <one line>
• Status: <where we are>
• Next: <the immediate next step>
<note any blocker>
```
