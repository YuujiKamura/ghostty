# WinUI3 COM Generator Requirements (2026-03-05)

## Goal

`src/apprt/winui3/com.zig` の再生成で ABI 崩壊を再発させないため、最低限の契約を固定する。

## Frozen Contracts

1. `IApplicationFactory.createInstance`  
`pub fn createInstance(self: *@This(), outer: ?*anyopaque) WinRTError!struct { inner: ?*anyopaque, instance: *IInspectable }`

2. `IXamlMetadataProvider.VTable.GetXmlnsDefinitions`  
`*const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT`

3. `ITabView` wrapper methods (App call-site required)
- `getTabItems`
- `putSelectedIndex`
- `addTabCloseRequested`
- `addAddTabButtonClick`
- `addSelectionChanged`

4. Required interfaces/constants
- `IVector`
- `IPropertyValueStatics`
- `IResourceDictionary`
- `IPanel`
- `ISolidColorBrush.Color`
- `IID_RoutedEventHandler`
- `IID_SizeChangedEventHandler`
- `IID_TypedEventHandler_TabCloseRequested`
- `IID_TypedEventHandler_AddTabButtonClick`
- `IID_SelectionChangedEventHandler`

## Generator Rules

1. WinRT の out 引数は戻り値に潰さず、vtbl 署名を保持する。  
2. `EventRegistrationToken` は `i64` として扱う。  
3. `HSTRING` と COM ポインタ引数を `i32` に降格しない。  
4. `createInstance` 系は `inner` と `instance` を返す構造化 wrapper を維持する。  
5. 互換 alias (`snake_case` / `CamelCase`) を壊さない。

## Validation Gate

変更後は下記 2 本を必須通過とする。

1. `zig test src/apprt/winui3/com_runtime.zig`  
2. `zig build -Dtarget=x86_64-windows -Dapp-runtime=winui3 -Drenderer=d3d11`

どちらか失敗なら生成変更を採用しない。

