// Auto-generated from C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd
// DO NOT EDIT — regenerate with: winmd2zig C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd IWindow
pub const IWindow = extern struct {
    // WinMD: Microsoft.UI.Xaml.IWindow
    // Blob: 01 00 79 ec f0 61 52 5d b5 56 86 fb 40 fa 4a f2 88 b0
    pub const IID = GUID{ .Data1 = 0x61f0ec79, .Data2 = 0x5d52, .Data3 = 0x56b5,
        .Data4 = .{ 0x86, 0xfb, 0x40, 0xfa, 0x4a, 0xf2, 0x88, 0xb0 } };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IWindow (slots 6-28)
        get_Bounds: VtblPlaceholder, // 6
        get_Visible: VtblPlaceholder, // 7
        get_Content: VtblPlaceholder, // 8
        put_Content: VtblPlaceholder, // 9
        get_CoreWindow: VtblPlaceholder, // 10
        get_Compositor: VtblPlaceholder, // 11
        get_Dispatcher: VtblPlaceholder, // 12
        get_DispatcherQueue: VtblPlaceholder, // 13
        get_Title: VtblPlaceholder, // 14
        put_Title: VtblPlaceholder, // 15
        get_ExtendsContentIntoTitleBar: VtblPlaceholder, // 16
        put_ExtendsContentIntoTitleBar: VtblPlaceholder, // 17
        add_Activated: VtblPlaceholder, // 18
        remove_Activated: VtblPlaceholder, // 19
        add_Closed: VtblPlaceholder, // 20
        remove_Closed: VtblPlaceholder, // 21
        add_SizeChanged: VtblPlaceholder, // 22
        remove_SizeChanged: VtblPlaceholder, // 23
        add_VisibilityChanged: VtblPlaceholder, // 24
        remove_VisibilityChanged: VtblPlaceholder, // 25
        Activate: VtblPlaceholder, // 26
        Close: VtblPlaceholder, // 27
        SetTitleBar: VtblPlaceholder, // 28
    };

    pub fn release(self: *IWindow) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// Auto-generated from C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd
// DO NOT EDIT — regenerate with: winmd2zig C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd ITabView
pub const ITabView = extern struct {
    // WinMD: Microsoft.UI.Xaml.Controls.ITabView
    // Blob: 01 00 e1 09 b5 07 38 1d 1b 55 95 f4 47 32 b0 49 f6 a6
    pub const IID = GUID{ .Data1 = 0x07b509e1, .Data2 = 0x1d38, .Data3 = 0x551b,
        .Data4 = .{ 0x95, 0xf4, 0x47, 0x32, 0xb0, 0x49, 0xf6, 0xa6 } };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // ITabView (slots 6-60)
        get_TabWidthMode: VtblPlaceholder, // 6
        put_TabWidthMode: VtblPlaceholder, // 7
        get_CloseButtonOverlayMode: VtblPlaceholder, // 8
        put_CloseButtonOverlayMode: VtblPlaceholder, // 9
        get_TabStripHeader: VtblPlaceholder, // 10
        put_TabStripHeader: VtblPlaceholder, // 11
        get_TabStripHeaderTemplate: VtblPlaceholder, // 12
        put_TabStripHeaderTemplate: VtblPlaceholder, // 13
        get_TabStripFooter: VtblPlaceholder, // 14
        put_TabStripFooter: VtblPlaceholder, // 15
        get_TabStripFooterTemplate: VtblPlaceholder, // 16
        put_TabStripFooterTemplate: VtblPlaceholder, // 17
        get_IsAddTabButtonVisible: VtblPlaceholder, // 18
        put_IsAddTabButtonVisible: VtblPlaceholder, // 19
        get_AddTabButtonCommand: VtblPlaceholder, // 20
        put_AddTabButtonCommand: VtblPlaceholder, // 21
        get_AddTabButtonCommandParameter: VtblPlaceholder, // 22
        put_AddTabButtonCommandParameter: VtblPlaceholder, // 23
        add_TabCloseRequested: VtblPlaceholder, // 24
        remove_TabCloseRequested: VtblPlaceholder, // 25
        add_TabDroppedOutside: VtblPlaceholder, // 26
        remove_TabDroppedOutside: VtblPlaceholder, // 27
        add_AddTabButtonClick: VtblPlaceholder, // 28
        remove_AddTabButtonClick: VtblPlaceholder, // 29
        add_TabItemsChanged: VtblPlaceholder, // 30
        remove_TabItemsChanged: VtblPlaceholder, // 31
        get_TabItemsSource: VtblPlaceholder, // 32
        put_TabItemsSource: VtblPlaceholder, // 33
        get_TabItems: VtblPlaceholder, // 34
        get_TabItemTemplate: VtblPlaceholder, // 35
        put_TabItemTemplate: VtblPlaceholder, // 36
        get_TabItemTemplateSelector: VtblPlaceholder, // 37
        put_TabItemTemplateSelector: VtblPlaceholder, // 38
        get_CanDragTabs: VtblPlaceholder, // 39
        put_CanDragTabs: VtblPlaceholder, // 40
        get_CanReorderTabs: VtblPlaceholder, // 41
        put_CanReorderTabs: VtblPlaceholder, // 42
        get_AllowDropTabs: VtblPlaceholder, // 43
        put_AllowDropTabs: VtblPlaceholder, // 44
        get_SelectedIndex: VtblPlaceholder, // 45
        put_SelectedIndex: VtblPlaceholder, // 46
        get_SelectedItem: VtblPlaceholder, // 47
        put_SelectedItem: VtblPlaceholder, // 48
        ContainerFromItem: VtblPlaceholder, // 49
        ContainerFromIndex: VtblPlaceholder, // 50
        add_SelectionChanged: VtblPlaceholder, // 51
        remove_SelectionChanged: VtblPlaceholder, // 52
        add_TabDragStarting: VtblPlaceholder, // 53
        remove_TabDragStarting: VtblPlaceholder, // 54
        add_TabDragCompleted: VtblPlaceholder, // 55
        remove_TabDragCompleted: VtblPlaceholder, // 56
        add_TabStripDragOver: VtblPlaceholder, // 57
        remove_TabStripDragOver: VtblPlaceholder, // 58
        add_TabStripDrop: VtblPlaceholder, // 59
        remove_TabStripDrop: VtblPlaceholder, // 60
    };

    pub fn release(self: *ITabView) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// Auto-generated from C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd
