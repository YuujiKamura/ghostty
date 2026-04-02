# MRT Core: IResourceManagerFactory CreateInstance 失敗の原因分析

Issue #107

## 結論: vtable ずれ — DllGetActivationFactory の戻り値を直接キャストしている

`getResourceManagerFactoryDirect` が `DllGetActivationFactory` の戻り値を
`IResourceManagerFactory` に直接キャストしているため、vtable slot 6 で
**CreateInstance ではなく IActivationFactory.ActivateInstance を呼んでいる**。

---

## 1. com_generated.zig の IResourceManagerFactory vtable (行 20728-20743)

```
slot 0: QueryInterface
slot 1: AddRef
slot 2: Release
slot 3: GetIids
slot 4: GetRuntimeClassName
slot 5: GetTrustLevel
slot 6: CreateInstance(HSTRING, **) -> HRESULT
```

IID: `{11ee6370-8585-40f0-9c43-265c34443a51}`

vtable 定義自体は正しい。IInspectable (6スロット) + CreateInstance (1スロット) = 7スロット。

## 2. DllGetActivationFactory が返すもの

`DllGetActivationFactory` の署名 (MSDN):
```c
HRESULT WINAPI DllGetActivationFactory(
    _In_  HSTRING activatableClassId,
    _Out_ IActivationFactory **factory
);
```

**戻り値は常に `IActivationFactory*` である。** `IResourceManagerFactory*` ではない。

`IActivationFactory` の vtable:
```
slot 0: QueryInterface
slot 1: AddRef
slot 2: Release
slot 3: GetIids
slot 4: GetRuntimeClassName
slot 5: GetTrustLevel
slot 6: ActivateInstance(**IInspectable) -> HRESULT  ← ここが問題
```

## 3. 何が起きているか

`getResourceManagerFactoryDirect` (App.zig 行 1371-1395):

```zig
var factory: ?*anyopaque = null;
const hr = get_factory_fn(class_name, &factory);
// ...
return @ptrCast(@alignCast(factory.?));  // ← IActivationFactory* を IResourceManagerFactory* にキャスト
```

この直接キャストにより:
- `factory_guard.get().CreateInstance(pri_path)` を呼ぶと
- vtable slot 6 が参照される
- しかし実体は **IActivationFactory.ActivateInstance** (引数: `**IInspectable`)
- `CreateInstance` は `(HSTRING, *?*anyopaque)` を渡す
- ActivateInstance は第1引数を `*?*IInspectable` として解釈する
- HSTRING ポインタを IInspectable 出力ポインタとして扱い、不正な結果になる

エラー 329 は Zig の `@intFromError(error.WinRTFailed)` のインデックス値であり、
実際の HRESULT は `hrCheck` 内でログされている `0x????????` の値を確認する必要がある。

## 4. RoGetActivationFactory との違い

`winrt.getActivationFactory` (winrt.zig 行 225-228) は正しく動作する:

```zig
pub fn getActivationFactory(comptime T: type, class_name: HSTRING) WinRTError!*T {
    var factory: ?*anyopaque = null;
    try hrCheck(RoGetActivationFactory(class_name, &T.IID, &factory));
    return @ptrCast(@alignCast(factory orelse return error.WinRTFailed));
}
```

`RoGetActivationFactory` は **IID を受け取り**、内部で:
1. `DllGetActivationFactory` → `IActivationFactory*` を取得
2. `QueryInterface(IID, &out)` → 要求されたインターフェースを取得
3. 正しい vtable を持つポインタを返す

つまり `RoGetActivationFactory` は QI を自動的にやってくれる。
`DllGetActivationFactory` は QI をやらない。

## 5. 正しい呼び出しパターン

`getResourceManagerFactoryDirect` を以下のように修正する必要がある:

```
DllGetActivationFactory(class_name, &raw_factory)
  → raw_factory は IActivationFactory*
  → raw_factory.QueryInterface(IResourceManagerFactory.IID, &typed_factory)
  → typed_factory.CreateInstance(pri_path)
```

または、IActivationFactory として受け取り、`queryInterface` メソッドで変換:

```zig
fn getResourceManagerFactoryDirect(class_name: winrt.HSTRING) !*gen.IResourceManagerFactory {
    // ... LoadLibrary, GetProcAddress は同じ ...

    var raw_factory: ?*anyopaque = null;
    const hr = get_factory_fn(class_name, &raw_factory);
    if (hr < 0 or raw_factory == null) return error.WinRTFailed;

    // DllGetActivationFactory は IActivationFactory を返す
    const activation_factory: *winrt.IActivationFactory = @ptrCast(@alignCast(raw_factory.?));
    defer activation_factory.release();  // QI 成功後に release

    // QueryInterface で IResourceManagerFactory を取得
    return activation_factory.queryInterface(gen.IResourceManagerFactory);
}
```

## 6. 補足: CreateInstance の引数について

`CreateInstance` の引数 `"MinimalXaml.pri"` はファイル名だけで正しいか、
フルパスが必要かは別問題。vtable ずれを直してからでないと確認できない。

WinRT API ドキュメント (Microsoft.Windows.ApplicationModel.Resources.ResourceManager)
の ResourceManager(String) コンストラクタは PRI ファイルのパスを受け取るが、
unpackaged アプリでの相対パス解決がどうなるかは、vtable 修正後にテストで確認すべき。

## 参考リンク

- [DllGetActivationFactory (MSDN)](https://learn.microsoft.com/en-us/previous-versions/br205771(v=vs.85))
- [ResourceManager Class (Windows App SDK)](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.applicationmodel.resources.resourcemanager?view=windows-app-sdk-1.3)
- [WindowsAppSDK IDL ソース](https://github.com/microsoft/WindowsAppSDK/blob/main/dev/MRTCore/mrt/Microsoft.Windows.ApplicationModel.Resources/src/Microsoft.Windows.ApplicationModel.Resources.idl)
