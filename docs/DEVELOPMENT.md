# 開発者向けメモ

## 仕組み

1. `ssh` で Frame に `list-shots.py` を標準入力から渡して `python3 -` で実行し、探す場所の画像の一覧（パス・サイズ・更新時刻）を ASCII だけの JSON で受け取る。Frame には何も書かない
2. `copied.tsv` に「パス + サイズ」があるものは飛ばす。撮ってから `settle_seconds` 秒以内のものとサイズ 0 のものは、書き込み中かもしれないので次の回へ
3. `sftp -b`（1 本の接続）でまとめて `get -p`（撮影時刻を保つ）。いったん `*.part` に保存し、サイズが一覧と同じなら本来の名前にして `copied.tsv` に追記
4. 保存先に同じ名前で同じサイズのファイルがあれば、コピーせずに記録だけする。サイズが違えば `_2` などを付ける

## Frame でスクリーンショットができる場所（2026-10 時点で確認）

| 撮り方 | 場所 |
|---|---|
| Steam / SteamVR のスクリーンショット | `~/.local/share/Steam/userdata/<ID>/760/remote/<AppID>/screenshots/*.jpg`（SteamVR は AppID 250820。`thumbnails/` は対象外） |
| aux-shortcuts のスクリーンショット | `~/Pictures/frame-aux-shortcuts/screenshot_*.png`（`screenshot_to_steam` がオンなら Steam 側にも入る） |
| デスクトップモードの Spectacle | `~/Pictures/Screenshots`（既定の場所。使っていなければ空） |

aux-shortcuts で `screenshot_to_steam` がオンだと、同じ写真が png と jpg の 2 枚コピーされます。片方だけでいいときは `sources` から外します。

## 設定（`%APPDATA%\frame-shot-sync\config.json`）

| 項目 | 既定 | 意味 |
|---|---|---|
| `frame_host` / `frame_user` | `frame` / `steamos` | 接続先 |
| `key_path` | `~/.ssh/id_ed25519_frame` | ssh の鍵（`~` は `%USERPROFILE%`）。無ければ ssh の既定 |
| `dest` | 空（ピクチャ\Steam Frame） | 保存先 |
| `interval_minutes` | 5 | くり返す間隔 |
| `settle_seconds` | 20 | 撮ってからこの秒数は待つ |
| `month_folders` | true | `YYYY-MM` のフォルダーに分ける（Frame 上の更新時刻で） |
| `sources` | 上の 3 か所 | `name` と `path`（Frame 側のフォルダー。`*` が使える） |

## コマンドラインオプション

`-Once` / `-DryRun` / `-IntervalMinutes 分` / `-Dest フォルダー` / `-State ファイル` / `-Config ファイル`

## テスト

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

本物の保存先・記録には触らず、一時フォルダーに 1 回コピーして、2 回目は何もコピーしないことを確かめます（Frame につながっている必要があります）。
