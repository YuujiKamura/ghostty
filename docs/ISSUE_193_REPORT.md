# Issue #193: DirectWrite Segfault & Tiny Text Fix Report

## 概要
Ghostty WinUI3 (XAML Islands) 版において、以下の2つの深刻な表示上の問題が発生していた。
1. **起動時・CJK文字表示時の Segfault**: フォントフォールバック処理中にクラッシュする。
2. **テキストサイズの縮小**: 高DPI環境でテキストが本来のサイズより著しく小さく表示される。

本レポートでは、これらの問題の根本原因の特定過程と、実施した修正内容について詳述する。

---

## 1. DirectWrite Segfault の修正

### 根本原因 A: 手書き VTable の定義ミス
`src/font/directwrite.zig` に存在した手書きの COM インターフェース定義において、`IDWriteFactory1` のメソッドスロット数が現実の ABI と不一致を起こしていた。
* **実際**: 2スロット (`GetEudcFontCollection`, `CreateCustomRenderingParams`)
* **コード**: 3スロットと定義されており、後続の `IDWriteFactory2` メソッド呼び出し時に 1スロット分のアドレスずれが発生。
* **結果**: `IDWriteFactory2::GetSystemFontFallback` を呼び出したつもりが、不正なアドレスを実行しようとして Segfault が発生。

### 根本原因 B: ジェネレータ (win-zig-bindgen) のバグ
手書き定義を廃止して自動生成に移行しようとした際、ジェネレータ側にも不具合が発見された。
* **内容**: Win32 COM におけるメソッド名の重複（オーバーライド）を Zig の構造体フィールド重複エラーを避けるために `_reserved_slot` としてスキップしていた。
* **問題**: DirectWrite のように `CreateCustomRenderingParams` が親と子で複数回定義される場合、これらは ABI 上で独立したスロットを占有するため、スキップすると VTable レイアウトが破壊される。

### 修正内容
1. **ジェネレータの修正**: `emit.zig` を修正し、!is_winrt_iface の場合は重複名にサフィックス（`_2`, `_3` 等）を付けて全スロットを出力するように変更。
2. **定義の刷新**: `dwrite_generated.zig` を最新の Win32 WinMD (70.0.11-preview) から再生成。
3. **コード統合**: `directwrite.zig` の手書き定義をすべて削除し、生成された `dw.IDWrite*` への参照に置き換え。`lpVtbl` 直接参照や `*void` キャストが必要な call site をすべて surgical に修正。

---

## 2. テキストサイズ縮小（Tiny Text）の修正

### 根本原因
2026-04-03 18:21付近に行われた upstream (本家) との同期 (`14b6fd6`) において、Windows 用マニフェストファイルが簡略化された変更を取り込んでいた。
* **差分**: `dist/windows/ghostty.manifest` から以下の設定が削除されていた。
  ```xml
  <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
  <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
  ```
* **結果**: プロセスが DPI Awareness を持たない（Unaware）と OS に判断され、高DPI環境でも 96DPI (100% スケール) として動作。物理的なピクセルサイズが半分以下になり、テキストが極端に小さく表示される原因となった。

### 修正内容
1. **マニフェストの復元**: `dist/windows/ghostty.manifest` に `PerMonitorV2` 設定を再追加。
2. **共通コントロールの復元**: 同時に削除されていた `Microsoft.Windows.Common-Controls` (v6) の依存関係も復元。

---

## 3. 検証結果

### 動作確認 (WinUI3 Runtime)
`./zig-out-winui3-test/bin/ghostty.exe` を起動し、以下のログ出力を確認。
* **DPI 認識**: `dpi=144`, `scale=1.50` (150% スケーリング環境で正しい値を認識)
* **セルサイズ**: `cell = .{ .width = 10, .height = 21 }` (スケーリング考慮済みのサイズ)
* **フォントフォールバック**: CJK 文字に対して「游ゴシック」が正しく適用され、クラッシュなし。
* **Visual Tree**: XAML Islands 経由の `SwapChainPanel` 描画、タブ操作、入力フォーカス管理がすべて正常動作。

