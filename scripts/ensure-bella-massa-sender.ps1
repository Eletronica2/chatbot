# Ensure Bella Massa default WhatsApp sender is +55 34 3195-1773 (WABA 507137542482993)
param(
    [string]$TenantId = "pizzaria_bella_massa",
    [string]$BackendUrl = $(if ($env:BACKEND_URL) { $env:BACKEND_URL } else { "http://localhost:8000" }),
    [string]$AdminEmail = $(if ($env:BELLA_ADMIN_EMAIL) { $env:BELLA_ADMIN_EMAIL } else { "admin@bellamassa.com.br" }),
    [string]$AdminPassword = $(if ($env:BELLA_ADMIN_PASSWORD) { $env:BELLA_ADMIN_PASSWORD } else { "Bella@2026!" }),
    [string]$AccountKey = "507137542482993",
    [string]$PhoneNumberId = "523040924230958",
    [string]$DisplayPhone = "+55 34 3195-1773"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Ensure Bella Massa sender ===" -ForegroundColor Cyan

$login = Invoke-RestMethod -Uri "$BackendUrl/api/v1/auth/login" -Method Post -Body (@{
    email = $AdminEmail
    password = $AdminPassword
} | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 20

$headers = @{ Authorization = "Bearer $($login.access_token)" }
$accountsUri = "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-accounts"
$rawAccounts = Invoke-RestMethod -Uri $accountsUri -Headers $headers -TimeoutSec 20
$accounts = @()
if ($null -ne $rawAccounts) {
    if ($rawAccounts -is [System.Array]) {
        $accounts = $rawAccounts
    } else {
        $accounts = @($rawAccounts)
    }
}

$existing = $accounts | Where-Object { $_.account_key -eq $AccountKey } | Select-Object -First 1

if ($existing) {
    Write-Host "Updating account $AccountKey as default sender..." -ForegroundColor DarkGray
    foreach ($acc in $accounts) {
        if ($acc.account_key -ne $AccountKey -and $acc.is_default) {
            try {
                Invoke-RestMethod -Uri "$accountsUri/$($acc.account_key)" -Method Patch -Headers $headers -Body (@{
                    is_default = $false
                } | ConvertTo-Json) -ContentType "application/json" | Out-Null
            } catch {
                Write-Host "[WARN] Could not unset default on $($acc.account_key): $($_.ErrorDetails.Message)" -ForegroundColor Yellow
            }
        }
    }
    $updated = Invoke-RestMethod -Uri "$accountsUri/$AccountKey" -Method Patch -Headers $headers -Body (@{
        display_phone_number = $DisplayPhone
        phone_number_id = $PhoneNumberId
        is_default = $true
        status = "active"
    } | ConvertTo-Json) -ContentType "application/json"
} else {
    Write-Host "Creating account $AccountKey..." -ForegroundColor DarkGray
    if (-not $env:META_ACCESS_TOKEN) {
        Write-Host "[WARN] META_ACCESS_TOKEN not set; account created without token (use sync-whatsapp-tokens.ps1)" -ForegroundColor Yellow
    }
    $updated = Invoke-RestMethod -Uri $accountsUri -Method Post -Headers $headers -Body (@{
        account_key = $AccountKey
        display_name = "Bella Massa WhatsApp"
        phone_number_id = $PhoneNumberId
        display_phone_number = $DisplayPhone
        access_token = $(if ($env:META_ACCESS_TOKEN) { $env:META_ACCESS_TOKEN } else { $null })
        verify_token = "super-secret-webhook-token"
        status = "active"
        is_default = $true
    } | ConvertTo-Json) -ContentType "application/json"
}

Write-Host "[OK] Default sender: $($updated.display_phone_number) (WABA $($updated.account_key))" -ForegroundColor Green
Write-Host "[OK] phone_number_id: $($updated.phone_number_id)" -ForegroundColor Green
