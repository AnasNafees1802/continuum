#!/usr/bin/env bash
# Continuum helper CLI (POSIX / Git Bash) — deterministic bookkeeping for the
# .aicontext/ ledger, shared across AI agents. The model writes the prose; this
# script does the mechanics. Backs the hooks of Claude Code, Codex, Gemini,
# Cursor and Windsurf (they share the same JSON-on-stdin hook contract).
#
# Commands:
#   catch-up [--event NAME] [--once]   session-start hook: emit ledger as JSON additionalContext
#   precompact [--event NAME]          compaction hook: tell the model to hand off NOW
#   guard                              stop hook: one gentle "you didn't save" nudge per session
#   import [--from auto|git|claude|codex|gemini]  reconstruct a missed handoff (+ always a git view)
#   save [--agent NAME]                stamp manifest.json at end of a handoff
#   compact                            rotate old JOURNAL entries into .aicontext/archive/
#   status | doctor                    health + cross-agent drift/gap report
set -uo pipefail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
has_py3() { command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; }
home_dir() { printf '%s' "${HOME:-$USERPROFILE}"; }

find_root() {
  local d="$PWD"
  while :; do
    [ -d "$d/.aicontext" ] && { printf '%s\n' "$d"; return 0; }
    local parent; parent="$(dirname "$d")"
    [ "$parent" = "$d" ] && break
    d="$parent"
  done
  return 1
}

now_human() { date '+%Y-%m-%d %H:%M'; }
now_iso()   { date '+%Y-%m-%dT%H:%M:%S%z'; }
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

git_sha()   { git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo ""; }
git_branch(){ git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""; }
git_dirty_sum() { git -C "$ROOT" status --porcelain 2>/dev/null | cksum | awk '{print $1}'; }

sha256_of() {
  if have sha256sum; then printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif have shasum; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif has_py3; then printf '%s' "$1" | python3 -c 'import sys,hashlib;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  fi
}

# JSON-escape stdin into a single string body (no surrounding quotes); joins lines with \n.
json_escape() {
  awk '
    { gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"") }
    NR==1 { printf "%s", $0; next }
    { printf "\\n%s", $0 }
  '
}

# Read a top-level scalar from manifest.json without a JSON parser.
manifest_get() {
  local key="$1" f="$ROOT/.aicontext/manifest.json"
  [ -f "$f" ] || return 0
  grep -oE "\"$key\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|null|[0-9]+)" "$f" | head -1 \
    | sed -E "s/\"$key\"[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"\$//; s/^null\$//"
}

# session marker (key=value text, our own format — no JSON parser needed)
marker_dir()  { printf '%s\n' "$ROOT/.aicontext/.session"; }
marker_file() { printf '%s\n' "$(marker_dir)/${1:-default}.env"; }
marker_get()  { [ -f "$2" ] && sed -nE "s/^$1=//p" "$2" | head -1; }
# Atomic single-field update: rewrite to a temp file, then rename. Never leaves a truncated marker.
marker_set()  { # key value file
  local k="$1" v="$2" f="$3" tmp
  mkdir -p "$(dirname "$f")"; tmp="$f.tmp.$$"
  if [ -f "$f" ] && grep -q "^$k=" "$f"; then
    sed "s|^$k=.*|$k=$v|" "$f" > "$tmp" && mv -f "$tmp" "$f"
  elif [ -f "$f" ]; then
    { cat "$f"; printf '%s=%s\n' "$k" "$v"; } > "$tmp" && mv -f "$tmp" "$f"
  else
    printf '%s=%s\n' "$k" "$v" > "$tmp" && mv -f "$tmp" "$f"
  fi
}

# Pull a string field out of the hook's stdin JSON, if any.
read_stdin_field() {
  printf '%s' "$STDIN_JSON" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E "s/.*:[[:space:]]*\"//; s/\"\$//"
}
# Session id, tolerating each platform's naming (Claude/Codex/Gemini/Cursor: session_id; Windsurf: trajectory_id).
stdin_sid() {
  local v
  v="$(read_stdin_field session_id)";    [ -n "$v" ] && { printf '%s' "$v"; return; }
  v="$(read_stdin_field trajectory_id)"; [ -n "$v" ] && { printf '%s' "$v"; return; }
  read_stdin_field execution_id
}

