# frame-shot-sync uninstaller (moves files aside; config and copied photos are kept)
# Usage: irm https://raw.githubusercontent.com/cympfh/frame-shot-sync/main/uninstall.ps1 | iex
$src = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/cympfh/frame-shot-sync/main/install.ps1'
& ([scriptblock]::Create($src)) -Uninstall
