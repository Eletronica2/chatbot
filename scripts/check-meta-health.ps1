# Check WhatsApp Cloud API health_status for a phone number ID
# Usage:
#   $env:META_ACCESS_TOKEN = "<token>"
#   powershell -ExecutionPolicy Bypass -File scripts/check-meta-health.ps1

param(
    [string]$PhoneNumberId = "1121301321069602",
    [string]$WabaId = "1651453995905846",
    [string]$ApiVersion = "v22.0"
)

$token = $env:META_ACCESS_TOKEN
if (-not $token) {
    Write-Host "[FAIL] Set META_ACCESS_TOKEN environment variable first." -ForegroundColor Red
    Write-Host "       Generate at: https://developers.facebook.com/apps/1009915888389805/whatsapp-business/wa-dev-console/"
    exit 1
}

Write-Host ""
Write-Host "=== Meta WhatsApp Health Check ===" -ForegroundColor Cyan
Write-Host "Phone Number ID: $PhoneNumberId"
Write-Host "WABA ID:         $WabaId"
Write-Host ""

function Invoke-MetaGet([string]$Path) {
    $uri = "https://graph.facebook.com/$ApiVersion/$Path"
    try {
        return Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
    } catch {
        $body = $_.ErrorDetails.Message
        Write-Host "[FAIL] GET $Path" -ForegroundColor Red
        if ($body) { Write-Host "       $body" -ForegroundColor DarkGray }
        return $null
    }
}

$phone = Invoke-MetaGet "$PhoneNumberId`?fields=health_status,display_phone_number,verified_name"
if ($phone) {
    Write-Host "[Phone] $($phone.display_phone_number) ($($phone.verified_name))" -ForegroundColor Green
    $hs = $phone.health_status
    if ($hs) {
        Write-Host "  can_send_message (overall): $($hs.can_send_message)"
        foreach ($entity in $hs.entities) {
            $color = if ($entity.can_send_message -eq "AVAILABLE") { "Green" } else { "Red" }
            Write-Host "  - $($entity.entity_type) $($entity.id): $($entity.can_send_message)" -ForegroundColor $color
            foreach ($err in ($entity.errors | ForEach-Object { $_ })) {
                Write-Host "      error $($err.error_code): $($err.error_description)" -ForegroundColor Yellow
                if ($err.possible_solution) {
                    Write-Host "      fix: $($err.possible_solution)" -ForegroundColor DarkGray
                }
            }
        }
    }
}

$waba = Invoke-MetaGet "$WabaId`?fields=health_status,name"
if ($waba) {
    Write-Host ""
    Write-Host "[WABA] $($waba.name)" -ForegroundColor Green
    if ($waba.health_status.can_send_message) {
        Write-Host "  can_send_message: $($waba.health_status.can_send_message)"
    }
}

Write-Host ""
Write-Host "Meta links:" -ForegroundColor Cyan
Write-Host "  Billing:          https://business.facebook.com/billing_hub/accounts"
Write-Host "  Support Home:     https://business.facebook.com/business-support-home"
Write-Host "  Account Quality:  https://business.facebook.com/accountquality"
Write-Host "  API Setup:        https://developers.facebook.com/apps/1009915888389805/whatsapp-business/wa-dev-console/"
Write-Host ""

if (-not $phone -or -not $phone.health_status) {
    Write-Host "Could not read health_status. Check META_ACCESS_TOKEN and Phone Number ID." -ForegroundColor Red
    exit 1
}

$wabaEntity = $phone.health_status.entities | Where-Object { $_.entity_type -eq "WABA" } | Select-Object -First 1
if ($wabaEntity -and $wabaEntity.can_send_message -eq "BLOCKED") {
    Write-Host "WABA sending is BLOCKED. Fix billing/errors above before recording videos." -ForegroundColor Red
    exit 1
}

if ($phone.health_status.can_send_message -eq "BLOCKED") {
    Write-Host "Sending is BLOCKED. Fix errors above before testing delivery." -ForegroundColor Red
    exit 1
}

Write-Host "Health check passed - WABA ready for business-initiated messages." -ForegroundColor Green
exit 0
