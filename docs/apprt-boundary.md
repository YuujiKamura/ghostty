# apprt boundary contract — fork-isolation のための境界規約

> **SSOT 注記**: 本 doc は派生 view。規律の SSOT は skill `~/.agents/skills/wrap-first-in-apprt/SKILL.md`。
> contributor (human + AI) が PR review / edit 判断時に visible に参照できる形に doc 化したもの。
> 規律本体の更新は skill 側で行い、本 doc は同期される (drift 検知は別 brief 候補)。

## なぜこの doc が要るか

ghostty-win は ghostty-org/ghostty の fork。本体 (= upstream-shared 領域) を直接触る edit は **後で必ず削る対象 = 書いた瞬間から債務**。本家マージで毎回コンフリクトする / upstream PR では受け入れられない / audit で削るコストが蓄積する。

2026-05-01 時点の audit で **119 ファイル**が `src/apprt/winui3/` の外で fork-edit されていた。これは「edit する瞬間に止まる」規律が働いていなかった結果。本 doc はその規律を contributor 全員に共有するためにある。

---

## 1. 境界の定義

ghostty-win の `src/` は 2 領域に分かれる:

### 本体 (apprt 共通領域 = upstream-shared)

upstream `ghostty-org/ghostty` と共有される領域。**default 触るな**。代表 path:

- `src/Surface.zig`, `src/App.zig`, `src/Command.zig` — 本体 3 巨頭
- `src/global.zig` — bootstrap
- `src/os/` — OS layer (例: `src/os/args.zig` 等、`git ls-files src/os/` で全列挙)
- `src/apprt/runtime.zig`, `src/apprt/action.zig`, `src/apprt/structs.zig`, `src/apprt/surface.zig` — apprt 共通 interface
- `src/apprt/embedded.zig` — macOS embed 用 (出荷しない)
- `src/apprt/gtk/` — Linux GTK 用 (出荷しない)
- `src/apprt/winui3.zig`, `src/apprt/win32.zig` — apprt 切替の dispatcher
- `src/build/`, `src/build_config.zig` — ビルドシステム

> macOS native apprt (`src/apprt/macos/`) は upstream 側に存在するが本 fork では shipping していない (この repo では存在しない場合あり)。upstream 経路で merge され得るので **「ついで」に触るな**。

全列挙は `git ls-files src/apprt/` および `git ls-files src/` で抽出可能。本 doc では代表 path のみ列挙する。

### fork 固有領域 (winui3)

- `src/apprt/winui3/` — WinUI3 apprt 配下、**fork が自由に触れる場所**
- `xaml/` — WinUI3 host 側の XAML / build artifact (managed)

このうち本 doc が扱うのは `src/apprt/winui3/` 中心の規約。

### 絶対 NO (出荷しない apprt)

merge で revert される運命の領域。**例外なく触るな**:

- `src/apprt/embedded.zig` — macOS embed 用、出荷しない
- `src/apprt/gtk/` — Linux GTK 用、出荷しない

---

## 2. wrap-first 原則

`src/` を直接触る前に、**1 秒で答えろ**:

> **この変更、`src/apprt/winui3/` 側で wrap できないか?**

- 「できる」 → 本体は触るな、winui3 側に書け (= default)
- 「できない (と感じた)」 → 下記 3 つの wrap pattern で再確認
- それでも本当に wrap 不能 → 本体 minimal touch + `UPSTREAM-SHARED-OK:` annotation 必須 (§4)

迷ったら **main agent / human reviewer に escalate**。`build_config.app_runtime` 条件分岐を本体に書こうとしてる時点で wrap-first がほぼ失敗してる、最初に立ち止まれ。

---

## 3. wrap 推奨パターン例

### Pattern 1: ファイルごと apprt 配下に移す

WinUI3 でしか使わない機能は本体ではなく `src/apprt/winui3/` 配下に置く。本体 `src/global.zig` には comptime gated import を残すだけ。

実例: `src/os/fontconfig_env.zig` → `src/apprt/winui3/font/env.zig` (commit `b4fb7199e`)。

**適用条件**: その機能が winui3 でしか必要ない、本体の他の apprt はそれ無しで動く。

### Pattern 2: Delegation stub に縮める

本体に呼び出し点があるが、ロジックは apprt-specific な場合。本体には委譲スタブだけ残し、実装は `src/apprt/winui3/` (または `src/apprt/win32/`) に extract する。本体側のコメントには `UPSTREAM-SHARED-OK: minimize footprint only (#239)` annotation を残す。

