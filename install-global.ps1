#requires -Version 5
<#
.SYNOPSIS
  Install Continuum ONCE into every AI coding agent on this machine (global / user-level).
.DESCRIPTION
  Injects the Continuum protocol into each agent's GLOBAL instruction file AND wires deterministic
  hooks (session-start catch-up, pre-compaction handoff, stop-nudge) into every agent that supports
  them: Claude Code, Codex, Gemini CLI, Cursor, Windsurf. A shared helper CLI is installed once to
  ~/.continuum/bin and every agent's hook points at it. Idempotent.
.PARAMETER All
  Install for every known agent, even ones not detected (creates their config dirs).
#>
[CmdletBinding()]
param([switch]$All)

$ErrorActionPreference = 'Stop'
$Src = $PSScriptRoot
# $HOME is read-only in PS; CONTINUUM_HOME lets you target/test a different home root.
$Home_ = if ($env:CONTINUUM_HOME) { $env:CONTINUUM_HOME } else { $HOME }

$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Text($p) { [System.IO.File]::ReadAllText($p) }
function Write-Text($p, $c) { [System.IO.File]::WriteAllText($p, $c, $Utf8) }
function Append-Text($p, $c) { [System.IO.File]::AppendAllText($p, $c, $Utf8) }
function Ensure-Dir($p) { $d = Split-Path -Parent $p; if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }

function Set-ManagedBlock($file, $snippet) {
    Ensure-Dir $file
    $existing = if (Test-Path -LiteralPath $file) { Read-Text $file } else { '' }
    if ($existing -match '(?s)<!-- CONTINUUM:BEGIN.*?CONTINUUM:END -->') {
        $updated = [regex]::Replace($existing, '(?s)<!-- CONTINUUM:BEGIN.*?CONTINUUM:END -->', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $snippet.TrimEnd() })
        Write-Text $file $updated; return 'updated'
    }
    elseif ([string]::IsNullOrWhiteSpace($existing)) { Write-Text $file $snippet; return 'created' }
    else { Append-Text $file ("`r`n" + $snippet); return 'appended' }
}

# --- shared helper install -------------------------------------------------
$BinDir = Join-Path $Home_ '.continuum\bin'
$BinPs1 = Join-Path $BinDir 'continuum.ps1'
$BinSh = Join-Path $BinDir 'continuum.sh'
function HookCmdPs($argstr) { "powershell -ExecutionPolicy Bypass -File `"$BinPs1`" $argstr" }
function HookCmdSh($argstr) { "bash `"$BinSh`" $argstr" }

# --- JSON hook writers (idempotent: strip our old entries, keep everyone else's) ---
function Load-Json($file) {
    if (Test-Path -LiteralPath $file) { $raw = Read-Text $file; if (-not [string]::IsNullOrWhiteSpace($raw)) { return ($raw | ConvertFrom-Json) } }
    return [pscustomobject]@{}
}
function Strip-Continuum($arr) {
    $kept = @()
    foreach ($g in @($arr)) { if (($g | ConvertTo-Json -Depth 8 -Compress) -notmatch 'continuum') { $kept += $g } }
    return , $kept
}
function Ensure-Hooks($s) { if (-not ($s.PSObject.Properties.Name -contains 'hooks') -or -not $s.hooks) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }; return $s }
function Put-Event($hooks, $event, $entry) {
    $existing = @(); if ($hooks.PSObject.Properties.Name -contains $event) { $existing = @($hooks.$event) }
    $arr = [object[]]((Strip-Continuum $existing) + $entry)
    if ($hooks.PSObject.Properties.Name -contains $event) { $hooks.$event = $arr } else { $hooks | Add-Member -NotePropertyName $event -NotePropertyValue $arr -Force }
}
function Wire-Nested($file, $defs) {   # Claude / Codex / Gemini: {hooks:{Event:[{matcher,hooks:[{type,command}]}]}}
    $s = Ensure-Hooks (Load-Json $file)
    foreach ($d in $defs) { Put-Event $s.hooks $d.e ([pscustomobject]@{ matcher = $d.m; hooks = @([pscustomobject]@{ type = 'command'; command = (HookCmdPs $d.a) }) }) }
    Ensure-Dir $file; Write-Text $file ($s | ConvertTo-Json -Depth 20)
}
function Wire-Cursor($file, $defs) {   # Cursor: {version:1, hooks:{event:[{command,type}]}}
    $s = Ensure-Hooks (Load-Json $file)
    if ($s.PSObject.Properties.Name -contains 'version') { $s.version = 1 } else { $s | Add-Member version 1 -Force }
    foreach ($d in $defs) { Put-Event $s.hooks $d.e ([pscustomobject]@{ command = (HookCmdPs $d.a); type = 'command' }) }
    Ensure-Dir $file; Write-Text $file ($s | ConvertTo-Json -Depth 20)
}
function Wire-Windsurf($file, $defs) { # Windsurf: {hooks:{event:[{command,powershell}]}}
    $s = Ensure-Hooks (Load-Json $file)
    foreach ($d in $defs) { Put-Event $s.hooks $d.e ([pscustomobject]@{ command = (HookCmdSh $d.a); powershell = (HookCmdPs $d.a) }) }
    Ensure-Dir $file; Write-Text $file ($s | ConvertTo-Json -Depth 20)
}

