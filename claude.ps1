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

# Default mode: OAuth pass-through (Claude Code's own login flow handles
# auth; the gateway forwards the resulting Bearer token upstream). Set
# CLAUDE_GATEWAY_USE_API_KEY=1 to force the gcloud → /issue-key →
# virtual-key flow (CI workflows; users without a Team-plan login).
$UseApiKey = [bool]$env:CLAUDE_GATEWAY_USE_API_KEY
# Identity attribution on the OAuth path. Three-step fallback so the
# typical pilot sees their name on the dashboards without setting
# anything: (1) CLAUDE_GATEWAY_API_USER if explicitly exported
# (usually email; matches the server-validated label on the
# API-key path); (2) $env:USERNAME on Windows or $env:USER on
# PowerShell-on-Linux/macOS; (3) the well-known placeholder for
# non-interactive contexts. Caveat: USERNAME yields a login name,
# not an email — set CLAUDE_GATEWAY_API_USER explicitly if you
# care about a unified view across API-key and OAuth paths.
$ApiUser = if ($env:CLAUDE_GATEWAY_API_USER) {
    $env:CLAUDE_GATEWAY_API_USER
} elseif ($env:USERNAME) {
    $env:USERNAME
} elseif ($env:USER) {
    $env:USER
} else {
    'claude-gw-user'
}

$key = $null
$expiresAt = [DateTime]::MinValue
if ($UseApiKey -and (Test-Path $KeyFile)) {
    $lines = Get-Content $KeyFile
    if ($lines.Count -ge 2) {
        $key = $lines[0]
        [DateTime]::TryParse($lines[1], [ref]$expiresAt) | Out-Null
    }
}

if ($UseApiKey -and (-not $key -or ($expiresAt - [DateTime]::UtcNow).TotalSeconds -lt 3600)) {
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
        # Distinguish a real network/DNS/TLS failure from a 4xx/5xx so
        # pilots don't go chasing imaginary VPN issues when the gateway
        # is reachable but unhappy. .Exception.Response is null on
        # network errors and populated for HTTP error responses on both
        # PS 5.1 (WebException) and PS 7+ (HttpResponseException).
        $statusCode = $null
        $body = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $body = (New-Object System.IO.StreamReader($stream)).ReadToEnd()
            } catch {}
        }
        if (-not $statusCode) {
            Die "could not reach gateway at $GatewayUrl (network/DNS/TLS failure: $($_.Exception.Message)). See $Runbook."
        } elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            Die "gateway rejected your identity ($statusCode): $body. Run 'gcloud auth login' if your token has expired."
        } elseif ($statusCode -ge 500) {
            Die "gateway error $statusCode from /issue-key: $body. See $Runbook."
        } else {
            Die "unexpected gateway response $statusCode: $body"
        }
    }
    $key = $resp.key
    if (-not $key) { Die "gateway response missing 'key'." }
    Set-Content -Path $KeyFile -Value @($key, $resp.expires_at) -NoNewline:$false
}

$env:ANTHROPIC_BASE_URL       = $GatewayUrl
if ($UseApiKey) {
    # Bearer auth, not x-api-key. The gateway's custom_auth.py reads only
    # the Authorization header; with ANTHROPIC_API_KEY set Claude Code
    # sends `x-api-key: <vk>` and every /v1/messages 401s. POSIX wrapper
    # was fixed in 174c656; same fix for Windows. Remove any pre-existing
    # ANTHROPIC_API_KEY in the parent env so it doesn't override the
    # auth-token path Claude Code falls back through.
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    $env:ANTHROPIC_AUTH_TOKEN = $key
}
# Default mode: do not touch ANTHROPIC_AUTH_TOKEN — Claude Code handles
# its own login flow and the gateway forwards the resulting token
# upstream.
# Isolate Claude Code's config dir only on the virtual-key path; let
# default OAuth mode read real credentials from %APPDATA%\.claude.
# Symptom of getting this wrong: `claude -p "..."` reports "Not logged
# in" because the non-interactive credential discovery doesn't fall
# back to the system credential store when CLAUDE_CONFIG_DIR points
# at an empty sandbox.
if ($UseApiKey) {
    $env:CLAUDE_CONFIG_DIR = (Join-Path $ConfigDir 'claude')
    New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR | Out-Null
}
# Two custom headers, newline-separated; Claude Code splits into
# individual HTTP headers. x-claude-gateway-user is laptop-trusted
# identity for server-side attribution on the OAuth path.
$env:ANTHROPIC_CUSTOM_HEADERS = "x-claude-gateway-cli: $WrapperVersion`nx-claude-gateway-user: $ApiUser"

# Native Claude Code OTEL telemetry (ADR-0009). Mirror of the POSIX
# wrapper block. Endpoint is hardcoded here until claude.ps1 gets the
# same runtime self-resolve refactor the POSIX wrapper got; override
# at the parent shell with $env:CLAUDE_GATEWAY_OTEL_ENDPOINT.
# CLAUDE_GATEWAY_NO_TELEMETRY=1 opts out (e.g. on a network where
# claudemonitor.vtgdev.net isn't reachable).
if (-not $env:CLAUDE_GATEWAY_NO_TELEMETRY) {
    $otelEndpoint = if ($env:CLAUDE_GATEWAY_OTEL_ENDPOINT) {
        $env:CLAUDE_GATEWAY_OTEL_ENDPOINT
    } else {
        'http://claudemonitor.vtgdev.net:4317'
    }
    $otelUser = if ($env:USER_EMAIL) { $env:USER_EMAIL } else { $ApiUser }
    if ($otelUser -eq 'claude-gw-user') {
        try {
            $gcloudEmail = (& gcloud config get-value account 2>$null | Select-Object -First 1)
            if ($gcloudEmail) { $otelUser = $gcloudEmail }
        } catch {}
    }
    $otelUsername = ($otelUser -split '@', 2)[0]
    $otelHost = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'unknown' }
    $env:CLAUDE_CODE_ENABLE_TELEMETRY    = '1'
    $env:OTEL_METRICS_EXPORTER           = 'otlp'
    $env:OTEL_LOGS_EXPORTER              = 'otlp'
    $env:OTEL_EXPORTER_OTLP_PROTOCOL     = 'grpc'
    $env:OTEL_EXPORTER_OTLP_ENDPOINT     = $otelEndpoint
    # Don't set service.name — Claude Code's SDK sets it internally and the
    # org collector filters on that default; overriding it drops the export.
    $env:OTEL_RESOURCE_ATTRIBUTES        = "user.email=$otelUser,user.name=$otelUsername,host.name=$otelHost,client.version=$WrapperVersion"
}

& $RealClaude @args
exit $LASTEXITCODE
