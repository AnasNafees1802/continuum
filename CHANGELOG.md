# Changelog

All notable changes to Continuum are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [2.2.2] — 2026-09-09

Fixes and a reinforcement gap, all found by heavy real-world use.

### Fixed
- **JOURNAL mojibake on rotation (PowerShell).** `compact` read `JOURNAL.md` with `Get-Content` at the
  PS 5.1 default codepage (cp1252), so every 20-entry rotation re-decoded UTF-8 and rewrote mangled
  em dashes / emoji, compounding over time and corrupting both the live journal and the archive. All
  journal and marker reads now force `-Encoding UTF8`. (bash was never affected.)
- **Silent save outside a git repo.** `save` now warns "not a git repository ... commit not stamped"
  instead of quietly stamping an empty commit, so the trust-but-verify promise is never silently skipped
  (bash + PowerShell).

### Changed
- **Global memory is now actively reinforced, not just documented.** The Stop-hook guard also reminds you
  to capture a durable cross-project preference with `continuum remember`, matching how it already gates
  `save`. Adapters + skill now state plainly that when the user says "remember this", that means
  `continuum remember` (the cross-tool memory), not the host agent's own memory. Closes the
  reinforcement/naming gap that made agents lean on `save` but skip global memory.

## [2.2.1] — 2026-09-05

### Fixed
- **Cross-system Python resolution.** The bash helper and installers probed only `python3`, so on
  Windows — where `python3` is often the non-functional Microsoft Store stub and the real interpreter is
  `python` or the `py -3` launcher — `save` silently fell back to a lossy scalar-only manifest update
  (dropping `sessionCount` / `agentsSeen`), and the bash installers couldn't wire hooks. A new resolver
  tries `python3` → `python` → `py -3` and verifies each actually executes (`-c ''`), skipping the stub.
  Applied in `bin/continuum.sh`, `install.sh`, `install-global.sh`, and `test/smoke.sh` (which now runs
  on any of the three). The PowerShell path was never affected (it uses native JSON, no Python).
- **`continuum help` output.** No longer spills past the command list into script internals (the usage
  printer now stops at the end of the header comment instead of a fixed line range).

## [2.2.0] — 2026-09-05

**Global memory — cross-project, cross-tool.** Continuum has always carried *project* context; now it
also carries the *developer*. Tell one agent a durable preference once and every agent remembers it, in
every project. This is the layer native vendor memory can't be: vendor memory follows the user inside
one tool; Continuum's follows the user across all of them — because it rides the SessionStart hook
Continuum already installs into every agent on the machine.

### Added
- **Personal memory store** at `~/.continuum/memory/MEMORY.md` (plain, human-readable markdown you can
  read, edit, and audit — not an opaque blob). Each entry carries a scope label and a `user`/`agent`
  source so agent-proposed memories stay visible.
- **`continuum remember "<text>" [--scope <area>] [--source user|agent]`** — save a durable, cross-project
  preference (dedups identical text). **`continuum forget <id|text>`** removes one; **`continuum memory`**
  lists them. All three work from any directory — no `.aicontext/` project needed.
- **Injected everywhere.** `catch-up` now emits a `GLOBAL MEMORY` block at session start in *every*
  project — including folders with no project ledger — so preferences reach every agent, every project.
  Existing installs get this on their next helper update; no re-wiring needed.
- Adapters + skill teach agents to apply injected memories and to capture new durable preferences (and
  to propose them, confirming first) — so it works on honor-protocol agents, not just Claude Code.

### Notes
- The store is local and plain-text by design — the security-correct answer to memory poisoning is a
  memory you can *see and edit*, not one hidden behind a process. Agents are told never to store secrets
  or one-off details, and to confirm before saving anything sensitive.

## [2.3.0] — 2026-09-10

### Added
- **Auto-update.** Installs update themselves. Catch-up spawns a throttled (once/24h), detached
  `self-update` that re-runs the idempotent bootstrap when the pushed `VERSION` differs. It applies for
  the next session and never blocks the current one. Opt out with `CONTINUUM_NO_AUTOUPDATE=1`. A `git
  push` now reaches every user with no manual reinstall.
- **Bare `continuum` on PATH.** The global installer ships shims (`continuum.cmd` for cmd/PowerShell, a
  `continuum` bash wrapper) and adds `~/.continuum/bin` to PATH, so `continuum <cmd>` works in any shell.

### Fixed
- **Ad-hoc commands (e.g. `remember`) silently failing → agent fell back to host memory.** Agents were
  told to run bare `continuum`, but the bin dir wasn't on PATH and a `.ps1` isn't callable from bash, so
  ad-hoc calls failed (hooks survived only because they use absolute paths). Catch-up now injects the
  exact per-machine invocation into session context (`CONTINUUM CLI: <resolved command>`), so an agent
  always knows how to run any command, even before the PATH change reaches a new shell. Memory-capture
  guidance points at it. Found from real heavy-use feedback.

## [2.1.0] — 2026-08-13

The "trust duo" from the roadmap: grounded state and safer imports. Both attack the premise that
an agent's self-report is reliable, without adding a dependency.

### Added
- **`continuum verify` (grounded state).** Configure a project check once (`verify --set "npm test"`);
  a run stamps pass/fail + the commit into the manifest. Catch-up then flags *"STATE is unverified
  against current code (N commits since the last passing verify)"* or *"last verification FAILED"* — so
  an agent stops trusting a "done" claim that nothing actually checked. `save --verify` runs it as part
  of a handoff. The check is your own command, so no new dependency.
- **Quarantined imports.** `continuum import` now tags reconstructed transcript content
  `[unverified-import]` and tells agents to treat it as untrusted *data*, not instructions; catch-up
  warns while the journal still holds unverified imported content. Closes a prompt-injection path where
  scraped pages or tool output could ride into the ledger and be trusted by every future session.

### Changed
- `manifest.json` schema -> `1.2` (`verifyCommand` / `verifiedCommit` / `verifiedAt` / `verifiedOk`).

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
