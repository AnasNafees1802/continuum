<#
  Continuum helper CLI (Windows / PowerShell) - deterministic bookkeeping for the
  .aicontext/ ledger, shared across AI agents. The model writes the prose; this
  script does the mechanics. Backs the hooks of Claude Code, Codex, Gemini,
  Cursor and Windsurf (shared JSON-on-stdin hook contract).

  Commands:
    catch-up [--event NAME] [--once]   session-start hook: emit ledger as JSON additionalContext
    precompact [--event NAME]          compaction hook: tell the model to hand off NOW
    guard                              stop hook: one gentle "you didn't save" nudge per session
    import [--from auto|git|claude|codex|gemini]   reconstruct a missed handoff (+ always a git view)
    save [--agent NAME]                stamp manifest.json at end of a handoff
    compact                            rotate old JOURNAL entries into .aicontext/archive/
    status | doctor                    health + cross-agent drift/gap report

  Uses only built-in PowerShell (ConvertFrom/To-Json, Get-Date, git) - no dependencies. ASCII-only for PS 5.1.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string] $Command = 'help',
  [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Rest
)
$ErrorActionPreference = 'SilentlyContinue'

# --- arg helpers -----------------------------------------------------------
function Arg-Val($name, $default) { for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq $name -and $i + 1 -lt $Rest.Count) { return $Rest[$i + 1] } }; return $default }
function Arg-Has($name) { return ($Rest -contains $name) }

# --- helpers ---------------------------------------------------------------
function Find-Root {
  $d = (Get-Location).Path
  while ($d) {
    if (Test-Path (Join-Path $d '.aicontext')) { return $d }
    $parent = Split-Path $d -Parent
    if ($parent -eq $d -or -not $parent) { break }
    $d = $parent
  }
  return $null
}
function Now-Human { Get-Date -Format 'yyyy-MM-dd HH:mm' }
function Now-Iso { Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz' }
function Now-Epoch { [int64]([datetimeoffset]::UtcNow).ToUnixTimeSeconds() }
function Git-Sha { param($r) (& git -C $r rev-parse HEAD 2>$null) }
function Git-Branch { param($r) (& git -C $r rev-parse --abbrev-ref HEAD 2>$null) }
function Stable-Hash { param([string]$s) if (-not $s) { return '0' }; $md5 = [System.Security.Cryptography.MD5]::Create(); ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) -join '' }
function Sha256-Hex { param([string]$s) $h = [System.Security.Cryptography.SHA256]::Create(); ($h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) -join '' }
function Git-DirtySum { param($r) Stable-Hash ((& git -C $r status --porcelain 2>$null | Out-String)) }
function File-MtimeEpoch { param($p) if (-not (Test-Path $p)) { return 0 }; [int64]([datetimeoffset]((Get-Item $p).LastWriteTimeUtc)).ToUnixTimeSeconds() }
function Encode-Cwd { param($p) ($p -replace '[^A-Za-z0-9]', '-') }

function Read-Manifest { param($r) $f = Join-Path $r '.aicontext\manifest.json'; if (Test-Path $f) { Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json } }
function Manifest-Get { param($r, $key) $m = Read-Manifest $r; if ($m -and $m.continuum -and ($m.continuum.PSObject.Properties.Name -contains $key)) { return $m.continuum.$key }; return $null }
function Set-Prop { param($obj, $name, $value) if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value } }

