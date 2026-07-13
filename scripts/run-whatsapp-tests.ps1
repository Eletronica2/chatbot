# Load scripts/.env.meta.local and run full WhatsApp test suite
param(
    [switch]$UseTestAccount,
    [switch]$TryRegister,
    [switch]$SkipSend
)

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $PSScriptRoot ".env.meta.local"

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($key) { Set-Item -Path "env:$key" -Value $val }
    }
    Write-Host "Loaded $envFile" -ForegroundColor DarkGray
} else {
    Write-Host "Tip: create scripts/.env.meta.local from .env.meta.local.example" -ForegroundColor Yellow
}

if (-not $env:META_ACCESS_TOKEN) {
    Write-Host "Fetching META_ACCESS_TOKEN from chatbot-backend (default WhatsApp account)..." -ForegroundColor DarkGray
    try {
        $py = "from app.db.mysql import MySQLDatabase; from app.security.crypto import TokenCipher; from app.config.settings import get_settings; s=get_settings(); db=MySQLDatabase(s.DATABASE_URL); row=db.fetch_one('SELECT wa.access_token_encrypted FROM whatsapp_accounts wa JOIN tenants t ON t.id=wa.tenant_id WHERE t.external_key=%s AND wa.is_default=1 LIMIT 1',('pizzaria_bella_massa',)); c=TokenCipher(s.APP_SECRET_KEY); print(c.decrypt(row.get('access_token_encrypted')) or '')"
        $fetched = docker exec chatbot-backend python -c $py
        if ($fetched) {
            $env:META_ACCESS_TOKEN = $fetched.Trim()
            Write-Host "Token loaded from DB." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "Could not load token from Docker: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ">>> BR account diagnostics (default WABA)" -ForegroundColor Cyan
$args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "test-whatsapp-api.ps1"))
if ($TryRegister) { $args += "-TryRegister" }
if ($SkipSend) { $args += "-SkipSend" }
& powershell @args
$codeBr = $LASTEXITCODE

Write-Host ""
Write-Host ">>> US test account send pipeline (App Review / hello_world)" -ForegroundColor Cyan
$argsUs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "test-whatsapp-api.ps1"), "-UseTestAccount")
if ($SkipSend) { $argsUs += "-SkipSend" }
& powershell @argsUs
$codeUs = $LASTEXITCODE

$code = if ($codeBr -ne 0 -or $codeUs -ne 0) { 1 } else { 0 }

Write-Host ""
Write-Host "Running smoke-test-app-review.ps1 ..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "smoke-test-app-review.ps1")
$smoke = $LASTEXITCODE

if ($code -ne 0 -or $smoke -ne 0) { exit 1 }
exit 0
