# CP Push Notification Spec (Issue #141)

## 問題
agent-deckがghosttyセッションの状態をリアルタイムで把握できない。
現状: PERSIST接続でリクエスト/レスポンスは可能だが、サーバーからのプッシュ通知がない。
ポーリング(TAIL→テキストパース→推測)では偽idle/偽runningが発生する。

## 解決策
PERSIST接続中にSUBSCRIBEコマンドでイベント購読。サーバーが状態変化をプッシュ通知する。

## プロトコル拡張

### クライアント→サーバー
```
PERSIST          → OK|PERSIST
SUBSCRIBE|status → OK|SUBSCRIBED|status
SUBSCRIBE|output → OK|SUBSCRIBED|output
UNSUBSCRIBE|status → OK|UNSUBSCRIBED|status
```

### サーバー→クライアント (プッシュ)
```
EVENT|STATUS|idle|1711612345678          ← プロンプト表示、タイムスタンプ付き
EVENT|STATUS|running|1711612345999       ← ツール実行中
EVENT|STATUS|thinking|1711612346100      ← モデル推論中
EVENT|OUTPUT|5|base64data                ← バッファ更新(行数+内容)
EVENT|EXIT|0                             ← PTYプロセス終了
```

## ghostty側の実装箇所

### 状態変化の検出源
1. **レンダラ**: cursor_blink_visible変化、画面更新 → output変化検出
2. **PTY/Termio**: プロセスexit → EXIT通知
3. **Surface**: focusCallback → idle/running推定の補助
4. **App.zig**: drainMailbox内のメッセージ種別で状態推定

### 具体的な変更
1. `zig-control-plane/src/pipe_server.zig`: SUBSCRIBE対応。購読クライアントリスト管理。writeAll()でプッシュ
2. `zig-control-plane/src/protocol.zig`: SUBSCRIBEコマンドパース
3. `src/apprt/winui3/control_plane.zig`: 状態変化時にpipe_serverにイベント通知
4. `src/apprt/winui3/App.zig`: drainMailbox内で状態変化を検出してCPに通知

## agent-deck側の実装箇所
1. `internal/tmux/driver_cp.go`: PERSIST+SUBSCRIBE接続。イベント受信ゴルーチン
2. `internal/tmux/stubs_windows.go`: status判定をイベントベースに変更
3. `cmd/agent-deck/session_cmd.go`: session showのstatus表示をリアルタイムに

## 最小実装(Phase 1)
EVENT|STATUS のみ。idle/running/thinkingの3状態。
ghostty側: PTY出力があればrunning、なければidle。シンプル。
agent-deck側: イベント受信→session.status更新。
