$SourceDir = 'C:\Users\Mr WaGdI\Downloads\Compressed\googog'
$OutputZip = '.\quran_audio.zip'

Write-Host '========================================'
Write-Host '  Quran Audio Packaging Script'
Write-Host '========================================'
Write-Host ''

if (-not (Test-Path $SourceDir)) {
    Write-Host 'ERROR: Source directory not found'
    exit 1
}

$files = Get-ChildItem -Path $SourceDir -Filter '*.mp3'
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
Write-Host "Found $($files.Count) MP3 files"
Write-Host "Total size: $([math]::Round($totalSize / 1MB, 2)) MB"
Write-Host ''

if (Test-Path $OutputZip) {
    Write-Host 'Removing existing zip file...'
    Remove-Item $OutputZip -Force
}

Write-Host 'Creating zip archive (this may take several minutes)...'
$startTime = Get-Date

Compress-Archive -Path (Join-Path $SourceDir '*.mp3') -DestinationPath $OutputZip -CompressionLevel Optimal

$elapsed = (Get-Date) - $startTime
$zipSize = (Get-Item $OutputZip).Length

Write-Host ''
Write-Host '========================================'
Write-Host '  ZIP CREATED SUCCESSFULLY!'
Write-Host '========================================'
Write-Host ''
Write-Host "Output: $OutputZip"
Write-Host "Zip size: $([math]::Round($zipSize / 1MB, 2)) MB"
Write-Host "Time: $([math]::Round($elapsed.TotalSeconds, 1)) seconds"
Write-Host ''

Write-Host 'Calculating SHA-256 hash...'
$hash = (Get-FileHash -Path $OutputZip -Algorithm SHA256).Hash.ToLower()
Write-Host ''
Write-Host "SHA-256: $hash"
Write-Host ''
Write-Host 'DONE! Now upload quran_audio.zip to GitHub Releases'
Write-Host 'Then paste the SHA-256 hash into audio_files_service.dart line 115'
Write-Host ''
