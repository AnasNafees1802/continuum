<!-- CONTINUUM:BEGIN -- managed block, safe to leave in place; re-run the Continuum global installer to update -->
## 🔁 Continuum — Cross-Agent Session Continuity

**For any project that contains a `.aicontext/` folder**, follow this protocol so work continues
seamlessly across AI coding agents — even after switching tools or hitting a usage limit.
`.aicontext/` is the shared source of truth; the full spec is in `.aicontext/PROTOCOL.md`.

- **Session start:** read `.aicontext/STATE.md` (plus the top 2–3 `JOURNAL.md` entries and `IN PROGRESS` items in `TASKS.md`), then give the user a short catch-up before doing anything else.
- **During work:** keep `.aicontext/TASKS.md` current; append technical decisions to `.aicontext/DECISIONS.md`.
- **Before ending, running low on context, or handing off (do this proactively):** overwrite the live sections of `STATE.md` (Current focus / Status / Next steps / Blockers), append a dated `JOURNAL.md` entry with a precise *Left off at*, then run the `continuum save` helper (it stamps `manifest.json` + the git commit; falls back to hand-editing if unavailable). Use real shell timestamps.

`STATE.md` is a living snapshot (overwrite it). `JOURNAL.md` and `DECISIONS.md` are append-only (newest on top — supersede, never delete). **Trust but verify:** if commits landed or the tree changed since the ledger was last saved, reconcile `STATE.md` against `git log`/`git status` before briefing — never present a stale ledger as fact. Continuum hooks run the catch-up and prompt the handoff automatically on Claude Code, Codex, Gemini and Cursor; on any agent, if a previous session ended abruptly (usage limit / crash), run `continuum import --from auto` to reconstruct it from the last agent's transcript plus git.

If a project has **no** `.aicontext/` and the user wants cross-agent continuity, create it
(`.aicontext/` + `STATE.md`, `TASKS.md`, `DECISIONS.md`, `JOURNAL.md`, `manifest.json`, `PROTOCOL.md`,
seeded from what the repo shows) and add `.aicontext/` to `.gitignore`. Otherwise ignore this block.
<!-- CONTINUUM:END -->
