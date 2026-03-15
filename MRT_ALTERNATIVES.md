# MRT Core ResourceManager 代替調査結果

## 現状の問題

`IResourceManagerFactory.CreateInstance("MinimalXaml.pri")` がエラー329 (`ERROR_OPERATION_IN_PROGRESS`, HRESULT `0x80070149`) で失敗。
DllGetActivationFactory は成功しているため、DLL ロードとファクトリ取得は正常。

## 1. IActivationFactory.ActivateInstance() — デフォルトコンストラクタ

**結論: 使える。ResourceManager はデフォルトコンストラクタを持つ。**

IDL 定義（WindowsAppSDK ソース `Microsoft.Windows.ApplicationModel.Resources.idl`）:
```
runtimeclass ResourceManager : [default] IResourceManager
{
    ResourceManager();           // ← デフォルトコンストラクタ
    ResourceManager(String fileName);  // ← ファイル名指定コンストラクタ
}
```

WinRT の `[Activatable]` 属性が2つ付いている:
- `[Activatable(65536, "...MrtContract")]` — デフォルトコンストラクタ（IActivationFactory.ActivateInstance）
- `[Activatable(IResourceManagerFactory, 65536, "...MrtContract")]` — fileName 指定（IResourceManagerFactory.CreateInstance）

**デフォルトコンストラクタの内部動作** (`ResourceManager.cpp`):
```cpp
ResourceManager::ResourceManager()
{
    winrt::hstring filePath;
    winrt::check_hresult(GetDefaultPriFile(filePath));  // ← 自動検索
    HRESULT hr = MrmCreateResourceManager(filePath.c_str(), &m_resourceManagerHandle);
    if (!IsResourceNotFound(hr)) { winrt::check_hresult(hr); }
}
```

デフォルトコンストラクタは `GetDefaultPriFile()` で PRI ファイルを **自動検索** する。
PRI が見つからなくてもエラーにはならない（`IsResourceNotFound` で吸収）。

**実装方法**: `IActivationFactory` の `ActivateInstance` (vtbl slot 6) を使う。
現コードの `getResourceManagerFactoryDirect()` で取得した factory ポインタを `IActivationFactory` として QI するか、
DllGetActivationFactory の戻り値は IActivationFactory そのものなので直接使える。

```zig
// factory は DllGetActivationFactory で取得済み
const activation_factory: *winrt.IActivationFactory = @ptrCast(@alignCast(factory));
const resource_manager = try activation_factory.activateInstance();
// → IInspectable が返る。必要なら IResourceManager に QI
```

## 2. PRI ファイルのパス指定

**結論: ファイル名のみ（バックスラッシュなし）が正しい。フルパスも可。`ms-appx:///` URI は不可。**

`MrmCreateResourceManager` のソースコード:
```cpp
if (wcschr(priFileName, L'\\') == nullptr)
{
    // バックスラッシュがない → ファイル名のみ → MrmGetFilePathFromName で解決
    MrmGetFilePathFromName(priFileName, &filepath);
    SetApplicationPriFile(filepath, ...);
}
else
{
    // バックスラッシュがある → フルパスとしてそのまま使用
    SetApplicationPriFile(priFileName, ...);
}
```

### ファイル名のみの場合の検索順序
`MrmGetFilePathFromName(filename)` は以下の順で検索:
1. **exe のあるディレクトリ** + filename（例: `...\bin\MinimalXaml.pri`）
2. **exe の親ディレクトリ** + filename

