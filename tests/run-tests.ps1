# SPDX-License-Identifier: MIT
# frame-shot-sync の動作テスト。一時フォルダーにコピーし、本物の保存先と記録には触らない。
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp = Join-Path $env:TEMP ("frame-shot-sync-test-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$state = Join-Path $tmp "state.tsv"
$fails = 0
function Check($cond, $what) { if ($cond) { Write-Host "ok   $what" } else { Write-Host "FAIL $what"; $script:fails++ } }

& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\frame-shot-sync.ps1" -Once -Dest "$tmp\pics" -State $state
$files = @(Get-ChildItem -Recurse -File "$tmp\pics" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne ".part" })
Check ($files.Count -gt 0) "1 回目: $($files.Count) 個コピーされた"
$lines = @(Get-Content -LiteralPath $state -Encoding UTF8 -ErrorAction SilentlyContinue)
Check ($lines.Count -eq $files.Count) "記録の行数がファイル数と同じ（$($lines.Count)）"
$bad = @(Get-ChildItem -Recurse -File "$tmp\pics" -Filter *.part -ErrorAction SilentlyContinue)
Check ($bad.Count -eq 0) ".part が残っていない"
Check (@($files | Where-Object { $_.DirectoryName -notmatch '\\\d{4}-\d{2}$' }).Count -eq 0) "YYYY-MM のフォルダーに分かれている"

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\frame-shot-sync.ps1" -Once -Dest "$tmp\pics" -State $state | Out-String
$files2 = @(Get-ChildItem -Recurse -File "$tmp\pics" | Where-Object { $_.Extension -ne ".part" })
Check ($files2.Count -eq $files.Count -and $out -match "新しいスクリーンショットはありません") "2 回目: 何もコピーしない"

Write-Host ""
Write-Host "テスト用フォルダー: $tmp （確認したら消してOK）"
if ($fails) { Write-Host "失敗 $fails 件"; exit 1 } else { Write-Host "すべて OK" }
