<!-- CONTINUUM:BEGIN -- managed block, safe to leave in place; re-run the installer to update -->
## 🔁 Continuum — Cross-Agent Session Continuity

This project keeps a **portable memory ledger in `.aicontext/`** so any AI coding agent can
resume exactly where another left off (after switching tools or hitting a usage limit).
`.aicontext/` is the source of truth. Full spec: `.aicontext/PROTOCOL.md`.

**At the START of every session — before anything else:**
1. Read `.aicontext/STATE.md` (what we're building, where we are, what's next).
2. Skim the top 2–3 entries of `.aicontext/JOURNAL.md` and `IN PROGRESS` in `.aicontext/TASKS.md`.
3. Give the user a 3–5 line catch-up, then continue the work.

**DURING work:** keep `.aicontext/TASKS.md` current; append technical decisions to `.aicontext/DECISIONS.md`.

**BEFORE you end, run low on context, or hand off — do this proactively:**
1. Overwrite the live sections of `.aicontext/STATE.md` (Current focus, Status, Next steps, Blockers).
2. Append a dated entry to `.aicontext/JOURNAL.md` (summary, changes, decisions, exact *Left off at*).
3. Bump `.aicontext/manifest.json` (`lastUpdated`, `lastAgent`, `agentsSeen`, `sessionCount`).

Use real shell timestamps (`date` / `Get-Date`). `STATE.md` is living (overwrite); `JOURNAL.md` and `DECISIONS.md` are append-only (newest on top).
<!-- CONTINUUM:END -->
