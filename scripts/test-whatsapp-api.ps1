# WhatsApp Cloud API test suite (mirrors Meta Postman collection)
# Usage:
#   $env:META_ACCESS_TOKEN = "<System User token>"
#   powershell -ExecutionPolicy Bypass -File scripts/test-whatsapp-api.ps1
#
# Optional overrides:
#   $env:WABA_ID, $env:PHONE_NUMBER_ID, $env:RECIPIENT, $env:API_VERSION
#   $env:BACKEND_URL, $env:GATEWAY_URL, $env:WA_PIN (for /register)
#
# Note: if cloudflared tunnels localhost:40000, scripts auto-fallback to LAN IP for Docker gateway.

param(
    [string]$ApiVersion = $(if ($env:API_VERSION) { $env:API_VERSION } else { "v22.0" }),
    [string]$WabaId = $(if ($env:WABA_ID) { $env:WABA_ID } else { "507137542482993" }),
    [string]$PhoneNumberId = $(if ($env:PHONE_NUMBER_ID) { $env:PHONE_NUMBER_ID } else { "523040924230958" }),
    [string]$Recipient = $(if ($env:RECIPIENT) { $env:RECIPIENT } else { "5534992665547" }),
    [string]$TestWabaId = "27281965408107469",
    [string]$TestPhoneNumberId = "1201264079728608",
    [string]$BackendUrl = $(if ($env:BACKEND_URL) { $env:BACKEND_URL } else { "http://localhost:8000" }),
    [string]$GatewayUrl = $(if ($env:GATEWAY_URL) { $env:GATEWAY_URL } else { "http://localhost:40000" }),
    [string]$TenantId = "pizzaria_bella_massa",
    [switch]$SkipSend,
    [switch]$TryRegister,
    [switch]$UseTestAccount
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib/gateway-url.ps1")
$GatewayUrl = Resolve-GatewayUrl -Preferred $GatewayUrl
$token = $env:META_ACCESS_TOKEN
$pin = if ($env:WA_PIN) { $env:WA_PIN } else { "123456" }
$internalKey = if ($env:INTERNAL_API_KEY) { $env:INTERNAL_API_KEY } else { "internal-chatbot-key" }

if ($UseTestAccount) {
    $WabaId = $TestWabaId
    $PhoneNumberId = $TestPhoneNumberId
}

$base = "https://graph.facebook.com/$ApiVersion"
$passed = 0
$failed = 0
$warned = 0

function Write-Step([string]$Name, [string]$Status, [string]$Detail = "", [string]$Level = "info") {
    $icon = switch ($Status) {
        "PASS" { "[PASS]"; $script:passed++ }
        "FAIL" { "[FAIL]"; $script:failed++ }
        "WARN" { "[WARN]"; $script:warned++ }
        default { "[....]" }
    }
    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "$icon $Name" -ForegroundColor $color
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray }
}

function Invoke-GraphGet([string]$Path) {
    $uri = "$base/$Path"
    try {
        return @{ ok = $true; data = (Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 45) }
    } catch {
        return @{ ok = $false; error = $_.ErrorDetails.Message }
    }
}

function Invoke-GraphPost([string]$Path, [object]$Body) {
    $uri = "$base/$Path"
    try {
        $json = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 8 -Compress) }
        return @{
            ok = $true
            data = (Invoke-RestMethod -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } -Body $json -ContentType "application/json" -TimeoutSec 45)
        }
    } catch {
        return @{ ok = $false; error = $_.ErrorDetails.Message }
    }
}

Write-Host ""
Write-Host "=== WhatsApp Cloud API Test Suite ===" -ForegroundColor Cyan
Write-Host "API:      $ApiVersion"
Write-Host "WABA:     $WabaId"
Write-Host "Phone ID: $PhoneNumberId"
Write-Host "To:       $Recipient"
Write-Host ""

if (-not $token) {
    Write-Step "META_ACCESS_TOKEN" "FAIL" "Set `$env:META_ACCESS_TOKEN (System User token with whatsapp_business_messaging)"
    exit 1
}