# Cheap, path-derivable transcript dirs (Claude + Gemini). Codex needs a cwd scan (import only).
encode_cwd() { printf '%s' "$1" | sed -E 's/[^A-Za-z0-9]/-/g'; }
list_project_transcripts() {   # prints *.jsonl paths for this project (Claude + Gemini)
  local h; h="$(home_dir)"
  ls -1 "$h/.claude/projects/$(encode_cwd "$ROOT")"/*.jsonl 2>/dev/null
  local gh; gh="$(sha256_of "$ROOT")"
  [ -n "$gh" ] && ls -1 "$h/.gemini/tmp/$gh/chats"/*.jsonl 2>/dev/null
}

# ---------------------------------------------------------------------------
# drift / gap reporting (shared by catch-up + status)
# ---------------------------------------------------------------------------
drift_line() {
  local last_commit head n dirty
  last_commit="$(manifest_get lastCommit)"
  head="$(git_sha)"
  [ -z "$head" ] && return 0
  if [ -n "$last_commit" ] && [ "$last_commit" != "$head" ]; then
    n="$(git -C "$ROOT" rev-list --count "$last_commit..HEAD" 2>/dev/null || echo '?')"
    printf '%s commit(s) landed since the ledger was last saved. ' "$n"
  fi
  dirty="$(git -C "$ROOT" status --porcelain 2>/dev/null | head -1)"
  [ -n "$dirty" ] && printf 'Working tree has uncommitted changes. '
}

# Did a PRIOR session (any agent) end without a handoff? Excludes the current session's transcript.
gap_detected() {
  local handoff h_epoch f m newest=0 any=0
  handoff="$(manifest_get handoffAt)"
  h_epoch=0; [ -n "$handoff" ] && h_epoch="$(date -d "$handoff" +%s 2>/dev/null || echo 0)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "$f" = "$CUR_TRANSCRIPT" ] && continue
    any=1; m="$(file_mtime "$f")"; [ "$m" -gt "$newest" ] && newest="$m"
  done < <(list_project_transcripts)
  [ "$any" = "0" ] && return 1
  [ -z "$handoff" ] && return 0
  [ "$newest" -gt "$h_epoch" ] 2>/dev/null
}

# ---------------------------------------------------------------------------
# catch-up (unified JSON additionalContext for every platform's hook)
# ---------------------------------------------------------------------------
build_catchup_body() {
  echo "Continuum session context - give the user a 3-5 line catch-up from this before doing anything else."
  local drift gapf=""
  drift="$(drift_line)"; gap_detected && gapf=1
  if [ -n "$drift" ] || [ -n "$gapf" ]; then
    echo
    [ -n "$drift" ] && echo "VERIFY: $drift"
    [ -n "$gapf" ] && echo "GAP: a previous session may have ended without a handoff (usage-limit/crash)."
    echo "Before briefing: reconcile STATE.md against 'git log'/'git status'; if a prior session went unsaved, run 'continuum import --from auto' to reconstruct, then fold it in."
  fi
  echo
  echo "----- STATE.md -----"
  cat "$ROOT/.aicontext/STATE.md" 2>/dev/null || echo "(missing)"
  echo
  echo "----- JOURNAL.md (top entries) -----"
  awk 'BEGIN{c=0} /^## /{c++} c<=3{print} c>3{exit}' "$ROOT/.aicontext/JOURNAL.md" 2>/dev/null
  echo
  echo "----- TASKS.md: In progress -----"
  awk '/^## .*[Ii]n progress/{f=1;next} /^## /{f=0} f' "$ROOT/.aicontext/TASKS.md" 2>/dev/null
}

cmd_catch_up() {
  local event="SessionStart" once=0
  while [ $# -gt 0 ]; do case "$1" in --event) event="$2"; shift 2;; --once) once=1; shift;; *) shift;; esac; done
  local sid mf; sid="$(stdin_sid)"; [ -z "$sid" ] && sid="default"; mf="$(marker_file "$sid")"
  # per-turn hosts (Windsurf) call this every prompt: only emit the first time per session.
  if [ "$once" = "1" ] && [ -f "$mf" ] && [ "$(marker_get caughtup "$mf")" = "1" ]; then exit 0; fi
  # Compute all values first, then write the whole marker in ONE atomic operation (temp + rename).
  local _sc _ss _se tmp; _sc="$(git_sha)"; _ss="$(git_dirty_sum)"; _se="$(date +%s)"
  mkdir -p "$(dirname "$mf")"; tmp="$mf.tmp.$$"
  { printf 'startCommit=%s\nstartStatus=%s\nstartEpoch=%s\nnudged=0\nhandoff=0\ncaughtup=1\n' "$_sc" "$_ss" "$_se"; } > "$tmp" && mv -f "$tmp" "$mf"
  local body; body="$(build_catchup_body)"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$event" "$(printf '%s' "$body" | json_escape)"
}

cmd_precompact() {
  local event="PreCompact"; while [ $# -gt 0 ]; do case "$1" in --event) event="$2"; shift 2;; *) shift;; esac; done
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" \
    "Continuum: context is about to compact and detail will be lost. BEFORE continuing, run the handoff NOW - overwrite the live sections of .aicontext/STATE.md, append a precise 'Left off at' entry to .aicontext/JOURNAL.md, then run 'continuum save'. Do this first, then resume."
}

cmd_guard() {
  # Stop fires every turn — nudge at most ONCE per session, only when real work went unsaved.
  local active; active="$(printf '%s' "$STDIN_JSON" | grep -oE '"stop_hook_active"[[:space:]]*:[[:space:]]*true')"
  [ -n "$active" ] && exit 0
  local sid mf; sid="$(stdin_sid)"; [ -z "$sid" ] && sid="default"; mf="$(marker_file "$sid")"
  [ -f "$mf" ] || exit 0
  [ "$(marker_get handoff "$mf")" = "1" ] && exit 0
  [ "$(marker_get nudged  "$mf")" = "1" ] && exit 0
  local start_commit start_status start_epoch work=0
  start_commit="$(marker_get startCommit "$mf")"
  start_status="$(marker_get startStatus "$mf")"
  start_epoch="$(marker_get startEpoch "$mf")"; [ -z "$start_epoch" ] && start_epoch=0
  [ "$(git_sha)" != "$start_commit" ] && work=1
  [ "$(git_dirty_sum)" != "$start_status" ] && work=1
  [ "$work" = "0" ] && exit 0
  local state_mtime; state_mtime="$(file_mtime "$ROOT/.aicontext/STATE.md")"
  if [ "$state_mtime" -gt "$start_epoch" ] 2>/dev/null; then exit 0; fi
  marker_set nudged 1 "$mf"
  printf '{"decision":"block","reason":"%s"}\n' \
    "Continuum: you changed files this session but haven't saved a handoff. Take ~20 seconds now: update the live sections of .aicontext/STATE.md, append a 'Left off at' entry to .aicontext/JOURNAL.md, then run 'continuum save'. If there is genuinely nothing worth saving, say so and stop - this reminder won't repeat."
}

cmd_save() {
  local agent="claude-code"
  while [ $# -gt 0 ]; do case "$1" in --agent) agent="$2"; shift 2;; *) shift;; esac; done
  local f="$ROOT/.aicontext/manifest.json"
  [ -f "$f" ] || { echo "continuum: no manifest.json at $f" >&2; return 1; }
  local uh ui sha sid tmp
  uh="$(now_human)"; ui="$(now_iso)"; sha="$(git_sha)"
  sid="$(stdin_sid)"; [ -z "$sid" ] && sid="$(ls -1t "$(marker_dir)" 2>/dev/null | head -1 | sed 's/\.env$//')"
  tmp="$f.tmp.$$"
  if have jq; then
    jq --arg u "$uh" --arg h "$ui" --arg a "$agent" --arg c "$sha" --arg s "${sid:-}" '
      .continuum.lastUpdated=$u | .continuum.handoffAt=$h | .continuum.lastAgent=$a
      | .continuum.lastCommit=$c | .continuum.lastSessionId=$s
      | .continuum.sessionCount=((.continuum.sessionCount // 0)+1)
      | .continuum.agentsSeen=(((.continuum.agentsSeen // []) + [$a]) | unique)
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  elif has_py3; then
    CONT_U="$uh" CONT_H="$ui" CONT_A="$agent" CONT_C="$sha" CONT_S="${sid:-}" python3 - "$f" <<'PY'
import json,os,sys
p=sys.argv[1]
d=json.load(open(p,encoding="utf-8-sig"))          # tolerate a BOM (PS may have written one)
c=d.setdefault("continuum",{})
c["lastUpdated"]=os.environ["CONT_U"]; c["handoffAt"]=os.environ["CONT_H"]
c["lastAgent"]=os.environ["CONT_A"]; c["lastCommit"]=os.environ["CONT_C"]
c["lastSessionId"]=os.environ["CONT_S"]; c["sessionCount"]=int(c.get("sessionCount",0))+1
seen=c.get("agentsSeen") or []
if os.environ["CONT_A"] not in seen: seen.append(os.environ["CONT_A"])
c["agentsSeen"]=seen
tmp=p+".tmp."+str(os.getpid())                      # atomic write (no BOM)
with open(tmp,"w",encoding="utf-8") as fh: json.dump(d,fh,indent=2); fh.write("\n")
os.replace(tmp,p)
PY
  else
    sed -i.bak -E \
      -e "s|(\"lastUpdated\"[[:space:]]*:[[:space:]]*\")[^\"]*|\1$uh|" \
      -e "s|(\"handoffAt\"[[:space:]]*:[[:space:]]*)(\"[^\"]*\"\|null)|\1\"$ui\"|" \
      -e "s|(\"lastAgent\"[[:space:]]*:[[:space:]]*\")[^\"]*|\1$agent|" \
      -e "s|(\"lastCommit\"[[:space:]]*:[[:space:]]*)(\"[^\"]*\"\|null)|\1\"$sha\"|" \
      "$f" && rm -f "$f.bak"
    echo "continuum: jq/python3 not found — updated scalar fields only (sessionCount/agentsSeen unchanged)." >&2
  fi
  [ -n "${sid:-}" ] && marker_set handoff 1 "$(marker_file "$sid")"
  echo "continuum: handoff saved (agent=$agent, commit=${sha:0:7}, at $uh)."
  cmd_compact --quiet
}

cmd_compact() {
  local quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1
  local j="$ROOT/.aicontext/JOURNAL.md"; [ -f "$j" ] || return 0
  local keep=20 total
  total="$(grep -c '^## ' "$j" 2>/dev/null || echo 0)"
  find "$(marker_dir)" -name '*.env' -type f -mtime +7 -delete 2>/dev/null || true
  if [ "$total" -le "$keep" ]; then
    [ "$quiet" = "0" ] && echo "continuum: JOURNAL has $total entries (<= $keep) — no rotation needed."
    return 0
  fi
  local year archive; year="$(date +%Y)"; archive="$ROOT/.aicontext/archive"
  mkdir -p "$archive"
  awk -v keep="$keep" '
    /^## /{c++}
    { if (c==0 || c<=keep) print > KEEPF; else print > ARCHF }
  ' KEEPF="$j.keep" ARCHF="$j.arch" "$j"
  cat "$j.arch" >> "$archive/JOURNAL-$year.md" 2>/dev/null || cat "$j.arch" > "$archive/JOURNAL-$year.md"
  mv "$j.keep" "$j"; rm -f "$j.arch"
  [ "$quiet" = "0" ] && echo "continuum: rotated old JOURNAL entries into archive/JOURNAL-$year.md (kept newest $keep)."
}

# ---------------------------------------------------------------------------
# import — multi-source reconstruction (native transcript + universal git view)
# ---------------------------------------------------------------------------
git_recon() {
  local head last base=""
  head="$(git_sha)"
  if [ -z "$head" ]; then echo "## Git view: (not a git repository)"; return 0; fi
  last="$(manifest_get lastCommit)"
  echo "## Git view (works on every platform)"
  echo "- Branch: $(git_branch)"
  if [ -n "$last" ] && [ "$last" != "$head" ] && git -C "$ROOT" cat-file -e "$last^{commit}" 2>/dev/null; then
    base="$last"
  fi
  if [ -n "$base" ]; then
    echo "- Commits since last saved handoff:"
    git -C "$ROOT" log --oneline "$base..HEAD" 2>/dev/null | sed 's/^/    /'
    echo "- Files changed since then:"
    git -C "$ROOT" diff --name-status "$base..HEAD" 2>/dev/null | sed 's/^/    /'
  else
    echo "- Recent commits:"
    git -C "$ROOT" log --oneline -10 2>/dev/null | sed 's/^/    /'
    echo "- Files in the latest commit:"
    git -C "$ROOT" show --name-status --format= HEAD 2>/dev/null | sed 's/^/    /'
  fi
  echo "- Uncommitted right now:"
  git -C "$ROOT" status --short 2>/dev/null | sed 's/^/    /'
}

cmd_import() {
  local from="auto"; while [ $# -gt 0 ]; do case "$1" in --from) from="$2"; shift 2;; *) shift;; esac; done
  echo "# Continuum reconstruction (from=$from)"
  echo "# Review/trim, then fold the useful parts into JOURNAL.md + STATE.md. You write the final prose."
  echo
  if [ "$from" != "git" ]; then
    if has_py3; then
      CONT_FROM="$from" CONT_ROOT="$ROOT" CONT_HOME="$(home_dir)" python3 - <<'PY'
import os,sys,glob,json,hashlib,re
frm=os.environ.get("CONT_FROM","auto"); root=os.environ["CONT_ROOT"]; home=os.environ["CONT_HOME"]
rootr=os.path.realpath(root)
def enc(p): return re.sub(r'[^A-Za-z0-9]','-',p)
def newest(fs): return max(fs,key=os.path.getmtime) if fs else None
def claude_file(): return newest(glob.glob(os.path.join(home,".claude","projects",enc(root),"*.jsonl")))
def gemini_file():
    h=hashlib.sha256(root.encode()).hexdigest()
    return newest(glob.glob(os.path.join(home,".gemini","tmp",h,"chats","*.jsonl")))
def deep_cwd(o):
    if isinstance(o,dict):
        v=o.get("cwd")
        if isinstance(v,str): return v
        for x in o.values():
            r=deep_cwd(x)
            if r: return r
    elif isinstance(o,list):
        for x in o:
            r=deep_cwd(x)
            if r: return r
    return None
def codex_file():
    best=None;bestm=-1
    for f in glob.glob(os.path.join(home,".codex","sessions","**","rollout-*.jsonl"),recursive=True):
        try:
            cwd=None
            with open(f,encoding="utf-8",errors="replace") as fh:
                for i,line in enumerate(fh):
                    if i>12: break
                    line=line.strip()
                    if not line: continue
                    try: e=json.loads(line)
                    except: continue
                    cwd=deep_cwd(e)
                    if cwd: break
            if cwd and os.path.realpath(cwd)==rootr:
                m=os.path.getmtime(f)
                if m>bestm: bestm=m; best=f
        except Exception: pass
    return best
cands={}
if frm in ("auto","claude"):
    f=claude_file();
    if f: cands["claude"]=f
if frm in ("auto","codex"):
    f=codex_file();
    if f: cands["codex"]=f
if frm in ("auto","gemini"):
    f=gemini_file();
    if f: cands["gemini"]=f
if not cands:
    print("(no %s transcript found for this project — relying on the git view below)\n" % (frm if frm!="auto" else "agent"))
    sys.exit(0)
if frm=="auto":
    src=max(cands, key=lambda k: os.path.getmtime(cands[k])); path=cands[src]
else:
    src=frm; path=cands[src]
# generic, format-tolerant extractor (works across Claude/Codex/Gemini schemas)
prompts=[]; files=set(); branch=""; first=None; last=None
FILEK={"file_path","notebook_path"}
def text_of(c):
    if isinstance(c,str): return c
    if isinstance(c,dict): return c.get("text") or text_of(c.get("content")) or text_of(c.get("parts"))
    if isinstance(c,list): return " ".join(t for t in (text_of(i) for i in c) if t)
    return None
def rec(o):
    global branch,first,last
    if isinstance(o,dict):
        b=o.get("gitBranch")
        if isinstance(b,str) and b: branch=b
        ts=o.get("timestamp") or o.get("time")
        if isinstance(ts,str):
            if not first: first=ts
            last=ts
        for k,v in o.items():
            if k in FILEK and isinstance(v,str) and (("/" in v) or ("\\" in v)): files.add(v)
        role=o.get("role") or o.get("type")
        if role in ("user","UserMessage","human"):
            t=text_of(o.get("content") if o.get("content") is not None else (o.get("text") or o.get("message")))
            if t:
                t=" ".join(t.split())
                if t and not t.startswith("<") and t not in prompts: prompts.append(t)
        for v in o.values(): rec(v)
    elif isinstance(o,list):
        for v in o: rec(v)
for line in open(path,encoding="utf-8",errors="replace"):
    line=line.strip()
    if not line: continue
    try: e=json.loads(line)
    except: continue
    rec(e)
print("## Transcript view — source: %s (%s)" % (src, os.path.basename(path)))
print("Branch: %s    Span: %s -> %s" % (branch or "n/a", first or "?", last or "?"))
print("\nUser asked (in order):")
for p in prompts[:12]: print("  -", p[:160])
if len(prompts)>12: print("  - ...and %d more" % (len(prompts)-12))
print("\nFiles touched:")
if files:
    for f in sorted(files): print("  -", f)
else:
    print("  - (none detected)")
print()
PY
    else
      echo "(python3 not available — skipping native transcript parse; git view below still works)"
      echo
    fi
  fi
  git_recon
  echo
  echo "**Left off at:** <infer from the views above>"
}

cmd_status() {
  [ -n "${ROOT:-}" ] || { echo "No .aicontext/ found from $PWD."; return 1; }
  echo "Continuum status — $ROOT/.aicontext"
  echo "  last saved : $(manifest_get lastUpdated || echo '(never)') by $(manifest_get lastAgent || echo '?')"
  echo "  sessions   : $(manifest_get sessionCount || echo 0)"
  echo "  branch     : $(git_branch || echo n/a)"
  local d; d="$(drift_line)"; echo "  drift      : ${d:-none (ledger matches HEAD)}"
  if gap_detected; then echo "  gap        : a prior session may have gone unsaved — run 'continuum import --from auto'"; else echo "  gap        : none"; fi
}

cmd_doctor() {
  local ok=1 h; h="$(home_dir)"
  echo "Continuum doctor"
  if [ -z "${ROOT:-}" ]; then echo "  x no .aicontext/ ledger found from $PWD"; return 1; fi
  echo "  ledger: $ROOT/.aicontext"
  for f in STATE.md TASKS.md DECISIONS.md JOURNAL.md manifest.json PROTOCOL.md; do
    if [ -f "$ROOT/.aicontext/$f" ]; then echo "  ok $f"; else echo "  x  $f MISSING"; ok=0; fi
  done
  if have jq; then jq empty "$ROOT/.aicontext/manifest.json" 2>/dev/null && echo "  ok manifest.json parses" || { echo "  x  manifest.json invalid JSON"; ok=0; }; fi
  echo "  hooks wired in:"
  local any=0
  for s in \
    "$ROOT/.claude/settings.local.json" "$h/.claude/settings.json" \
    "$h/.codex/hooks.json" "$h/.gemini/settings.json" \
    "$h/.cursor/hooks.json" "$h/.codeium/windsurf/hooks.json"; do
    [ -f "$s" ] || continue
    if grep -q 'continuum' "$s" 2>/dev/null; then echo "    - ${s/#$h/~}"; any=1; fi
  done
  [ "$any" = "0" ] && echo "    (none found — run the installer; the honor-protocol still works via AGENTS.md)"
  [ "$ok" = "1" ] && echo "  -> healthy" || echo "  -> problems found (see above); re-run the Continuum installer to repair."
}

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
CMD="${1:-help}"; shift || true

# Only the hook commands receive JSON on stdin. Reading stdin for manual commands
# (save/import/status/…) would BLOCK on a non-tty pipe that never closes. Guard with a timeout.
STDIN_JSON=""
case "$CMD" in
  catch-up|precompact|guard)
    if [ ! -t 0 ]; then
      if have timeout; then STDIN_JSON="$(timeout 2 cat 2>/dev/null || true)"
      else STDIN_JSON="$(cat 2>/dev/null || true)"; fi
    fi ;;
esac
CUR_TRANSCRIPT="$(read_stdin_field transcript_path 2>/dev/null || true)"
if ! ROOT="$(find_root)"; then
  case "$CMD" in catch-up|precompact|guard) exit 0;; esac   # never break a session
  ROOT=""
fi

case "$CMD" in
  # Hook commands are FAIL-SAFE: any internal failure must never break the host agent —
  # swallow errors and always exit 0 (emitting valid JSON or nothing, never half-output).
  catch-up)   cmd_catch_up "$@" 2>/dev/null || true; exit 0 ;;
  precompact) cmd_precompact "$@" 2>/dev/null || true; exit 0 ;;
  guard)      cmd_guard 2>/dev/null || true; exit 0 ;;
  save)       cmd_save "$@" ;;
  compact)    cmd_compact "$@" ;;
  import)     cmd_import "$@" ;;
  status)     cmd_status ;;
  doctor)     cmd_doctor ;;
  help|-h|--help) usage ;;
  *) echo "continuum: unknown command '$CMD' (try: catch-up precompact guard import save compact status doctor)" >&2; exit 2 ;;
esac
