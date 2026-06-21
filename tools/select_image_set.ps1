<#
.SYNOPSIS
  Swap which Qur'an page-image set is bundled in the app.

.DESCRIPTION
  The app bundles exactly ONE set of page_*.webp images under assets/images/
  (alongside the icons). The other set is parked, un-bundled, under image_sets/.
  This script moves files between those two locations so the build stays small.

    high_fidelity : ~92 MB, less compressed (ships by default, no download)
    standard      : ~24 MB, lighter (legacy; pairs with the download model)

  After switching, also set the matching flag in lib/config/image_config.dart:
    high_fidelity -> const kBundleHighFidelityImages = true;
    standard      -> const kBundleHighFidelityImages = false;

.EXAMPLE
  pwsh tools/select_image_set.ps1 -Set standard
  pwsh tools/select_image_set.ps1 -Set high_fidelity
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('standard', 'high_fidelity')]
  [string]$Set
)

$ErrorActionPreference = 'Stop'
$root        = Split-Path $PSScriptRoot -Parent
$images      = Join-Path $root 'assets\images'
$archiveRoot = Join-Path $root 'image_sets'
$marker      = Join-Path $archiveRoot '.active_set'

New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null

# Which set is currently bundled in assets/images? Default assumption: high_fidelity.
$current = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { 'high_fidelity' }

if ($current -eq $Set) {
  Write-Host "Image set '$Set' is already the active (bundled) set. Nothing to do."
  exit 0
}

$source = Join-Path $archiveRoot $Set
$sourcePages = @(Get-ChildItem $source -Filter 'page_*.webp' -ErrorAction SilentlyContinue)
if ($sourcePages.Count -eq 0) {
  throw "No page_*.webp found in '$source'. Cannot switch to '$Set'."
}

# 1. Park the currently-bundled pages into their archive folder.
$park = Join-Path $archiveRoot $current
New-Item -ItemType Directory -Force -Path $park | Out-Null
$activePages = @(Get-ChildItem $images -Filter 'page_*.webp' -ErrorAction SilentlyContinue)
if ($activePages.Count -gt 0) {
  Write-Host "Parking $($activePages.Count) '$current' pages -> image_sets/$current ..."
  $activePages | Move-Item -Destination $park -Force
}

# 2. Bring the requested set into the bundle.
Write-Host "Activating $($sourcePages.Count) '$Set' pages -> assets/images ..."
$sourcePages | Move-Item -Destination $images -Force

Set-Content -Path $marker -Value $Set -Encoding ascii

$flag = if ($Set -eq 'high_fidelity') { 'true' } else { 'false' }
$count = @(Get-ChildItem $images -Filter 'page_*.webp').Count
$sizeMb = '{0:N1}' -f ((Get-ChildItem $images -Filter 'page_*.webp' | Measure-Object Length -Sum).Sum / 1MB)
Write-Host ""
Write-Host "Done. Bundled set is now '$Set' — $count pages, $sizeMb MB."
Write-Host "NEXT: set 'const kBundleHighFidelityImages = $flag;' in lib/config/image_config.dart"
