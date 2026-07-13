# Start full coexistence session: Docker + 3 Cloudflare tunnels + admin release build.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/start-coexistence-session.ps1
#
# After URLs appear, paste values in Meta (or use Assistente de coexistencia no painel).

param(
    [int]$AdminPort = 7357,
    [string]$InfraDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $InfraDir) { $InfraDir = Join-Path $root "infra" }
$admin = Join-Path $root "admin-panel"
$webDir = Join-Path $admin "build\web"
$logDir = Join-Path $env:TEMP "atenda-coexistence-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Invoke-ExternalCommand {
    param(
        [string]$Label,
        [scriptblock]$Command
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command 2>&1 | ForEach-Object {
            $line = "$_"
            if ($line) { Write-Host "       $line" -ForegroundColor DarkGray }
        }
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "$Label falhou (exit $LASTEXITCODE)"
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-GatewayLocalUrl {
    try {
        $probe = Invoke-WebRequest -Uri "http://127.0.0.1:40000/health" -TimeoutSec 3 -UseBasicParsing
        if ($probe.StatusCode -eq 200 -and $probe.Content -match 'healthy') {
            return "http://127.0.0.1:40000"
        }
    } catch {}
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InterfaceAlias -notmatch 'Loopback' -and
            ($_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or $_.IPAddress -like '172.*')
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip) {
        try {
            $probe = Invoke-WebRequest -Uri "http://${ip}:40000/health" -TimeoutSec 3 -UseBasicParsing
            if ($probe.StatusCode -eq 200) { return "http://${ip}:40000" }
        } catch {}
    }
    return "http://127.0.0.1:40000"
}

function Wait-TunnelUrl {
    param(
        [string]$LogFile,
        [int]$TimeoutSec = 90
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        foreach ($file in @($LogFile, ($LogFile -replace '\.log$', '.err.log'))) {
            if (-not (Test-Path $file)) { continue }
            $text = Get-Content $file -Raw -ErrorAction SilentlyContinue
            if ($text -match '(https://[a-z0-9-]+\.trycloudflare\.com)') {
                return $Matches[1]
            }
        }
        Start-Sleep -Seconds 2
    }
    return $null
}