### フルパスの場合
バックスラッシュ (`\`) を含むパスはそのまま `SetApplicationPriFile` に渡される。

### 現コードの `"MinimalXaml.pri"` は正しいか？
- ファイル名のみ → `MrmGetFilePathFromName` が `ghostty.exe` と同じディレクトリで検索
- `zig-out-winui3-islands/bin/` に `ghostty.exe` と `MinimalXaml.pri` が両方あるので **パスは正しい**

### フルパスで試す場合
```zig
const pri_path = winrt.hstring("C:\\Users\\yuuji\\ghostty-win\\zig-out-winui3-islands\\bin\\MinimalXaml.pri");
```

## 3. PRI ファイル名の規約

**結論: unpackaged app では `resources.pri` が推奨だが必須ではない。ただし、デフォルトコンストラクタを使う場合は `resources.pri` が検索される。**

### デフォルトコンストラクタ (ActivateInstance) の検索順序
`GetDefaultPriFile()` → `MrmGetFilePathFromName(nullptr)` の検索順:
1. `MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY` 環境変数のディレクトリ + `resources.pri`
2. 同ディレクトリ + `[exe名].pri`（例: `ghostty.pri`）
3. exe のあるディレクトリ + `resources.pri`
4. exe のあるディレクトリ + `[exe名].pri`（例: `ghostty.pri`）

### Microsoft ドキュメントの記述
> "A package typically contains a single PRI file per language, named **resources.pri**."
> "The **resources.pri** file at the root of each package is automatically loaded when the ResourceManager object is instantiated."

### unpackaged app のドキュメント
> "Use the overloaded constructor of ResourceManager to pass file name of your app's .pri file when resolving resources from code as there is no default view in unpackaged scenarios."
> MakePri.exe の出力例: `makepri new /pr <PROJECTROOT> /cf <PRICONFIG> /of resources.pri`

### 結論
- **デフォルトコンストラクタを使うなら**: `resources.pri` か `ghostty.pri` にリネームすべき
- **CreateInstance(fileName) を使うなら**: `MinimalXaml.pri` のままでも動くはず
- **推奨**: `resources.pri` にリネームしてデフォルトコンストラクタを使う

## 4. winui3-baseline での MRT Core 使用状況

**結論: winui3-baseline は ResourceManager を明示的に使っていない。**

- C# コード内に `ResourceManager`, `MrtCore`, `ResourceLoader` の呼び出しなし
- PRI ファイルは MSBuild が自動生成: `WinUI3Baseline.pri`, `Microsoft.UI.pri`, `Microsoft.UI.Xaml.Controls.pri`
- C# WinUI3 アプリはフレームワークが PRI を自動ロードするため、手動の ResourceManager 操作は不要
- `resources.pri` というファイルは存在しない（代わりに `WinUI3Baseline.pri` がある）

## 5. 推奨アクション

### 方法A: デフォルトコンストラクタ（最もシンプル）
1. `MinimalXaml.pri` を `resources.pri` にリネーム（ビルドスクリプトで対応）
2. `onResourceManagerRequested` で `IActivationFactory.ActivateInstance()` を使用
3. PRI が見つからなくてもクラッシュしない（内部で吸収される）

### 方法B: CreateInstance にフルパスを渡す
1. `GetModuleFileNameW` で exe パスを取得
2. ディレクトリ部分 + `MinimalXaml.pri` を結合してフルパスを作成
3. `IResourceManagerFactory.CreateInstance(full_path)` を呼ぶ

### 方法C: CreateInstance のファイル名をデバッグ
エラー329 の原因が PRI パスではない可能性もある:
- DllGetActivationFactory が返す factory が再入禁止状態かもしれない
- CreateInstance 呼び出し時に既に他の MRM 操作が進行中かもしれない
- `ERROR_OPERATION_IN_PROGRESS` は「操作が進行中」なので、初期化タイミングの問題の可能性

### エラー329の真因について
`ERROR_OPERATION_IN_PROGRESS` (0x80070149) は MRM 固有のエラーではなく、一般的な Win32 エラー。
考えられる原因:
- ResourceManagerRequested イベントハンドラ内で MRM を初期化しようとしているが、XAML フレームワーク側が既に MRM セッションを持っている
- **デフォルトコンストラクタなら MRM の再初期化を避けられる可能性がある**（内部で GetDefaultPriFile → MrmCreateResourceManager の流れが異なるパスを通る）

## ソース参照

- WindowsAppSDK `ResourceManager.cpp`: デフォルトコンストラクタは `GetDefaultPriFile()` → `MrmCreateResourceManager()` を呼ぶ
- WindowsAppSDK `Helper.cpp`: `GetDefaultPriFile()` は packaged/unpackaged を自動判定
- WindowsAppSDK `MRM.cpp`: `MrmCreateResourceManager()` はファイル名のみなら exe ディレクトリで検索、フルパスならそのまま使用
- WindowsAppSDK `MRM.cpp`: `MrmGetFilePathFromName(nullptr)` は `resources.pri` → `[exe名].pri` の順で検索
- MS Docs: unpackaged app では ResourceManager のオーバーロードコンストラクタで PRI ファイル名を渡す
