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
4. **Trust but verify** — if commits landed or the working tree changed since the ledger was last saved, reconcile `STATE.md` against `git log`/`git status` before you brief. A confidently-wrong catch-up is worse than none.
5. **If the last session ended without a handoff** (usage-limit or crash cut-off), reconstruct it: on Claude Code run `continuum import` (rebuilds a draft from the session transcript); elsewhere reconstruct from `git log` + `git diff`. Fold the useful parts into `STATE.md`/`JOURNAL.md`.
6. Give the user a short **catch-up** (3–5 lines): *where we are* and *the next step*. Then proceed.

If `.aicontext/` is missing, this project hasn't been initialized — tell the user to run the Continuum installer.

### 2. DURING WORK — *keep the ledger live*
- Update **`TASKS.md`** as items move (backlog → in progress → done).
- When you make a technical/architectural choice, append to **`DECISIONS.md`** (decision, why, alternatives).
- Keep edits small and frequent rather than one giant write at the end — a session can be cut off (limit reached, crash) at any time.

### 3. HANDOFF — *before you end, run low on context, or the user switches agents*
This is the moment that makes continuity work. Do all of it:
1. **Update `STATE.md`** — overwrite *Current focus*, *Status*, *Next steps*, *Blockers*. This is what the next agent reads first; make it accurate.
2. **Append a `JOURNAL.md` entry** — what you did, files touched, decisions, and the precise *Left off at* point.
3. **Run `continuum save`** — stamps `manifest.json` (`lastUpdated`, `handoffAt`, `lastAgent`, `agentsSeen`, `sessionCount++`, and the current git commit for drift checks) and rotates the journal if large. If the helper isn't available, do this by hand.

> ⚠️ If you sense your context window is filling or you're being cut off, do the HANDOFF
> step **immediately and proactively** — don't wait to be asked. A 30-second handoff now
> saves the next agent (or the next you) from rediscovering everything.

---

## Automation (hooks + helper CLI) — cross-platform
The three moments are backed by deterministic hooks so continuity never depends on anyone remembering.
**Claude Code, Codex, Cursor** wire all three; **Gemini** wires catch-up + pre-compaction; **Windsurf**
(no session hook) runs catch-up on its first per-turn hook:
- **session start** injects the catch-up (STATE + top journal + drift/gap notes) automatically.
- **pre-compaction** prompts a handoff right before context is compacted — the "running low" moment.
- **stop** gives *one* gentle reminder per session if you changed files but never saved (agents that support it).

A helper CLI (installed once to `~/.continuum/bin/continuum.{ps1,sh}`, or `.claude/skills/continuum/bin/`
per-project) does the mechanics — the model still writes the prose:
- **`continuum save`** — stamp `manifest.json` + git commit at the end of a handoff, and rotate the journal.
- **`continuum import --from auto`** — reconstruct a missed handoff (usage-limit/crash). It reads the last
  agent's transcript (Claude Code, Codex, or Gemini) **and always appends a git-based view**, so it works
  on every platform — including a switch like Codex → Claude or Claude → Codex.
- **`continuum status` / `doctor`** — drift/gap report and ledger/hook health check across all agents.
- **`continuum compact`** — rotate old `JOURNAL.md` entries into `.aicontext/archive/` to bound token cost.

Agents without a hook for a given moment still follow it manually via this protocol — the ledger is
identical and portable either way. Native transcript parsing covers Claude/Codex/Gemini; Cursor and
Windsurf rely on the universal git-based reconstruction.

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
