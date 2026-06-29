#!/usr/bin/env bash
# Continuum GLOBAL installer (macOS / Linux) — install once for ALL agents.
# Injects the Continuum protocol into each agent's global instruction file so every project you open
# in any agent follows the protocol when it has a .aicontext/ folder.
# Targets: Claude Code, Codex, Gemini CLI, Antigravity, Windsurf. Idempotent.
#
# Usage:
#   ./install-global.sh         # install for detected agents only
#   ALL=1 ./install-global.sh   # install for every known agent (creates config dirs)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL="${ALL:-0}"
SNIPPET="$(cat "$SRC/adapters/global.md")"

set_managed_block() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -q 'CONTINUUM:BEGIN' "$file"; then
    sed -i.bak '/<!-- CONTINUUM:BEGIN/,/CONTINUUM:END -->/d' "$file" && rm -f "$file.bak"
    printf '%s\n' "$SNIPPET" >> "$file"; echo "      block updated"
  elif [ ! -f "$file" ] || [ ! -s "$file" ]; then
    printf '%s\n' "$SNIPPET" > "$file"; echo "      block created"
  else
    printf '\n%s\n' "$SNIPPET" >> "$file"; echo "      block appended"
  fi
}

# name|detection dir|global file|install-claude-skill(0/1)
AGENTS=(
  "Claude Code|$HOME/.claude|$HOME/.claude/CLAUDE.md|1"
  "Codex|$HOME/.codex|$HOME/.codex/AGENTS.md|0"
  "Gemini CLI|$HOME/.gemini|$HOME/.gemini/GEMINI.md|0"
  "Antigravity|$HOME/.gemini|$HOME/.gemini/AGENTS.md|0"
  "Windsurf|$HOME/.codeium/windsurf|$HOME/.codeium/windsurf/memories/global_rules.md|0"
)

echo
echo "Continuum - global install (once for all agents)"
echo "  source: $SRC"
echo

for entry in "${AGENTS[@]}"; do
  IFS='|' read -r name dir file skill <<< "$entry"
  if [ ! -d "$dir" ] && [ "$ALL" != "1" ]; then
    printf '  - %-12s skipped (not detected; ALL=1 to force)\n' "$name"
    continue
  fi
  printf '  + %-12s %s\n' "$name" "${file/#$HOME/~}"
  set_managed_block "$file"
  if [ "$skill" = "1" ]; then
    mkdir -p "$HOME/.claude/skills/continuum"
    cp "$SRC/skill/continuum/SKILL.md" "$HOME/.claude/skills/continuum/SKILL.md"
    echo "      skill installed -> ~/.claude/skills/continuum/SKILL.md"
  fi
done

echo
echo "Done. Every detected agent now follows Continuum in any project with a .aicontext/ folder."
echo "Restart any running agent session to pick up the new global config."
echo
