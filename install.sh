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

# Resolve a WORKING Python across systems (Linux python3, Windows python / py -3; skip the Store stub).
PY_BIN=""; PY_DONE=0
have_py() {
  [ "$PY_DONE" = "1" ] && { [ -n "$PY_BIN" ]; return; }
  PY_DONE=1; local c
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c '' >/dev/null 2>&1; then PY_BIN="$c"; return 0; fi
  done
  command -v py >/dev/null 2>&1 && py -3 -c '' >/dev/null 2>&1 && { PY_BIN="py -3"; return 0; }
  return 1
}

# Merge Continuum hooks into a Claude Code settings JSON, idempotently (refresh ours, keep the rest).
merge_hooks() {
  local settings="$1" script="$2"
  mkdir -p "$(dirname "$settings")"
  if have_py; then
    CONT_SETTINGS="$settings" CONT_SCRIPT="$script" $PY_BIN - <<'PY'
import json, os, shutil
p = os.environ["CONT_SETTINGS"]; sc = os.environ["CONT_SCRIPT"]
if os.path.exists(p):
    with open(p, encoding="utf-8-sig") as fh: d = json.load(fh)
else:
    d = {}
if not isinstance(d, dict): raise ValueError("settings must be an object")
if "hooks" in d and not isinstance(d["hooks"], dict): raise ValueError("hooks must be an object")
hooks = d.setdefault("hooks", {})
for event, matcher, sub in [("SessionStart", "startup|resume|clear", "catch-up"),
                            ("PreCompact", "manual|auto", "precompact"),
                            ("Stop", "", "guard")]:
    cmd = 'bash "%s" %s' % (sc, sub)
    groups = hooks.get(event, [])
    if not isinstance(groups, list): raise ValueError("hook event must be an array")
    kept = []
    for g in groups:
        if not isinstance(g, dict) or not isinstance(g.get("hooks"), list):
            raise ValueError("nested hook group must contain an array")
        children = g["hooks"]
        if any(not isinstance(h, dict) for h in children): raise ValueError("hook must be an object")
        remaining = [h for h in children if not any(t in str(h.get("command", "")) for t in ("continuum.ps1", "continuum.sh"))]
        if remaining or not children: kept.append(dict(g, hooks=remaining))
    kept.append({"matcher": matcher, "hooks": [{"type": "command", "command": cmd}]})
    hooks[event] = kept
if os.path.exists(p): shutil.copy2(p, p + ".continuum.bak")
tmp = p + ".tmp." + str(os.getpid())
try:
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2); fh.write("\n")
    os.replace(tmp, p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print("  wired SessionStart/PreCompact/Stop hooks -> %s" % p)
PY
  else
    echo "  ! install Python to auto-wire hooks (skill/protocol still works without them)."
  fi
}

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
echo "[1/5] Context ledger (.aicontext/)"
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

# --- 2. Claude Code skill + helper CLI -------------------------------------
echo "[2/5] Claude Code skill + helper (.claude/skills/continuum/)"
BIN_DEST="$TARGET/.claude/skills/continuum/bin"
mkdir -p "$BIN_DEST"
cp "$SRC/skill/continuum/SKILL.md" "$TARGET/.claude/skills/continuum/SKILL.md"
cp "$SRC/bin/continuum.sh" "$BIN_DEST/continuum.sh"
cp "$SRC/bin/continuum.ps1" "$BIN_DEST/continuum.ps1"
chmod +x "$BIN_DEST/continuum.sh" 2>/dev/null || true
echo "  installed .claude/skills/continuum/SKILL.md + bin/continuum.sh|.ps1"

# --- 3. Claude Code hooks (deterministic capture) --------------------------
echo "[3/5] Claude Code hooks (.claude/settings.local.json)"
merge_hooks "$TARGET/.claude/settings.local.json" "$BIN_DEST/continuum.sh"

# --- 4. Agent adapters -----------------------------------------------------
echo "[4/5] Agent adapters"
SNIPPET="$(cat "$SRC/adapters/snippet.md")"
for f in CLAUDE.md AGENTS.md .windsurfrules; do
  set_managed_block "$TARGET/$f" "$SNIPPET"
done

# --- 5. gitignore ----------------------------------------------------------
echo "[5/5] .gitignore"
GI="$TARGET/.gitignore"
for line in '.aicontext/' '.claude/settings.local.json'; do
  if [ -f "$GI" ] && grep -qxF "$line" "$GI"; then
    echo "  kept    $line already ignored"
  else
    printf '\n# Continuum (machine-local)\n%s\n' "$line" >> "$GI"
    echo "  added   $line to .gitignore"
  fi
done

echo
echo "Continuum installed."
echo "Next: open this project in any agent — it will read .aicontext/STATE.md and catch up."
echo
