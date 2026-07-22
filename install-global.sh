#!/usr/bin/env bash
# Continuum GLOBAL installer (macOS / Linux) — install once for ALL agents.
# Injects the Continuum protocol into each agent's global instruction file AND wires deterministic
# hooks into every agent that supports them (Claude Code, Codex, Gemini, Cursor, Windsurf). A shared
# helper CLI is installed once to ~/.continuum/bin and every agent's hook points at it. Idempotent.
#
# Usage:
#   ./install-global.sh         # detected agents only
#   ALL=1 ./install-global.sh   # every known agent (creates config dirs)
#   CONTINUUM_HOME=/path ...     # target a different home root (testing)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL="${ALL:-0}"
HOME_DIR="${CONTINUUM_HOME:-$HOME}"
SNIPPET="$(cat "$SRC/adapters/global.md")"

BIN_DIR="$HOME_DIR/.continuum/bin"
BIN_SH="$BIN_DIR/continuum.sh"
BIN_PS1="$BIN_DIR/continuum.ps1"

has_py3() { command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; }

set_managed_block() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -q 'CONTINUUM:BEGIN' "$file"; then
    sed -i.bak '/<!-- CONTINUUM:BEGIN/,/CONTINUUM:END -->/d' "$file" && rm -f "$file.bak"
    printf '%s\n' "$SNIPPET" >> "$file"; echo "      protocol block updated -> $file"
  elif [ ! -f "$file" ] || [ ! -s "$file" ]; then
    printf '%s\n' "$SNIPPET" > "$file"; echo "      protocol block created -> $file"
  else
    printf '\n%s\n' "$SNIPPET" >> "$file"; echo "      protocol block appended -> $file"
  fi
}

# Merge Continuum hooks into an agent settings/hooks JSON, idempotently, preserving other keys.
# $1=file  $2=format(nested|cursor|windsurf)  $3=defs JSON
merge_hooks() {
  local file="$1" fmt="$2" defs="$3"
  mkdir -p "$(dirname "$file")"
  if has_py3; then
    CONT_FILE="$file" CONT_FMT="$fmt" CONT_SH="$BIN_SH" CONT_PS="$BIN_PS1" CONT_DEFS="$defs" python3 - <<'PY'
import json, os
f=os.environ["CONT_FILE"]; fmt=os.environ["CONT_FMT"]; sh=os.environ["CONT_SH"]; ps=os.environ["CONT_PS"]
defs=json.loads(os.environ["CONT_DEFS"])
try:
    with open(f) as fh: d=json.load(fh)
except Exception:
    d={}
if not isinstance(d, dict): d={}
hooks=d.setdefault("hooks", {})
def cmdsh(a): return 'bash "%s" %s' % (sh, a)
def cmdps(a): return 'powershell -ExecutionPolicy Bypass -File "%s" %s' % (ps, a)
if fmt=="cursor": d["version"]=1
for spec in defs:
    e=spec["e"]; a=spec["a"]; m=spec.get("m","")
    kept=[g for g in hooks.get(e, []) if "continuum" not in json.dumps(g)]
    if fmt=="cursor":     entry={"command":cmdsh(a), "type":"command"}
    elif fmt=="windsurf": entry={"command":cmdsh(a), "powershell":cmdps(a)}
    else:                 entry={"matcher":m, "hooks":[{"type":"command","command":cmdsh(a)}]}
    kept.append(entry); hooks[e]=kept
with open(f, "w") as fh:
    json.dump(d, fh, indent=2); fh.write("\n")
print("      hooks wired -> %s" % f)
PY
  else
    echo "      ! install python3 to auto-wire hooks for this agent (protocol still works via its instruction file)."
  fi
}

NESTED_FULL='[{"e":"SessionStart","m":"startup|resume|clear","a":"catch-up --event SessionStart"},{"e":"PreCompact","m":"manual|auto","a":"precompact --event PreCompact"},{"e":"Stop","m":"","a":"guard"}]'
GEMINI_DEFS='[{"e":"SessionStart","m":"startup|resume|clear","a":"catch-up --event SessionStart"},{"e":"PreCompress","m":"auto|manual","a":"precompact --event PreCompress"}]'
CURSOR_DEFS='[{"e":"sessionStart","a":"catch-up --event sessionStart"},{"e":"preCompact","a":"precompact --event preCompact"},{"e":"stop","a":"guard"}]'
WINDSURF_DEFS='[{"e":"pre_user_prompt","a":"catch-up --once --event pre_user_prompt"}]'

# name|detect dir|block file(-)|kind|hook file(-)|skill(0/1)
AGENTS=(
  "Claude Code|$HOME_DIR/.claude|$HOME_DIR/.claude/CLAUDE.md|nested|$HOME_DIR/.claude/settings.json|1"
  "Codex|$HOME_DIR/.codex|$HOME_DIR/.codex/AGENTS.md|nested|$HOME_DIR/.codex/hooks.json|0"
  "Gemini CLI|$HOME_DIR/.gemini|$HOME_DIR/.gemini/GEMINI.md|gemini|$HOME_DIR/.gemini/settings.json|0"
  "Antigravity|$HOME_DIR/.gemini|$HOME_DIR/.gemini/AGENTS.md|none|-|0"
  "Cursor|$HOME_DIR/.cursor|-|cursor|$HOME_DIR/.cursor/hooks.json|0"
  "Windsurf|$HOME_DIR/.codeium/windsurf|$HOME_DIR/.codeium/windsurf/memories/global_rules.md|windsurf|$HOME_DIR/.codeium/windsurf/hooks.json|0"
)

echo
echo "Continuum - global install (once for all agents)"
echo "  source: $SRC"
echo

# Shared helper CLI: install once, referenced by every agent's hooks.
mkdir -p "$BIN_DIR"
cp "$SRC/bin/continuum.sh" "$BIN_SH"; cp "$SRC/bin/continuum.ps1" "$BIN_PS1"; chmod +x "$BIN_SH" 2>/dev/null || true
echo "  helper CLI -> $BIN_DIR"
echo

for entry in "${AGENTS[@]}"; do
  IFS='|' read -r name dir block kind hook skill <<< "$entry"
  if [ ! -d "$dir" ] && [ "$ALL" != "1" ]; then
    printf '  - %-12s skipped (not detected; ALL=1 to force)\n' "$name"; continue
  fi
  printf '  + %-12s\n' "$name"
  [ "$block" != "-" ] && set_managed_block "$block"
  if [ "$skill" = "1" ]; then
    mkdir -p "$HOME_DIR/.claude/skills/continuum/bin"
    cp "$SRC/skill/continuum/SKILL.md" "$HOME_DIR/.claude/skills/continuum/SKILL.md"
    cp "$SRC/bin/continuum.sh" "$HOME_DIR/.claude/skills/continuum/bin/continuum.sh"
    cp "$SRC/bin/continuum.ps1" "$HOME_DIR/.claude/skills/continuum/bin/continuum.ps1"
    echo "      skill installed -> ~/.claude/skills/continuum/"
  fi
  case "$kind" in
    nested)   merge_hooks "$hook" nested   "$NESTED_FULL" ;;
    gemini)   merge_hooks "$hook" nested   "$GEMINI_DEFS" ;;
    cursor)   merge_hooks "$hook" cursor   "$CURSOR_DEFS" ;;
    windsurf) merge_hooks "$hook" windsurf "$WINDSURF_DEFS" ;;
    none)     : ;;
  esac
done

echo
echo "Done. Detected agents catch up + hand off automatically in any project with a .aicontext/ folder."
echo "Restart any running agent session to pick up the new global config."
echo
