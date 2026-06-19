param(
    [string]$BaseUrl = "",
    [string]$ApiKey = ""
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

function Format-Categories {
    param($Categories)

    if ($null -eq $Categories) {
        return "<null>"
    }

    if ($Categories -is [array]) {
        return (($Categories | ForEach-Object { "$_" }) -join ", ")
    }

    if ($Categories -is [System.Collections.IDictionary] -or $Categories.PSObject.Properties.Count -gt 0) {
        return (($Categories | ConvertTo-Json -Compress -Depth 8))
    }

    "$Categories"
}

function Invoke-Models {
    param(
        [string]$Label,
        [string]$Url,
        [hashtable]$Headers
    )

    Write-Host ""
    Write-Host "==== $Label ===="
    Write-Host "GET $Url"

    try {
        $response = Invoke-RestMethod -Method Get -Uri $Url -Headers $Headers -TimeoutSec 60
    }
    catch {
        Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message
        }
        return
    }

    $items = @($response.data)
    Write-Host "Total models: $($items.Count)"

    $groups = $items |
        ForEach-Object {
            [PSCustomObject]@{
                Category = Format-Categories $_.categories
                Id = "$($_.id)"
            }
        } |
        Group-Object Category |
        Sort-Object Count -Descending

    Write-Host ""
    Write-Host "Category summary:"
    foreach ($group in $groups) {
        Write-Host ("{0,4}  {1}" -f $group.Count, $group.Name)
    }

    Write-Host ""
    Write-Host "Models:"
    $items |
        Sort-Object id |
        ForEach-Object {
            $id = "$($_.id)"
            $categories = Format-Categories $_.categories
            Write-Host ("- {0}    categories={1}" -f $id, $categories)
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

$BaseUrl = Normalize-BaseUrl $BaseUrl
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "API Key is empty."
}

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

Invoke-Models -Label "Plain /models" -Url "$BaseUrl/models" -Headers $headers
Invoke-Models -Label "/models?categories=video" -Url "$BaseUrl/models?categories=video" -Headers $headers

Write-Host ""
Write-Host "Done. API Key was read only in-memory and was not written to disk."
