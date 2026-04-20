cwd: C:/Users/yuuji/ghostty-win

# Team Dispatcher-Stall-Mitigation — Claude streaming 下の XAML Dispatcher queue stall

## 症状 (main-thread が実機観察、2026-04-20 23:40)
- 現 binary: `zig-out-winui3/bin/ghostty.exe`, `optimize=ReleaseFast`, HEAD `e4d99ae8b` (fork/feat/ui-hang-resilience-integration、#212 P0/P1 fix 5 本込み)
- Claude Code CLI を xhigh effort で thinking burst させると (1+ 分の連続 reasoning)、**Dispatcher queue が詰まってセッションが応答停止**
- **window drag (WM_NCHITTEST) + resize は生きたまま** — P1 #2 `CP inputs route via queueIo` と P0 #1 `tsfGetCursorRect tryLock` で Win32 message pump が Dispatcher から分離されているため
- 結果: 「window は生きてるように見えるが、Claude / CP pipe / XAML input dispatch は止まってる」**新しい症状クラス**
- issue #214 の original hang と完全一致ではないが同系統。#212 P0/P1 fix で軽減されたが **根絶されていない**

## 範囲の区別 (これは Team CP-Race-Fix とは別問題)
- **Team CP-Race-Fix (ghostty-2148 が作業中、brief: `.dispatch/team-cp-pipe-race-fix-brief.md`)**: spawn 直後の CP pipe bind 前の送信失敗 (init-time race)
- **本 team (Dispatcher-Stall-Mitigation)**: 稼働中の session で Dispatcher queue 詰まり (runtime stall)
- 両者は **別の時間帯 / 別の根本原因 / 別の code path** — scope を混ぜるな

## タスク (優先順、diagnosis → mitigation の 2 段)

### P0. 再現 + 計測 (推測で fix しない、memory `hypothesis-log-reproduce-verify` 必読)
1. `scripts/repro-dispatcher-stall.ps1` or `.cmd` を作成、以下を自動化:
   - ghostty を 1 個だけ spawn (max 3 session 制約、別 session 邪魔するな)
   - claude CLI を起動、長文 prompt + xhigh effort で thinking burst 誘発
   - 誘発中に `deckpilot send <sess> "ping"` を 100ms 間隔で発射
   - **応答までの latency の分布**を記録 (p50, p95, p99, max)
   - 並行して Dispatcher queue 長 (観測手段がなければ追加要、P1 の範囲)
2. 計測 log を `.dispatch/dispatcher-stall-measurements-<timestamp>.log` に格納
3. 再現できない環境差 → report 記載で停止

### P1. 根本原因特定
`src/apprt/winui3/` 配下を以下の観点で読む:
- Dispatcher queue に何が入っているか? (XAML text update, log render, tab update, etc.)
- queue length を観測できる箇所があるか? `Microsoft.UI.Dispatching.DispatcherQueue` API から pending item count は公式には取れない、代替手段要
- Claude の stdout → WinUI3 への stream 経路: `src/apprt/winui3/App.zig` の input sink + CP pipe 周辺? TSF / input route 部分?
- Tier 1 heartbeat (`#212` の `ui_stall detected`) は何を measure してるか、Dispatcher queue length とは違うか

**仮説候補** (report で択一、根拠付き):
- (a) Claude token streaming が XAML TextBlock.Text を高頻度更新 → Dispatcher 溢れ
- (b) log render path (debug log が大量) が Dispatcher 消費
- (c) Tier 1 heartbeat 自体が Dispatcher 飢餓引き起こし (meta-bug)
- (d) その他 (計測結果次第)

### P2. Mitigation (**fix でなく mitigation**、hard fix は out of scope で良い)
以下から計測結果に基づき選択:
- **(a) UI update coalescing**: 同じ element への連続更新を 16ms (60Hz) 単位で 1 回に集約、Dispatcher 負荷下げる
- **(b) priority lane**: CP pipe input / キー入力 は high priority で Dispatcher に挿入、render 系 は low priority に下げ、high が preempt できるように
- **(c) stall-detect + force-yield**: Dispatcher が N ms pump してないのを Tier 1 が検出したら `PostMessage(HWND_BROADCAST, WM_NULL, ...)` or 同等で強制 yield
- **(d) circuit breaker**: queue が閾値超えたら新規 enqueue を drop、`"[UI throttled]"` 通知を 1 行だけ出す
- (a) が最も副作用少ない、(c)(d) は workaround 寄り

### P3. 実装 + 再計測 + commit
選んだ option を実装、P0 の repro で latency p95 < 500ms (閾値は計測結果から調整) を確認、独立 commit

## スコープ (厳守)
触っていい:
- `src/apprt/winui3/` 配下 (Dispatcher 関連コード)
- `src/apprt/winui3/App.zig` の init / input sink / Tier 1 heartbeat 周辺
- `src/renderer/` または XAML render 経路 (read-only で理解、改変は慎重に)
- `scripts/` に repro スクリプト追加
- `.dispatch/team-dispatcher-stall-mitigation-*` (新規)
- `docs/` に設計メモ

触ってはいけない:
- `src/apprt/winui3/control_plane.zig`, `pipe_server.zig` の **CP pipe init 部分** (Team CP-Race-Fix scope)
- `src/apprt/` の他 runtime
- `src/terminal/`, `src/font/` 以下の core ロジック改変
- `vendor/`, `tools/conpty-bridge/`
- `xaml/` 以下 (XAML markup 改変しない、Zig 側で対処)
- upstream (ghostty-org) への一切のアクション
- 他 team の file (`team-cp-pipe-race-fix-*`, `team-g-*`) 改変

## 禁止
- `git add .` / `-A` / `-u` 禁止、**`git add <specific-file>` + `git commit -o <paths>`**
- `--no-verify`, force push, upstream push
- `zig build` 直接 (必ず `./build-winui3.sh --release=fast`)
- 推測で fix (P0 repro と P1 仮説なしに P2/P3 に進むな)
- **4+ session stress test 禁止**。自分が 4 人目になりうる、max 3 session
- hard fix (Dispatcher 自体の置き換え、XAML render pipeline 改変等) は scope 外、**停止して report**
- Team CP-Race-Fix と同時間帯に ghostty-win worktree の共有ファイル (App.zig 等) を同時編集するな、conflict 回避のため serialize

## 検証
- `./build-winui3.sh --release=fast` green
- `scripts/repro-dispatcher-stall.ps1` の latency p95 が fix 後に明確に下がる (数値示せ)
- 既存の挙動 (normal session, window drag) が regression しない

## 完了条件
- P0-P3 すべて
- **worker branch**: `p1-task-214-dispatcher-stall-mitigation` (`fork` remote へ push)
- `git push fork p1-task-214-dispatcher-stall-mitigation`
- `.dispatch/team-dispatcher-stall-mitigation-report.md`: 仮説 validation、選んだ option、計測 before/after、既知の残り問題
- PR 起票は Team PR-Curator (後続 session) が担当、本 team は branch push まで

## 参考 memory
- `~/.claude/projects/C--Users-yuuji/memory/win32-cp-pipe-architecture.md`
- `~/.claude/projects/C--Users-yuuji/memory/project_ghostty_winui3_hang_28900.md`
- `~/.claude/projects/C--Users-yuuji/memory/hypothesis-log-reproduce-verify.md`
- `~/.claude/projects/C--Users-yuuji/memory/feedback_parallel_team_index_contamination.md`
- Team G report (既存 Tier 1 heartbeat の挙動): `.dispatch/team-g-winui3-dispatcher-watchdog-report.md`
- Issue #214 の discussion と原 issue body
