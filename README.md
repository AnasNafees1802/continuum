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
└── .claude/skills/continuum/SKILL.md   # full protocol as a Claude Code skill
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

It detects which agents you have and writes to each one's global instruction file:

| Agent | Global file |
|-------|-------------|
| Claude Code | `~/.claude/CLAUDE.md` + skill `~/.claude/skills/continuum/` |
| Codex | `~/.codex/AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| Antigravity | `~/.gemini/AGENTS.md` (cross-tool; avoids the GEMINI.md conflict) |
| Windsurf | `~/.codeium/windsurf/memories/global_rules.md` |

After this, the only per-project step is creating the `.aicontext/` ledger — which any agent will
do for you on request (Claude self-bootstraps; or run Option B).

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

- **History importer** — bootstrap `.aicontext/` from an agent's existing native logs
  (Claude Code's `~/.claude/projects/*.jsonl`, then Codex/Cursor/Gemini), inspired by
  [claude-code-history-viewer](https://github.com/jhlee0409/claude-code-history-viewer).
- ✅ ~~One-line remote install~~ — shipped (see [One line, no clone](#-one-line-no-clone-recommended)).
- More native adapters as agents diverge from `AGENTS.md`.

## Author

Built by **[Anas Nafees](https://www.linkedin.com/in/anas-nafees/)**.

Continuum is open source and contributions are welcome — open an issue or PR at
[github.com/AnasNafees1802/continuum](https://github.com/AnasNafees1802/continuum).
If it saves you from re-explaining your project to yet another agent, a ⭐ is appreciated.

## License

[MIT](LICENSE) © Anas Nafees — free to use, modify, and distribute. Use it everywhere.
