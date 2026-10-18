# SPDX-License-Identifier: MIT
# frame-shot-sync (Windows 側)
# Steam Frame で撮ったスクリーンショットを、ssh で PC に自動コピーします（Frame 側のファイルは消さない・変えない）。
#
#   powershell -ExecutionPolicy Bypass -File frame-shot-sync.ps1           # 5 分ごとにコピー（Ctrl+C で終了）
#   powershell -ExecutionPolicy Bypass -File frame-shot-sync.ps1 -Once     # 1 回だけコピーして終わる
#   ... -DryRun                                                            # コピーせず、コピーするものを表示
#   ... -Dest D:\test -State D:\test\state.tsv                             # 保存先・記録ファイルを変える（テスト用）
[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$DryRun,
    [double]$IntervalMinutes = 0,
    [string]$Dest = "",
    [string]$State = "",
    [string]$Config = ""
)
$ErrorActionPreference = "Stop"
$Version = "0.1.0"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------- 設定
$defaults = [ordered]@{
    frame_host       = "frame"      # Steam Frame のホスト名か IP
    frame_user       = "steamos"
    key_path         = "~/.ssh/id_ed25519_frame"   # 無ければ ssh の既定の鍵を使う
    dest             = ""           # 空なら「ピクチャ\Steam Frame」
    interval_minutes = 5
    settle_seconds   = 20           # 撮ってからこの秒数たっていないファイルは、書き込み中かもしれないので次回に回す
    month_folders    = $true        # 保存先の下に YYYY-MM のフォルダーを作る
    sources          = @(
        [ordered]@{ name = "steam"; path = "~/.local/share/Steam/userdata/*/760/remote/*/screenshots" },
        [ordered]@{ name = "aux-shortcuts"; path = "~/Pictures/frame-aux-shortcuts" },
        [ordered]@{ name = "spectacle"; path = "~/Pictures/Screenshots" }
    )
}
if (-not $Config) { $Config = Join-Path $env:APPDATA "frame-shot-sync\config.json" }
$cfg = @{}
foreach ($k in $defaults.Keys) { $cfg[$k] = $defaults[$k] }
if (Test-Path -LiteralPath $Config) {
    $json = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) {
        if ($cfg.ContainsKey($p.Name)) { $cfg[$p.Name] = $p.Value }
        elseif ($p.Name -notlike "_*") { Write-Warning "知らない設定項目 $($p.Name) は無視します" }
    }
}
if ($Dest) { $cfg.dest = $Dest }
if (-not $cfg.dest) { $cfg.dest = Join-Path ([Environment]::GetFolderPath("MyPictures")) "Steam Frame" }
if ($IntervalMinutes -gt 0) { $cfg.interval_minutes = $IntervalMinutes }
if (-not $State) { $State = Join-Path $env:LOCALAPPDATA "frame-shot-sync\copied.tsv" }
$key = [string]$cfg.key_path
if ($key.StartsWith("~")) { $key = Join-Path $env:USERPROFILE $key.Substring(1).TrimStart("/", "\") }
$target = "$($cfg.frame_user)@$($cfg.frame_host)"
$sshOpts = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=10")
if (Test-Path -LiteralPath $key) { $sshOpts = @("-i", $key, "-o", "IdentitiesOnly=yes") + $sshOpts }

function Log([string]$msg) { Write-Host ("{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }

# ---------------------------------------------------------------- 記録（コピー済みの一覧）
$script:copied = @{}
function Load-State {
    if (Test-Path -LiteralPath $State) {
        foreach ($line in [IO.File]::ReadAllLines($State, [Text.Encoding]::UTF8)) {
            $f = $line.Split("`t")
            if ($f.Count -ge 2) { $script:copied["$($f[0])|$($f[1])"] = $true }
        }
    }
}
function Add-State([string]$remote, [long]$size, [string]$local) {
    $dir = Split-Path -Parent $State
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::AppendAllText($State, "$remote`t$size`t$local`n", (New-Object Text.UTF8Encoding $false))
    $script:copied["$remote|$size"] = $true
}

# ---------------------------------------------------------------- Frame の一覧（読むだけ）
function Get-RemoteList {
    $lister = [IO.File]::ReadAllText((Join-Path $here "list-shots.py"), [Text.Encoding]::UTF8)
    $b64Script = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lister))
    $arg = @{ sources = @($cfg.sources) } | ConvertTo-Json -Depth 5 -Compress
    $b64Arg = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($arg))
    $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $out = & ssh @sshOpts $target "echo $b64Script | base64 -d | python3 - $b64Arg" 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code -ne 0 -or -not $out) { return $null }
    return (($out | Out-String) | ConvertFrom-Json)
}

