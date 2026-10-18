# SPDX-License-Identifier: MIT
# frame-shot-sync (Windows) installer. User space only, no admin, no autostart.
#   irm https://raw.githubusercontent.com/cympfh/frame-shot-sync/main/install.ps1 | iex
# Uninstall (moves files aside; config is kept):
#   irm https://raw.githubusercontent.com/cympfh/frame-shot-sync/main/uninstall.ps1 | iex
param([switch]$Uninstall)
$ErrorActionPreference = "Stop"
$repo = "cympfh/frame-shot-sync"
$ref = if ($env:FRAME_SHOT_SYNC_REF) { $env:FRAME_SHOT_SYNC_REF } else { "main" }
$dest = Join-Path $env:LOCALAPPDATA "frame-shot-sync"
$confDir = Join-Path $env:APPDATA "frame-shot-sync"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ($Uninstall) {
    if (Test-Path -LiteralPath $dest) {
        $aside = Join-Path $env:LOCALAPPDATA "frame-shot-sync-uninstalled\$stamp"
        New-Item -ItemType Directory -Force -Path (Split-Path $aside) | Out-Null
        Move-Item -LiteralPath $dest -Destination $aside
        Write-Host "Moved $dest to $aside (config in $confDir is kept)."
    } else {
        Write-Host "Not installed."
    }
    return
}

New-Item -ItemType Directory -Force -Path $dest, $confDir | Out-Null
$wc = New-Object System.Net.WebClient
foreach ($f in @("frame-shot-sync.ps1", "list-shots.py", "config.example.json")) {
    $url = "https://raw.githubusercontent.com/$repo/$ref/$f"
    $tmp = Join-Path $dest "$f.new"
    $wc.DownloadFile($url, $tmp)   # bytes as-is (keeps the UTF-8 BOM)
    Move-Item -Force -LiteralPath $tmp -Destination (Join-Path $dest $f)
}
$conf = Join-Path $confDir "config.json"
if (-not (Test-Path -LiteralPath $conf)) {
    Copy-Item -LiteralPath (Join-Path $dest "config.example.json") -Destination $conf
    Write-Host "Created config from the sample: $conf"
} else {
    Write-Host "Kept existing config: $conf"
}
$run = "powershell -ExecutionPolicy Bypass -File `"$dest\frame-shot-sync.ps1`""
Write-Host ""
Write-Host "Installed to $dest"
Write-Host "Start (every 5 min) : $run"
Write-Host "Copy once          : $run -Once"
Write-Host "Stop               : Ctrl+C in that window"
