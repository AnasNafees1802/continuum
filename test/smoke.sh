#!/usr/bin/env bash
# Continuum smoke tests — exercise the helper CLI end-to-end on a throwaway ledger.
# Requires: bash, git, python3 (for JSON assertions). Run: bash test/smoke.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONT="$SRC/bin/continuum.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1 || { echo "smoke: python3 is required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "smoke: git is required"; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.aicontext"
cp "$SRC"/templates/aicontext/* "$T/.aicontext/"
for f in "$T"/.aicontext/*; do sed -e 's/{{PROJECT_NAME}}/smoke/g' -e 's/{{DATE}}/2026-01-01 00:00/g' "$f" > "$f.x" && mv "$f.x" "$f"; done
cd "$T"
git init -q .; git config user.email s@s.s; git config user.name s
git add -A; git commit -qm init >/dev/null 2>&1
printf 'x\n' > feature.py; git add -A; git commit -qm feat >/dev/null 2>&1

echo "Continuum smoke tests (ledger: $T)"

# 1. save -> manifest is valid JSON, no BOM, sessionCount incremented, commit stamped
# (paths are relative to the ledger cwd so assertions work regardless of shell/python path forms)
bash "$CONT" save --agent smoke >/dev/null 2>&1
if python3 - .aicontext/manifest.json <<'PY'
import json,sys
raw=open(sys.argv[1],'rb').read()
assert raw[:3]!=b'\xef\xbb\xbf', "manifest has a UTF-8 BOM"
c=json.loads(raw.decode('utf-8'))['continuum']
assert c['sessionCount']==1, "sessionCount=%r"%c['sessionCount']
assert c['lastCommit'], "lastCommit not stamped"
assert c['lastAgent']=='smoke', "lastAgent=%r"%c['lastAgent']
assert 'smoke' in (c.get('agentsSeen') or []), "agentsSeen missing"
PY
then ok "save: valid no-BOM manifest, sessionCount=1, commit+agent stamped"; else bad "save manifest"; fi

# 2. save again -> sessionCount 2 (idempotent bookkeeping)
bash "$CONT" save --agent smoke >/dev/null 2>&1
if python3 -c "import json;assert json.load(open('.aicontext/manifest.json'))['continuum']['sessionCount']==2"
then ok "save: sessionCount increments to 2"; else bad "save sessionCount increment"; fi

# 3. catch-up -> stdout is a single valid JSON object with additionalContext
if printf '{"session_id":"smoke1"}' | bash "$CONT" catch-up --event SessionStart | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['hookSpecificOutput']['hookEventName']=='SessionStart';assert 'STATE.md' in d['hookSpecificOutput']['additionalContext']"
then ok "catch-up: emits valid JSON additionalContext"; else bad "catch-up JSON"; fi

# 4. guard nudges at most once per session (dirty tree, STATE not updated)
python3 -c "import os,time;os.utime('.aicontext/STATE.md',(time.time()-3600,)*2)"
printf 'work\n' > newwork.txt
G1="$(printf '{"session_id":"smoke1","stop_hook_active":false}' | bash "$CONT" guard)"
G2="$(printf '{"session_id":"smoke1","stop_hook_active":false}' | bash "$CONT" guard)"
if echo "$G1" | grep -q '"decision":"block"' && [ -z "$G2" ]
then ok "guard: nudges once, silent thereafter"; else bad "guard once ($G1 / $G2)"; fi

# 4b. guard also nudges when you committed code but never logged a decision
printf '{"session_id":"smoke2"}' | bash "$CONT" catch-up >/dev/null 2>&1
python3 -c "import os,time;t=time.time();os.utime('.aicontext/STATE.md',(t+3600,)*2);os.utime('.aicontext/DECISIONS.md',(t-3600,)*2)"
printf 'feat\n' > feat_b.txt; git add -A >/dev/null 2>&1; git commit -qm "smoke feat" >/dev/null 2>&1
GD="$(printf '{"session_id":"smoke2","stop_hook_active":false}' | bash "$CONT" guard)"
if echo "$GD" | grep -q 'DECISIONS.md'
then ok "guard: nudges when commits made without a logged decision"; else bad "guard decision nudge ($GD)"; fi

# 4c. guard must NOT false-nag after a real save, even if this session's marker wasn't stamped
printf '{"session_id":"smoke3"}' | bash "$CONT" catch-up >/dev/null 2>&1
printf 'more\n' > feat_c.txt; git add -A >/dev/null 2>&1; git commit -qm "smoke c" >/dev/null 2>&1
bash "$CONT" save --agent smoke >/dev/null 2>&1
sed -i 's/^handoff=1/handoff=0/' .aicontext/.session/smoke3.env 2>/dev/null   # simulate a manual save that never stamped the marker
GC="$(printf '{"session_id":"smoke3","stop_hook_active":false}' | bash "$CONT" guard)"
if [ -z "$GC" ]
then ok "guard: silent after a save even if the marker wasn't stamped (no false nag)"; else bad "guard false-nag after save ($GC)"; fi

# 5. compact -> rotate a >20-entry journal down to 20 + archive the rest
{ echo "# Session Journal"; echo; for i in $(seq 25 -1 1); do printf '## 2026-01-%02d 10:00 - a\nentry %d\n\n' "$i" "$i"; done; } > "$T/.aicontext/JOURNAL.md"
bash "$CONT" compact >/dev/null 2>&1
KEPT="$(grep -c '^## ' "$T/.aicontext/JOURNAL.md")"
if [ "$KEPT" = "20" ] && [ -f "$T/.aicontext/archive/JOURNAL-2026.md" ]
then ok "compact: kept 20 entries, archived the rest"; else bad "compact (kept=$KEPT)"; fi

# 6. import --from git always produces a git view (universal floor)
# capture then grep (grep -q would close the pipe early and SIGPIPE the producer under pipefail)
IMP="$(bash "$CONT" import --from git 2>/dev/null)"
if printf '%s' "$IMP" | grep -q 'Git view'
then ok "import --from git: produces git reconstruction"; else bad "import git view"; fi

# 7. doctor reports healthy on a well-formed ledger
if bash "$CONT" doctor | grep -q 'healthy'
then ok "doctor: reports healthy"; else bad "doctor healthy"; fi

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