# 1. Debug token scopes
$dbg = Invoke-GraphGet "debug_token?input_token=$token"
if ($dbg.ok) {
    $d = $dbg.data.data
    $scopes = ($d.scopes -join ", ")
    $granular = @()
    foreach ($g in $d.granular_scopes) {
        $ids = ($g.target_ids -join ",")
        $granular += "$($g.scope) -> [$ids]"
    }
    Write-Step "Debug token" "PASS" "app=$($d.app_id) valid=$($d.is_valid) scopes=$scopes"
    foreach ($line in $granular) {
        Write-Host "       $line" -ForegroundColor DarkGray
    }
    $hasWaba = $false
    foreach ($g in $d.granular_scopes) {
        if ($g.target_ids -contains $WabaId) { $hasWaba = $true }
    }
    if (-not $hasWaba -and $d.granular_scopes) {
        Write-Step "Token WABA scope" "WARN" "Token may not include WABA $WabaId - assign in Business Manager > System Users"
    } else {
        Write-Step "Token WABA scope" "PASS" "WABA $WabaId authorized"
    }
} else {
    Write-Step "Debug token" "FAIL" $dbg.error
}

# 2. List phone numbers on WABA
$list = Invoke-GraphGet "$WabaId/phone_numbers?fields=id,display_phone_number,status,platform_type,code_verification_status"
if ($list.ok) {
    $phones = @($list.data.data)
    Write-Step "GET WABA phone_numbers" "PASS" "$($phones.Count) number(s)"
    foreach ($p in $phones) {
        $line = "       {0} / {1} / {2} / id={3}" -f $p.display_phone_number, $p.status, $p.platform_type, $p.id
        Write-Host $line -ForegroundColor DarkGray
    }
} else {
    Write-Step "GET WABA phone_numbers" "FAIL" $list.error
}

# 3. Phone status + health
$phone = Invoke-GraphGet "$PhoneNumberId`?fields=display_phone_number,verified_name,status,platform_type,is_on_biz_app,health_status,code_verification_status"
if ($phone.ok) {
    $p = $phone.data
    Write-Step "GET phone status" "PASS" "$($p.display_phone_number) status=$($p.status) platform=$($p.platform_type)"
    if ($p.health_status) {
        Write-Host "       can_send_message: $($p.health_status.can_send_message)" -ForegroundColor DarkGray
    }
    if ($p.status -eq "DISCONNECTED" -or $p.status -eq "OFFLINE") {
        Write-Step "Phone connected" "WARN" "status=$($p.status) - complete Embedded Signup coexistence (QR on PC)"
    } elseif ($p.status -eq "CONNECTED") {
        Write-Step "Phone connected" "PASS" "CONNECTED"
    }
} else {
    Write-Step "GET phone status" "FAIL" $phone.error
}

# 4. Subscribe app to WABA
$sub = Invoke-GraphPost "$WabaId/subscribed_apps" "{}"
if ($sub.ok -and $sub.data.success) {
    Write-Step "POST subscribed_apps" "PASS" "Webhook subscription OK"
} else {
    Write-Step "POST subscribed_apps" "WARN" $(if ($sub.error) { $sub.error } else { "already subscribed or partial" })
}

# 5. Optional register (Cloud API only - fails for SMB coexistence)
if ($TryRegister) {
    $reg = Invoke-GraphPost "$PhoneNumberId/register" @{ messaging_product = "whatsapp"; pin = $pin }
    if ($reg.ok -and $reg.data.success) {
        Write-Step "POST register" "PASS" "PIN accepted"
    } else {
        $msg = if ($reg.error) { $reg.error } else { "unknown" }
        if ($msg -match "SMB") {
            Write-Step "POST register" "WARN" "SMB/coexistence - use Embedded Signup, not /register"
        } else {
            Write-Step "POST register" "FAIL" $msg
        }
    }
}

# 6. List templates
$tplPath = "$WabaId/message_templates?fields=name,language,status" + '&limit=25'
$tpl = Invoke-GraphGet $tplPath
$approvedTemplate = $null
if ($tpl.ok) {
    $templates = @($tpl.data.data)
    Write-Step "GET message_templates" "PASS" "$($templates.Count) template(s)"
    foreach ($t in $templates) {
        $tline = "       {0} / {1} / {2}" -f $t.name, $t.language, $t.status
        Write-Host $tline -ForegroundColor DarkGray
        $tStatus = [string]$t.status
        if (-not $approvedTemplate -and $tStatus.ToUpper() -eq "APPROVED") {
            $approvedTemplate = $t
        }
    }
    if (-not $approvedTemplate) {
        Write-Step "Approved template" "WARN" "No APPROVED template - create one or use hello_world after Meta adds it"
    }
} else {
    Write-Step "GET message_templates" "FAIL" $tpl.error
}

