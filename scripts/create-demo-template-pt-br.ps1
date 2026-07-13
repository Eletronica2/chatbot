# Create demo_bella_massa template (pt_BR) for App Review video
param(
    [string]$TenantId = "pizzaria_bella_massa",
    [string]$AccountKey = "507137542482993",
    [string]$BackendUrl = $(if ($env:BACKEND_URL) { $env:BACKEND_URL } else { "http://localhost:8000" }),
    [string]$AdminEmail = $(if ($env:BELLA_ADMIN_EMAIL) { $env:BELLA_ADMIN_EMAIL } else { "admin@bellamassa.com.br" }),
    [string]$AdminPassword = $(if ($env:BELLA_ADMIN_PASSWORD) { $env:BELLA_ADMIN_PASSWORD } else { "Bella@2026!" }),
    [string]$TemplateName = "demo_bella_massa",
    [string]$Language = "pt_BR",
    [string]$BodyText = "Ola! Este e um disparo de teste da Bella Massa pelo Atenda Ai."
)

$ErrorActionPreference = "Stop"

Write-Host "=== Create demo template pt_BR ===" -ForegroundColor Cyan

$login = Invoke-RestMethod -Uri "$BackendUrl/api/v1/auth/login" -Method Post -Body (@{
    email = $AdminEmail
    password = $AdminPassword
} | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 20

$headers = @{ Authorization = "Bearer $($login.access_token)" }
$listUri = "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-templates?account_key=$AccountKey"

$existing = @(Invoke-RestMethod -Uri $listUri -Headers $headers -TimeoutSec 30)
$found = $existing | Where-Object { $_.name -eq $TemplateName -and $_.language -eq $Language } | Select-Object -First 1

if ($found) {
    Write-Host "[OK] Template already exists: $TemplateName ($Language) status=$($found.status)" -ForegroundColor Green
    exit 0
}

try {
    $created = Invoke-RestMethod -Uri "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-templates" -Method Post -Headers $headers -Body (@{
        name = $TemplateName
        language = $Language
        category = "UTILITY"
        body_text = $BodyText
        account_key = $AccountKey
    } | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 45

    Write-Host "[OK] Created: $($created.name) | $($created.language) | status=$($created.status)" -ForegroundColor Green
    Write-Host "     Aguarde aprovacao Meta (APPROVED) antes de enviar pelo painel." -ForegroundColor Yellow
} catch {
    $detail = $_.ErrorDetails.Message
    if ($detail -match 'permissao para criar|permissão para criar|2494160|gerenciar modelos|Invalid parameter') {
        Write-Host "[WARN] WABA sem permissao para criar modelos (complete coexistencia Embedded Signup)." -ForegroundColor Yellow
        Write-Host "       Crie o template manualmente no WhatsApp Manager ou apos CONNECTED." -ForegroundColor Yellow
        exit 0
    }
    throw
}