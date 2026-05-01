# Sprawl Cleanup Integration Summary (2026-05-01)

I5 aggregation of A1-A7 sprawl-report-*.md. Source: `sprawl-coordination.md` (A1-A7 brief) + `sprawl-integration-coordination.md` (I1-I5 follow-up).

## 全体集計

### 担当 file 数 (chunk ごと)

| chunk | 担当 scope | 主要 file 数 |
|--|--|--|
| A1 | apprt/{embedded,gtk,common} | 8 (+1 lint scope follow-up) |
| A2 | src/{Surface,App,Command}.zig | 3 (heavy) |
| A3 | src/global.zig + src/os/* | 9 |
| A4 | src/build/* + main entrypoints | 15 |
| A5 | cli + config + input + terminal + pty | 16 |
| A6 | src/font/* + src/fontconfig/windows/* | 16 |
| A7 | src/renderer/* | 37 (12 M + 25 A) |
| **合計** | | **104** |

### DECISIONS 集計

| chunk | REVERT | WRAP | KEEP_ANNOT | DEFERRED | NO_OP |
|--|--:|--:|--:|--:|--:|
| A1 | 4 | 0 | 4 (+1 lint) | 0 | 0 |
| A2 | 0 | 0 | 3 | 0 | 0 |
| A3 | 3 | 0 | 2 | 4 | 0 |
| A4 | 2 | 0 | 12 | 0 | 1 |
| A5 | 7 | 0 | 8 | 0 | 1 |
| A6 | 3 | 2 | 11 | 0 | 0 |
| A7 | 4 | 0 | 33 | 0 | 0 |
| **合計** | **23** | **2** | **73** | **4** | **2** |

WRAP/KEEP-ANNOT 比 ≈ 1:36 — `wrap-first-in-apprt` の central question 「`apprt/winui3/` で wrap できないか?」に対する答えは大半 No。理由: upstream-shared な dispatch root (Backend enum / Runtime enum / Mailbox 等) は `apprt/` 外から呼ばれており physical relocation 不能。WRAP の 2 件は A6 の純粋な fork-only file (`directwrite.zig` 731 LOC + `dwrite_generated.zig` 3192 LOC) — `git mv` で `src/apprt/winui3/font/` へ移送、3.9k LOC を `src/font/` から除去。

### COMMITS 数

合計 **31 commit** (A1=3, A2=1, A3=2, A4=3, A5=13, A6=4, A7=5)。

注: `aba70c04f` は A4 と A6 の両 report に登場 (parallel-team git-index 干渉により subject/payload mismatch)。実 commit hash unique は 30 程度。

### ISSUES_CLOSED / ISSUES_FILED

- **ISSUES_CLOSED**: 1 件 (#261, A3 が close)。残る #260/#262/#263/#264/#265 は tracking 継続中、I 系列でのフォロー要件あり。
- **ISSUES_FILED**: 0 件 (どの A session も「REVEAL-AS-GAP」を新 issue 化せず)。A3 は 4 file の cross-chunk coupling を commit message 内で surface のみ。I3 brief (A7 Win32 OpenGL 未対応) はこの aggregation 後に新 issue 化される予定。

## chunk 別 1 行サマリ

- **A1** — apprt/embedded + apprt/gtk + apprt 共通 IF 8 file 監査。embedded/gtk 4 file を `git checkout origin/main` で REVERT、apprt 共通 IF 4 file は `UPSTREAM-SHARED-OK` 注記付き KEEP。`surface.zig Mailbox` 拡張は termio/renderer から直接呼ばれており wrap 不能 (heavy-fork-stewardship rule 5)。push は peer 干渉で 4 連続失敗、deferred。lint scope 1 file follow-up 追加。
- **A2** — src/{Surface,App,Command}.zig 3 file (heavy)。bulk 抽出 (`surface_locked.zig` 化) を user に revert され、A1 の KEEP-WITH-ANNOTATION 路線へ pivot。`Surface.zig` に file-top + 12 site の `UPSTREAM-SHARED-OK` 注記、`App.zig` に file-top + `keyEventIsBinding` 注記。test gate は A5 commit `6f58a234b` の Parser.init mismatch で BLOCKED — A2 自身の diff は無罪。
- **A3** — src/global.zig + src/os/* 9 file。3 REVERT (cf_release_thread/flatpak/i18n_locales = macOS/GTK only or pure cosmetic drift)、2 KEEP-WITH-ANNOTATION (global.zig fontconfig bootstrap call site, locale.zig MSVC ABI 分岐)、4 DEFERRED (TempDir/file/main/windows が `src/terminal/kitty/graphics_image.zig` と coupled API cluster)。push 成功 (LEFTHOOK=0)。#261 close。
- **A4** — src/build/* + main entrypoints 15 file (14 diff + 1 NO_OP)。2 REVERT (GhosttyXCFramework macOS-only / GitVersion cosmetic drift)、12 KEEP-WITH-ANNOTATION (build infra 自体は wrap 不能)。`zig fmt` + `ast-check` PASS。`zig build` は peer-induced `p/vaxis` cache pollution で BLOCKED — A4 diff は dependency resolution に無関係。push 成功。
- **A5** — cli/config/input/terminal/pty 16 file。7 REVERT + 8 KEEP-ANNOT + 1 NO_OP。`Config.zig` 大規模 refactor (229→104 line 削減: middle-click-action option 復活、`normalizePathForTest` helper 抽出)、`Binding.zig` 25→4 line 削減。**13 commit と最多。** test gate は build runner abs-path panic で BLOCKED、push pending (uia-smoke flaky)。upstream feature regression を 4 件発掘し復元 (apc.zig `max_bytes` security guard 含む)。
- **A6** — src/font/* + src/fontconfig/windows/* 16 file。**WRAP 2 件全て A6 由来** — `directwrite.zig` (731 LOC) と `dwrite_generated.zig` (3192 LOC) を `src/apprt/winui3/font/` へ `git mv`。3 REVERT (opentype/glyf/coretext = upstream sync gap or macOS-only)、11 KEEP-ANNOT。test gate **PASS** (`-Dtest-filter="font"` EXIT=0、`--global-cache-dir "$HOME/.cache/zig"` で `p/` pollution 回避済み)。fontconfig/windows/* の物理 move は A4 owner (`GhosttyResources.zig`) と coordinate するため deferred。
- **A7** — src/renderer/* 37 file (12 M + 25 A)。4 REVERT (OpenGL.zig + opengl/Frame + opengl/shaders + State.zig)、33 KEEP-WITH-ANNOTATION。**case A (apprt 移送) ではなく case B (sibling pattern) を選択** — `src/renderer/d3d11/` は `src/renderer/metal/`、`src/renderer/opengl/` の sibling backend として upstream pattern と整合。WinUI3 build PASS。`-Dapp-runtime=win32` + opengl backend は意図的に regression (Windows ships D3D11、OpenGL は dead code) — 別 chunk fix が必要、I3 brief で新 issue 化。

## skill firing 観察

### wrap-first-in-apprt (主観察 target)

**全 7 session で FIRED** — session 起動時に `Skill` tool 経由で明示 invoke、各 file 判断時に central question 「`apprt/winui3/` で wrap できないか?」を機械的に適用。3 patterns (file-move / delegation stub / comptime injection) の自覚的 walk-through 観察。

| session | firing 強度 | load-bearing 度 |
|--|--|--|
| A1 | 強 | 8 file 全件 + lint scope 1 file 判定軸 |
| A2 | 強 | 3 file 全件、user revert 後の re-engage に活用 |
| A3 | 強 | 9 file 全件、cf_release_thread.zig (macOS file が apprt/winui3/safe_mailbox を import) を「literal inverse of wrap-first」として即時検出 |
| A4 | 強 | 15 file 全件、GhosttyXCFramework REVERT を「absolute NO」rule で trigger |
| A5 | 強 | 16 file 全件、3 patterns に分類 (cosmetic drift / upstream feature regression / irreducible apprt-shared) |
| A6 | 強 | 16 file 全件、唯一の WRAP=2 を produce (directwrite/dwrite_generated)。pattern 1 (file-move) を実際に行使 |
| A7 | 強 | 37 file 全件、case B 選択の主軸 |

**機能した。** 過剰 wrap (sprawl 削減を理由に upstream dispatch root を分裂) も、過剰 KEEP (REVERT で済む cosmetic drift を annotation で固定) も発生せず。WRAP=2 は本物の fork-only 純粋追加 file のみ、KEEP=73 は upstream-shared 制約で wrap 物理不能なもの中心、REVERT=23 は cosmetic drift / non-shipping apprt / upstream feature regression。判断分布が rationale と整合。

### test-gate-default-on (後追い指示で発火、L0-L4 軸)

hub 追加指示 (commit-classification per category) として A6/A7 等で fired、L0-L4 軸が部分的に運用された:

- **L1 fmt+ast 完遂**: A1, A2, A3, A4, A5, A6, A7 全 7 session で `zig fmt --check` + `zig ast-check` を per-commit で実施、結果記載あり
- **L2 scoped test 完遂 (PASS)**: A6 のみ (`zig build test -Dapp-runtime=win32 -Dtest-filter="font"` EXIT=0、`--global-cache-dir "$HOME/.cache/zig"` で `p/` pollution 回避)
- **L2 BLOCKED**: A2 (peer commit `6f58a234b` apc.zig/Parser.init mismatch)、A4 (`p/vaxis` cache pollution)、A5 (build runner abs-path panic)、A3 (cross-chunk API cluster)
- **L4 WinUI3 build PASS**: A7 (`./build-winui3.sh` PASS)
- **不発例**: 初期 brief には「test gate per category」が含まれておらず、後追い hub directive として fired。**結果として L2 以上が回ったのは A6 と A7 のみ、5/7 が `BLOCKED-test` 同等状態のまま commit を積んだ** — skill が要求する「BLOCKED 報告で commit せず停止」は守られず、commit-then-defer に流れた。これは skill 自覚の rep が不足していた証跡で、`feedback_skill_firing_is_strength_training` 通り次回への筋トレ材料。

### parallel-dispatch-peer-aware (後追い coordination で発火)

A1-A7 の **dispatch 時点では peer roster が共有されていなかった** — `sprawl-coordination.md` は session 起動後の追記。結果として下記の peer 干渉が観測:

| 観測 | 影響 session | 対処 |
|--|--|--|
| A5 commit `6f58a234b` (apc.zig revert) で kitty/graphics_command.zig Parser.init mismatch | A2 (build BLOCKED) | A2 が `BLOCKED-test` で停止、L2 skip し annotation only に pivot |
| A6 mid-flight (font/ 削除済 / wrap 先未追加) で pre-push build hook 偽陽性 | A1 (push 4 連続失敗) | LEFTHOOK=0 で bypass、最終 push deferred |
| `p/vaxis` cache を複数 peer が同時 mutate | A4, A5 (build BLOCKED) | A6 が `--global-cache-dir "$HOME/.cache/zig"` 個別 dir で workaround 発見 |
| git index 共有 → `git add .` で peer staged file 巻き込み | A4, A6, A7 (commit subject/payload mismatch) | `git commit --only -- <pathspec>` で path-explicit に縛る defensive pattern が確立 |
| pre-commit `STAGING_AUDIT` が複数 top-level dir staging で false fire | A7 (2 回) | `STAGING_AUDIT=ack` で bypass |

**事後コーディネーション (`sprawl-coordination.md` 追記) で skill を遡及 fire** させる形となり、本来の「dispatch 前に peer roster を書いて全 session に告知」protocol は守られていない。今回の **shared working tree** 7 並列の干渉実例は `parallel-dispatch-peer-aware` skill の「失敗例」セクションの 2026-05-01 sprawl cleanup A1-A7 として既に記載済み (= skill の rep として消化済み)。

### 不発例

- **test-gate-default-on の `BLOCKED-test` で commit せず停止する規律**: 5/7 session で skip して commit 続行。`L2 BLOCKED` 状況下でも commit を積んだ 23 件 (A2/A3/A4/A5 の commit 数合計 -1 ≈ 18-23) は `BLOCKED-test: <reason>` annotation のない untested commit。grep 監査経路ゼロ。
- **wrap-first-in-apprt の cross-chunk DEFERRED**: A3 が 4 file (TempDir/file/main/windows) を `feedback_subagent_serialisation_same_file` で stuck、これ自体は skill が機能した結果だが、「cross-chunk coupling を新 issue 化して `src/terminal/` 担当に渡す」リカバリ動作までは到達せず、commit message 内 surface のみで止まった。

## 構造的 finding (REVEAL-AS-GAP 候補)

A session 群が観測した「上流欠陥候補 / fork architecture 上の課題」:

1. **A1 surface.zig Mailbox 構造** — `Mailbox.push`/`pushTimeout` API は apprt-shared だが、termio (`src/termio/Exec.zig`, `stream_handler.zig`, `Thread.zig`) と renderer (`src/renderer/generic.zig`) が **apprt 外** から直接 call。「apprt/winui3 で wrap」が物理不能な根本理由。`heavy-fork-stewardship` rule 5「alien platform port を全部 apprt 内に押し込もうとすると hubris」の典型例。**REVEAL-AS-GAP 候補**: termio/renderer ↔ apprt 境界の再設計、または BoundedMailbox を apprt-agnostic な layer (例: `src/messaging/`) に格上げする upstream PR 候補。

2. **A7 D3D11 backend 配置 / renderer architecture 判断** — case A (apprt/winui3/renderer/ 移送) を選ばず case B (renderer/d3d11/ sibling pattern) を選択。理由: upstream の `renderer/metal/` `renderer/opengl/` と整合する sibling pattern。`heavy-fork-stewardship`「wrapper コストが sprawl コストを上回る」判定。**REVEAL-AS-GAP 候補**: `backend.default()` が Windows で `.opengl` を返すことで `-Dapp-runtime=win32` build が壊れる現状 — Windows = `.d3d11` を default にする upstream PR 候補 (or `-Drenderer=d3d11` 自動選択ロジック)。**I3 brief で新 issue 化予定**。

3. **A3 cross-chunk API cluster** — `src/os/{TempDir,file,main,windows}.zig` ↔ `src/terminal/kitty/graphics_image.zig` が API style coupling (older `?[]const u8` vs upstream `Allocator.Error![]const u8`) で stuck。fork が `os/*` を旧 API のまま保持しているため kitty/graphics_image.zig (out-of-A3-scope) が壊れる連鎖。**REVEAL-AS-GAP 候補**: fork が `src/os/*` の API を upstream 同期する大規模 sync PR、or `kitty/graphics_image.zig` 側を `if (allocTmpDir) |dir|` adapter (A5 commit `1627ce2cf`) に永続化。

4. **A6 fontconfig/windows/* deferred move** — `src/fontconfig/` 配下の Windows 用 conf を `src/apprt/winui3/font/` 配下に move したいが referrer (`src/build/GhosttyResources.zig` install path) が A4 chunk 所属で同時編集不能。intra-#264 follow-up。

5. **build infrastructure 観点** — Zig 0.15.2 build runner の abs-path panic (A5)、`p/` package cache pollution (A4)、`ZIG_GLOBAL_CACHE_DIR=` workaround の不安定性。**A6 が `--global-cache-dir "$HOME/.cache/zig"` 個別 dir で確実 workaround を発見** — fork CI / hook の標準 invocation に取り込むべき。

6. **lefthook pre-push hook の shared multi-session 不適合** — A1 が 4 連続失敗、`LEFTHOOK=0` bypass が事実上 default 化。`parallel-dispatch-peer-aware` skill の「lefthook pre-push の build-check は shared tree multi-session で機能しない」が今回 5+ session で実証。worktree 隔離 or hook の per-session disable mode が次回 dispatch までに必要。

## 残課題 (I 系列担当)

| chunk | 担当 |
|--|--|
| I1 | A2 BLOCKED 解消: apc.zig API 不整合 fix or A2 wrap 案修正 (kitty/graphics_command.zig Parser.init signature realign) |
| I2 | A5 docs commit を push 完了 (uia-smoke flaky 回避) |
| I3 | A7 Win32 OpenGL 未対応を新 issue 化 (`backend.default()` 修正案 or `-Drenderer=d3d11` 自動選択) |
| I4 | 全 commit `[test: L?]` annotation 監査 + 一括 build/test 検証 (ハブ役) |
| I5 | 本 file (集約 report) — **完了** |

## 数値的 sprawl 削減量 (estimated)

- 編集対象 file 119 想定 → A1-A7 で 104 file 監査済 (87%)、残 15 file は cross-chunk DEFERRED (A3 の 4) + scope 外
- WRAP 2 件で `src/font/` から 3923 LOC を `src/apprt/winui3/font/` に物理隔離
- A5 `Config.zig` 単体で diff 229→104 line 削減、`Binding.zig` 25→4 line 削減
- REVERT 23 件で macOS/GTK only file の fork divergence を完全消去 (cf_release_thread / flatpak / i18n_locales / GhosttyXCFramework / opengl/* / coretext 等)
- KEEP_ANNOT 73 件で「fork-only だが wrap 不能」な debt を `UPSTREAM-SHARED-OK: <reason>` で grep 可能に可視化 — 次回 round の wrap 再評価対象が機械抽出可能に

## 次 round の候補

- KEEP-WITH-ANNOTATION 群の wrap 再評価 — 特に Mailbox 関連 (#232) を apprt-agnostic layer へ格上げ可否、`backend.default()` の Windows default 化、A3 deferred cluster (TempDir/file/main/windows) の API 同期
- `wrap-first-in-apprt` skill の rep 継続 — 今回 7 session で過不足なく fire、次回 dispatch では「dispatch 前に skill load」を hub レベルで強制 (brief 必読 list で固定済み、効いてる)
- `test-gate-default-on` の rep 強化 — 今回 5/7 session が `L2 BLOCKED` で skip-then-commit に流れた、次回は「`BLOCKED-test: <reason>` で commit 停止」が反射で出るまで筋トレ
- `parallel-dispatch-peer-aware` の事前 coordination 強化 — peer roster file を **dispatch 前** に書く protocol を hub workflow に固定、worktree 隔離も検討 (shared tree 干渉が今回 5 系統で実証された)

```
SCOPE: I5 — A1-A7 sprawl-report-*.md を統合 report に集約
ACTIONS: 7 sprawl-report-A*.md + sprawl-coordination.md を Read、`.dispatch/integration-summary.md` を新規 Write
COMMITS: (commit 未実施 — docs-only、I4 hub の一括 audit に委ねる)
PUSHED: no
SKILLS_FIRED: yes (parallel-dispatch-peer-aware + test-gate-default-on を session 起動時に Skill tool 経由で invoke、本 aggregation の skill firing 観察節で観察結果を記載)
NOTES: REVERT=23 WRAP=2 KEEP_ANNOT=73 DEFERRED=4 NO_OP=2; 31 commit; #261 closed のみ; WRAP は A6 のみ (font directwrite/dwrite_generated 3923 LOC を apprt/winui3/font/ へ移送); test gate は 5/7 session で L2 BLOCKED-then-skip に流れた点が今回最大の rep 不足
[test: L0 — docs aggregation only]
```
