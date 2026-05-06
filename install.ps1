# VeeCode Claude Gateway — installer for the `claude` wrapper (Windows).
# Per-user install (no admin). Re-running upgrades the wrapper in place. See
# https://github.com/veecode-claude-gateway/claude-gateway-parent/blob/main/docs/developer-setup.md
$ErrorActionPreference = 'Stop'

$GatewayUrl     = if ($env:CLAUDE_GATEWAY_URL)         { $env:CLAUDE_GATEWAY_URL }         else { 'https://gateway.example.com' }
$WrapperVersion = if ($env:CLAUDE_GATEWAY_VERSION)     { $env:CLAUDE_GATEWAY_VERSION }     else { 'dev' }
$InstallDir     = if ($env:CLAUDE_GATEWAY_INSTALL_DIR) { $env:CLAUDE_GATEWAY_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'claude-gateway\bin' }
$WrapperUrl     = if ($env:CLAUDE_GATEWAY_WRAPPER_URL) { $env:CLAUDE_GATEWAY_WRAPPER_URL } else { 'https://veecode-claude-gateway.github.io/claude.ps1' }
$InstallPath    = Join-Path $InstallDir 'claude.ps1'

function Log([string]$m) { Write-Host "install: $m" }
function Die([string]$m) { Write-Error "install: $m"; exit 1 }

# 1) Locate the real `claude.exe` / `claude.cmd`, skipping any previously installed wrapper.
$realClaude = $null
foreach ($cmd in Get-Command claude -All -ErrorAction SilentlyContinue) {
    $p = $cmd.Source
    if (-not $p) { continue }
    if ($p -ieq $InstallPath) { continue }
    if ((Get-Item $p).Extension -ieq '.ps1') {
        $head = Get-Content $p -TotalCount 5 -ErrorAction SilentlyContinue
        if ($head -join "`n" -match 'VeeCode Claude Gateway wrapper') { continue }
    }
    $realClaude = $p
    break
}
if (-not $realClaude) { Die "couldn't find real 'claude' on PATH. Install Claude Code first: https://docs.claude.com/en/docs/claude-code" }
Log "real claude binary: $realClaude"

# 2) Fetch the wrapper template (or use a local copy if present alongside this script).
$scriptDir = Split-Path -Parent $PSCommandPath
$localTemplate = Join-Path $scriptDir 'claude.ps1'
if (Test-Path $localTemplate) {
    $template = Get-Content $localTemplate -Raw
} else {
    $template = (Invoke-WebRequest -Uri $WrapperUrl -UseBasicParsing).Content
}

# 3) Substitute placeholders. Plain string Replace (not -replace) — paths contain
# backslashes that regex would chew on.
$rendered = $template
$rendered = $rendered.Replace('@@GATEWAY_URL@@',     $GatewayUrl)
$rendered = $rendered.Replace('@@REAL_CLAUDE@@',     $realClaude)
$rendered = $rendered.Replace('@@WRAPPER_VERSION@@', $WrapperVersion)

# 4) Install.
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Set-Content -Path $InstallPath -Value $rendered -Encoding utf8
Log "installed wrapper to $InstallPath"

# Make sure $InstallDir is on the user PATH so `claude` (via a shim) resolves.
$shim = Join-Path $InstallDir 'claude.cmd'
"@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0claude.ps1`" %*" | Set-Content -Path $shim -Encoding ascii
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not ($userPath -split ';' | Where-Object { $_ -ieq $InstallDir })) {
    [Environment]::SetEnvironmentVariable('Path', "$InstallDir;$userPath", 'User')
    Log "added $InstallDir to user PATH (open a new shell to pick it up)"
}

# 5) Verify by absolute path (does not depend on PATH being re-read).
try {
    & $shim --version | Out-Null
    Log "verify ok: '$shim --version' returned 0"
} catch {
    Log "warning: '$shim --version' did not return 0 ($($_.Exception.Message))"
    Log "  this is expected if CLAUDE_GATEWAY_URL is the placeholder or 'gcloud auth login' has not been run yet"
    Log "  re-run after: `$env:CLAUDE_GATEWAY_URL = '<real gateway>'; gcloud auth login"
}
Log "done. Open a new shell so the PATH change takes effect, then run 'claude'."
