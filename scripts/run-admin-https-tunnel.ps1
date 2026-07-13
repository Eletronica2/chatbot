# Admin Flutter Web em HTTPS via Cloudflare (para Meta Embedded Signup).
# Modo DEBUG (flutter run) nao funciona pelo tunnel — use este script (build RELEASE).
#
# Pre-requisitos:
#   1. Docker/backend rodando em http://localhost:8000
#   2. Tunnel do backend (outro terminal):
#        cloudflared tunnel --url http://localhost:8000
#      Copie a URL HTTPS (ex: https://abc.trycloudflare.com)
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/run-admin-https-tunnel.ps1 -ApiBaseUrl "https://SEU-BACKEND.trycloudflare.com"
#
# Depois configure no app Meta 873826165763092 (Facebook Login for Business > Settings):
#   - Allowed Domains for JavaScript SDK: <subdominio-admin>.trycloudflare.com
#   - Valid OAuth Redirect URIs: https://<subdominio-admin>.trycloudflare.com/
#   - Dominios do app (basic): <subdominio-admin>.trycloudflare.com

param(
    [int]$Port = 7357,
    [string]$ApiBaseUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$admin = Join-Path $root "admin-panel"
$webDir = Join-Path $admin "build\web"

Write-Host ""
Write-Host "=== Admin HTTPS (release build) ===" -ForegroundColor Cyan
Write-Host "API_BASE_URL: $ApiBaseUrl"
Write-Host ""

Push-Location $admin
try {
    Write-Host "Building Flutter web (release)..." -ForegroundColor Yellow
    flutter build web --release --dart-define=API_BASE_URL=$ApiBaseUrl
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
} finally {
    Pop-Location
}

if (-not (Test-Path $webDir)) {
    throw "Pasta nao encontrada: $webDir"
}

Write-Host ""
Write-Host "Servindo $webDir em http://0.0.0.0:$Port ..." -ForegroundColor Yellow
Write-Host "Iniciando Cloudflare Tunnel..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Quando aparecer a URL https://....trycloudflare.com:" -ForegroundColor Green
Write-Host "  1. Abra essa URL no navegador (nao localhost)"
Write-Host "  2. Cadastre o dominio na Meta (veja cabecalho deste script)"
Write-Host ""

$serveJob = Start-Job -ScriptBlock {
    param($dir, $port)
    Set-Location $dir
    py -m http.server $port --bind 0.0.0.0 2>&1
} -ArgumentList $webDir, $Port

Start-Sleep -Seconds 2
try {
    $probe = Invoke-WebRequest -Uri "http://localhost:$Port" -TimeoutSec 5 -UseBasicParsing
    Write-Host "Servidor local OK (status $($probe.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "AVISO: servidor local ainda nao respondeu em :$Port" -ForegroundColor Red
}

try {
    cloudflared tunnel --url "http://localhost:$Port"
} finally {
    Stop-Job $serveJob -ErrorAction SilentlyContinue
    Remove-Job $serveJob -ErrorAction SilentlyContinue
}
