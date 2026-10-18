# frame-shot-sync

Steam Frame で撮ったスクリーンショットを、**PC の「ピクチャ\Steam Frame」へ自動でコピー** します。
VR の中で撮った写真が、外したらもう PC にそろっています。Frame 側の写真は消しません。

```
ピクチャ\Steam Frame\
  2026-10\
    20261014213555_1.jpg
    screenshot_2026-10-14_21-28-23.png
```

Steam のスクリーンショット（SteamVR で撮ったものも含む）と、[aux-shortcuts](https://github.com/sasaken1102r/frame) のスクリーンショットボタンで撮ったものをコピーします。

## 必要なもの

- PC から Frame に、パスワードなしで ssh できること（鍵 `%USERPROFILE%\.ssh\id_ed25519_frame` を使います。別の鍵なら設定で変更）
- Windows 10 / 11 の PowerShell（追加のインストールや管理者権限は要りません）

## インストール

PC の PowerShell に貼り付けて Enter:

```powershell
irm https://raw.githubusercontent.com/cympfh/frame-shot-sync/main/install.ps1 | iex
```

## 使い方

5 分ごとにコピー（使い終わったらそのウィンドウで Ctrl+C）:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\frame-shot-sync\frame-shot-sync.ps1"
```

いま 1 回だけコピーしたいときは、最後に ` -Once` を付けます。自動では起動しません。

## アンインストール

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cympfh/frame-shot-sync/main/install.ps1))) -Uninstall
```

外したファイルは消さずに `%LOCALAPPDATA%\frame-shot-sync-uninstalled\` へ移します。設定ファイルとコピー済みの写真は残ります。

<details>
<summary>くわしい情報（設定・開発者向け）</summary>

- 設定: `%APPDATA%\frame-shot-sync\config.json`（初回にサンプルからコピー）。Frame のホスト名（既定 `frame`）、鍵、保存先、間隔、探す場所。項目は [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- コピー済みの一覧は `%LOCALAPPDATA%\frame-shot-sync\copied.tsv`。PC 側で写真を消したり移したりしても、もう一度はコピーしません
- 撮ってから 20 秒たっていないファイルは書き込み中かもしれないので、次の回に回します
- コピーするものを確かめるだけなら ` -DryRun`
- Frame の中では一覧を読むだけで、ファイルを書いたり消したりしません

</details>

ほかの Steam Frame 用ツール: [frame-tools](https://github.com/cympfh/frame-tools)
