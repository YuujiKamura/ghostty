# Debug Build Performance Optimization

---
最終更新: 2026-04-12
完了: 3/5 タスク
---

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** デバッグビルドでも日常使いできる速度にする（slow_runtime_safetyの制御オプション追加 + ホットパスログ最適化）

**Architecture:** ビルドオプション `-Dslow-safety` を追加し、Config→terminal_options→build_config経由でintegrity checksのON/OFFを制御。build-winui3.shのデフォルトをfalseに設定。

**Tech Stack:** Zig build system, build_config.zig, terminal build_options

**Issue:** #85

---

### Task 1: ビルドオプション `-Dslow-safety` を追加 [x]
<!-- src/build/Config.zig に slow_safety フィールドと -Dslow-safety オプション実装済み -->

**Files:**
- Modify: `src/build/Config.zig:66-110` (init関数)
- Modify: `src/build/Config.zig:514-524` (terminalOptions関数)

**Step 1: Config.zig の init() に `-Dslow-safety` オプションを追加**

`src/build/Config.zig` の `init()` 内、`optimize` 取得直後に追加:

```zig
const slow_safety = b.option(bool, "slow-safety", "Enable slow runtime safety checks (default: true for Debug)") orelse switch (optimize) {
    .Debug => true,
    .ReleaseSafe, .ReleaseSmall, .ReleaseFast => false,
};
```

Config構造体にフィールド追加:
```zig
slow_safety: bool = true,
```

init() の `.config` 初期化に追加:
```zig
.slow_safety = slow_safety,
```

**Step 2: terminalOptions() で slow_safety を使うように変更**

`src/build/Config.zig` の terminalOptions 内:

```zig
// Before:
.slow_runtime_safety = switch (self.optimize) {
    .Debug => true,
    .ReleaseSafe, .ReleaseSmall, .ReleaseFast => false,
},

// After:
.slow_runtime_safety = self.slow_safety,
```

**Step 3: ビルド確認**

```bash
# デフォルト（Debug = slow_safety true）
zig build -Dapp-runtime=winui3 --prefix zig-out-winui3 2>&1 | head -5

# slow-safety=false 指定
zig build -Dapp-runtime=winui3 -Dslow-safety=false --prefix zig-out-winui3 2>&1 | head -5
```

Expected: 両方ともビルド成功

**Step 4: コミット**

```bash
git add src/build/Config.zig
git commit -m "feat(build): add -Dslow-safety option to control integrity checks in Debug builds (#85)"
```

---

### Task 2: build_config.zig を build_options 経由に統一 [-]
<!-- 要確認: build_config.zig の slow_runtime_safety が build_options 経由かどうか未確認 -->

**Files:**
- Modify: `src/build_config.zig:75-81`

**Step 1: slow_runtime_safety の定義を確認**

現在 `src/build_config.zig:75` は comptime で `builtin.mode` から判定している。
`src/terminal/build_options.zig` 経由の `slow_runtime_safety` と二重定義になっている。

terminal以外のコード（renderer等）が `build_config.slow_runtime_safety` を参照しているか確認:

```bash
grep -r "build_config\.slow_runtime_safety" src/ --include="*.zig" | grep -v terminal/
```

参照がなければ terminal 側の build_options 経由のみで十分。参照があれば build_config.zig 側も同様にオプション化する。

**Step 2: build_config.zig の fallback を確認して対応**

terminal外から参照がある場合、build_config.zig側も `-Dslow-safety` に連動させる必要がある。
（具体的な修正はStep 1の結果次第）

**Step 3: ビルド確認**

```bash
zig build -Dapp-runtime=winui3 -Dslow-safety=false --prefix zig-out-winui3
```

**Step 4: コミット**

```bash
git add src/build_config.zig
git commit -m "refactor(build): unify slow_runtime_safety with -Dslow-safety option (#85)"
```

---

### Task 3: build-winui3.sh にデフォルトオプション追加 [x]
<!-- build-winui3.sh に -Dslow-safety=false が含まれていることを確認済み -->

**Files:**
- Modify: `build-winui3.sh`

**Step 1: 現在のbuild-winui3.shを確認**

```bash
cat build-winui3.sh
```

**Step 2: `-Dslow-safety=false` をデフォルトに追加**

既存の `--prefix zig-out-winui3` と同様に、`-Dslow-safety=false` をデフォルト引数に追加。
コメントで意図を明記:

```bash
# Disable slow integrity checks for usable debug builds (re-enable with -Dslow-safety=true)
```

**Step 3: ビルド確認**

```bash
./build-winui3.sh
```

Expected: ビルド成功、zig-out-winui3/bin/ に出力

**Step 4: コミット**

```bash
git add build-winui3.sh
git commit -m "perf(build): disable slow safety checks by default in WinUI3 debug builds (#85)"
```

---

### Task 4: ホットパスのログレベル最適化 [-]
<!-- 実装状態未確認 -->

**Files:**
- Modify: `src/apprt/winui3/Surface.zig` (スクロールバー更新のlog.debug)
- Modify: `src/renderer/generic.zig` (レンダリングループのlog.debug)

**Step 1: ホットパスのlog.debugを特定**

以下が毎フレーム/毎イベントで呼ばれるログ:
- `src/apprt/winui3/Surface.zig` の `onScrollBarValueChanged` 内
- `src/renderer/generic.zig` のフレーム処理内

**Step 2: 頻度の高いログをコメントアウトまたは条件付きに**

毎フレーム呼ばれるものは `if (comptime build_config.slow_runtime_safety)` ガードで囲む。
初期化時の1回きりのログはそのまま残す。

**Step 3: ビルド確認**

```bash
./build-winui3.sh
```

**Step 4: コミット**

```bash
git add src/apprt/winui3/Surface.zig src/renderer/generic.zig
git commit -m "perf(log): gate hot-path debug logs behind slow_runtime_safety (#85)"
```

---

### Task 5: 性能比較テスト [-]
<!-- 手動実行タスク。実行未確認 -->

**Step 1: 3モードでビルド**

```bash
# Mode A: Debug (slow_safety=true, デフォルト)
zig build -Dapp-runtime=winui3 -Dslow-safety=true --prefix zig-out-winui3-slow

# Mode B: Debug (slow_safety=false, 新デフォルト)
./build-winui3.sh

# Mode C: ReleaseFast
zig build -Dapp-runtime=winui3 -Doptimize=ReleaseFast --prefix zig-out-winui3-fast
```

**Step 2: 各モードで大量出力テスト**

```powershell
# 各バイナリで起動し、以下を実行:
seq 1 10000
# または
yes "long line of text for performance testing" | head -5000
```

体感でフリーズするかどうか、スクロール追随の滑らかさを確認。

**Step 3: 結果をイシューにコメント**

```bash
gh issue comment 85 --body "性能比較結果: ..."
```
