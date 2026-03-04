# WinUI3: TabView有効時に初期タブが白画面になる

## 概要

WinUI3バックエンドで `TabView` を有効にした場合、初期タブのコンテンツが白画面になることがある。  
同一ビルドで `TabView` を使わない単一ビュー構成では、端末描画は正常に表示される。

## 期待動作

- TabView有効時でも、初期タブに端末コンテンツが表示されること
- 初期化直後の画面が白背景のまま固定されないこと

## 実際の動作

- Window/TabViewの生成ログは成功
- `SwapChainPanel` の作成と `SetSwapChain` も成功ログが出る場合がある
- それでも UI 上は白画面のままになるケースがある

## 再現条件（現時点）

1. `ghostty-win` を WinUI3 + D3D11 で起動
2. `GHOSTTY_WINUI3_ENABLE_TABVIEW=true`（既定）
3. 初期タブ表示時に白画面化

補足:
- `GHOSTTY_WINUI3_ENABLE_TABVIEW=false` 相当の単一ビュー構成では表示される

## 既知の事実

- `TabViewItem` への `putContent(panel)` 呼び出しは実行されている
- `IContentControl.getContent()` で read-back すると非nullを返すケースがある
- `Swap chain bound to SwapChainPanel (UI thread)` ログが出るケースでも白画面が発生する

## 仮説

1. **TabViewテンプレート/リソース適用不足**
   - `XamlControlsResources` の適用タイミングまたはリソース辞書構成が不完全
   - `TabViewBackground` 系リソースの未設定/不整合により白背景が前面化

2. **Composition SwapChain の Present設定不整合**
   - `SwapChainPanel` 経由で `DXGI_PRESENT_ALLOW_TEARING` を使うと描画されない環境差がある可能性

3. **TabView配下レイアウトとレンダーサイズのミスマッチ**
   - HWNDクライアントサイズと実際の `SwapChainPanel` の表示領域差

## 参考実装（Windows Terminal）

Windows Terminal では TabView を次の形で扱っている:

- `XamlControlsResources` を App リソースへマージ  
  `src/cascadia/TerminalApp/App.xaml`
- `TabViewBackground` 等のテーマ別リソース定義  
  `src/cascadia/TerminalApp/App.xaml`
- `TabViewItem.Content(Border{})` を明示設定する初期化（BODGY コメントあり）  
  `src/cascadia/TerminalApp/Tab.cpp`
- タブ選択/更新の管理  
  `src/cascadia/TerminalApp/TabManagement.cpp`
- TabView本体XAML  
  `src/cascadia/TerminalApp/TabRowControl.xaml`

## Geminiに依頼したい検討ポイント

1. Ghostty WinUI3 側の初期化順序を Windows Terminal と突き合わせ  
   （Application resources -> TabView create -> TabViewItem content -> selection）
2. `TabViewItem.Content` を `SwapChainPanel` 直設定せず、ラッパー `Grid/Border` を挟む方式の検証
3. `DXGI present flags` を composition path 専用に分岐した場合の影響評価
4. TabView系の `ThemeDictionaries` 最小セットを追加した場合の再現率変化

## 関連ファイル（ghostty-win）

- `src/apprt/winui3/App.zig`
- `src/apprt/winui3/Surface.zig`
- `src/apprt/winui3/com.zig`
- `src/renderer/D3D11.zig`

