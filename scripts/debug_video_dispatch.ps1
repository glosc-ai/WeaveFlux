param(
    [string]$BaseUrl = "",
    [string]$ApiKey = "",
    [string]$Model = "",
    [string]$Prompt = "",
    [string]$Size = "1024x576",
    [double]$MotionScale = 0.5,
    [string]$ImagePath = ""
)

$ErrorActionPreference = "Stop"

function Read-SecretPlainText {
    param([string]$Prompt)

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Normalize-BaseUrl {
    param([string]$Value)
    $trimmed = $Value.Trim()
    while ($trimmed.EndsWith("/")) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }
    $trimmed
}

function Protect-Key {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "<empty>"
    }
    if ($Value.Length -le 12) {
        return "***"
    }
    return $Value.Substring(0, 6) + "..." + $Value.Substring($Value.Length - 4)
}

function To-PrettyJson {
    param($Value)
    $Value | ConvertTo-Json -Depth 20
}

function Invoke-DebugPost {
    param(
        [string]$Label,
        [string]$Url,
        [hashtable]$Headers,
        $BodyObject
    )

    $bodyJson = $BodyObject | ConvertTo-Json -Depth 20 -Compress
    $bodyPretty = $BodyObject | ConvertTo-Json -Depth 20

    Write-Host ""
    Write-Host "==== $Label ===="
    Write-Host "POST $Url"
    Write-Host "Headers:"
    Write-Host ("  Authorization: Bearer {0}" -f (Protect-Key $ApiKey))
    Write-Host "  Content-Type: application/json"
    Write-Host "Request body:"
    Write-Host $bodyPretty
    Write-Host ""
    Write-Host "Sending..."

    try {
        $response = Invoke-WebRequest `
            -Method Post `
            -Uri $Url `
            -Headers $Headers `
            -Body $bodyJson `
            -ContentType "application/json" `
            -TimeoutSec 120 `
            -ErrorAction Stop

        Write-Host "Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
        Write-Host "Response headers:"
        $response.Headers.GetEnumerator() |
            Sort-Object Key |
            ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Key, ($_.Value -join ", ")) }
        Write-Host "Response body:"
        Write-Host $response.Content
    }
    catch {
        Write-Host "Request failed" -ForegroundColor Red
        if ($_.Exception.Response) {
            $resp = $_.Exception.Response
            Write-Host "Status: $([int]$resp.StatusCode) $($resp.StatusDescription)" -ForegroundColor Red
            Write-Host "Response headers:"
            $resp.Headers.GetEnumerator() |
                Sort-Object Key |
                ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Key, ($_.Value -join ", ")) }
        }
        else {
            Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red
        }

        if ($_.ErrorDetails.Message) {
            Write-Host "Response body:"
            Write-Host $_.ErrorDetails.Message
        }
    }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $inputBaseUrl = Read-Host -Prompt "Base URL [https://one.gloscai.com/v1]"
    if ([string]::IsNullOrWhiteSpace($inputBaseUrl)) {
        $BaseUrl = "https://one.gloscai.com/v1"
    }
    else {
        $BaseUrl = $inputBaseUrl
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = Read-SecretPlainText "API Key"
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = Read-Host -Prompt "Video model"
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = Read-Host -Prompt "Prompt"
}

$inputSize = Read-Host -Prompt "Size [$Size]"
if (-not [string]::IsNullOrWhiteSpace($inputSize)) {
    $Size = $inputSize
}

$inputMotion = Read-Host -Prompt "Motion scale [$MotionScale]"
if (-not [string]::IsNullOrWhiteSpace($inputMotion)) {
    $MotionScale = [double]$inputMotion
}

if ([string]::IsNullOrWhiteSpace($ImagePath)) {
    $ImagePath = Read-Host -Prompt "Optional image path for I2V [leave empty for T2V]"
}

$BaseUrl = Normalize-BaseUrl $BaseUrl
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "API Key is empty." }
if ([string]::IsNullOrWhiteSpace($Model)) { throw "Model is empty." }
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw "Prompt is empty." }

$imageBase64 = ""
if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
    if (-not (Test-Path -LiteralPath $ImagePath)) {
        throw "Image path does not exist: $ImagePath"
    }
    $imageBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ImagePath))
}

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

$videoBody = [ordered]@{
    model = $Model
    prompt = $Prompt
    size = $Size
    motion_scale = $MotionScale
}
if ($imageBase64.Length -gt 0) {
    $videoBody.image = "<base64 omitted; length=$($imageBase64.Length)>"
}

$actualVideoBody = [ordered]@{
    model = $Model
    prompt = $Prompt
    size = $Size
    motion_scale = $MotionScale
}
if ($imageBase64.Length -gt 0) {
    $actualVideoBody.image = $imageBase64
}

$chatText = "$Prompt`n`nVideo generation parameters:`nsize: $Size`nmotion_scale: $MotionScale"
if ($imageBase64.Length -gt 0) {
    $chatContent = @(
        [ordered]@{ type = "text"; text = $chatText },
        [ordered]@{ type = "image_url"; image_url = [ordered]@{ url = "data:image/jpeg;base64,<base64 omitted; length=$($imageBase64.Length)>" } }
    )
    $actualChatContent = @(
        [ordered]@{ type = "text"; text = $chatText },
        [ordered]@{ type = "image_url"; image_url = [ordered]@{ url = "data:image/jpeg;base64,$imageBase64" } }
    )
}
else {
    $chatContent = $chatText
    $actualChatContent = $chatText
}

$chatBody = [ordered]@{
    model = $Model
    messages = @(
        [ordered]@{
            role = "user"
            content = $chatContent
        }
    )
    size = $Size
    motion_scale = $MotionScale
}

$actualChatBody = [ordered]@{
    model = $Model
    messages = @(
        [ordered]@{
            role = "user"
            content = $actualChatContent
        }
    )
    size = $Size
    motion_scale = $MotionScale
}

Write-Host ""
Write-Host "This script prints request/response data. API Key is redacted; image Base64 is omitted in printed body."

Invoke-DebugPost `
    -Label "/video/generations body used by Go core" `
    -Url "$BaseUrl/video/generations" `
    -Headers $headers `
    -BodyObject $actualVideoBody

Invoke-DebugPost `
    -Label "/videos/generations compatibility body" `
    -Url "$BaseUrl/videos/generations" `
    -Headers $headers `
    -BodyObject $actualVideoBody

Write-Host ""
Write-Host "Printed body for /video(s)/generations with image redacted, if present:"
Write-Host (To-PrettyJson $videoBody)

Invoke-DebugPost `
    -Label "/chat/completions fallback body used by Go core" `
    -Url "$BaseUrl/chat/completions" `
    -Headers $headers `
    -BodyObject $actualChatBody

Write-Host ""
Write-Host "Printed body for /chat/completions with image redacted, if present:"
Write-Host (To-PrettyJson $chatBody)

Write-Host ""
Write-Host "Done. API Key was read only in-memory and was not written to disk."