if ($SkipSend) {
    Write-Host ""
    Write-Host "Skipped send tests (-SkipSend)." -ForegroundColor Yellow
} else {
    # 7. Send template hello_world (common default)
    $tplBody = @{
        messaging_product = "whatsapp"
        to = $Recipient
        type = "template"
        template = @{
            name = "hello_world"
            language = @{ code = "en_US" }
        }
    }
    $sendTpl = Invoke-GraphPost "$PhoneNumberId/messages" $tplBody
    if ($sendTpl.ok -and $sendTpl.data.messages) {
        $mid = $sendTpl.data.messages[0].id
        Write-Step "POST messages (template hello_world)" "PASS" "message_id=$mid"
    } else {
        $err = if ($sendTpl.error) { $sendTpl.error } else { "no message id" }
        if ($err -match "133010") {
            Write-Step "POST messages (template hello_world)" "WARN" "#133010 not registered - coexistence QR required"
        } elseif ($err -match "130497") {
            Write-Step "POST messages (template hello_world)" "WARN" "#130497 region mismatch - use BR sender for BR recipient"
        } elseif ($err -match "131030") {
            Write-Step "POST messages (template hello_world)" "WARN" "#131030 recipient not in test list - add in API Setup > To"
        } else {
            Write-Step "POST messages (template hello_world)" "FAIL" $err
        }
    }

    # 8. Send via project gateway
    try {
        $gwBody = @{
            tenant_id = $TenantId
            to = $Recipient
            template_name = "hello_world"
            language_code = "en_US"
            phone_number_id = $PhoneNumberId
        } | ConvertTo-Json
        $gw = Invoke-RestMethod -Uri "$GatewayUrl/send-template" -Method Post -Headers @{ "x-internal-api-key" = $internalKey } -Body $gwBody -ContentType "application/json" -TimeoutSec 45
        if ($gw.ok -and $gw.message_id) {
            Write-Step "Gateway POST /send-template" "PASS" "message_id=$($gw.message_id)"
        } else {
            Write-Step "Gateway POST /send-template" "FAIL" ($gw | ConvertTo-Json -Compress)
        }
    } catch {
        $detail = $_.ErrorDetails.Message
        if ($detail -match "133010") {
            Write-Step "Gateway POST /send-template" "WARN" "#133010 - phone not registered on Cloud API"
        } else {
            Write-Step "Gateway POST /send-template" "FAIL" $detail
        }
    }

    # 9. Backend template send API
    try {
        $login = Invoke-RestMethod -Uri "$BackendUrl/api/v1/auth/login" -Method Post -Body '{"email":"admin@bellamassa.com.br","password":"Bella@2026!"}' -ContentType "application/json" -TimeoutSec 20
        $bh = @{ Authorization = "Bearer $($login.access_token)" }
        $bsend = @{
            account_key = $WabaId
            template_name = "hello_world"
            language = "en_US"
            to = $Recipient
        } | ConvertTo-Json
        $br = Invoke-RestMethod -Uri "$BackendUrl/api/v1/tenants/$TenantId/whatsapp-templates/send" -Method Post -Headers $bh -Body $bsend -ContentType "application/json" -TimeoutSec 45
        Write-Step "Backend POST /whatsapp-templates/send" "PASS" "message_id=$($br.message_id) to=$($br.to)"
    } catch {
        $detail = $_.ErrorDetails.Message
        if (-not $detail) { $detail = $_.Exception.Message }
        if ($detail -match '133010|not registered') {
            Write-Step "Backend POST /whatsapp-templates/send" "WARN" "Phone not registered - coexistence required"
        } elseif ($detail -match "APPROVED|nao encontrado") {
            Write-Step "Backend POST /whatsapp-templates/send" "WARN" $detail
        } else {
            Write-Step "Backend POST /whatsapp-templates/send" "FAIL" $detail
        }
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "  PASS: $passed  WARN: $warned  FAIL: $failed"
Write-Host ""
Write-Host "Postman collection: https://www.postman.com/meta/whatsapp-business-platform/collection/wlk6lh4/whatsapp-cloud-api" -ForegroundColor DarkGray
Write-Host ""

if ($failed -gt 0) { exit 1 }
exit 0
