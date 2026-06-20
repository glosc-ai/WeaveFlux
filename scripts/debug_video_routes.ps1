param(
    [string]$BaseUrl = "",
    [string]$ApiKey = "",
    [string]$Model = "",
    [string]$Prompt = "",
    [string]$Size = "1024x576",
    [ValidateSet("ti2vid", "keyframes")]
    [string]$Mode = "ti2vid",
    [double]$MotionScale = 0.5,
    [int]$Duration = 5,
    [string]$FirstFramePath = "",
    [string]$LastFramePath = "",
    [switch]$SkipChatFallback
)

$ErrorActionPreference = "Stop"

function Read-SecretPlainText {
    param([string]$PromptText)

    $secure = Read-Host -Prompt $PromptText -AsSecureString
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
    if ([string]::IsNullOrWhiteSpace($Value)) { return "<empty>" }
    if ($Value.Length -le 12) { return "***" }
    return $Value.Substring(0, 6) + "..." + $Value.Substring($Value.Length - 4)
}

function Convert-FileToDataUrl {
    param(
        [string]$Path,
        [string]$MimeType
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File does not exist: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    "data:$MimeType;base64,$([Convert]::ToBase64String($bytes))"
}

function Redact-Body {
    param($BodyObject)
    $json = $BodyObject | ConvertTo-Json -Depth 30
    $json = $json -replace 'data:image/[^"]+', '<image data url omitted>'
    $json = $json -replace 'data:video/[^"]+', '<video data url omitted>'
    $json
}

function Try-ExtractTaskId {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return "" }
    try {
        $json = $Body | ConvertFrom-Json -ErrorAction Stop
        foreach ($name in @("task_id", "taskId", "id")) {
            if ($json.PSObject.Properties.Name -contains $name) {
                $value = [string]$json.$name
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        }
        if ($json.data) {
            foreach ($name in @("task_id", "taskId", "id")) {
                if ($json.data.PSObject.Properties.Name -contains $name) {
                    $value = [string]$json.data.$name
                    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
                }
            }
        }
    }
    catch {
        # Fall through to regex extraction.
    }

    $match = [regex]::Match($Body, '(?i)"(?:task_id|taskId|id)"\s*:\s*"([^"]+)"')
    if ($match.Success) { return $match.Groups[1].Value }
    ""
}

function Invoke-DebugPost {
    param(
        [string]$Label,
        [string]$Path,
        [hashtable]$Headers,
        $BodyObject
    )

    $url = "$BaseUrl$Path"
    $bodyJson = $BodyObject | ConvertTo-Json -Depth 30 -Compress

    Write-Host ""
    Write-Host "==== POST $Path :: $Label ====" -ForegroundColor Cyan
    Write-Host "URL: $url"
    Write-Host "Authorization: Bearer $(Protect-Key $ApiKey)"
    Write-Host "Content-Type: application/json"
    Write-Host "Request body:"
    Write-Host (Redact-Body $BodyObject)

    $result = [ordered]@{
        path = $Path
        ok = $false
        status = ""
        body = ""
        task_id = ""
    }

    try {
        $response = Invoke-WebRequest `
            -Method Post `
            -Uri $url `
            -Headers $Headers `
            -Body $bodyJson `
            -ContentType "application/json" `
            -TimeoutSec 180 `
            -ErrorAction Stop

        $result.ok = $true
        $result.status = "$($response.StatusCode) $($response.StatusDescription)"
        $result.body = [string]$response.Content
        $result.task_id = Try-ExtractTaskId $result.body

        Write-Host "Status: $($result.status)" -ForegroundColor Green
        Write-Host "Response body:"
        Write-Host $result.body
        if ($result.task_id) {
            Write-Host "Extracted task_id: $($result.task_id)" -ForegroundColor Green
        }
    }
    catch {
        if ($_.Exception.Response) {
            $resp = $_.Exception.Response
            $result.status = "$([int]$resp.StatusCode) $($resp.StatusDescription)"
            Write-Host "Status: $($result.status)" -ForegroundColor Red
        }
        else {
            $result.status = "Exception"
            Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red
        }

        if ($_.ErrorDetails.Message) {
            $result.body = [string]$_.ErrorDetails.Message
            $result.task_id = Try-ExtractTaskId $result.body
            Write-Host "Response body:"
            Write-Host $result.body
        }
    }

    [pscustomobject]$result
}

function Invoke-DebugGet {
    param(
        [string]$Path,
        [hashtable]$Headers
    )

    $url = "$BaseUrl$Path"
    Write-Host ""
    Write-Host "==== GET $Path ====" -ForegroundColor Cyan
    Write-Host "URL: $url"
    Write-Host "Authorization: Bearer $(Protect-Key $ApiKey)"

    try {
        $response = Invoke-WebRequest `
            -Method Get `
            -Uri $url `
            -Headers $Headers `
            -TimeoutSec 120 `
            -ErrorAction Stop

        Write-Host "Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
        Write-Host "Response body:"
        Write-Host $response.Content
    }
    catch {
        if ($_.Exception.Response) {
            $resp = $_.Exception.Response
            Write-Host "Status: $([int]$resp.StatusCode) $($resp.StatusDescription)" -ForegroundColor Red
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
    $BaseUrl = if ([string]::IsNullOrWhiteSpace($inputBaseUrl)) { "https://one.gloscai.com/v1" } else { $inputBaseUrl }
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

$BaseUrl = Normalize-BaseUrl $BaseUrl
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "API Key is empty." }
if ([string]::IsNullOrWhiteSpace($Model)) { throw "Model is empty." }
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw "Prompt is empty." }

$firstFrame = Convert-FileToDataUrl -Path $FirstFramePath -MimeType "image/jpeg"
$lastFrame = Convert-FileToDataUrl -Path $LastFramePath -MimeType "image/jpeg"

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

$videoBody = [ordered]@{
    model = $Model
    prompt = $Prompt
    size = $Size
    mode = $Mode
    motion_scale = $MotionScale
    duration = $Duration
}
if ($firstFrame) { $videoBody.image = $firstFrame }
if ($lastFrame) { $videoBody.last_frame_image = $lastFrame }

$chatText = @"
$Prompt

Video generation parameters:
mode: $Mode
size: $Size
motion_scale: $MotionScale
duration: $Duration
"@

$chatBody = [ordered]@{
    model = $Model
    messages = @(
        [ordered]@{
            role = "user"
            content = $chatText
        }
    )
    size = $Size
    mode = $Mode
    motion_scale = $MotionScale
}

Write-Host ""
Write-Host "This script prints route-level request/response diagnostics. API Key is redacted." -ForegroundColor Yellow
Write-Host "BaseUrl: $BaseUrl"
Write-Host "Model: $Model"
Write-Host "Mode: $Mode"

$results = @()
$results += Invoke-DebugPost -Label "new-api task route from router/video-router.go" -Path "/video/generations" -Headers $headers -BodyObject $videoBody
$results += Invoke-DebugPost -Label "plural task route from router/video-router.go" -Path "/videos/generations" -Headers $headers -BodyObject $videoBody
$results += Invoke-DebugPost -Label "OpenAI-compatible videos route from router/video-router.go" -Path "/videos" -Headers $headers -BodyObject $videoBody
if (-not $SkipChatFallback) {
    $results += Invoke-DebugPost -Label "chat fallback currently used by app" -Path "/chat/completions" -Headers $headers -BodyObject $chatBody
}

$taskId = ($results | Where-Object { -not [string]::IsNullOrWhiteSpace($_.task_id) } | Select-Object -First 1).task_id
if ($taskId) {
    Write-Host ""
    Write-Host "Testing task fetch routes with task_id=$taskId" -ForegroundColor Yellow
    foreach ($path in @(
        "/video/generations/$taskId",
        "/videos/generations/$taskId",
        "/videos/$taskId",
        "/videos/$taskId/content",
        "/tasks/$taskId"
    )) {
        Invoke-DebugGet -Path $path -Headers $headers
    }
}
else {
    Write-Host ""
    Write-Host "No task_id extracted from any response. Compare the status/body above to identify whether the route, model, group, or payload is rejected." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
$results | ForEach-Object {
    Write-Host ("  {0,-24} {1} task_id={2}" -f $_.path, $_.status, $(if ($_.task_id) { $_.task_id } else { "<none>" }))
}

