#!/usr/bin/env bash
# Continuum installer (macOS / Linux) — cross-agent session continuity.
# Creates the .aicontext/ ledger, installs the `continuum` Claude Code skill, and injects an
# auto-loaded instruction block into CLAUDE.md, AGENTS.md, .windsurfrules. Idempotent.
#
# Usage:
#   ./install.sh                 # install into the current directory
#   ./install.sh /path/to/proj   # install into a specific project
#   FORCE=1 ./install.sh         # overwrite existing ledger files
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "${1:-$PWD}" && pwd)"
NOW="$(date '+%Y-%m-%d %H:%M')"
PROJECT_NAME="$(basename "$TARGET")"
FORCE="${FORCE:-0}"

expand_tokens() { sed -e "s/{{PROJECT_NAME}}/${PROJECT_NAME//\//\\/}/g" -e "s/{{DATE}}/$NOW/g"; }

# Idempotently set the managed Continuum block in a file.
set_managed_block() {
  local file="$1" snippet="$2"
  if [ -f "$file" ] && grep -q 'CONTINUUM:BEGIN' "$file"; then
    # Replace existing block (delete from BEGIN to END, then append fresh).
    sed -i.bak '/<!-- CONTINUUM:BEGIN/,/CONTINUUM:END -->/d' "$file" && rm -f "$file.bak"
    # Trim trailing blank lines, then append.
    printf '%s\n' "$snippet" >> "$file"
    echo "  updated $(basename "$file")"
  elif [ ! -f "$file" ] || [ ! -s "$file" ]; then
    printf '%s\n' "$snippet" > "$file"
    echo "  created $(basename "$file")"
  else
    printf '\n%s\n' "$snippet" >> "$file"
    echo "  appended $(basename "$file")"
  fi
}

echo
echo "Continuum installer"
echo "  source : $SRC"
echo "  target : $TARGET"
echo

# --- 1. Ledger -------------------------------------------------------------
echo "[1/4] Context ledger (.aicontext/)"
mkdir -p "$TARGET/.aicontext"
for f in "$SRC"/templates/aicontext/*; do
  name="$(basename "$f")"
  dest="$TARGET/.aicontext/$name"
  if [ -f "$dest" ] && [ "$FORCE" != "1" ] && [ "$name" != "PROTOCOL.md" ]; then
    echo "  kept    .aicontext/$name (already present)"
  else
    expand_tokens < "$f" > "$dest"
    echo "  wrote   .aicontext/$name"
  fi
done

# --- 2. Claude Code skill --------------------------------------------------
echo "[2/4] Claude Code skill (.claude/skills/continuum/)"
mkdir -p "$TARGET/.claude/skills/continuum"
cp "$SRC/skill/continuum/SKILL.md" "$TARGET/.claude/skills/continuum/SKILL.md"
echo "  installed .claude/skills/continuum/SKILL.md"

# --- 3. Agent adapters -----------------------------------------------------
echo "[3/4] Agent adapters"
SNIPPET="$(cat "$SRC/adapters/snippet.md")"
for f in CLAUDE.md AGENTS.md .windsurfrules; do
  set_managed_block "$TARGET/$f" "$SNIPPET"
done

# --- 4. gitignore ----------------------------------------------------------
echo "[4/4] .gitignore"
GI="$TARGET/.gitignore"
if [ -f "$GI" ] && grep -qxF '.aicontext/' "$GI"; then
  echo "  kept    .aicontext/ already ignored"
else
  printf '\n# Continuum local memory ledger (machine-local)\n.aicontext/\n' >> "$GI"
  echo "  added   .aicontext/ to .gitignore"
fi

echo
echo "Continuum installed."
echo "Next: open this project in any agent — it will read .aicontext/STATE.md and catch up."
echo
