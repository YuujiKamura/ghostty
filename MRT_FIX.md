# Unpackaged App MRT Core ResourceManager CLASS_NOT_REGISTERED Fix

## Cause
In an **unpackaged** application using the Windows App SDK (WinUI 3), calling `RoGetActivationFactory` (or its high-level equivalents like `winrt.getActivationFactory`) for the WinRT class `Microsoft.Windows.ApplicationModel.Resources.ResourceManager` often fails with **`CLASS_NOT_REGISTERED` (0x80040154)**.

This occurs because:
1.  **No System Registration:** Unlike built-in WinRT classes (e.g., `Windows.UI.Composition.Compositor`), MRT Core classes are not registered globally in the Windows COM/WinRT registry.
2.  **Missing from Framework Manifest:** Even after successfully initializing the Windows App SDK Bootstrapper (`MddBootstrapInitialize`), some namespaces—including `Microsoft.Windows.ApplicationModel.Resources`—are not always included in the framework package's manifest (`AppxManifest.xml`) in certain SDK versions (like 1.4/1.5).
3.  **Redirection Failure:** Since it's not in the manifest, the system's `RoGetActivationFactory` (in `combase.dll`) doesn't know how to redirect the activation to the implementation DLL in the framework package.

## Solution
In an unpackaged app, you must manually load the implementation DLL and call its exported **`DllGetActivationFactory`** function.

### Steps to Implement in Zig (Direct COM/WinRT)

1.  **Initialize the Bootstrapper:** Ensure `MddBootstrapInitialize` is called successfully. This adds the framework package to the process's package graph and DLL search path.
2.  **Load the Implementation DLL:** The MRT Core is implemented in `Microsoft.Windows.ApplicationModel.Resources.dll`. Because the bootstrapper added the framework package to the path, you can load it by name.
3.  **Call DllGetActivationFactory:** Directly request the activation factory for `Microsoft.Windows.ApplicationModel.Resources.ResourceManager`.

### Sample Zig Fix Pattern

Instead of:
```zig
const res_manager_class = winrt.hstring("Microsoft.Windows.ApplicationModel.Resources.ResourceManager") catch ...;
var factory = winrt.getActivationFactory(gen.IResourceManagerFactory, res_manager_class) catch ...;
```

Use a fallback pattern:
```zig
fn getResourceManagerFactory() !*gen.IResourceManagerFactory {
    const class_name = try winrt.hstring("Microsoft.Windows.ApplicationModel.Resources.ResourceManager");
    defer winrt.deleteHString(class_name);

    // 1. Try standard activation first
    if (winrt.getActivationFactory(gen.IResourceManagerFactory, class_name)) |factory| {
        return factory;
    } else |_| {
        // 2. Fallback for unpackaged: Manual load
        const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.Windows.ApplicationModel.Resources.dll");
        const module = std.os.windows.kernel32.GetModuleHandleW(dll_name) orelse 
                       std.os.windows.kernel32.LoadLibraryW(dll_name) orelse 
                       return error.WinRTFailed;

        const DllGetActivationFactoryFn = *const fn (winrt.HSTRING, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT;
        const get_factory_fn: DllGetActivationFactoryFn = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "DllGetActivationFactory") orelse return error.WinRTFailed);

        var factory: ?*anyopaque = null;
        try winrt.hrCheck(get_factory_fn(class_name, &gen.IResourceManagerFactory.IID, &factory));
        return @ptrCast(@alignCast(factory orelse return error.WinRTFailed));
    }
}
```

## Additional Requirements
*   **PRI File:** The `ResourceManager` requires a `.pri` file in the application directory. In an unpackaged app, the default `ResourceManager()` constructor looks for `resources.pri`. If your PRI is named `[AssemblyName].pri`, you must use `IResourceManagerFactory.CreateInstance(priPath)` to initialize it.
*   **Target Architecture:** Ensure your app is built for a specific architecture (x64, ARM64). `AnyCPU` is not supported for Windows App SDK WinRT activation.