function Unique-Path([string]$path, [long]$size) {
    # 同じ名前で同じサイズのファイルがすでにあれば、それを使う（上書きしない）
    if (-not (Test-Path -LiteralPath $path)) { return @($path, $false) }
    if ((Get-Item -LiteralPath $path).Length -eq $size) { return @($path, $true) }
    $dir = Split-Path -Parent $path
    $base = [IO.Path]::GetFileNameWithoutExtension($path)
    $ext = [IO.Path]::GetExtension($path)
    for ($i = 2; ; $i++) {
        $p = Join-Path $dir "${base}_$i$ext"
        if (-not (Test-Path -LiteralPath $p)) { return @($p, $false) }
        if ((Get-Item -LiteralPath $p).Length -eq $size) { return @($p, $true) }
    }
}

# ---------------------------------------------------------------- 1 回分の同期
function Sync-Once {
    $script:shown = 0
    $list = Get-RemoteList
    if (-not $list) { Log "Frame ($($cfg.frame_host)) につながりません。電源とネットワークを確認してください。次の回にまた試します。"; return }
    $new = @(); $waiting = 0
    foreach ($f in $list.files) {
        if ($script:copied.ContainsKey("$($f.p)|$($f.s)")) { continue }
        if ($f.s -le 0 -or ($list.now - $f.m) -lt $cfg.settle_seconds) { $waiting++; continue }   # 書き込み中かも
        $new += $f
    }
    if ($waiting) { Log "撮ったばかりのファイル $waiting 個は、次の回にコピーします" }
    if (-not $new.Count) { Log "新しいスクリーンショットはありません（Frame 上に $(@($list.files).Count) 個、コピー済み）"; return }
    Log "新しいスクリーンショット: $($new.Count) 個"

    $jobs = @()
    foreach ($f in $new) {
        $when = [DateTimeOffset]::FromUnixTimeMilliseconds([long]($f.m * 1000)).LocalDateTime
        $dir = $cfg.dest
        if ($cfg.month_folders) { $dir = Join-Path $dir ($when.ToString("yyyy-MM")) }
        $name = [IO.Path]::GetFileName($f.p)
        $r = Unique-Path (Join-Path $dir $name) ([long]$f.s)
        if ($DryRun) {
            $script:shown++
            if ($script:shown -le 20) { Log "  (DryRun) $($f.p) -> $($r[0])" }
            continue
        }
        if ($r[1]) { Add-State $f.p $f.s $r[0]; Log "  すでにあります: $($r[0])"; continue }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $jobs += [pscustomobject]@{ remote = $f.p; size = [long]$f.s; local = $r[0]; part = "$($r[0]).part" }
    }
    if ($DryRun) { if ($new.Count -gt 20) { Log "  （ほか $($new.Count - 20) 個）" }; return }
    if (-not $jobs.Count) { return }

    # sftp 1 本でまとめて取ってくる（-p で撮影時刻を保つ）。いったん .part に保存し、サイズが合ったら本来の名前にする
    $batch = Join-Path $env:TEMP "frame-shot-sync-batch.txt"
    $lines = foreach ($j in $jobs) { "-get -p `"$($j.remote)`" `"$($j.part.Replace('\', '/'))`"" }
    [IO.File]::WriteAllLines($batch, $lines, (New-Object Text.UTF8Encoding $false))
    $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    & sftp @sshOpts -q -b $batch $target 2>&1 | Out-Null
    $ErrorActionPreference = $old
    $ok = 0
    foreach ($j in $jobs) {
        if ((Test-Path -LiteralPath $j.part) -and (Get-Item -LiteralPath $j.part).Length -eq $j.size) {
            Move-Item -LiteralPath $j.part -Destination $j.local
            Add-State $j.remote $j.size $j.local
            $ok++
        } else {
            Log "  コピーできませんでした（次の回にまた試します）: $($j.remote)"
        }
    }
    Log "コピーしました: $ok 個 → $($cfg.dest)"
}

# ---------------------------------------------------------------- main
foreach ($cmd in @("ssh", "sftp")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd が見つかりません。Windows の「オプション機能」で OpenSSH クライアントを入れてください。" }
}
Load-State
Log "frame-shot-sync $Version  Frame: $target  保存先: $($cfg.dest)"
if ($Once -or $DryRun) { Sync-Once; return }
Log "$($cfg.interval_minutes) 分ごとにコピーします。やめるときは Ctrl+C"
while ($true) {
    try { Sync-Once } catch { Log "エラー: $($_.Exception.Message)" }
    Start-Sleep -Seconds ([int]([double]$cfg.interval_minutes * 60))
}
