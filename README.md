# 🔁 Continuum

**Cross-agent session continuity for AI coding agents.**

Switch from Codex to Claude to Antigravity — or come back tomorrow after hitting a usage limit —
and your agent already knows *what you're building, where you are, and what's next.* No re-explaining.

---

## The problem

You're building with one AI coding agent. You ship a couple of features, then the **daily limit
hits** and it stops. You switch to another agent — but it knows *nothing*. You burn time and tokens
re-explaining the project, and you lose the thread of *why* things were done a certain way.

Each agent keeps its own private history (Claude Code in `~/.claude/projects/`, others elsewhere),
and none of them share. The context is trapped in a silo.

## The solution

Continuum puts a small, structured **memory ledger inside your project** at `.aicontext/`, and
teaches *every* agent the same simple protocol:

> **Read it when you start. Update it before you stop.**

Because the memory lives in the repo — not in any one agent's silo — context survives the switch.
Any agent, any day, picks up exactly where the last one left off.

```
your-project/
├── .aicontext/              # 📦 the portable memory (gitignored, machine-local)
│   ├── STATE.md             #   ⭐ where we are right now — read this first
│   ├── TASKS.md             #   in progress / backlog / done
│   ├── DECISIONS.md         #   append-only: why we chose what we chose
│   ├── JOURNAL.md           #   append-only: per-session handoff log
│   ├── manifest.json        #   metadata (last agent, session count, …)
│   └── PROTOCOL.md          #   the full spec agents follow
├── CLAUDE.md                # auto-loaded by each agent; carries the
├── AGENTS.md                # "read/update .aicontext/" instruction block
├── .windsurfrules           # (Codex/Antigravity/Windsurf/Gemini read AGENTS.md)
├── .claude/
│   ├── settings.local.json  # ⚙️ Claude Code hooks (machine-local, gitignored)
│   └── skills/continuum/
│       ├── SKILL.md         #   full protocol as a Claude Code skill
│       └── bin/             #   the `continuum` helper CLI (.ps1 + .sh)
```

## Which agents?

