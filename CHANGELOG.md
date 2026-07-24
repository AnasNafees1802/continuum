# Changelog

All notable changes to Continuum are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.1] — 2026-07-24

### Fixed
- **False "you didn't save" nag.** The Stop-hook guard nagged even after a real `continuum save`,
  because a manually-run `save` has no `session_id` (that only arrives via a hook's stdin) and so
  couldn't stamp the current session's marker. The guard now also treats the session as handed-off
  when `manifest.handoffAt` is newer than the session start, independent of the per-session marker.
  Found by dogfooding (the guard nagged its own author after a completed save).

## [2.0.0] — 2026-07-23

Turns Continuum from an honor-protocol ("read `.aicontext/` at start, update before you stop")
into **deterministic, cross-agent capture** — because the case it exists for (a usage-limit or
crash killing a session) is exactly when a voluntary handoff can't run.

### Added
- **Helper CLI** — `bin/continuum.{ps1,sh}`, zero runtime dependencies:
  `save`, `import`, `status`, `doctor`, `compact`, plus the hook-backed `catch-up` / `precompact` / `guard`.
- **Native hooks, wired by the installers** into every agent that has them:
  Claude Code, Codex, and Cursor (session-start / pre-compaction / stop); Gemini (session-start /
  pre-compress); Windsurf via its per-turn hook. Unified JSON `additionalContext` output for all.
- **`continuum import --from auto`** — reconstruct a missed handoff from the last agent's transcript
  (native Claude / Codex / Gemini parsers) **plus a universal git-based view**, so recovery works even
  across a tool switch (Codex ⇄ Claude) and even on agents whose logs can't be parsed.
- **Drift detection** — session catch-up compares the saved git commit to `HEAD` and warns before
  briefing from a stale ledger.
- **Ledger-hygiene enforcement** — the stop-hook now also nudges (once/session) when you *committed*
  code but never updated `DECISIONS.md`, and catch-up flags a lagging decision log. This extends
  enforcement beyond `STATE.md`/save to the parts that were previously honor-only (`TASKS.md`,
  `DECISIONS.md`) — found because the author's own dogfooding let those two go stale.
- **Journal rotation** — `compact` archives old `JOURNAL.md` entries into `.aicontext/archive/`.
- Shared helper installed once to `~/.continuum/bin`; per-agent hook formats merged idempotently.
- Smoke-test suite (`test/smoke.sh`) and this changelog.

### Changed
- `manifest.json` schema → `1.1` (`handoffAt`, `lastCommit`, `lastSessionId`).
- Handoff bookkeeping is now deterministic (`continuum save`) instead of the model hand-editing JSON.

### Fixed
- **Atomic writes** for markers, `manifest.json`, and the rotated journal (temp file + rename) — an
  interrupted process can no longer leave a truncated/empty file. *(found by dogfooding)*
- **No BOM** on JSON the helper writes — PowerShell 5.1's `Set-Content -Encoding utf8` added a UTF-8
  BOM that broke Python/`jq` parsers, the exact cross-tool boundary Continuum depends on. *(found via a real Antigravity `save`)*
- Transcript file-path detection restricted to `file_path`/`notebook_path` — the generic `path` key
  matched agents' internal directories and polluted the reconstruction. *(found via a real Codex rollout)*
- Hook commands are now **fail-safe**: any internal error is swallowed and the hook exits 0 with valid
  JSON or nothing — a helper failure can never break the host agent.
- Installer hook idempotency matches the helper filename (`continuum.ps1`/`continuum.sh`), not the bare
  word `continuum`, so an unrelated user hook can't be clobbered.

### Verified on real sessions
Claude Code (hook catch-up + drift + gap), Codex (catch-up + `import` from a real rollout), and
Antigravity (honor-protocol + autonomously driving the CLI, despite having no hooks and binary
transcripts). Gemini/Cursor parsers are tested in simulation and rely on the git-based floor pending
a real-session pass.

## [1.0.0]
- Initial release: portable `.aicontext/` ledger + `AGENTS.md`/`CLAUDE.md`/`.windsurfrules` adapters +
  the `continuum` Claude Code skill; one-line remote installer.
