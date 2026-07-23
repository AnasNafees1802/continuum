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

has_py3() { command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; }

# Merge Continuum hooks into a Claude Code settings JSON, idempotently (refresh ours, keep the rest).
merge_hooks() {
  local settings="$1" script="$2"
  mkdir -p "$(dirname "$settings")"
  if has_py3; then
    CONT_SETTINGS="$settings" CONT_SCRIPT="$script" python3 - <<'PY'
import json, os
p = os.environ["CONT_SETTINGS"]; sc = os.environ["CONT_SCRIPT"]
try:
    with open(p) as fh: d = json.load(fh)
except Exception:
    d = {}
if not isinstance(d, dict): d = {}
hooks = d.setdefault("hooks", {})
for event, matcher, sub in [("SessionStart", "startup|resume|clear", "catch-up"),
                            ("PreCompact", "manual|auto", "precompact"),
                            ("Stop", "", "guard")]:
    cmd = 'bash "%s" %s' % (sc, sub)
    kept = [g for g in hooks.get(event, [])
            if not any(t in " ".join(h.get("command", "") for h in g.get("hooks", [])) for t in ("continuum.ps1", "continuum.sh"))]
    kept.append({"matcher": matcher, "hooks": [{"type": "command", "command": cmd}]})
    hooks[event] = kept
with open(p, "w") as fh:
    json.dump(d, fh, indent=2); fh.write("\n")
print("  wired SessionStart/PreCompact/Stop hooks -> %s" % p)
PY
  elif command -v jq >/dev/null 2>&1; then
    [ -f "$settings" ] || echo '{}' > "$settings"
    local ev m sub cmd
    for spec in "SessionStart|startup|resume|clear|catch-up" "PreCompact|manual|auto|precompact" "Stop||guard"; do
      ev="${spec%%|*}"; rest="${spec#*|}"; sub="${rest##*|}"; m="${rest%|*}"
      cmd="bash \"$script\" $sub"
      jq --arg ev "$ev" --arg m "$m" --arg cmd "$cmd" '
        .hooks[$ev] = (((.hooks[$ev] // []) | map(select([.hooks[]?.command] | any(. != null and (contains("continuum"))) | not)))
                       + [{matcher:$m, hooks:[{type:"command", command:$cmd}]}])' \
        "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
    done
    echo "  wired SessionStart/PreCompact/Stop hooks -> $settings"
  else
    echo "  ! install python3 or jq to auto-wire hooks (skill/protocol still works without them)."
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
