# package.ps1
# Creates a versioned CurseForge zip in the WoW AddOns folder.
# Triggered automatically by .githooks/post-commit.

# 1. Resolve Repo Root correctly
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$RepoRoot = (Get-Item $RepoRoot).FullName
Write-Host "Repo Root: $RepoRoot" -ForegroundColor Cyan

# 2. Find .toc to get Addon Name
$tocFile = Get-ChildItem -Path $RepoRoot -Filter "*.toc" | Select-Object -First 1
if (-not $tocFile) {
    Write-Host "Error: No .toc file found in $RepoRoot" -ForegroundColor Red
    exit 1
}
$addonName = $tocFile.BaseName
Write-Host "Addon Name: $addonName" -ForegroundColor Yellow

# 3. Get Git Hash
Push-Location $RepoRoot
$hash = git rev-parse --short HEAD 2>$null
Pop-Location
if ($LASTEXITCODE -ne 0 -or -not $hash) {
    Write-Host "Warning: Could not get git hash. ZIP will not be versioned." -ForegroundColor Yellow
    $hash = "dev"
} else {
    $hash = $hash.Trim()
}
Write-Host "Commit Hash: $hash" -ForegroundColor Yellow

# 4. Resolve WoW AddOns path
$wowPathsFile = Join-Path $RepoRoot "wow_paths.json"
$wowAddonsPath = $null

if (Test-Path $wowPathsFile) {
    $config = Get-Content $wowPathsFile -Raw | ConvertFrom-Json
    if ($config.wowAddonPath -and (Test-Path $config.wowAddonPath)) {
        $wowAddonsPath = $config.wowAddonPath
    }
}

if (-not $wowAddonsPath) {
    $defaultPath = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns"
    if (Test-Path $defaultPath) {
        $wowAddonsPath = $defaultPath
    }
}

if (-not $wowAddonsPath) {
    Write-Host "Error: WoW AddOns folder not found. Check wow_paths.json." -ForegroundColor Red
    exit 1
}
Write-Host "Target AddOns Folder: $wowAddonsPath" -ForegroundColor Cyan

# 5. Cleanup Stale Zips
Write-Host "Cleaning up stale zips..." -ForegroundColor Gray
Get-ChildItem -Path $wowAddonsPath -Filter "$addonName-*.zip" | Remove-Item -Force -ErrorAction SilentlyContinue

# 6. Verify Deployed Folder exists
$addonSource = Join-Path $wowAddonsPath $addonName
if (-not (Test-Path $addonSource)) {
    Write-Host "Error: Deployed folder '$addonSource' not found. Run deploy.ps1 first." -ForegroundColor Red
    exit 1
}

# 7. Create Zip
$zipPath = Join-Path $wowAddonsPath "$addonName-$hash.zip"
Write-Host "Creating Zip: $zipPath" -ForegroundColor Green

# Stage to Temp to ensure clean structure <AddonName>/<files>
$tempStaging = Join-Path $env:TEMP "eq_pkg_$addonName"
if (Test-Path $tempStaging) { Remove-Item $tempStaging -Recurse -Force }
New-Item -ItemType Directory -Path $tempStaging | Out-Null

$stagingAddon = Join-Path $tempStaging $addonName
Copy-Item -Path $addonSource -Destination $stagingAddon -Recurse -Force

Compress-Archive -Path "$stagingAddon" -DestinationPath $zipPath -CompressionLevel Fastest -Force

Remove-Item $tempStaging -Recurse -Force

Write-Host "✅ Packaging Complete!" -ForegroundColor Green
