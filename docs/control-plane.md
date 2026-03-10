# Control Plane (Named Pipe IPC)

Win32 / WinUI3 両方の apprt で利用可能な、Named Pipe ベースの IPC サーバ。
外部ツール (PowerShell, 自動化スクリプト) から Ghostty セッションの状態照会・入力送信ができる。

## 有効化

環境変数を設定して Ghostty を起動:

```powershell
$env:GHOSTTY_CONTROL_PLANE = "1"
# または
$env:GHOSTTY_WIN32_CONTROL_PLANE = "1"   # Win32版互換
```

## アーキテクチャ

```
PowerShell / 外部ツール
    |
    | Named Pipe (\\.\pipe\ghostty-winui3-{session}-{pid})
    v
ControlPlane (別スレッド)
    |
    | WM_APP_CONTROL_INPUT (WM_USER+4)
    v
UI スレッド → activeSurface().core_surface.textCallback()
```

- パイプサーバは専用スレッドで動作
- INPUT コマンドは pending queue に入り、PostMessage で UI スレッドに通知
- STATE/TAIL の読み取りは core_surface のスナップショットなので COM 不要

## ファイル配置

| パス | 説明 |
|------|------|
| `%LOCALAPPDATA%\ghostty\control-plane\winui3\sessions\` | セッションファイル |
| `%LOCALAPPDATA%\ghostty\control-plane\winui3\logs\` | ログファイル |
| `%LOCALAPPDATA%\ghostty\control-plane\win32\sessions\` | Win32版セッション |

## プロトコル

### PING
```
→ PING
← PONG|{session}|{pid}|0x{hwnd}
```

### STATE
```
→ STATE
← STATE|{session}|{pid}|0x{hwnd}|{title}|prompt={0|1}|selection={0|1}|pwd={path}|tab_count={n}|active_tab={n}

→ STATE|2          # タブ2を指定
← STATE|...|tab_count=5|active_tab=0
```

### TAIL
```
→ TAIL              # デフォルト20行
→ TAIL|50           # 50行
← TAIL|{session}|{lines}
{viewport content}
```

### INPUT
```
→ INPUT|{from}|{base64-encoded-text}
← ACK|{session}|{pid}
```

テキストは UTF-8 を Base64 エンコードして送る。アクティブタブに入力される。

### MSG
```
→ MSG|{from}|{text}
← ACK|{session}|{pid}
```

ログファイルに記録されるだけ。ターミナルには表示されない。

## PowerShell スクリプト

### セッション一覧
```powershell
.\scripts\winui3-control-list.ps1
```

出力例:
```
Session    Pid   Hwnd       Prompt Selection Pwd          TabCount ActiveTab Title
-------    ---   ----       ------ --------- ---          -------- --------- -----
winui3-123 12345 0x001A0B20 1      0         C:\Users\me  3        0         Ghostty
```

### コマンド送信
```powershell
# 生存確認
.\scripts\winui3-control-send.ps1 -SessionName winui3-123 -Type PING

# 状態取得
.\scripts\winui3-control-send.ps1 -SessionName winui3-123 -Type STATE

# 特定タブの状態
.\scripts\winui3-control-send.ps1 -SessionName winui3-123 -Type STATE -TabIndex 2

# テキスト入力
.\scripts\winui3-control-send.ps1 -SessionName winui3-123 -Type INPUT -Text "ls -la"

# ビューポート取得
.\scripts\winui3-control-send.ps1 -SessionName winui3-123 -Type TAIL -Lines 50
```

## WinUI3 vs Win32 の違い

| 項目 | Win32 | WinUI3 |
|------|-------|--------|
| パイプ名 | `ghostty-win32-*` | `ghostty-winui3-*` |
| セッションDir | `control-plane\win32\` | `control-plane\winui3\` |
| PostMessage | `WM_GHOSTTY_CONTROL_INPUT` (WM_USER+1) | `WM_APP_CONTROL_INPUT` (WM_USER+4) |
| タブ対応 | なし (単一Surface) | あり (`STATE|N`, `tab_count`, `active_tab`) |
| デフォルト名 | `win32-{pid}` | `winui3-{pid}` |

## ソースファイル

| ファイル | 役割 |
|----------|------|
| `src/apprt/winui3/control_plane.zig` | IPC サーバ本体 |
| `src/apprt/winui3/App.zig` | 統合 (create/destroy/callbacks) |
| `src/apprt/winui3/Surface.zig` | 状態クエリメソッド |
| `src/apprt/winui3/os.zig` | `WM_APP_CONTROL_INPUT` 定数 |
| `src/apprt/winui3/wndproc.zig` | メッセージハンドラ |
| `scripts/winui3-control-*.ps1` | PowerShell クライアント |
