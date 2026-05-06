# VeeCode Claude Gateway wrapper (Windows) — see meta-repo docs/developer-setup.md.
# Routes Claude Code through the corporate gateway, attributing spend to the
# active gcloud identity. install.ps1 substitutes the @@-delimited placeholders.
$ErrorActionPreference = 'Stop'

$GatewayUrl      = '@@GATEWAY_URL@@'
$RealClaude      = '@@REAL_CLAUDE@@'
$WrapperVersion  = '@@WRAPPER_VERSION@@'

$ConfigDir = Join-Path $env:LOCALAPPDATA 'claude-gateway'
$KeyFile   = Join-Path $ConfigDir 'key'
$Runbook   = 'https://github.com/veecode-claude-gateway/claude-gateway-parent/blob/main/docs/runbooks/'

function Die([string]$msg) { Write-Error "claude-gateway: $msg"; exit 1 }

New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

$key = $null
$expiresAt = [DateTime]::MinValue
if (Test-Path $KeyFile) {
    $lines = Get-Content $KeyFile
    if ($lines.Count -ge 2) {
        $key = $lines[0]
        [DateTime]::TryParse($lines[1], [ref]$expiresAt) | Out-Null
    }
}

if (-not $key -or ($expiresAt - [DateTime]::UtcNow).TotalSeconds -lt 3600) {
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        Die "gcloud not found on PATH. Install gcloud and run 'gcloud auth login'. See $Runbook."
    }
    $token = (& gcloud auth print-access-token 2>$null)
    if (-not $token) { Die "'gcloud auth print-access-token' failed. Run 'gcloud auth login'." }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/issue-key" `
            -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/json' -Body '{}' -TimeoutSec 10
    } catch {
        Die "could not reach gateway at $GatewayUrl ($($_.Exception.Message)). See $Runbook."
    }
    $key = $resp.key
    if (-not $key) { Die "gateway response missing 'key'." }
    Set-Content -Path $KeyFile -Value @($key, $resp.expires_at) -NoNewline:$false
}

$env:ANTHROPIC_BASE_URL        = $GatewayUrl
$env:ANTHROPIC_API_KEY         = $key
$env:CLAUDE_CONFIG_DIR         = (Join-Path $ConfigDir 'claude')
$env:ANTHROPIC_DEFAULT_HEADERS = "x-claude-gateway-cli: $WrapperVersion"
New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR | Out-Null

& $RealClaude @args
exit $LASTEXITCODE
