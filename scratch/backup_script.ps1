$temp = "backups\temp_backup"
New-Item -ItemType Directory -Force -Path $temp | Out-Null
robocopy . $temp /MIR /XD build .dart_tool .git .idea "android\.gradle" __pycache__ "windows\flutter\ephemeral" backups temp_quran_repo /XF *.zip *.exe *.apk | Out-Null
if ($LASTEXITCODE -le 7) {
    tar.exe -a -c -f "backups\quran_app_FULL_backup_2026_05_07_clean.zip" -C $temp .
}
Remove-Item $temp -Recurse -Force
