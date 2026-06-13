Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead('quran_audio.zip')
$entries = $zip.Entries | Sort-Object Name

Write-Host "Total files: $($entries.Count)"
Write-Host ""

Write-Host "=== First 20 files ==="
$entries | Select-Object -First 20 | ForEach-Object { Write-Host $_.Name }

Write-Host ""
Write-Host "=== Surah 5 (Al-Ma'idah) files ==="
$entries | Where-Object { $_.Name -like '005*' } | ForEach-Object { Write-Host $_.Name }

Write-Host ""
Write-Host "=== Surah 9 (At-Tawbah) files ==="
$entries | Where-Object { $_.Name -like '009*' } | ForEach-Object { Write-Host $_.Name }

Write-Host ""
Write-Host "=== File count per surah ==="
for ($s = 1; $s -le 114; $s++) {
    $prefix = $s.ToString().PadLeft(3, '0')
    $count = ($entries | Where-Object { $_.Name -like "$prefix*" }).Count
    Write-Host "Surah ${s}: $count files"
}

$zip.Dispose()
