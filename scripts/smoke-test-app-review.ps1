# Smoke test for Meta App Review recording prep
# Usage: powershell -ExecutionPolicy Bypass -File scripts/smoke-test-app-review.ps1

$ErrorActionPreference = "Continue"

$BackendUrl = if ($env:BACKEND_URL) { $env:BACKEND_URL } else { "http://localhost:8000" }
$GatewayUrl = if ($env:GATEWAY_URL) { $env:GATEWAY_URL } else { "http://localhost:40000" }
$VerifyToken = if ($env:META_VERIFY_TOKEN) { $env:META_VERIFY_TOKEN } else { "super-secret-webhook-token" }
$BellaEmail = if ($env:BELLA_ADMIN_EMAIL) { $env:BELLA_ADMIN_EMAIL } else { "admin@bellamassa.com.br" }
$BellaPassword = if ($env:BELLA_ADMIN_PASSWORD) { $env:BELLA_ADMIN_PASSWORD } else { "Bella@2026!" }
$TenantId = "pizzaria_bella_massa"

function Write-Check([string]$Label, [bool]$Ok, [string]$Detail = "") {
    $icon = if ($Ok) { "[OK]" } else { "[FAIL]" }
    $color = if ($Ok) { "Green" } else { "Red" }
    Write-Host "$icon $Label" -ForegroundColor $color
    if ($Detail) { Write-Host "     $Detail" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "=== Smoke test App Review (Atenda Ai) ===" -ForegroundColor Cyan
Write-Host ""

$allOk = $true

# 1. Docker containers
$requiredContainers = @(
    "chatbot-mysql",
    "chatbot-backend",
    "chatbot-whatsapp-gateway",
    "chatbot-flow-engine"
)
foreach ($name in $requiredContainers) {
    $running = docker ps --filter "name=$name" --filter "status=running" --format "{{.Names}}" 2>$null
    $ok = $running -eq $name
    if (-not $ok) { $allOk = $false }
    Write-Check "Container $name" $ok
}

# 2. Backend health
try {
    $health = Invoke-RestMethod -Uri "$BackendUrl/health" -TimeoutSec 10
    $healthOk = $health.status -eq "ok" -or $health.status -eq "healthy"
    if (-not $healthOk) { $allOk = $false }
    Write-Check "Backend GET /health" $healthOk ($health | ConvertTo-Json -Compress)
} catch {
    $allOk = $false
    Write-Check "Backend GET /health" $false $_.Exception.Message
}

# 3. Gateway webhook verify
try {
    $verifyUri = "$GatewayUrl/webhook?hub.mode=subscribe&hub.verify_token=$VerifyToken&hub.challenge=smoke-test-challenge"
    $challenge = Invoke-RestMethod -Uri $verifyUri -TimeoutSec 10
    $verifyOk = $challenge -eq "smoke-test-challenge"
    if (-not $verifyOk) { $allOk = $false }
    Write-Check "Gateway webhook verify (GET)" $verifyOk
} catch {
    $allOk = $false
    Write-Check "Gateway webhook verify (GET)" $false $_.Exception.Message
}

# 4. Bella Massa WhatsApp account in DB
try {
    $dbQuery = @"
SELECT wa.phone_number_id, wa.account_key, wa.display_phone_number, t.external_key
FROM whatsapp_accounts wa
JOIN tenants t ON t.id = wa.tenant_id
WHERE t.external_key = 'pizzaria_bella_massa'
LIMIT 1;
"@
    $dbResult = docker exec chatbot-mysql mysql -uchatbot -pchatbot chatbot -N -e $dbQuery 2>$null
    $dbOk = [bool]$dbResult
    if (-not $dbOk) { $allOk = $false }
    Write-Check "WhatsApp account Bella Massa (DB)" $dbOk ($dbResult -join " | ")
} catch {
    $allOk = $false
    Write-Check "WhatsApp account Bella Massa (DB)" $false $_.Exception.Message
}

# 5. Login + list conversations
try {
    $loginBody = @{ email = $BellaEmail; password = $BellaPassword } | ConvertTo-Json
    $login = Invoke-RestMethod -Uri "$BackendUrl/api/v1/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -TimeoutSec 15
    $token = $login.access_token
    $loginOk = [bool]$token
    if (-not $loginOk) { $allOk = $false }
    Write-Check "Login Bella Massa admin" $loginOk $BellaEmail

    if ($loginOk) {
        $headers = @{ Authorization = "Bearer $token" }
        $conversations = Invoke-RestMethod -Uri "$BackendUrl/api/v1/conversations?limit=5" -Headers $headers -TimeoutSec 15
        $convCount = if ($conversations -is [array]) { $conversations.Count } else { 0 }
        Write-Check "List conversations API" $true "$convCount conversation(s) visible"
        if ($convCount -eq 0) {
            Write-Host "     Tip: send 'Oi' from your phone to the Meta test number, then re-run." -ForegroundColor Yellow
        }
    }
} catch {
    $allOk = $false
    Write-Check "Login Bella Massa admin" $false $_.Exception.Message
}

# 6. Template list API (Video 2 prep)
try {
    if ($token) {
        $headers = @{ Authorization = "Bearer $token" }
        $templatesUri = "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-templates"
        $templates = Invoke-RestMethod -Uri $templatesUri -Headers $headers -TimeoutSec 20
        $tplCount = if ($templates -is [Array]) { $templates.Count } else { 0 }
        Write-Check "List WhatsApp templates API" $true "$tplCount template(s)"
    }
} catch {
    Write-Check "List WhatsApp templates API" $false $_.Exception.Message
    Write-Host "     If token expired on Meta account, renew in backoffice before Video 2." -ForegroundColor Yellow
}

# 7. Template send route exists (Video 2 / Templates WhatsApp screen)
try {
    if ($token) {
        $headers = @{ Authorization = "Bearer $token" }
        $sendUri = "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-templates/send"
        try {
            Invoke-RestMethod -Uri $sendUri -Method Post -Headers $headers -Body (@{
                template_name = "smoke_test_nonexistent"
                language = "pt_BR"
            } | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 20 | Out-Null
            Write-Check "Template send API route" $true "POST /whatsapp-templates/send reachable"
        } catch {
            $status = $_.Exception.Response.StatusCode.value__
            $routeOk = $status -eq 400
            Write-Check "Template send API route" $routeOk "HTTP $status (400 = route OK, token/template validation)"
        }
    }
} catch {
    Write-Check "Template send API route" $false $_.Exception.Message
}

Write-Host ""
Write-Host "=== Manual steps (cannot automate) ===" -ForegroundColor Cyan
Write-Host "  1. Meta Developers -> WhatsApp -> API Setup -> add YOUR phone as test recipient"
Write-Host "  2. cloudflared tunnel --url http://localhost:40000 (update Meta webhook URL)"
Write-Host "  3. Record Video 1 (Conversas -> reply -> phone receives message)"
Write-Host "  4. Record Video 2 (Backoffice -> WhatsApp -> create template -> PENDING)"
Write-Host "  5. Submit App Review with videos + public URLs"
Write-Host ""
Write-Host "Full guide: docs/gravar-videos-app-review.md"
Write-Host ""

if ($allOk) {
    Write-Host "Core stack checks passed. Complete manual Meta steps before recording." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some checks failed. Fix stack issues before recording." -ForegroundColor Red
    exit 1
}
