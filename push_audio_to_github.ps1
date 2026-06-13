# Script to push individual MP3 files to GitHub repo
# This makes each file accessible via raw.githubusercontent.com

$SourceDir = 'C:\Users\Mr WaGdI\Downloads\Compressed\googog'
$RepoUrl = 'https://github.com/mahfodqr/quran-app-files.git'
$CloneDir = Join-Path $PSScriptRoot 'temp_quran_repo'

Write-Host '========================================'
Write-Host '  Push Audio Files to GitHub'
Write-Host '========================================'
Write-Host ''

# Step 1: Clone the repo
if (Test-Path $CloneDir) {
    Write-Host 'Removing old temp directory...'
    Remove-Item $CloneDir -Recurse -Force
}

Write-Host 'Cloning repository...'
git clone $RepoUrl $CloneDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'ERROR: Failed to clone repo. Make sure git is installed and you have access.'
    exit 1
}

# Step 2: Create audio directory
$AudioDir = Join-Path $CloneDir 'audio'
if (-not (Test-Path $AudioDir)) {
    New-Item -ItemType Directory -Path $AudioDir | Out-Null
}

# Step 3: Copy MP3 files
$files = Get-ChildItem -Path $SourceDir -Filter '*.mp3'
Write-Host "Copying $($files.Count) MP3 files..."
foreach ($file in $files) {
    Copy-Item $file.FullName -Destination $AudioDir
}
Write-Host 'Copy complete!'

# Step 4: Git add, commit, push
Set-Location $CloneDir
Write-Host ''
Write-Host 'Adding files to git...'
git add audio/
Write-Host 'Committing...'
git commit -m 'Add Quran audio files (Al-Huthaifi)'
Write-Host ''
Write-Host 'Pushing to GitHub (this will take a while - 1GB of files)...'
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ''
    Write-Host '========================================'
    Write-Host '  SUCCESS! Files pushed to GitHub'
    Write-Host '========================================'
    Write-Host ''
    Write-Host 'Files are now accessible at:'
    Write-Host 'https://raw.githubusercontent.com/mahfodqr/quran-app-files/main/audio/SSSAAA.mp3'
} else {
    Write-Host ''
    Write-Host 'ERROR: Push failed. Check your git credentials.'
}

# Cleanup
Set-Location $PSScriptRoot