# session marker (key=value text; matches the bash version)
function Marker-Dir { param($r) Join-Path $r '.aicontext\.session' }
function Marker-File { param($r, $sid) if (-not $sid) { $sid = 'default' }; Join-Path (Marker-Dir $r) ($sid + '.env') }
function Marker-Get { param($file, $key) if (-not (Test-Path $file)) { return $null }; foreach ($line in Get-Content $file) { if ($line -match "^$key=(.*)$") { return $Matches[1] } }; return $null }
# Atomic write: build content fully, write a temp file, then rename over the target.
# A truncated/empty file can never appear even if the process is killed mid-run.
function Write-Lines-Atomic {
  param($file, $lines)
  $dir = Split-Path $file -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = "$file.tmp.$PID"
  Set-Content -Path $tmp -Value $lines -Encoding ascii
  Move-Item -Path $tmp -Destination $file -Force
}
# Atomic UTF-8 write WITHOUT BOM. PS 5.1's Set-Content -Encoding utf8 adds a BOM, which breaks
# Python/jq readers — a cross-tool hazard for JSON the other agents must parse.
function Write-Text-Atomic {
  param($file, $text)
  $dir = Split-Path $file -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $tmp = "$file.tmp.$PID"
  [System.IO.File]::WriteAllText($tmp, $text, $enc)
  Move-Item -Path $tmp -Destination $file -Force
}
function Marker-Set {
  param($file, $key, $value)
  $lines = @(); $found = $false
  if (Test-Path $file) { $lines = @(foreach ($line in Get-Content $file) { if ($line -match "^$key=") { $found = $true; "$key=$value" } else { $line } }) }
  if (-not $found) { $lines += "$key=$value" }
  Write-Lines-Atomic $file $lines
}

# stdin (hook JSON)
$StdinObj = $null
if ([Console]::IsInputRedirected -and $Command -in @('catch-up', 'precompact', 'guard')) {
  $raw = [Console]::In.ReadToEnd()
  if ($raw) { try { $StdinObj = $raw | ConvertFrom-Json } catch {} }
}
function Stdin-Sid {
  if ($StdinObj) { foreach ($k in 'session_id', 'trajectory_id', 'execution_id') { if ($StdinObj.$k) { return $StdinObj.$k } } }
  return $null
}
function Stdin-Transcript { if ($StdinObj -and $StdinObj.transcript_path) { return $StdinObj.transcript_path } return $null }