$NestedFull = @(
    @{ e = 'SessionStart'; m = 'startup|resume|clear'; a = 'catch-up --event SessionStart' },
    @{ e = 'PreCompact'; m = 'manual|auto'; a = 'precompact --event PreCompact' },
    @{ e = 'Stop'; m = ''; a = 'guard' }
)
$GeminiDefs = @(
    @{ e = 'SessionStart'; m = 'startup|resume|clear'; a = 'catch-up --event SessionStart' },
    @{ e = 'PreCompress'; m = 'auto|manual'; a = 'precompact --event PreCompress' }
)
$CursorDefs = @(
    @{ e = 'sessionStart'; a = 'catch-up --event sessionStart' },
    @{ e = 'preCompact'; a = 'precompact --event preCompact' },
    @{ e = 'stop'; a = 'guard' }
)
$WindsurfDefs = @( @{ e = 'pre_user_prompt'; a = 'catch-up --once --event pre_user_prompt' } )

# name | detection dir | instruction (block) file or $null | hookKind | hook file | defs | install-claude-skill
$agents = @(
    @{ name = 'Claude Code'; dir = Join-Path $Home_ '.claude'; block = Join-Path $Home_ '.claude\CLAUDE.md'; kind = 'nested'; hook = Join-Path $Home_ '.claude\settings.json'; defs = $NestedFull; skill = $true }
    @{ name = 'Codex'; dir = Join-Path $Home_ '.codex'; block = Join-Path $Home_ '.codex\AGENTS.md'; kind = 'nested'; hook = Join-Path $Home_ '.codex\hooks.json'; defs = $NestedFull; skill = $false }
    @{ name = 'Gemini CLI'; dir = Join-Path $Home_ '.gemini'; block = Join-Path $Home_ '.gemini\GEMINI.md'; kind = 'nested'; hook = Join-Path $Home_ '.gemini\settings.json'; defs = $GeminiDefs; skill = $false }
    @{ name = 'Antigravity'; dir = Join-Path $Home_ '.gemini'; block = Join-Path $Home_ '.gemini\AGENTS.md'; kind = 'none'; hook = $null; defs = $null; skill = $false }
    @{ name = 'Cursor'; dir = Join-Path $Home_ '.cursor'; block = $null; kind = 'cursor'; hook = Join-Path $Home_ '.cursor\hooks.json'; defs = $CursorDefs; skill = $false }
    @{ name = 'Windsurf'; dir = Join-Path $Home_ '.codeium\windsurf'; block = Join-Path $Home_ '.codeium\windsurf\memories\global_rules.md'; kind = 'windsurf'; hook = Join-Path $Home_ '.codeium\windsurf\hooks.json'; defs = $WindsurfDefs; skill = $false }
)

$snippet = Read-Text (Join-Path $Src 'adapters/global.md')

Write-Host ""
Write-Host "Continuum - global install (once for all agents)" -ForegroundColor Cyan
Write-Host "  source: $Src"
Write-Host ""

# Shared helper CLI: install once, referenced by every agent's hooks.
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item -LiteralPath (Join-Path $Src 'bin/continuum.ps1') -Destination $BinDir -Force
Copy-Item -LiteralPath (Join-Path $Src 'bin/continuum.sh') -Destination $BinDir -Force
Write-Host ("  helper CLI -> " + $BinDir.Replace($Home_, '~')) -ForegroundColor DarkGray
Write-Host ""

foreach ($a in $agents) {
    $detected = Test-Path -LiteralPath $a.dir
    if (-not $detected -and -not $All) {
        Write-Host ("  - {0,-12} skipped (not detected; use -All to force)" -f $a.name) -ForegroundColor DarkGray
        continue
    }
    $tag = if ($detected) { '' } else { ' [forced]' }
    Write-Host ("  + {0,-12}{1}" -f $a.name, $tag) -ForegroundColor Green

    if ($a.block) {
        $result = Set-ManagedBlock $a.block $snippet
        Write-Host ("      protocol block {0} -> {1}" -f $result, $a.block.Replace($Home_, '~')) -ForegroundColor DarkGray
    }
    if ($a.skill) {
        $skillDir = Join-Path $Home_ '.claude\skills\continuum'
        New-Item -ItemType Directory -Force -Path (Join-Path $skillDir 'bin') | Out-Null
        Copy-Item -LiteralPath (Join-Path $Src 'skill/continuum/SKILL.md') -Destination $skillDir -Force
        Copy-Item -LiteralPath (Join-Path $Src 'bin/continuum.ps1') -Destination (Join-Path $skillDir 'bin') -Force
        Copy-Item -LiteralPath (Join-Path $Src 'bin/continuum.sh') -Destination (Join-Path $skillDir 'bin') -Force
        Write-Host "      skill installed -> ~\.claude\skills\continuum\" -ForegroundColor DarkGray
    }
    switch ($a.kind) {
        'nested' { Wire-Nested $a.hook $a.defs; Write-Host ("      hooks wired -> " + $a.hook.Replace($Home_, '~')) -ForegroundColor DarkGray }
        'cursor' { Wire-Cursor $a.hook $a.defs; Write-Host ("      hooks wired -> " + $a.hook.Replace($Home_, '~')) -ForegroundColor DarkGray }
        'windsurf' { Wire-Windsurf $a.hook $a.defs; Write-Host ("      hooks wired -> " + $a.hook.Replace($Home_, '~') + " (per-turn: no session hook)") -ForegroundColor DarkGray }
        default { }
    }
}

Write-Host ""
Write-Host "Done. Detected agents now catch up + hand off automatically in any project with a .aicontext/ folder." -ForegroundColor Green
Write-Host "Restart any running agent session to pick up the new global config." -ForegroundColor Yellow
Write-Host ""
