function Resolve-GatewayUrl {
    param(
        [string]$Preferred = $(if ($env:GATEWAY_URL) { $env:GATEWAY_URL } else { "http://localhost:40000" })
    )

    function Test-GatewayHealth([string]$BaseUrl) {
        try {
            $health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 4
            return ($health.status -eq "healthy")
        } catch {
            return $false
        }
    }

    if (Test-GatewayHealth $Preferred) {
        return $Preferred
    }

    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InterfaceAlias -notmatch 'Loopback' -and
            ($_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or $_.IPAddress -like '172.*')
        } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if ($ip) {
        $alt = "http://${ip}:40000"
        if (Test-GatewayHealth $alt) {
            Write-Host "Gateway: using $alt (localhost:40000 may be cloudflared tunnel)" -ForegroundColor Yellow
            return $alt
        }
    }

    return $Preferred
}
