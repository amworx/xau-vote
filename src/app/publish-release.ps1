# Publishes a release manifest for the in-app updater.
#
#   powershell -ExecutionPolicy Bypass -File publish-release.ps1 `
#       -Apk build\app\outputs\flutter-apk\app-release.apk `
#       -Version 1.0.1 -VersionCode 2 -Notes "Fixes the market-status pill"
#
# Uploads the APK to the `app-releases` bucket, then records the manifest row
# the app reads.
#
# Requires SUPABASE_SERVICE_ROLE_KEY in the environment (or passed with
# -ServiceRoleKey). The service role is required because the bucket is
# public-read with no write policy: the publishable key ships inside the APK, so
# allowing it to write would let anyone who unzips the app replace the binary.
# The manifest row is only served after the client's SHA-256 check passes, so a
# swapped object still cannot be installed.
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][int]$VersionCode,
    [string]$Notes = '',
    [string]$SupabaseUrl = 'https://mfrzwmqgwgcyaxehdbqh.supabase.co',
    [string]$ServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY
)

$ErrorActionPreference = 'Stop'

if (-not $ServiceRoleKey) {
    throw 'Set SUPABASE_SERVICE_ROLE_KEY, or pass -ServiceRoleKey. The publishable key cannot write here by design.'
}

if (-not (Test-Path -LiteralPath $Apk)) {
    throw "APK not found: $Apk"
}

$apkItem = Get-Item -LiteralPath $Apk
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Apk).Hash.ToLower()
$fileName = "xv-$Version.apk"

Write-Host "Publishing $Version (code $VersionCode)"
Write-Host "  file : $fileName ($([math]::Round($apkItem.Length / 1MB, 1)) MB)"
Write-Host "  sha  : $sha"

# 1. Upload the APK. x-upsert makes re-publishing the same version safe.
$uploadUri = "$SupabaseUrl/storage/v1/object/app-releases/$fileName"
try {
    Invoke-WebRequest -Uri $uploadUri -Method Post -Headers @{
        Authorization = "Bearer $ServiceRoleKey"
        apikey         = $ServiceRoleKey
        'Content-Type' = 'application/vnd.android.package-archive'
        'x-upsert'     = 'true'
    } -InFile $apkItem.FullName -UseBasicParsing -TimeoutSec 1800 | Out-Null
    Write-Host '  uploaded'
} catch {
    throw "Upload failed: $($_.Exception.Message)"
}

# 2. Record the manifest. The digest must be the one just computed, so the
#    client's verification compares against the real bytes on the server.
$body = @{
    version     = $Version
    versionCode = $VersionCode
    apkUrl      = "$SupabaseUrl/storage/v1/object/public/app-releases/$fileName"
    sha256      = $sha
    sizeBytes   = $apkItem.Length
    notes       = $Notes
} | ConvertTo-Json

try {
    Invoke-WebRequest -Uri "$SupabaseUrl/rest/v1/app_releases" -Method Post -Headers @{
        Authorization = "Bearer $ServiceRoleKey"
        apikey         = $ServiceRoleKey
        'Content-Type' = 'application/json'
        Prefer         = 'return=representation'
    } -Body $body -UseBasicParsing -TimeoutSec 120 | Out-Null
    Write-Host '  manifest recorded'
} catch {
    throw "Manifest insert failed: $($_.Exception.Message)"
}

# 3. Confirm what the app will actually see.
try {
    $manifest = Invoke-RestMethod -Uri "$SupabaseUrl/functions/v1/app-release" -TimeoutSec 60
    Write-Host "  endpoint reports: $($manifest.version) (code $($manifest.versionCode))"
} catch {
    Write-Warning "  endpoint check failed: $($_.Exception.Message)"
}

Write-Host "Published. Apps on a lower build will offer $Version on the next manual check."