- **Claude Code** — via `CLAUDE.md` + the `continuum` skill.
- **Codex, Antigravity, Windsurf, Gemini CLI, Cursor, Zed, …** — via **`AGENTS.md`**, the
  [emerging cross-agent standard](https://agents.md) read by 60k+ projects.
- **Windsurf** — also gets a native `.windsurfrules` for belt-and-suspenders coverage.

Any agent that reads one of those files participates automatically.

## Install

### ⚡ One line, no clone (recommended)

Installs Continuum into **every AI agent on your machine, once** — applies to all your projects:

```powershell
# Windows / PowerShell
irm https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.ps1 | iex
```
```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.sh | bash
```

That downloads the repo to a temp folder, runs the global installer, and cleans up. Variations:

| Goal | Windows | macOS / Linux |
|------|---------|---------------|
| Force **all** known agents | `$env:CONTINUUM_ALL='1'; irm …/bootstrap.ps1 \| iex` | `curl -fsSL …/bootstrap.sh \| CONTINUUM_ALL=1 bash` |
| **Per-project** ledger in current dir | `$env:CONTINUUM_MODE='project'; irm …/bootstrap.ps1 \| iex` | `curl -fsSL …/bootstrap.sh \| CONTINUUM_MODE=project bash` |

> Piping a script from the internet to your shell runs remote code. That's standard for installers,
> but you should trust the source — read [`bootstrap.ps1`](bootstrap.ps1) / [`bootstrap.sh`](bootstrap.sh)
> first if you like. Prefer not to pipe? Use the clone method below.

---

### Or clone and run the installer yourself

```bash
git clone https://github.com/AnasNafees1802/continuum.git
cd continuum
```

#### Option A — Global: install once, for every agent (recommended)

Wires the Continuum protocol into each agent's **global** config so *every* project you open in
*any* agent follows it automatically (when that project has a `.aicontext/` folder). Run it once
from the cloned folder:

```powershell
# Windows / PowerShell  (-ExecutionPolicy Bypass avoids the unsigned-script block)
powershell -ExecutionPolicy Bypass -File .\install-global.ps1         # detected agents only
powershell -ExecutionPolicy Bypass -File .\install-global.ps1 -All    # force all known agents
```

```bash
# macOS / Linux
bash ./install-global.sh             # detected agents only
ALL=1 bash ./install-global.sh       # force all known agents
```

It installs the shared helper once to `~/.continuum/bin/`, then for each agent it detects writes the
protocol into that agent's global instruction file **and** wires its native hooks:

| Agent | Global instruction file | Hooks wired into |
|-------|-------------------------|------------------|
| Claude Code | `~/.claude/CLAUDE.md` + skill `~/.claude/skills/continuum/` | `~/.claude/settings.json` |
| Codex | `~/.codex/AGENTS.md` | `~/.codex/hooks.json` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/settings.json` |
| Antigravity | `~/.gemini/AGENTS.md` (cross-tool; avoids the GEMINI.md conflict) | — |
| Cursor | (User Rules / `AGENTS.md` in-repo) | `~/.cursor/hooks.json` |
| Windsurf | `~/.codeium/windsurf/memories/global_rules.md` | `~/.codeium/windsurf/hooks.json` |

Hook merges are idempotent and preserve any hooks you already have. After this, the only per-project
step is creating the `.aicontext/` ledger — which any agent will do for you on request (Claude
self-bootstraps; or run Option B).

#### Option B — Per-project: set up the ledger + adapter files in one repo

Run from the cloned folder, pointing at the project you want continuity for:

```powershell
# Windows / PowerShell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Target C:\path\to\my-project
```
```bash
# macOS / Linux
bash ./install.sh /path/to/my-project
```

This creates `.aicontext/` and drops `CLAUDE.md` / `AGENTS.md` / `.windsurfrules` adapters in the repo
root. Useful when you *haven't* done the global install, or want the adapters committed for teammates.

> All installers are **idempotent** — re-run any time to refresh without touching accumulated context.
> The per-project installer takes `-Force` (PS) / `FORCE=1` (sh) to also reset the ledger.

## How it stays reliable

A memory ledger is only as good as the discipline that keeps it current. The naïve version —
"agent, please read this at start and update it before you stop" — breaks in exactly the case
Continuum exists for: **when a usage limit or crash kills the session, there's no chance to write
the handoff.** So Continuum doesn't rely on remembering. It wires **native hooks** into every agent
that has them and uses a **shared helper CLI** for the bookkeeping:

- **Guaranteed catch-up** — a session-start hook injects `STATE.md` (plus recent journal + drift
  notes) into context every session. Catching up stops being something the agent might forget.
- **Handoff before context loss** — a pre-compaction hook fires right as the context window is about
  to compact and prompts the handoff *then*, while the detail still exists.
- **A gentle safety net, not a nag** — a stop hook reminds you *once per session* if you changed
  files but never saved. Never twice.
- **Reconstruction for hard kills** — if a session ends with no handoff (limit/crash), the next
  session detects the gap and `continuum import --from auto` rebuilds a draft handoff from the last
  agent's own transcript **plus** a git-based view. The one moment a hook *can't* capture is
  recovered after the fact — even across a tool switch (Codex → Claude, or back).
- **Never trust a stale ledger** — catch-up compares the saved git commit to `HEAD` and flags drift
  ("12 commits + uncommitted changes since last save"), so the agent verifies against `git` instead
  of confidently briefing you from an out-of-date snapshot.
- **Bounded cost** — `continuum save` rotates old `JOURNAL.md` entries into `.aicontext/archive/`, so
  the ledger never bloats the context it's meant to save.

The helper is plain PowerShell + bash (no runtime, no dependencies). It only does mechanics —
timestamps, `manifest.json`, git checks, transcript parsing, rotation. **The agent still writes the
actual prose**; that judgment isn't something to automate away.

### What's automated, per agent

| Agent | Catch-up (start) | Handoff prompt | Stop nudge | Native transcript recon |
|-------|:---:|:---:|:---:|:---:|
| Claude Code | ✅ `SessionStart` | ✅ `PreCompact` | ✅ `Stop` | ✅ |
| Codex | ✅ `SessionStart` | ✅ `PreCompact` | ✅ `Stop` | ✅ (matched by cwd) |
| Gemini CLI | ✅ `SessionStart` | ✅ `PreCompress` | — | ✅ |
| Cursor | ✅ `sessionStart` | ✅ `preCompact` | ✅ `stop` | git-based |
| Windsurf | ✅ (first per-turn hook) | — | — | git-based |

> **Universal floor:** even where native hooks or transcript parsing aren't available, the
> **git-based reconstruction** (`--from git`, always included in `auto`) rebuilds "what changed" from
> `git log`/`git diff`, and the honor-protocol in each agent's instruction file (`AGENTS.md` /
> `GEMINI.md` / `CLAUDE.md` / rules) still drives read-at-start, save-before-stop. Continuity never
> fully fails, on any tool.

## How it works in practice

1. **Day 1, Codex:** you build a feature. Before the limit hits, Codex updates `STATE.md` and
   appends a `JOURNAL.md` entry: *"Built auth flow, left off at wiring the token refresh."*
2. **Day 1, later, Claude Code:** you open the project. Claude reads `.aicontext/STATE.md`, says
   *"📍 Caught up: building the auth flow, next is token refresh,"* and continues — no re-explaining.
3. **Day 2, Antigravity:** same thing. Everyone shares one brain.

## Design choices

- **Gitignored by default** — `.aicontext/` is machine-local, not pushed. The adapter files *are*
  committed, so the protocol travels with the repo and each clone re-inits its own local ledger.
  (Want it shared with your team? Remove `.aicontext/` from `.gitignore` and commit it.)
- **Plain Markdown + JSON** — no runtime, no service, no lock-in. Readable and editable by hand.
- **`STATE.md` is living; `JOURNAL.md`/`DECISIONS.md` are append-only** — so you always have both a
  fast current snapshot and a full, trustworthy history.

## Roadmap

- ✅ ~~Deterministic capture~~ — shipped: native session-start / pre-compaction / stop hooks on Claude
  Code, Codex, Gemini and Cursor (Windsurf via its per-turn hook).
- ✅ ~~History importer~~ — shipped: `continuum import --from auto` reconstructs a missed handoff from the
  last agent's transcript (Claude/Codex/Gemini native parsers) plus a universal git-based view.
- ✅ ~~Drift detection~~ — shipped: catch-up flags commits/changes since the ledger was last saved.
- ✅ ~~One-line remote install~~ — shipped (see [One line, no clone](#-one-line-no-clone-recommended)).
- **Native transcript parsers for Cursor/Windsurf** (SQLite `state.vscdb`) — today they use git-based reconstruction.
- **Team mode** — optional shared (committed) ledger with conflict-resistant per-session journal files.

## Author

Built by **[Anas Nafees](https://www.linkedin.com/in/anas-nafees/)**.

Continuum is open source and contributions are welcome — open an issue or PR at
[github.com/AnasNafees1802/continuum](https://github.com/AnasNafees1802/continuum).
If it saves you from re-explaining your project to yet another agent, a ⭐ is appreciated.

## License

[MIT](LICENSE) © Anas Nafees — free to use, modify, and distribute. Use it everywhere.
