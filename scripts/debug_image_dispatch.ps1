param(
    [string]$BaseUrl = "",
    [string]$ApiKey = "",
    [string]$Model = "",
    [string]$Prompt = "",
    [string]$Size = "1024x1024",
    [string]$Quality = "standard",
    [int]$Count = 1,
    [string]$NegativePrompt = "",
    [string]$Seed = "",
    [string]$ReferenceImagePath = "",
    [int]$TimeoutSec = 180
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

function Convert-FileToDataUrl {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Reference image path does not exist: $Path"
    }

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $mimeType = switch ($extension) {
        ".png" { "image/png" }
        ".webp" { "image/webp" }
        default { "image/jpeg" }
    }
    $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
    "data:$mimeType;base64,$base64"
}

function Redact-Body {
    param($BodyObject)

    $json = $BodyObject | ConvertTo-Json -Depth 30
    $json = $json -replace 'data:image/[^"]+', '<image data url omitted>'
    $json = $json -replace '"b64_json"\s*:\s*"[^"]+"', '"b64_json": "<base64 omitted>"'
    $json
}

function Write-Headers {
    param($Headers)

    if ($null -eq $Headers) {
        return
    }
    $Headers.GetEnumerator() |
        Sort-Object Key |
        ForEach-Object {
            $value = $_.Value
            if ($value -is [array]) {
                $value = $value -join ", "
            }
            Write-Host ("  {0}: {1}" -f $_.Key, $value)
        }
}

function Invoke-DebugPost {
    param(
        [string]$Label,
        [string]$Url,
        [hashtable]$Headers,
        $BodyObject,
        [int]$TimeoutSec
    )

    $bodyJson = $BodyObject | ConvertTo-Json -Depth 30 -Compress

    Write-Host ""
    Write-Host "==== $Label ===="
    Write-Host "POST $Url"
    Write-Host "Headers:"
    Write-Host ("  Authorization: Bearer {0}" -f (Protect-Key $ApiKey))
    Write-Host "  Content-Type: application/json"
    Write-Host "Request body:"
    Write-Host (Redact-Body $BodyObject)
    Write-Host ""
    Write-Host "Sending..."

    try {
        $response = Invoke-WebRequest `
            -Method Post `
            -Uri $Url `
            -Headers $Headers `
            -Body $bodyJson `
            -ContentType "application/json" `
            -TimeoutSec $TimeoutSec `
            -UseBasicParsing `
            -ErrorAction Stop

        Write-Host "Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
        Write-Host "Response headers:"
        Write-Headers $response.Headers
        Write-Host "Response body:"
        Write-Host $response.Content
        return
    }
    catch {
        Write-Host "Request failed" -ForegroundColor Red
        if ($_.Exception.Response) {
            $resp = $_.Exception.Response
            Write-Host "Status: $([int]$resp.StatusCode) $($resp.StatusDescription)" -ForegroundColor Red
            Write-Host "Response headers:"
            Write-Headers $resp.Headers
        }
        else {
            Write-Host "Exception: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
        }

        if ($_.ErrorDetails.Message) {
            Write-Host "Response body:"
            Write-Host $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object IO.StreamReader($stream)
                    $content = $reader.ReadToEnd()
                    if ($content) {
                        Write-Host "Response body:"
                        Write-Host $content
                    }
                }
            }
            catch {
                Write-Host "Failed to read error response body: $($_.Exception.Message)"
            }
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
    $Model = Read-Host -Prompt "Image model"
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = Read-Host -Prompt "Prompt"
}

$inputSize = Read-Host -Prompt "Size [$Size]"
if (-not [string]::IsNullOrWhiteSpace($inputSize)) {
    $Size = $inputSize
}

$inputQuality = Read-Host -Prompt "Quality [$Quality]"
if (-not [string]::IsNullOrWhiteSpace($inputQuality)) {
    $Quality = $inputQuality
}

$inputCount = Read-Host -Prompt "Count [$Count]"
if (-not [string]::IsNullOrWhiteSpace($inputCount)) {
    $Count = [int]$inputCount
}

if ([string]::IsNullOrWhiteSpace($NegativePrompt)) {
    $NegativePrompt = Read-Host -Prompt "Negative prompt [optional]"
}

if ([string]::IsNullOrWhiteSpace($Seed)) {
    $Seed = Read-Host -Prompt "Seed [optional]"
}

if ([string]::IsNullOrWhiteSpace($ReferenceImagePath)) {
    $ReferenceImagePath = Read-Host -Prompt "Reference image path for image-to-image [optional]"
}

$BaseUrl = Normalize-BaseUrl $BaseUrl
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "API Key is empty." }
if ([string]::IsNullOrWhiteSpace($Model)) { throw "Model is empty." }
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw "Prompt is empty." }
if ($Count -le 0) { $Count = 1 }

$imageDataUrl = Convert-FileToDataUrl -Path $ReferenceImagePath

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

$imageBody = [ordered]@{
    model = $Model
    prompt = $Prompt
    size = $Size
    quality = $Quality
    n = $Count
}
if (-not [string]::IsNullOrWhiteSpace($NegativePrompt)) {
    $imageBody.negative_prompt = $NegativePrompt
}
if (-not [string]::IsNullOrWhiteSpace($Seed)) {
    $imageBody.seed = $Seed
}
if (-not [string]::IsNullOrWhiteSpace($imageDataUrl)) {
    $imageBody.image = $imageDataUrl
}

$chatPromptParts = @(
    $Prompt,
    "",
    "Image generation parameters:",
    "size: $Size",
    "quality: $Quality",
    "count: $Count"
)
if (-not [string]::IsNullOrWhiteSpace($NegativePrompt)) {
    $chatPromptParts += "negative_prompt: $NegativePrompt"
}
if (-not [string]::IsNullOrWhiteSpace($Seed)) {
    $chatPromptParts += "seed: $Seed"
}
$chatText = $chatPromptParts -join "`n"

$chatContent = @(
    [ordered]@{ type = "text"; text = $chatText }
)
if (-not [string]::IsNullOrWhiteSpace($imageDataUrl)) {
    $chatContent += [ordered]@{ type = "image_url"; image_url = [ordered]@{ url = $imageDataUrl } }
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
    quality = $Quality
    n = $Count
}

Write-Host ""
Write-Host "This script prints image-generation request/response data."
Write-Host "API Key is redacted; reference image Base64 is omitted in printed body."
Write-Host "It mirrors WeaveFlux Go core: /images/generations first, /images/generations/ second, /chat/completions fallback third."

Invoke-DebugPost `
    -Label "/images/generations body used by Go core" `
    -Url "$BaseUrl/images/generations" `
    -Headers $headers `
    -BodyObject $imageBody `
    -TimeoutSec $TimeoutSec

Invoke-DebugPost `
    -Label "/images/generations/ compatibility body" `
    -Url "$BaseUrl/images/generations/" `
    -Headers $headers `
    -BodyObject $imageBody `
    -TimeoutSec $TimeoutSec

Invoke-DebugPost `
    -Label "/chat/completions fallback body used by Go core" `
    -Url "$BaseUrl/chat/completions" `
    -Headers $headers `
    -BodyObject $chatBody `
    -TimeoutSec $TimeoutSec

Write-Host ""
Write-Host "Done. API Key was read only in-memory and was not written to disk."