実例: `src/Command.zig` の Win32 wait ロジックを `src/apprt/win32/spawn.zig` に extract (issue #239)。

**適用条件**: call site が本体に固定されているが、ロジック分離は可能。

### Pattern 3: Comptime parameter / hook injection

振る舞いが apprt 毎に違うが call site が本体にある (= 移動できない) 場合。本体は generic な hook 呼び出しだけにし、policy は apprt が注入する。

実例 (想定形): `src/Surface.zig` の focus mailbox push policy を、apprt-injected comptime hook にする。

**適用条件**: pattern 1/2 が両方使えない時のみ。実装コストが高い (Surface.zig 規模で 6-10h) ので、安易に「これしか手がない」と判定する前に pattern 1/2 を必ず先に検討。

### platform 固有 init の扱い

WinUI3 固有の起動経路 (例: XAML island bootstrap, WinRT registration) は `src/apprt/winui3/App.zig` 等の init 経路に置け。**`src/global.zig` に `if (build_config.app_runtime == .winui3)` 分岐を生やすな** ── これが §6 で言う sprawl の典型。

---

## 4. 本体を触っていい時の justify 手順

irreducible に本体を触る必要がある場合 (例: `src/build_config.zig` に新 build option を追加 / 共通 type の field 追加) のみ許可。**ただし全条件を満たせ**:

1. **annotation 必須**: 触る箇所のコメントに `// UPSTREAM-SHARED-OK: <一行で理由>` (例: `UPSTREAM-SHARED-OK: comptime branch on app_runtime, no runtime cost`)
2. **commit trailer 必須**: commit message 末尾に `UPSTREAM-SHARED-OK: <理由>` trailer を付ける
3. **justify は 2 種のいずれか**:
   - (a) **upstream に PR 出す予定** ── fork-only 価値ではなく upstream にも益がある変更
   - (b) **純粋 bugfix で他 apprt にも益がある** ── 例: race condition fix、null deref fix
4. **触る箇所を最小化**: 1 行で済むなら 1 行。巨大ブロック追加は避け、ロジックは apprt 側に extract する
5. **出荷しない apprt (embedded / gtk) は例外なく触るな** ── (a)(b) どちらの justify でも対象外

(a)(b) のどちらにも当てはまらない場合は touchable ではない、wrap-first に戻れ。

---

## 5. 過去事案: 119 file sprawl の reflection

2026-05-01 の audit 時点で `src/apprt/winui3/` 外に **119 ファイル** の fork-edit があった。これは「ちょっとだけだから本体に書く」が積み重なった結果。

学び:

- 「ちょっと」の積み重ねが 119 件、edit 1 件ごとに gate しないと止まらない
- `if (build_config.app_runtime == .winui3) { ... } else { ... }` を本体に増殖 = apprt が機能してない signal、wrap し直し対象
- `Surface.zig` に fork-only public method (例: `hasSelectionLocked`, `pwdLocked`, `panePid`, scrollbar callback) を生やす ── winui3 側で wrap & 委譲が正解
- 「あとで audit で拾う」前提で書くな ── **拾うコストは書くコストの 5x**、最初から wrap が安い
- 出荷しない apprt (embedded/gtk) を「ついでに」直すな ── merge で revert される運命

`build_config` 条件分岐が本体に増殖しているのは「wrap できる場所がない」のではなく、**wrap-first を edit 時に発火させていない**徴候。doc 化しても shortcut 化されるリスクは残るので、PR review で「これ wrap できないか?」を質問するのが運用の肝。

---

## 6. 関連参照

- **規律 SSOT**: `~/.agents/skills/wrap-first-in-apprt/SKILL.md` (本 doc の元になる skill)
- **上位 framework**: `~/.agents/skills/heavy-fork-stewardship/` (fork 全体の運用規律)
- **upstream 提案作法**: `~/.agents/skills/oss-contribution-etiquette/`
- **境界 type 契約**: `docs/apprt-contract.md` (apprt interface 側、本 doc は edit 規律側)
- **WinUI3 specific**: `docs/winui3-contract-usage.md`, `docs/winui3-playbook.md`

---

## 7. 迷ったら escalate

「wrap できるか分からない」「本体を触る justify が (a)(b) のどちらに当たるか曖昧」── そう感じた時点で edit を止め、main agent (= 全体俯瞰を担う coordinator) または human reviewer に判断を委ねろ。本 doc の規約は context 依存の判断を完全には自動化しない。doc を shortcut として使うな。
