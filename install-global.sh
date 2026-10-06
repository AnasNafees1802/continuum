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
  if have_py; then
    CONT_FILE="$file" CONT_FMT="$fmt" CONT_SH="$BIN_SH" CONT_PS="$BIN_PS1" CONT_DEFS="$defs" $PY_BIN - <<'PY'
import json, os, shutil
f=os.environ["CONT_FILE"]; fmt=os.environ["CONT_FMT"]; sh=os.environ["CONT_SH"]; ps=os.environ["CONT_PS"]
defs=json.loads(os.environ["CONT_DEFS"])
if os.path.exists(f):
    with open(f, encoding="utf-8-sig") as fh: d=json.load(fh)
else:
    d={}
if not isinstance(d, dict): raise ValueError("settings must be an object")
if "hooks" in d and not isinstance(d["hooks"], dict): raise ValueError("hooks must be an object")
hooks=d.setdefault("hooks", {})
def cmdsh(a): return 'bash "%s" %s' % (sh, a)
def cmdps(a): return 'powershell -ExecutionPolicy Bypass -File "%s" %s' % (ps, a)
if fmt=="cursor": d["version"]=1
for spec in defs:
    e=spec["e"]; a=spec["a"]; m=spec.get("m","")
    groups = hooks.get(e, [])
    if not isinstance(groups, list): raise ValueError("hook event must be an array")
    kept = []
    for g in groups:
        if not isinstance(g, dict): raise ValueError("hook entry must be an object")
        if "hooks" in g:
            children = g["hooks"]
            if not isinstance(children, list) or any(not isinstance(h, dict) for h in children):
                raise ValueError("nested hooks must be an array of objects")
            remaining = [h for h in children if not any(t in str(h.get("command", "")) for t in ("continuum.ps1", "continuum.sh"))]
            if remaining or not children: kept.append(dict(g, hooks=remaining))
        elif not any(t in str(g.get("command", "")) for t in ("continuum.ps1", "continuum.sh")):
            kept.append(g)
    if fmt=="cursor":     entry={"command":cmdsh(a), "type":"command"}
    elif fmt=="windsurf": entry={"command":cmdsh(a), "powershell":cmdps(a)}
    else:                 entry={"matcher":m, "hooks":[{"type":"command","command":cmdsh(a)}]}
    kept.append(entry); hooks[e]=kept
if os.path.exists(f): shutil.copy2(f, f + ".continuum.bak")
tmp = f + ".tmp." + str(os.getpid())
try:
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2); fh.write("\n")
    os.replace(tmp, f)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print("      hooks wired -> %s" % f)
PY
  else
    echo "      ! install Python to auto-wire hooks for this agent (protocol still works via its instruction file)."
  fi
}

# Resolve an ABSOLUTE python for the MCP launch command (a GUI client may not share the shell PATH).
MCP_PYEXE=""; MCP_PYPRE=""
if have_py; then MCP_PYEXE="$($PY_BIN -c 'import sys; print(sys.executable)')"; fi
[ -z "$MCP_PYEXE" ] && MCP_PYEXE="python3"

# Register the Continuum MCP server in a client config (servers live under a top-level "mcpServers"
# object in every supported client). The JSON merge is in bin/register-mcp.py: atomic + backup + any depth.
register_mcp() {
  local file="$1"
  have_py || { echo "      ! install Python to auto-register the MCP server (protocol still works via the instruction file)."; return 0; }
  if CONT_FILE="$file" CONT_SRV="$BIN_DIR/continuum-mcp.py" CONT_PY="$MCP_PYEXE" CONT_PYPRE="$MCP_PYPRE" \
       $PY_BIN "$SRC/bin/register-mcp.py" >/dev/null
  then echo "      MCP server registered -> $file"
  else echo "      ! could not register MCP server -> $file"; fi
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

show_banner() {
  local bf="$SRC/banner.txt" w ver
  w="${COLUMNS:-0}"; [ "$w" = "0" ] && w="$(tput cols 2>/dev/null || echo 80)"
  echo
  if [ -f "$bf" ] && [ "$w" -ge 94 ] 2>/dev/null; then
    if [ -t 1 ]; then
      local M C R; M=$'\033[95m'; C=$'\033[96m'; R=$'\033[0m'
      sed -e "s/[#%*]\{1,\}/${M}&${R}/g" -e "s/[+=]\{1,\}/${C}&${R}/g" "$bf"
    else
      cat "$bf"
    fi
  else
    echo "   C O N T I N U U M"
  fi
  echo
  echo "   One shared memory for every AI coding agent."
  ver="$(cat "$SRC/VERSION" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$ver" ] && echo "   Global install  -  v$ver" || echo "   Global install"
  echo
}
show_banner

# Shared helper CLI: install once, referenced by every agent's hooks.
mkdir -p "$BIN_DIR"
cp "$SRC/bin/continuum.sh" "$BIN_SH"; cp "$SRC/bin/continuum.ps1" "$BIN_PS1"; chmod +x "$BIN_SH" 2>/dev/null || true
cp "$SRC/bin/continuum-mcp.py" "$BIN_DIR/continuum-mcp.py" 2>/dev/null || true   # MCP server (any MCP client)
[ -f "$SRC/VERSION" ] && cp "$SRC/VERSION" "$BIN_DIR/VERSION"
# Shim so a bare `continuum` works in any POSIX shell (bin dir is added to PATH below).
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$BIN_SH" > "$BIN_DIR/continuum"; chmod +x "$BIN_DIR/continuum" 2>/dev/null || true
# Put the bin dir on PATH via the user's shell rc files (idempotent; new shells pick it up). Skip for a custom CONTINUUM_HOME.
if [ -z "${CONTINUUM_HOME:-}" ]; then
  for rc in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc" "$HOME_DIR/.profile"; do
    [ -f "$rc" ] || continue
    grep -q '.continuum/bin' "$rc" || printf '\n# Continuum CLI on PATH\nexport PATH="$HOME/.continuum/bin:$PATH"\n' >> "$rc"
  done
fi
echo "  helper CLI -> $BIN_DIR (bare 'continuum' available in new shells)"
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

# MCP server: register with every client whose servers live under a top-level "mcpServers" object -
# Claude Code (~/.claude.json, USER scope so it shows in /mcp), Cursor, Windsurf, Gemini. This is
# additive to the hooks (gives on-demand tools/resources); Codex uses TOML config and is covered by hooks.
echo
echo "  MCP server (Continuum context/memory over MCP — for any MCP client):"
for m in \
  "Claude Code|$HOME_DIR/.claude|$HOME_DIR/.claude.json" \
  "Codex|$HOME_DIR/.codex|$HOME_DIR/.codex/config.toml" \
  "Cursor|$HOME_DIR/.cursor|$HOME_DIR/.cursor/mcp.json" \
  "Windsurf|$HOME_DIR/.codeium/windsurf|$HOME_DIR/.codeium/windsurf/mcp_config.json" \
  "Gemini CLI|$HOME_DIR/.gemini|$HOME_DIR/.gemini/settings.json"; do
  IFS='|' read -r mn md mf <<< "$m"
  if [ -d "$md" ] || [ "$ALL" = "1" ]; then printf '  + %-12s\n' "$mn"; register_mcp "$mf"; else printf '  - %-12s skipped (not detected; ALL=1 to force)\n' "$mn"; fi
done

echo
echo "Done. Detected agents catch up + hand off automatically in any project with a .aicontext/ folder."
echo "Restart any running agent session to pick up the new global config."
echo