function Start-AdminStaticServer {
    param(
        [string]$WebDir,
        [int]$Port
    )
    $log = Join-Path $logDir "admin-http.log"
    $errLog = Join-Path $logDir "admin-http.err.log"
    if (Test-Path $log) { Remove-Item $log -Force }
    if (Test-Path $errLog) { Remove-Item $errLog -Force }
    $proc = Start-Process -FilePath "py" `
        -ArgumentList @("-m", "http.server", "$Port", "--bind", "0.0.0.0") `
        -WorkingDirectory $WebDir `
        -RedirectStandardOutput $log `
        -RedirectStandardError $errLog `
        -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port" -TimeoutSec 2 -UseBasicParsing
            if ($r.StatusCode -eq 200) {
                return $proc.Id
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    throw "Servidor admin nao respondeu em http://127.0.0.1:$Port"
}

function Start-TunnelJob {
    param(
        [string]$Name,
        [string]$LocalUrl
    )
    $log = Join-Path $logDir "$Name.log"
    $errLog = Join-Path $logDir "$Name.err.log"
    if (Test-Path $log) { Remove-Item $log -Force }
    if (Test-Path $errLog) { Remove-Item $errLog -Force }
    $proc = Start-Process -FilePath "cloudflared" `
        -ArgumentList @("tunnel", "--url", $LocalUrl) `
        -RedirectStandardOutput $log `
        -RedirectStandardError $errLog `
        -PassThru -WindowStyle Hidden
    return @{ Name = $Name; Log = $log; ErrLog = $errLog; Pid = $proc.Id }
}

Write-Host ""
Write-Host "=== Coexistence session (Atenda Ai) ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/5] Docker compose up..." -ForegroundColor Yellow
Push-Location $InfraDir
try {
    Invoke-ExternalCommand -Label "docker compose" {
        docker compose up -d mysql backend-api whatsapp-gateway flow-engine ai-engine
    }
} finally {
    Pop-Location
}

$deadline = (Get-Date).AddSeconds(60)
do {
    try {
        $h = Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 3
        if ($h.status -eq "healthy" -or $h.status -eq "ok") { break }
    } catch {}
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

Write-Host "[2/5] Starting Cloudflare tunnels (backend + gateway)..." -ForegroundColor Yellow
$gatewayLocal = Get-GatewayLocalUrl
Write-Host "       Gateway local: $gatewayLocal" -ForegroundColor DarkGray
$backendTunnel = Start-TunnelJob -Name "backend" -LocalUrl "http://localhost:8000"
$gatewayTunnel = Start-TunnelJob -Name "gateway" -LocalUrl $gatewayLocal

$backendUrl = Wait-TunnelUrl -LogFile $backendTunnel.Log
$gatewayUrl = Wait-TunnelUrl -LogFile $gatewayTunnel.Log

if (-not $backendUrl) {
    Write-Host "[WARN] Backend tunnel URL not detected. Use scripts/run-backend-https-tunnel.ps1 manually." -ForegroundColor Yellow
    $backendUrl = "http://localhost:8000"
}
if (-not $gatewayUrl) {
    Write-Host "[WARN] Gateway tunnel URL not detected. Use cloudflared on port 40000 manually." -ForegroundColor Yellow
    $gatewayUrl = "http://localhost:40000"
}

$gatewayHost = if ($gatewayUrl -match 'https://([^/]+)') { $Matches[1] } else { "SEU-TUNNEL-GATEWAY.trycloudflare.com" }
$webhookUrl = "https://$gatewayHost/webhook"

Write-Host "[3/5] Building admin web (release) API=$backendUrl ..." -ForegroundColor Yellow
Push-Location $admin
try {
    Invoke-ExternalCommand -Label "flutter build web" {
        flutter build web --release --dart-define=API_BASE_URL=$backendUrl
    }
} finally {
    Pop-Location
}

Write-Host "[4/5] Starting admin static server + tunnel..." -ForegroundColor Yellow
if (-not (Test-Path $webDir)) {
    throw "Build do admin nao encontrado em $webDir. Rode o script do inicio ou flutter build web --release."
}
$adminHttpPid = Start-AdminStaticServer -WebDir $webDir -Port $AdminPort
Write-Host "       Admin HTTP PID: $adminHttpPid (http://127.0.0.1:$AdminPort)" -ForegroundColor DarkGray

$adminTunnel = Start-TunnelJob -Name "admin" -LocalUrl "http://127.0.0.1:$AdminPort"
$adminUrl = Wait-TunnelUrl -LogFile $adminTunnel.Log
if (-not $adminUrl) {
    Write-Host "[WARN] Admin tunnel URL not detected." -ForegroundColor Yellow
    $adminUrl = "https://SEU-TUNNEL-ADMIN.trycloudflare.com"
}

$adminHost = if ($adminUrl -match 'https://([^/]+)') { $Matches[1] } else { "seu-tunnel-admin.trycloudflare.com" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " COEXISTENCE SESSION - COPIE NA META" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "APP ID:              873826165763092"
Write-Host "CONFIG ID:           2257921298375333"
Write-Host "VERIFY TOKEN:        super-secret-webhook-token"
Write-Host ""
Write-Host "DOMINIO ADMIN (App Domains + JS SDK):" -ForegroundColor Cyan
Write-Host "  $adminHost"
Write-Host ""
Write-Host "REDIRECT URI (Facebook Login for Business):" -ForegroundColor Cyan
Write-Host "  $adminUrl/"
Write-Host ""
Write-Host "WEBHOOK CALLBACK URL:" -ForegroundColor Cyan
Write-Host "  $webhookUrl"
Write-Host ""
Write-Host "ABRIR PAINEL:" -ForegroundColor Cyan
Write-Host "  $adminUrl"
Write-Host ""
Write-Host "META LINKS:" -ForegroundColor Cyan
Write-Host "  https://developers.facebook.com/apps/873826165763092/settings/basic/"
Write-Host "  https://developers.facebook.com/apps/873826165763092/fb-login/settings/"
Write-Host "  https://developers.facebook.com/apps/873826165763092/whatsapp-business/wa-settings/"
Write-Host ""
Write-Host "LOGIN: admin@bellamassa.com.br | tenant pizzaria_bella_massa"
Write-Host "Backoffice -> WhatsApp -> Assistente coexistencia -> etapa Conectar"
Write-Host ""
Write-Host "Tunnels PID: backend=$($backendTunnel.Pid) gateway=$($gatewayTunnel.Pid) admin=$($adminTunnel.Pid)"
Write-Host "Admin HTTP PID: $adminHttpPid"
Write-Host "Logs: $logDir"
Write-Host "Press Ctrl+C to stop (tunnels keep running until killed)." -ForegroundColor DarkGray
Write-Host ""

try {
    if ($adminUrl -match '^https://') {
        Start-Process $adminUrl
        Start-Process "https://developers.facebook.com/apps/873826165763092/fb-login/settings/"
    }
} catch {}

Write-Host "Session ready. Tunnels running in background." -ForegroundColor Green
Write-Host "To stop tunnels later:" -ForegroundColor DarkGray
Write-Host "  Stop-Process -Id $($backendTunnel.Pid),$($gatewayTunnel.Pid),$($adminTunnel.Pid),$adminHttpPid -Force -ErrorAction SilentlyContinue"
