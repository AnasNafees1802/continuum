#requires -Version 5
<#
.SYNOPSIS
  Install Continuum ONCE into every AI coding agent on this machine (global / user-level).
.DESCRIPTION
  Injects the Continuum protocol into each agent's GLOBAL instruction file, so every project you
  open in any agent automatically follows the protocol when it has a `.aicontext/` folder.
  Targets: Claude Code, Codex, Gemini CLI, Antigravity, Windsurf. Idempotent.

  By default it installs only for agents it detects (their config dir exists). Use -All to install
  for every known agent regardless of detection.
.PARAMETER All
  Install for every known agent, even ones not detected on this machine (creates their config dirs).
.EXAMPLE
  ./install-global.ps1
.EXAMPLE
  ./install-global.ps1 -All
#>
[CmdletBinding()]
param([switch]$All)

$ErrorActionPreference = 'Stop'
$Src = $PSScriptRoot
$Home_ = $HOME

# UTF-8 no-BOM I/O (PS 5.1 default mangles emoji/em-dashes).
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

$snippet = Read-Text (Join-Path $Src 'adapters/global.md')

# agent | detection dir | global instruction file | also install Claude skill?
$agents = @(
    @{ name = 'Claude Code'; dir = Join-Path $Home_ '.claude'; file = Join-Path $Home_ '.claude\CLAUDE.md'; skill = $true }
    @{ name = 'Codex'; dir = Join-Path $Home_ '.codex'; file = Join-Path $Home_ '.codex\AGENTS.md'; skill = $false }
    @{ name = 'Gemini CLI'; dir = Join-Path $Home_ '.gemini'; file = Join-Path $Home_ '.gemini\GEMINI.md'; skill = $false }
    @{ name = 'Antigravity'; dir = Join-Path $Home_ '.gemini'; file = Join-Path $Home_ '.gemini\AGENTS.md'; skill = $false }
    @{ name = 'Windsurf'; dir = Join-Path $Home_ '.codeium\windsurf'; file = Join-Path $Home_ '.codeium\windsurf\memories\global_rules.md'; skill = $false }
)

Write-Host ""
Write-Host "Continuum - global install (once for all agents)" -ForegroundColor Cyan
Write-Host "  source: $Src"
Write-Host ""

foreach ($a in $agents) {
    $detected = Test-Path -LiteralPath $a.dir
    if (-not $detected -and -not $All) {
        Write-Host ("  - {0,-12} skipped (not detected; use -All to force)" -f $a.name) -ForegroundColor DarkGray
        continue
    }
    $result = Set-ManagedBlock $a.file $snippet
    $tag = if ($detected) { '' } else { ' [forced]' }
    Write-Host ("  + {0,-12} {1}{2}" -f $a.name, $a.file.Replace($Home_, '~'), $tag) -ForegroundColor Green
    Write-Host ("      block {0}" -f $result) -ForegroundColor DarkGray

    if ($a.skill) {
        $skillDir = Join-Path $Home_ '.claude\skills\continuum'
        New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $Src 'skill/continuum/SKILL.md') -Destination $skillDir -Force
        Write-Host "      skill installed -> ~\.claude\skills\continuum\SKILL.md" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Done. Every detected agent now follows Continuum in any project with a .aicontext/ folder." -ForegroundColor Green
Write-Host "Restart any running agent session to pick up the new global config." -ForegroundColor Yellow
Write-Host ""
