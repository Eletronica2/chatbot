# Sync META_ACCESS_TOKEN to all Bella Massa WhatsApp accounts in the backend DB.
# Usage:
#   $env:META_ACCESS_TOKEN = "<System User token>"
#   powershell -ExecutionPolicy Bypass -File scripts/sync-whatsapp-tokens.ps1
#
# Or load from scripts/.env.meta.local

param(
    [string]$TenantId = "pizzaria_bella_massa",
    [string]$BackendUrl = $(if ($env:BACKEND_URL) { $env:BACKEND_URL } else { "http://localhost:8000" }),
    [string]$AdminEmail = $(if ($env:BELLA_ADMIN_EMAIL) { $env:BELLA_ADMIN_EMAIL } else { "admin@bellamassa.com.br" }),
    [string]$AdminPassword = $(if ($env:BELLA_ADMIN_PASSWORD) { $env:BELLA_ADMIN_PASSWORD } else { "Bella@2026!" })
)

$envFile = Join-Path $PSScriptRoot ".env.meta.local"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($key -and -not (Get-Item -Path "env:$key" -ErrorAction SilentlyContinue).Value) {
            Set-Item -Path "env:$key" -Value $val
        }
    }
}

$token = $env:META_ACCESS_TOKEN
if (-not $token) {
    Write-Host "[FAIL] Set META_ACCESS_TOKEN or scripts/.env.meta.local" -ForegroundColor Red
    exit 1
}

$login = Invoke-RestMethod -Uri "$BackendUrl/api/v1/auth/login" -Method Post -Body (@{
    email = $AdminEmail
    password = $AdminPassword
} | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 20

$headers = @{ Authorization = "Bearer $($login.access_token)" }
$accounts = Invoke-RestMethod -Uri "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-accounts" -Headers $headers -TimeoutSec 20

foreach ($account in $accounts) {
    $body = @{
        account_key = $account.account_key
        phone_number_id = $account.phone_number_id
        display_phone_number = $account.display_phone_number
        display_name = $account.display_name
        access_token = $token
        verify_token = "super-secret-webhook-token"
        is_default = $account.is_default
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-accounts" -Method Put -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 30 | Out-Null
    Write-Host "[OK] $($account.account_key) ($($account.display_phone_number))" -ForegroundColor Green
}

Write-Host "Done. All accounts now use the same System User token." -ForegroundColor Cyan