// DO NOT EDIT — regenerate with: winmd2zig C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd IApplicationStatics
pub const IApplicationStatics = extern struct {
    // WinMD: Microsoft.UI.Xaml.IApplicationStatics
    // Blob: 01 00 f5 09 0d 4e 58 43 2c 51 a9 87 50 3b 52 84 8e 95
    pub const IID = GUID{ .Data1 = 0x4e0d09f5, .Data2 = 0x4358, .Data3 = 0x512c,
        .Data4 = .{ 0xa9, 0x87, 0x50, 0x3b, 0x52, 0x84, 0x8e, 0x95 } };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IApplicationStatics (slots 6-9)
        get_Current: VtblPlaceholder, // 6
        Start: VtblPlaceholder, // 7
        LoadComponent: VtblPlaceholder, // 8
        LoadComponent_2: VtblPlaceholder, // 9
    };

    pub fn release(self: *IApplicationStatics) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// Auto-generated from C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd
// DO NOT EDIT — regenerate with: winmd2zig C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd IApplicationFactory
pub const IApplicationFactory = extern struct {
    // WinMD: Microsoft.UI.Xaml.IApplicationFactory
    // Blob: 01 00 57 66 d9 9f 94 52 65 5a a1 db 4f ea 14 35 97 da
    pub const IID = GUID{ .Data1 = 0x9fd96657, .Data2 = 0x5294, .Data3 = 0x5a65,
        .Data4 = .{ 0xa1, 0xdb, 0x4f, 0xea, 0x14, 0x35, 0x97, 0xda } };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IApplicationFactory (slots 6-6)
        CreateInstance: VtblPlaceholder, // 6
    };

    pub fn release(self: *IApplicationFactory) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// Auto-generated from C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd
// DO NOT EDIT — regenerate with: winmd2zig C:\Users\yuuji\AppData\Local\Temp\Microsoft.UI.Xaml.winmd IApplication
pub const IApplication = extern struct {
    // WinMD: Microsoft.UI.Xaml.IApplication
    // Blob: 01 00 e7 f4 a8 06 46 11 af 55 82 0d eb d5 56 43 b0 21
    pub const IID = GUID{ .Data1 = 0x06a8f4e7, .Data2 = 0x1146, .Data3 = 0x55af,
        .Data4 = .{ 0x82, 0x0d, 0xeb, 0xd5, 0x56, 0x43, 0xb0, 0x21 } };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IApplication (slots 6-17)
        get_Resources: VtblPlaceholder, // 6
        put_Resources: VtblPlaceholder, // 7
        get_DebugSettings: VtblPlaceholder, // 8
        get_RequestedTheme: VtblPlaceholder, // 9
        put_RequestedTheme: VtblPlaceholder, // 10
        get_FocusVisualKind: VtblPlaceholder, // 11
        put_FocusVisualKind: VtblPlaceholder, // 12
        get_HighContrastAdjustment: VtblPlaceholder, // 13
        put_HighContrastAdjustment: VtblPlaceholder, // 14
        add_UnhandledException: VtblPlaceholder, // 15
        remove_UnhandledException: VtblPlaceholder, // 16
        Exit: VtblPlaceholder, // 17
    };

    pub fn release(self: *IApplication) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};
