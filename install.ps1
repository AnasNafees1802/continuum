#requires -Version 5
<#
.SYNOPSIS
  Install Continuum (cross-agent session continuity) into a project.
.DESCRIPTION
  Creates the .aicontext/ memory ledger, installs the `continuum` Claude Code skill,
  and injects an auto-loaded instruction block into CLAUDE.md, AGENTS.md, and .windsurfrules
  so every AI coding agent reads/writes the same portable context. Idempotent - safe to re-run.
.PARAMETER Target
  The project directory to install into. Defaults to the current directory.
.PARAMETER Force
  Overwrite existing ledger files (STATE/TASKS/DECISIONS/JOURNAL/manifest). Off by default so
  re-running never destroys accumulated context.
.EXAMPLE
  ./install.ps1
.EXAMPLE
  ./install.ps1 -Target C:\code\my-project
#>
[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Src = $PSScriptRoot
$Target = (Resolve-Path -LiteralPath $Target).Path
$Now = Get-Date -Format 'yyyy-MM-dd HH:mm'
$ProjectName = Split-Path -Leaf $Target

# UTF-8 without BOM: PowerShell 5.1's Get-Content/Set-Content default to ANSI and corrupt
# non-ASCII (emoji, em-dashes). Use .NET I/O with explicit UTF-8 for correct round-tripping.
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Text($p) { [System.IO.File]::ReadAllText($p) }
function Write-Text($p, $c) {
    $tmp = "$p.tmp.$PID"
    try {
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination "$p.continuum.bak" -Force }
        [System.IO.File]::WriteAllText($tmp, $c, $Utf8)
        Move-Item -LiteralPath $tmp -Destination $p -Force
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Append-Text($p, $c) { [System.IO.File]::AppendAllText($p, $c, $Utf8) }
function Settings-Json($value) {
    function Check-Depth($node, [int]$depth) {
        if ($depth -gt 90) { throw 'Settings nesting exceeds the safe serialization limit; file left unchanged' }
        if ($node -is [pscustomobject]) { foreach ($property in $node.PSObject.Properties) { Check-Depth $property.Value ($depth + 1) } }
        elseif ($node -is [array]) { foreach ($item in $node) { Check-Depth $item ($depth + 1) } }
    }
    Check-Depth $value 0
    return ($value | ConvertTo-Json -Depth 100)
}

function Write-Step($msg) { Write-Host "  $msg" }
function Ensure-Dir($p) { $d = Split-Path -Parent $p; if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }
function Expand-Tokens($text) {
    $text.Replace('{{PROJECT_NAME}}', $ProjectName).Replace('{{DATE}}', $Now)
}

# Merge the Continuum hooks into a Claude Code settings JSON, idempotently: refresh any existing
# continuum entries, preserve everything else. $cmdBuilder: { param($sub) <full command string> }.
function Set-ContinuumHooks($settingsPath, $cmdBuilder) {
    Ensure-Dir $settingsPath
    $s = if (Test-Path -LiteralPath $settingsPath) {
        $raw = Read-Text $settingsPath
        $raw | ConvertFrom-Json
    }
    else { [pscustomobject]@{} }
    if ($s -isnot [pscustomobject]) { throw 'Settings must be a JSON object' }
    if (-not ($s.PSObject.Properties.Name -contains 'hooks')) {
        $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $hooks = $s.hooks
    if ($hooks -isnot [pscustomobject]) { throw 'Hooks must be an object' }
    $defs = @(
        @{ event = 'SessionStart'; matcher = 'startup|resume|clear'; sub = 'catch-up' },
        @{ event = 'PreCompact'; matcher = 'manual|auto'; sub = 'precompact' },
        @{ event = 'Stop'; matcher = ''; sub = 'guard' }
    )
    foreach ($d in $defs) {
        $entry = [pscustomobject]@{ matcher = $d.matcher; hooks = @([pscustomobject]@{ type = 'command'; command = (& $cmdBuilder $d.sub) }) }
        $kept = @()
        if ($hooks.PSObject.Properties.Name -contains $d.event) {
            if ($hooks.($d.event) -isnot [array]) { throw 'Hook event must be an array' }
            foreach ($grp in @($hooks.($d.event))) {
                if ($grp.hooks -isnot [array]) { throw 'Nested hooks must be an array' }
                foreach ($h in $grp.hooks) { if ($h -isnot [pscustomobject]) { throw 'Hook entry must be an object' } }
                $children = @($grp.hooks | Where-Object { $_.command -notmatch 'continuum\.(ps1|sh)' })
                if ($children.Count -gt 0 -or $grp.hooks.Count -eq 0) { $grp.hooks = $children; $kept += $grp }
            }
        }
        $arr = [object[]](@($kept) + $entry)
        if ($hooks.PSObject.Properties.Name -contains $d.event) { $hooks.($d.event) = $arr }
        else { $hooks | Add-Member -NotePropertyName $d.event -NotePropertyValue $arr -Force }
    }
    Write-Text $settingsPath (Settings-Json $s)
}

# Inject (or refresh) the managed Continuum block in a file, idempotently.
function Set-ManagedBlock($file, $snippet) {
    $existing = if (Test-Path -LiteralPath $file) { Read-Text $file } else { '' }
    if ($existing -match '(?s)<!-- CONTINUUM:BEGIN.*?CONTINUUM:END -->') {
        $updated = [regex]::Replace($existing, '(?s)<!-- CONTINUUM:BEGIN.*?CONTINUUM:END -->', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $snippet.TrimEnd() })
        Write-Text $file $updated
        return 'updated'
    }
    elseif ([string]::IsNullOrWhiteSpace($existing)) {
        Write-Text $file $snippet
        return 'created'
    }
    else {
        Append-Text $file ("`r`n" + $snippet)
        return 'appended'
    }
}

Write-Host ""
Write-Host "Continuum installer" -ForegroundColor Cyan
Write-Host "  source : $Src"
Write-Host "  target : $Target"
Write-Host ""

# --- 1. Ledger: .aicontext/ ------------------------------------------------
Write-Host "[1/5] Context ledger (.aicontext/)" -ForegroundColor Cyan
$ctxDir = Join-Path $Target '.aicontext'
New-Item -ItemType Directory -Force -Path $ctxDir | Out-Null
$alwaysOverwrite = @('PROTOCOL.md')   # spec files, never user-edited
Get-ChildItem -LiteralPath (Join-Path $Src 'templates/aicontext') -File | ForEach-Object {
    $dest = Join-Path $ctxDir $_.Name
    $exists = Test-Path -LiteralPath $dest
    if ($exists -and -not $Force -and ($alwaysOverwrite -notcontains $_.Name)) {
        Write-Step "kept    .aicontext/$($_.Name) (already present)"
    }
    else {
        $content = Expand-Tokens (Read-Text $_.FullName)
        Write-Text $dest $content
        $verb = if ($exists) { 'updated' } else { 'created' }
        Write-Step "$verb .aicontext/$($_.Name)"
    }
}

# --- 2. Claude Code skill + helper CLI -------------------------------------
Write-Host "[2/5] Claude Code skill + helper (.claude/skills/continuum/)" -ForegroundColor Cyan
$skillDest = Join-Path $Target '.claude/skills/continuum'
$binDest = Join-Path $skillDest 'bin'
New-Item -ItemType Directory -Force -Path $binDest | Out-Null
Copy-Item -LiteralPath (Join-Path $Src 'skill/continuum/SKILL.md') -Destination $skillDest -Force
Copy-Item -LiteralPath (Join-Path $Src 'bin/continuum.ps1') -Destination $binDest -Force
Copy-Item -LiteralPath (Join-Path $Src 'bin/continuum.sh') -Destination $binDest -Force
Write-Step "installed .claude/skills/continuum/SKILL.md + bin/continuum.ps1|.sh"

# --- 3. Claude Code hooks (deterministic capture) --------------------------
Write-Host "[3/5] Claude Code hooks (.claude/settings.local.json)" -ForegroundColor Cyan
$ps1Path = Join-Path $binDest 'continuum.ps1'
$cmdBuilder = { param($sub) "powershell -ExecutionPolicy Bypass -File `"$ps1Path`" $sub" }
$settingsLocal = Join-Path $Target '.claude/settings.local.json'
Set-ContinuumHooks $settingsLocal $cmdBuilder
Write-Step "wired SessionStart/PreCompact/Stop hooks -> continuum.ps1 (machine-local)"

# --- 4. Agent adapter files ------------------------------------------------
Write-Host "[4/5] Agent adapters" -ForegroundColor Cyan
$snippet = Read-Text (Join-Path $Src 'adapters/snippet.md')
foreach ($f in @('CLAUDE.md', 'AGENTS.md', '.windsurfrules')) {
    $result = Set-ManagedBlock (Join-Path $Target $f) $snippet
    Write-Step "$result $f"
}

# --- 5. gitignore the local ledger -----------------------------------------
Write-Host "[5/5] .gitignore" -ForegroundColor Cyan
$gi = Join-Path $Target '.gitignore'
$giLines = if (Test-Path -LiteralPath $gi) { Get-Content -LiteralPath $gi } else { @() }
foreach ($line in @('.aicontext/', '.claude/settings.local.json')) {
    if ($giLines -contains $line) {
        Write-Step "kept    $line already ignored"
    }
    else {
        Append-Text $gi "`r`n# Continuum (machine-local)`r`n$line`r`n"
        Write-Step "added   $line to .gitignore"
    }
}

Write-Host ""
Write-Host "Continuum installed." -ForegroundColor Green
Write-Host "Next: open this project in any agent - it will read .aicontext/STATE.md and catch up."
Write-Host ""
