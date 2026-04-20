cwd: C:/Users/yuuji/ghostty-win

# Team G — WinUI3 apprt dispatcher watchdog

## 目的
Issue **YuujiKamura/ghostty#214** (WinUI3 runtime: thinking-state timer freeze / CP pipe input stalls under 4+ concurrent Claude sessions) の investigation #2 を実装:

> 2. Add a watchdog in the WinUI3 apprt that logs when the main thread dispatcher goes >3s without pumping. Write to CP pipe so external monitors (deckpilot) can detect

次回 hang が発生した際に「どの session の dispatcher がどの瞬間に止まったか」を外部から観測できるようにする。hang 自体の fix ではない、observability 追加のみ。

## 前提 (要読み込み)
- `PLAN.md` (プロジェクト規約、セッション開始時に必読と CLAUDE.md に明記)
- `AGENTS.md` (存在すれば)
- `src/apprt/winui3/` または類似パス — WinUI3 apprt の zig 実装箇所
- CP pipe 書き込み先: 既存の CP pipe server 実装を流用 (grep で `CP` / `named-pipe` / `pipe-server` 当たりを探せ、memory `win32-cp-pipe-architecture` 参照)
- 既存の hang memory: `~/.claude/projects/C--Users-yuuji/memory/project_ghostty_winui3_hang_28900.md` — 類似症状、併記して related-to-issue-139 と記録

## 要件
1. WinUI3 apprt の **main dispatcher thread が pulse を出す仕組み** を追加:
   - 毎 N 秒 (N=1 を既定値、将来調整可能) に tick をログ先へ書き出す
   - ログ先候補: (a) 既存 CP pipe の新規メッセージ種 `DISPATCHER_PULSE`、(b) `%LOCALAPPDATA%/ghostty/dispatcher-watchdog-<pid>.log` に追記、(c) 両方。CP pipe 側に寄せるのが deckpilot との親和性で有利、brief としては CP pipe 経由を優先、log file は fallback
   - pulse payload: `timestamp`, `session_pid`, 可能なら `last_message_processed_id` や `queue_length`
2. **別 thread (watchdog)** が pulse を監視、前 pulse から **3 秒**超過したら alert を書き出す:
   - alert 先: (a) `stderr`、(b) CP pipe の `DISPATCHER_STALL` メッセージ、(c) log file
   - alert payload: `detected_at`, `session_pid`, `last_pulse_at`, `elapsed_ms`
3. 既存の ghostty WinUI3 起動/シャットダウンに統合:
   - `init` 時に watchdog thread spawn
   - `deinit` 時に watchdog kill + log close
   - app crash 時に log flush
4. **deckpilot 側の consume は実装しない** (別 team scope)、ghostty 側が吐く契約だけ固める
5. 計測コスト: pulse thread の CPU 負荷 < 0.1% at idle、memory overhead < 1MB
6. `./build-winui3.sh` が通ること (必ずラッパー経由、直接 zig build で WinUI3 を触るな — CLAUDE.md 明記)
7. 単一セッション起動で動作確認、log に tick が 1 秒ごとに載り、`Sleep(5000)` 等で main thread を意図的にブロックすると DISPATCHER_STALL alert が立つことを目視確認
8. 4 session 同時起動での hang 再現テストはこの team の scope 外 (issue 再現実験は人手判断)。あくまで **watchdog 単体が機能することを検証**

## スコープ (厳守)
触っていい:
- `src/apprt/winui3/` 配下 (watchdog module 追加、init/deinit 接続)
- `src/terminal/` は read-only で参照可 (既存 dispatcher パターン理解用)
- `src/cp-pipe/` or 相当 (CP pipe の message type enum 拡張)
- `build.zig` (新規ファイル登録が必要なら)
- `docs/` (設計メモ追加、任意)
- `.dispatch/team-g-winui3-dispatcher-watchdog-report.md` (新規 report)

触ってはいけない:
- `src/apprt/` の他 runtime (embedded, gtk, macos 等) — WinUI3 のみ
- `src/terminal/` の既存コード **改変** (参照のみ)
- `zig-out*/` (ビルド成果物)
- `vendor/`, `third_party/`, 他 submodule 内部
- `PLAN.md`, `AGENTS.md`, `CLAUDE.md` (読むだけ、改変禁止)
- `scripts/`, `.github/`
- upstream (`origin` = ghostty-org/ghostty) には **絶対 push するな** / PR も issue comment も禁止 (CLAUDE.md 明記)
- remote `fork` (= YuujiKamura/ghostty) への push は自由

## 禁止
- `git add .` / `-A` / `-u` 全部禁止。**`git add <specific-file>` + `git commit -o <path>...`** のみ (memory `feedback_parallel_team_index_contamination.md`)
- `--no-verify`, force push, upstream push
- WinUI3 build を `zig build` 直接実行 (必ず `./build-winui3.sh`)
- テスト hang 再現で 4 session 同時起動する実験
- watchdog 以外の「ついでに直したい」修正 (issue #214 の他 investigation は別 team)

## 検証
- `./build-winui3.sh` green
- 単一 WinUI3 ghostty 起動 → log に pulse tick が出る
- 意図的に main thread を `Sleep(5000)` で止める dev 用 flag or test fixture を使って DISPATCHER_STALL が立つことを確認
- 確認 log は `.dispatch/team-g-winui3-dispatcher-watchdog-report.md` に貼り付け

## 完了条件
- watchdog module 実装 (zig)
- CP pipe / log 出力経路 (最低どちらか、両方が望ましい)
- 単体動作確認 (pulse tick + stall alert)
- `./build-winui3.sh` 成功
- **fork (YuujiKamura/ghostty) の main branch に独立 commit + push**
- `.dispatch/team-g-winui3-dispatcher-watchdog-report.md` に: 何を追加したか、どのファイルを触ったか、検証 log、既知の未解決点
- issue #214 に **コメントを追加しない** (main-thread が後で PR 紐付けて処理、session が commit だけする)
