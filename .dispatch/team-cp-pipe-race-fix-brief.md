cwd: C:/Users/yuuji/ghostty-win

# Team CP-Race-Fix — CP pipe init race で deckpilot が壊れた input を送る問題を直す

## 再現シグネチャ
1. ghostty WinUI3 binary (現 `zig-out-winui3/bin/ghostty.exe`, `optimize=ReleaseFast`, HEAD `e4d99ae8b`) を **短時間に複数 spawn** する (for ループで nohup 3 個連続、間隔 < 10s)
2. `deckpilot list` で全員 `idle` に見える (session 登録は成功)
3. 直後の `deckpilot send <session> "任意テキスト"` が `text_not_visible|phase1_timeout` を返す
4. `deckpilot show <session>` で terminal 表示を覗くと、送ったテキストが **部分的に corrupt 配送**されてる (例: `cd C:/Users/yuuji/skill-miner && claude` を送ったのに terminal に `\` だけ落ちて cmd が「'\' は認識されません」エラー出す)
5. **単独 spawn (他 session のない間での 1 個だけ spawn)** では再現しない — `submit_failed_stuck|400ms → 正常受理` の既知の初回 failure パターンで済む

## 仮説 (main-thread の切り分け)
deckpilot daemon は ghostty 新 session を **「session 登録完了 + CP pipe bind 完了」の区別なく** `idle` 扱いする。
- ghostty apprt (WinUI3) 側: session 名と pid を daemon 用 registry に publish する処理と、CP pipe (Named Pipe) を `CreateNamedPipe` + `ConnectNamedPipe` で listening にする処理が **並列 or 逆順** で走っている
- 複数 session 同時 spawn 時、daemon 側 register は先に race で勝ち、pipe bind は遅れて完了する。deckpilot send の phase 1 (probably `CreateFile` on pipe path) は register 直後に発行されるが pipe server 未 bind → phase1_timeout
- `\` 1 文字 corrupt は、phase1_timeout 後の retry or buffer-leak で **input 先頭の byte だけ先行到達** した痕跡 (推測)

**必ずこの仮説を最初に validate しろ**。間違ってたら diagnosis からやり直し。

## タスク (優先順)

### P0. 再現 & 計測 (**推測で fix しない**)
1. `scripts/repro-cp-race.ps1` or `.cmd` を新規作成:
   - 3 個の ghostty を 1s 間隔 (or <500ms) で連続 spawn
   - 各 session に対し `deckpilot send ... "echo READY"` を spawn 直後に発射
   - 応答と terminal 内容を log
   - 3 個すべて `submit_ok` + terminal に `READY` が出れば pass、1 個でも text_not_visible or corrupt なら fail
2. このスクリプトで **必ず失敗を再現**。再現しないなら環境差なので report して停止

### P1. 根本原因特定
`src/apprt/winui3/` 配下で以下を **読んで順序を確定**:
- CP pipe server 初期化コード (memory `win32-cp-pipe-architecture` 参照、`control_plane.zig` 周辺)
- session name + pid publish 処理 (daemon 側と ghostty 側の契約、session registry への書き込みパス)
- 両者を呼び出すコード (多分 `App.zig` の init 経路)
- **呼び出し順序 + 同期機構を書き出せ**。report に手書きで

### P2. Fix (選択肢から **根拠付きで選べ**)
以下 3 案あり、どれかで固定:
- **(a) pipe-first, register-second**: CP pipe が `ConnectNamedPipe` async 発行か、少なくとも listen queue に入った後にだけ registry publish。シンプルだが async I/O の場合 "listening" の定義が fuzzy
- **(b) ready-event handshake**: pipe server が "ready" イベントを auto-reset event や completion flag で立てて、register 側がそれを待ってから publish。堅いが lock 追加
- **(c) deckpilot 側 retry**: daemon は pipe bind まで待たず register、deckpilot send が phase1_timeout した時に backoff retry (例: 50ms × 20 回)。ghostty 側変更ゼロで済む caller-side workaround
- **判断基準**: (a) < (b) < (c) の順で「ghostty の invariant を守る度合い」が上がるが実装コストも上がる。(c) は最小コストで済むが症状の根を残す。**主観で選ぶな、memory `hypothesis-log-reproduce-verify` 原則でまず計測、計測結果から選べ**

### P3. Fix 適用 + 再計測
選んだ option で実装。P0 の再現スクリプトで **3/3 pass** すること、既存の `./build-winui3.sh` + spawn 単独の挙動が変わらないこと

## スコープ (厳守)
触っていい:
- `src/apprt/winui3/` 配下 (CP pipe 初期化と session register)
- `src/cp-*.zig`, `src/control_plane.zig` 相当
- `scripts/` に repro スクリプト追加
- `.dispatch/team-cp-pipe-race-fix-*` (新規)
- `docs/` に調査メモ (任意)
- `build.zig` (新ファイル登録の必要があれば)

触ってはいけない:
- `src/apprt/` の他 runtime (embedded, gtk, macos)
- `src/terminal/`, `src/font/`, `src/renderer/`
- `vendor/`, `third_party/`, submodule 内部
- `zig-out*/` 成果物
- `xaml/` 以下 (Config.load cache と競合しない方針)
- `tools/conpty-bridge/` (別責務)
- **`~/.agents/skills/dispatch-impl-via-deckpilot/`** や deckpilot 側コード (別 repo)
- upstream (ghostty-org) への一切のアクション (PR / issue / comment 禁止)
- main branch への直 push

## 禁止
- `git add .` / `-A` / `-u` 禁止。**`git add <specific-file>` + `git commit -o <paths>`** 必須
- `--no-verify`, force push, upstream push
- `zig build` を直接 (必ず `./build-winui3.sh`)
- 推測で fix しない (P0 の repro と P1 の 根拠なしに P2 に進むな)
- 4+ session 同時実験は hang リスク、**最大 3 session stress test まで**に留めろ (memory `project_ghostty_winui3_hang_28900` 参照)
- deckpilot CLI 側を直すのは許容範囲外 (deckpilot repo は別、本 team は ghostty-win 側で完結)
- fix が大規模になりそうなら **停止して report のみ**出して main-thread 判断を仰げ

## 検証
- `./build-winui3.sh --release=fast` green
- `scripts/repro-cp-race.{ps1,cmd}` が 3/3 pass
- 既存の単独 spawn → `deckpilot send "echo hi"` が以前と同等に通る (regression 0)

## 完了条件
- P0-P3 すべて (P2 で workaround(c) 選んだ場合も code 変更あり)
- 独立 commit (**worker branch 名**: `p1-task-cp-pipe-init-race` 相当、main や feat/... には push しない)
- `git push fork p1-task-cp-pipe-init-race`
- `.dispatch/team-cp-pipe-race-fix-report.md` 書き込み: 仮説 validation、選んだ option、実装差分要約、repro before/after
- **PR 起票は team 外**: Team PR-Curator が後続で起票するので、push して branch を置くだけ

## 参考 memory
- `~/.claude/projects/C--Users-yuuji/memory/win32-cp-pipe-architecture.md` (CP pipe 全体設計)
- `~/.claude/projects/C--Users-yuuji/memory/project_ghostty_winui3_hang_28900.md` (多session hang 既往)
- `~/.claude/projects/C--Users-yuuji/memory/feedback_parallel_team_index_contamination.md` (git add . 禁止)
- `~/.claude/projects/C--Users-yuuji/memory/hypothesis-log-reproduce-verify.md` (仮説→repro→修正の規律)
