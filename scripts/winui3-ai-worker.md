# winui3-ai-worker

`winui3-ai-worker.ps1` は、Windows Terminal dev package 上の AI worker を起動・送信・停止するための統一入口です。

## 原則

- `start` は起動だけを行う
- `status` は状態確認だけを行う
- `send` は `-Text` で明示した内容だけを送る
- スクリプト自身が勝手にダミータスクや確認用タスクを送ることはしない
- `gemini` は WT 上では one-shot 実行を使う。対話 TUI は既定で起動しない

## 使い方

### Codex + Git Bash

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\winui3-ai-worker.ps1 -Action start -Agent codex -Shell gitbash -Session wt-ai-codex
```

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\winui3-ai-worker.ps1 -Action send -Agent codex -Shell gitbash -Session wt-ai-codex -Text "やらせたい内容"
```

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\winui3-ai-worker.ps1 -Action status -Agent codex -Shell gitbash -Session wt-ai-codex
```

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\winui3-ai-worker.ps1 -Action stop -Agent codex -Shell gitbash -Session wt-ai-codex
```

### Gemini + PowerShell

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\winui3-ai-worker.ps1 -Action start -Agent gemini -Shell powershell -Session wt-ai-gemini
```

## 補足

- `Session` を省略すると `wt-<agent>-<shell>` 形式が使われる
- `winui3-codex-worker.ps1` は後方互換ラッパー
- モデル切り替えが必要なら `-Model` を使う