# --- transcript discovery --------------------------------------------------
function Claude-File { param($r) $d = Join-Path $env:USERPROFILE (".claude\projects\" + (Encode-Cwd $r)); if (Test-Path $d) { Get-ChildItem $d -Filter *.jsonl -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName } }
function Gemini-File { param($r) $d = Join-Path $env:USERPROFILE (".gemini\tmp\" + (Sha256-Hex $r) + "\chats"); if (Test-Path $d) { Get-ChildItem $d -Filter *.jsonl -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName } }
function Deep-Cwd {
  param($o)
  if ($o -is [System.Management.Automation.PSCustomObject]) {
    if ($o.cwd -is [string]) { return $o.cwd }
    foreach ($p in $o.PSObject.Properties) { $r = Deep-Cwd $p.Value; if ($r) { return $r } }
  }
  elseif ($o -is [object[]]) { foreach ($x in $o) { $r = Deep-Cwd $x; if ($r) { return $r } } }
  return $null
}
function Codex-File {
  param($r)
  $base = Join-Path $env:USERPROFILE '.codex\sessions'
  if (-not (Test-Path $base)) { return $null }
  $rootFull = try { (Resolve-Path $r).Path } catch { $r }
  $best = $null; $bestm = [datetime]::MinValue
  foreach ($f in (Get-ChildItem $base -Recurse -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue)) {
    $cwd = $null; $i = 0
    foreach ($line in (Get-Content $f.FullName -Encoding UTF8)) {
      if ($i -ge 12) { break }; $i++
      $line = $line.Trim(); if (-not $line) { continue }
      try { $e = $line | ConvertFrom-Json } catch { continue }
      $cwd = Deep-Cwd $e; if ($cwd) { break }
    }
    if ($cwd) {
      $cwdFull = try { (Resolve-Path $cwd).Path } catch { $cwd }
      if ($cwdFull -eq $rootFull -and $f.LastWriteTime -gt $bestm) { $bestm = $f.LastWriteTime; $best = $f.FullName }
    }
  }
  return $best
}
function List-ProjectTranscripts {
  param($r)
  $out = @()
  $c = Join-Path $env:USERPROFILE (".claude\projects\" + (Encode-Cwd $r))
  if (Test-Path $c) { $out += (Get-ChildItem $c -Filter *.jsonl -File | ForEach-Object { $_.FullName }) }
  $g = Join-Path $env:USERPROFILE (".gemini\tmp\" + (Sha256-Hex $r) + "\chats")
  if (Test-Path $g) { $out += (Get-ChildItem $g -Filter *.jsonl -File | ForEach-Object { $_.FullName }) }
  return $out
}

# --- drift / gap -----------------------------------------------------------
function Drift-Line {
  param($r)
  $head = Git-Sha $r; if (-not $head) { return '' }
  $out = ''
  $last = Manifest-Get $r 'lastCommit'
  if ($last -and $last -ne $head) { $n = (& git -C $r rev-list --count "$last..HEAD" 2>$null); if (-not $n) { $n = '?' }; $out += "$n commit(s) landed since the ledger was last saved. " }
  $dirty = (& git -C $r status --porcelain 2>$null | Select-Object -First 1)
  if ($dirty) { $out += 'Working tree has uncommitted changes. ' }
  return $out
}
function Gap-Detected {
  param($r)
  $handoff = Manifest-Get $r 'handoffAt'
  $hEpoch = 0
  if ($handoff) { try { $hEpoch = [int64]([datetimeoffset]::Parse($handoff)).ToUnixTimeSeconds() } catch { $hEpoch = 0 } }
  $any = $false; $newest = 0
  foreach ($f in (List-ProjectTranscripts $r)) {
    if ($f -eq $script:CurTranscript) { continue }
    $any = $true; $m = File-MtimeEpoch $f; if ($m -gt $newest) { $newest = $m }
  }
  if (-not $any) { return $false }
  if (-not $handoff) { return $true }
  return ($newest -gt $hEpoch)
}

# --- catch-up (unified JSON additionalContext) -----------------------------
function Build-CatchupBody {
  param($r)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('Continuum session context - give the user a 3-5 line catch-up from this before doing anything else.')
  $drift = Drift-Line $r; $gap = Gap-Detected $r
  if ($drift -or $gap) {
    [void]$sb.AppendLine('')
    if ($drift) { [void]$sb.AppendLine("VERIFY: $drift") }
    if ($gap) { [void]$sb.AppendLine('GAP: a previous session may have ended without a handoff (usage-limit/crash).') }
    [void]$sb.AppendLine("Before briefing: reconcile STATE.md against 'git log'/'git status'; if a prior session went unsaved, run 'continuum import --from auto' to reconstruct, then fold it in.")
  }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('----- STATE.md -----')
  $st = Get-Content (Join-Path $r '.aicontext\STATE.md') -Raw -Encoding UTF8; if (-not $st) { $st = '(missing)' }
  [void]$sb.AppendLine($st.TrimEnd())
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('----- JOURNAL.md (top entries) -----')
  $jc = 0
  foreach ($line in (Get-Content (Join-Path $r '.aicontext\JOURNAL.md') -Encoding UTF8)) { if ($line -match '^## ') { $jc++ }; if ($jc -le 3) { [void]$sb.AppendLine($line) } else { break } }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('----- TASKS.md: In progress -----')
  $f = $false
  foreach ($line in (Get-Content (Join-Path $r '.aicontext\TASKS.md') -Encoding UTF8)) { if ($line -match '^##\s+.*[Ii]n progress') { $f = $true; continue }; if ($line -match '^## ') { $f = $false }; if ($f) { [void]$sb.AppendLine($line) } }
  return $sb.ToString()
}
function Emit-AdditionalContext { param($event, $text) (@{ hookSpecificOutput = @{ hookEventName = $event; additionalContext = $text } } | ConvertTo-Json -Compress -Depth 6) }

function Cmd-CatchUp {
  param($r)
  $event = Arg-Val '--event' 'SessionStart'; $once = Arg-Has '--once'
  $sid = Stdin-Sid; if (-not $sid) { $sid = 'default' }
  $mf = Marker-File $r $sid
  if ($once -and (Test-Path $mf) -and ((Marker-Get $mf 'caughtup') -eq '1')) { exit 0 }
  # Compute all values first, then write the whole marker in ONE atomic operation.
  $sc = Git-Sha $r; $ss = Git-DirtySum $r; $se = Now-Epoch
  Write-Lines-Atomic $mf @("startCommit=$sc", "startStatus=$ss", "startEpoch=$se", "nudged=0", "handoff=0", "caughtup=1")
  Write-Output (Emit-AdditionalContext $event (Build-CatchupBody $r))
}

function Cmd-PreCompact {
  $event = Arg-Val '--event' 'PreCompact'
  $msg = "Continuum: context is about to compact and detail will be lost. BEFORE continuing, run the handoff NOW - overwrite the live sections of .aicontext/STATE.md, append a precise 'Left off at' entry to .aicontext/JOURNAL.md, then run 'continuum save'. Do this first, then resume."
  Write-Output (Emit-AdditionalContext $event $msg)
}

function Cmd-Guard {
  param($r)
  if ($StdinObj -and $StdinObj.stop_hook_active -eq $true) { exit 0 }
  $sid = Stdin-Sid; if (-not $sid) { $sid = 'default' }
  $mf = Marker-File $r $sid
  if (-not (Test-Path $mf)) { exit 0 }
  if ((Marker-Get $mf 'handoff') -eq '1') { exit 0 }
  if ((Marker-Get $mf 'nudged') -eq '1') { exit 0 }
  $startCommit = Marker-Get $mf 'startCommit'; $startStatus = Marker-Get $mf 'startStatus'
  $startEpoch = [int64](Marker-Get $mf 'startEpoch'); if (-not $startEpoch) { $startEpoch = 0 }
  $work = $false
  if ((Git-Sha $r) -ne $startCommit) { $work = $true }
  if ((Git-DirtySum $r) -ne $startStatus) { $work = $true }
  if (-not $work) { exit 0 }
  if ((File-MtimeEpoch (Join-Path $r '.aicontext\STATE.md')) -gt $startEpoch) { exit 0 }
  Marker-Set $mf 'nudged' '1'
  $reason = "Continuum: you changed files this session but haven't saved a handoff. Take ~20 seconds now: update the live sections of .aicontext/STATE.md, append a 'Left off at' entry to .aicontext/JOURNAL.md, then run 'continuum save'. If there is genuinely nothing worth saving, say so and stop - this reminder won't repeat."
  Write-Output (@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress)
}

function Cmd-Save {
  param($r)
  $agent = Arg-Val '--agent' 'claude-code'
  $f = Join-Path $r '.aicontext\manifest.json'
  if (-not (Test-Path $f)) { Write-Error "continuum: no manifest.json at $f"; return }
  $m = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $m.continuum) { Set-Prop $m 'continuum' ([pscustomobject]@{}) }
  $c = $m.continuum
  $sid = Stdin-Sid
  Set-Prop $c 'lastUpdated' (Now-Human)
  Set-Prop $c 'handoffAt' (Now-Iso)
  Set-Prop $c 'lastAgent' $agent
  Set-Prop $c 'lastCommit' (Git-Sha $r)
  Set-Prop $c 'lastSessionId' ($(if ($sid) { $sid } else { '' }))
  $count = 0; if ($c.PSObject.Properties.Name -contains 'sessionCount') { $count = [int]$c.sessionCount }
  Set-Prop $c 'sessionCount' ($count + 1)
  $seen = @(); if ($c.PSObject.Properties.Name -contains 'agentsSeen' -and $c.agentsSeen) { $seen = @($c.agentsSeen) }
  if ($seen -notcontains $agent) { $seen += $agent }
  Set-Prop $c 'agentsSeen' $seen
  Write-Text-Atomic $f ($m | ConvertTo-Json -Depth 12)
  if ($sid) { Marker-Set (Marker-File $r $sid) 'handoff' '1' }
  $sha = Git-Sha $r; $short = if ($sha) { $sha.Substring(0, [Math]::Min(7, $sha.Length)) } else { '' }
  Write-Output "continuum: handoff saved (agent=$agent, commit=$short, at $(Now-Human))."
  Cmd-Compact $r $true
}

function Cmd-Compact {
  param($r, $quiet = $false)
  $j = Join-Path $r '.aicontext\JOURNAL.md'
  if (-not (Test-Path $j)) { return }
  $keep = 20
  $md = Marker-Dir $r
  if (Test-Path $md) { Get-ChildItem $md -Filter *.env -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue }
  $lines = Get-Content $j
  $headerIdx = @(); for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## ') { $headerIdx += $i } }
  if ($headerIdx.Count -le $keep) { if (-not $quiet) { Write-Output "continuum: JOURNAL has $($headerIdx.Count) entries (<= $keep) - no rotation needed." }; return }
  $cut = $headerIdx[$keep]
  $keepLines = $lines[0..($cut - 1)]; $archLines = $lines[$cut..($lines.Count - 1)]
  $archive = Join-Path $r '.aicontext\archive'
  if (-not (Test-Path $archive)) { New-Item -ItemType Directory -Force -Path $archive | Out-Null }
  $af = Join-Path $archive ("JOURNAL-" + (Get-Date -Format yyyy) + ".md")
  $enc = New-Object System.Text.UTF8Encoding($false)
  $prev = if (Test-Path $af) { [System.IO.File]::ReadAllText($af, $enc) } else { '' }
  [System.IO.File]::WriteAllText($af, ($prev + ($archLines -join "`n") + "`n"), $enc)
  Write-Text-Atomic $j (($keepLines -join "`n") + "`n")
  if (-not $quiet) { Write-Output "continuum: rotated old JOURNAL entries into archive/JOURNAL-$(Get-Date -Format yyyy).md (kept newest $keep)." }
}

# --- import (multi-source) -------------------------------------------------
function Git-Recon {
  param($r)
  $head = Git-Sha $r
  if (-not $head) { Write-Output '## Git view: (not a git repository)'; return }
  $last = Manifest-Get $r 'lastCommit'
  Write-Output '## Git view (works on every platform)'
  Write-Output ("- Branch: " + (Git-Branch $r))
  $base = $null
  if ($last -and $last -ne $head) { & git -C $r cat-file -e "$last^{commit}" 2>$null; if ($LASTEXITCODE -eq 0) { $base = $last } }
  if ($base) {
    Write-Output '- Commits since last saved handoff:'
    (& git -C $r log --oneline "$base..HEAD" 2>$null) | ForEach-Object { "    $_" }
    Write-Output '- Files changed since then:'
    (& git -C $r diff --name-status "$base..HEAD" 2>$null) | ForEach-Object { "    $_" }
  }
  else {
    Write-Output '- Recent commits:'
    (& git -C $r log --oneline -10 2>$null) | ForEach-Object { "    $_" }
    Write-Output '- Files in the latest commit:'
    (& git -C $r show --name-status --format= HEAD 2>$null) | ForEach-Object { "    $_" }
  }
  Write-Output '- Uncommitted right now:'
  (& git -C $r status --short 2>$null) | ForEach-Object { "    $_" }
}

$script:prompts = New-Object System.Collections.Generic.List[string]
$script:files = New-Object System.Collections.Generic.HashSet[string]
$script:branch = ''; $script:tfirst = $null; $script:tlast = $null
function Text-Of {
  param($c)
  if ($c -is [string]) { return $c }
  if ($c -is [System.Management.Automation.PSCustomObject]) { if ($c.text) { return $c.text }; if ($c.content) { return (Text-Of $c.content) }; if ($c.parts) { return (Text-Of $c.parts) } }
  if ($c -is [object[]]) { return (($c | ForEach-Object { Text-Of $_ }) -join ' ') }
  return $null
}
function Walk-Node {
  param($o)
  if ($o -is [string]) { return }
  if ($o -is [System.Management.Automation.PSCustomObject]) {
    foreach ($p in $o.PSObject.Properties) {
      $k = $p.Name; $v = $p.Value
      if ($k -eq 'gitBranch' -and $v -is [string] -and $v) { $script:branch = $v }
      if (($k -eq 'timestamp' -or $k -eq 'time') -and $v -is [string]) { if (-not $script:tfirst) { $script:tfirst = $v }; $script:tlast = $v }
      if (($k -eq 'file_path' -or $k -eq 'notebook_path') -and $v -is [string] -and ($v -match '[\\/]')) { [void]$script:files.Add($v) }
    }
    $role = $o.role; if (-not $role) { $role = $o.type }
    if ($role -in @('user', 'UserMessage', 'human')) {
      $src = $o.content; if ($null -eq $src) { $src = $o.text }; if ($null -eq $src) { $src = $o.message }
      $t = Text-Of $src
      if ($t) { $t = ($t -replace '\s+', ' ').Trim(); if ($t -and -not $t.StartsWith('<') -and -not $script:prompts.Contains($t)) { $script:prompts.Add($t) } }
    }
    foreach ($p in $o.PSObject.Properties) { Walk-Node $p.Value }
  }
  elseif ($o -is [object[]]) { foreach ($x in $o) { Walk-Node $x } }
}
function Cmd-Import {
  param($r)
  $from = Arg-Val '--from' 'auto'
  Write-Output "# Continuum reconstruction (from=$from)"
  Write-Output '# Review/trim, then fold the useful parts into JOURNAL.md + STATE.md. You write the final prose.'
  Write-Output ''
  if ($from -ne 'git') {
    $cands = @{}
    if ($from -in @('auto', 'claude')) { $f = Claude-File $r; if ($f) { $cands['claude'] = $f } }
    if ($from -in @('auto', 'codex')) { $f = Codex-File $r; if ($f) { $cands['codex'] = $f } }
    if ($from -in @('auto', 'gemini')) { $f = Gemini-File $r; if ($f) { $cands['gemini'] = $f } }
    if ($cands.Count -eq 0) {
      Write-Output "(no transcript found for this project - relying on the git view below)"
      Write-Output ''
    }
    else {
      $src = if ($from -eq 'auto') { ($cands.GetEnumerator() | Sort-Object { (Get-Item $_.Value).LastWriteTime } -Descending | Select-Object -First 1).Key } else { $from }
      $path = $cands[$src]
      foreach ($line in (Get-Content $path -Encoding UTF8)) { $line = $line.Trim(); if (-not $line) { continue }; try { $e = $line | ConvertFrom-Json } catch { continue }; Walk-Node $e }
      Write-Output ("## Transcript view - source: $src (" + (Split-Path $path -Leaf) + ")")
      $b = if ($script:branch) { $script:branch } else { 'n/a' }
      $ff = if ($script:tfirst) { $script:tfirst } else { '?' }; $ll = if ($script:tlast) { $script:tlast } else { '?' }
      Write-Output "Branch: $b    Span: $ff -> $ll"
      Write-Output ''
      Write-Output 'User asked (in order):'
      $n = 0; foreach ($p in $script:prompts) { if ($n -ge 12) { break }; $one = $p; if ($one.Length -gt 160) { $one = $one.Substring(0, 160) }; Write-Output "  - $one"; $n++ }
      if ($script:prompts.Count -gt 12) { Write-Output "  - ...and $($script:prompts.Count - 12) more" }
      Write-Output ''
      Write-Output 'Files touched:'
      if ($script:files.Count -eq 0) { Write-Output '  - (none detected)' } else { foreach ($fp in ($script:files | Sort-Object)) { Write-Output "  - $fp" } }
      Write-Output ''
    }
  }
  Git-Recon $r
  Write-Output ''
  Write-Output '**Left off at:** <infer from the views above>'
}

function Cmd-Status {
  param($r)
  $v = Manifest-Get $r 'lastUpdated'; if (-not $v) { $v = '(never)' }
  $a = Manifest-Get $r 'lastAgent'; if (-not $a) { $a = '?' }
  $sc = Manifest-Get $r 'sessionCount'; if (-not $sc) { $sc = 0 }
  $b = Git-Branch $r; if (-not $b) { $b = 'n/a' }
  $d = Drift-Line $r; if (-not $d) { $d = 'none (ledger matches HEAD)' }
  Write-Output "Continuum status - $r\.aicontext"
  Write-Output "  last saved : $v by $a"
  Write-Output "  sessions   : $sc"
  Write-Output "  branch     : $b"
  Write-Output "  drift      : $d"
  if (Gap-Detected $r) { Write-Output "  gap        : a prior session may have gone unsaved - run 'continuum import --from auto'" } else { Write-Output '  gap        : none' }
}

function Cmd-Doctor {
  param($r)
  $ok = $true
  Write-Output 'Continuum doctor'
  Write-Output "  ledger: $r\.aicontext"
  foreach ($f in 'STATE.md', 'TASKS.md', 'DECISIONS.md', 'JOURNAL.md', 'manifest.json', 'PROTOCOL.md') { if (Test-Path (Join-Path $r ".aicontext\$f")) { Write-Output "  ok $f" } else { Write-Output "  X  $f MISSING"; $ok = $false } }
  try { Get-Content (Join-Path $r '.aicontext\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; Write-Output '  ok manifest.json parses' } catch { Write-Output '  X  manifest.json invalid JSON'; $ok = $false }
  Write-Output '  hooks wired in:'
  $any = $false
  $u = $env:USERPROFILE
  $paths = @((Join-Path $r '.claude\settings.local.json'), (Join-Path $u '.claude\settings.json'), (Join-Path $u '.codex\hooks.json'), (Join-Path $u '.gemini\settings.json'), (Join-Path $u '.cursor\hooks.json'), (Join-Path $u '.codeium\windsurf\hooks.json'))
  foreach ($s in $paths) { if ((Test-Path $s) -and (Select-String -Path $s -Pattern 'continuum' -Quiet)) { Write-Output "    - $s"; $any = $true } }
  if (-not $any) { Write-Output '    (none found - run the installer; the honor-protocol still works via AGENTS.md)' }
  if ($ok) { Write-Output '  -> healthy' } else { Write-Output '  -> problems found (see above); re-run the Continuum installer to repair.' }
}

function Usage { Write-Output 'Continuum helper - commands: catch-up precompact guard import save compact status doctor' }

# --- dispatch --------------------------------------------------------------
$script:CurTranscript = Stdin-Transcript
$ROOT = Find-Root
if (-not $ROOT) {
  if ($Command -in @('catch-up', 'precompact', 'guard')) { exit 0 }
  Write-Output 'continuum: no .aicontext/ ledger found from this directory.'
  exit 1
}
switch ($Command) {
  'catch-up' { Cmd-CatchUp $ROOT }
  'precompact' { Cmd-PreCompact }
  'guard' { Cmd-Guard $ROOT }
  'save' { Cmd-Save $ROOT }
  'compact' { Cmd-Compact $ROOT $false }
  'import' { Cmd-Import $ROOT }
  'status' { Cmd-Status $ROOT }
  'doctor' { Cmd-Doctor $ROOT }
  default { Usage }
}
exit 0