---

## 4. Technical Deep Dive: 構造的知見の記録

今回の修正には、単なるコード修正では説明しきれない、複数のシステムが交差する技術的知見が含まれている。

### A. DirectWrite VTable スロットの「密かなずれ」
DirectWrite インターフェースは、COM の継承構造をそのまま VTable の並びに反映する。
* `IDWriteFactory` (21メソッド)
* `IDWriteFactory1` (2メソッド: `GetEudcFontCollection`, `CreateCustomRenderingParams`)
* `IDWriteFactory2` (5メソッド: `GetSystemFontFallback` はここに含まれる)

手書き定義では `IDWriteFactory1` を 3 スロットと誤認していた。この「+1」の誤差は、`IDWriteFactory1` 自体を呼ぶ分には問題にならないが、その後に続く `IDWriteFactory2` の全メソッドの関数ポインタを「1つ分後ろ」に押し出す。
結果として、`GetSystemFontFallback` を呼び出した際、実際にはその隣の `CreateFontFallbackBuilder` もしくは未定義のメモリ領域を叩くことになり、関数シグネチャの不一致、あるいは単純な不正アドレス参照による Segfault を引き起こした。
**教訓**: COM ABI において手書き定義は「爆弾」であり、WinMD 等の信頼できるメタデータから機械生成した定義への SSOT (Single Source of Truth) 化が不可欠である。

### B. ジェネレータにおける「名前重複」の扱い
`win-zig-bindgen` の初期実装では、Zig の `extern struct` フィールド名の重複を避けるため、同名メソッドを `_reserved_slot_N` というプレースホルダーに置き換えていた。
しかし、Win32 COM（特に DirectWrite や D3D11）では、**「親クラスと同じ名前だが、引数が異なるメソッド（オーバーロード）」が、VTable 上の全く別のスロットとして独立して存在する**ケースがある。
これをプレースホルダーにしてしまうと、名前空間の衝突は避けられるが、VTable のレイアウトそのものが破壊され、ABI 互換性が失われる。
**解決策**: フィールド名にサフィックス（`_2`, `_3`）を付けて Zig 側の衝突を回避しつつ、VTable スロットの実体をすべて維持するロジックが必要であった。

### C. マニフェスト消失による「計算ロジックの無力化」
テキストサイズが小さくなった問題の本質は、`src/font` の計算コードではなく、`dist/windows/ghostty.manifest` という「プロセス宣言」にあった。
* **現象**: `PerMonitorV2` 宣言がないプロセスに対し、Windows は「このアプリは高DPIを理解できない」と判断する。
* **副作用**: `GetDpiForWindow` などの API が、たとえ 4K モニター上であっても常に 96 (100%) を返すようになる。
* **結果**: Ghostty 内部の「DPI を考慮してフォントサイズを決定するロジック」に入力される変数が 96 固定になり、物理的に著しく小さいフォントがレンダリングされる。
これが「upstream とのマージ」という、一見無害な操作によって引き起こされた点は、マニフェストファイルが Windows アプリの挙動を支配する「暗黙のコード」であることを示唆している。

### D. FreeType と DirectWrite の協調（SimpleTextAnalysisSource）
Windows 版 Ghostty はレンダリングに FreeType を使うが、フォント探索とフォールバック（「この文字を表示できるフォントは何か？」の判定）には DirectWrite を使う。
今回の修正で `SimpleTextAnalysisSource` のシグネチャを厳密化した。これは DirectWrite の `MapCharacters` に渡すための COM 実装であり、`IUnknown` の参照カウント管理や UTF-16 文字列のメモリレイアウトにおいて、一分の隙も許されない（1バイトのずれが文字化けやクラッシュに直結する）。
今回の刷新により、この協調レイヤーの型安全性も確保された。
