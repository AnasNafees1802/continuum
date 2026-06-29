# 🔁 Continuum Protocol

This project uses **Continuum**: a portable, agent-agnostic memory so any AI coding agent
(Claude Code, Codex, Antigravity, Windsurf, Gemini, Cursor, …) can resume exactly where
another left off — even after you switch tools or hit a usage limit.

The shared memory lives in **`.aicontext/`**. It is the single source of truth.
Treat it the way you'd treat a careful teammate's handoff notes.

---

## The three moments

### 1. SESSION START — *catch up before doing anything*
Before responding to the user's first real request:
1. Read **`.aicontext/STATE.md`** — the current state (what we're building, where we are, next steps).
2. Skim the top **2–3 entries** of **`.aicontext/JOURNAL.md`** and the **`IN PROGRESS`** items in **`.aicontext/TASKS.md`**.
3. (Optional) Check **`.aicontext/DECISIONS.md`** if you're about to touch an area with prior decisions.
4. Give the user a short **catch-up** (3–5 lines): *where we are* and *the next step*. Then proceed.

If `.aicontext/` is missing, this project hasn't been initialized — tell the user to run the Continuum installer.

### 2. DURING WORK — *keep the ledger live*
- Update **`TASKS.md`** as items move (backlog → in progress → done).
- When you make a technical/architectural choice, append to **`DECISIONS.md`** (decision, why, alternatives).
- Keep edits small and frequent rather than one giant write at the end — a session can be cut off (limit reached, crash) at any time.

### 3. HANDOFF — *before you end, run low on context, or the user switches agents*
This is the moment that makes continuity work. Do all of it:
1. **Update `STATE.md`** — overwrite *Current focus*, *Status*, *Next steps*, *Blockers*. This is what the next agent reads first; make it accurate.
2. **Append a `JOURNAL.md` entry** — what you did, files touched, decisions, and the precise *Left off at* point.
3. **Bump `manifest.json`** — set `lastUpdated`, `lastAgent`, add yourself to `agentsSeen` if new, increment `sessionCount`.

> ⚠️ If you sense your context window is filling or you're being cut off, do the HANDOFF
> step **immediately and proactively** — don't wait to be asked. A 30-second handoff now
> saves the next agent (or the next you) from rediscovering everything.

---

## Rules of the ledger
- **`STATE.md`** is *living* — overwrite its sections to stay current. It should never be stale.
- **`DECISIONS.md`** and **`JOURNAL.md`** are *append-only* — newest on top, never rewrite history. Supersede, don't delete.
- Get real timestamps from the shell (`date` / `Get-Date`), not from memory.
- Write for an agent who knows *nothing* about this session. Be concrete: file paths, command names, exact next step.
- Keep it tight. This is a briefing, not a transcript. The agent's native history still holds the verbatim log.

## Why gitignored?
`.aicontext/` is gitignored by default in this project — the memory is local to your machine and
not pushed. The adapter files (`CLAUDE.md`, `AGENTS.md`, `.windsurfrules`) *are* committed so the
protocol travels with the repo; each clone re-initializes its own local ledger via the installer.
