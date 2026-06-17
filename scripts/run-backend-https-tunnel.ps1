# Expoe o backend API (porta 8000) em HTTPS para o admin tunelado chamar a API sem mixed-content.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/run-backend-https-tunnel.ps1
#
# Copie a URL https://....trycloudflare.com e use no admin:
#   scripts/run-admin-https-tunnel.ps1 -ApiBaseUrl "https://....trycloudflare.com"

param(
    [int]$Port = 8000
)

Write-Host ""
Write-Host "=== Backend API HTTPS Tunnel ===" -ForegroundColor Cyan
Write-Host "Certifique-se de que o backend esta em http://localhost:$Port (docker compose up)" -ForegroundColor Yellow
Write-Host ""

cloudflared tunnel --url "http://localhost:$Port"
