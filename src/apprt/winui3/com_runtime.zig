const std = @import("std");
const winrt = @import("winrt.zig");
const com = @import("com.zig");

pub const HRESULT = winrt.HRESULT;
pub const GUID = winrt.GUID;

pub const S_OK: HRESULT = 0;
pub const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));

pub const IID_IUnknown = GUID{
    .Data1 = 0x00000000,
    .Data2 = 0x0000,
    .Data3 = 0x0000,
    .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

pub const IID_IAgileObject = GUID{
    .Data1 = 0x94ea2b94,
    .Data2 = 0xe9cc,
    .Data3 = 0x49e0,
    .Data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 },
};

pub const IID_IMarshal = GUID{
    .Data1 = 0x00000003,
    .Data2 = 0x0000,
    .Data3 = 0x0000,
    .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

pub fn guidEql(a: *const GUID, b: *const GUID) bool {
    return a.Data1 == b.Data1 and
        a.Data2 == b.Data2 and
        a.Data3 == b.Data3 and
        std.mem.eql(u8, &a.Data4, &b.Data4);
}

pub const IUnknownVTable = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
};

fn unknownVTable(this: *anyopaque) *const IUnknownVTable {
    const vtbl_ptr_ptr: *const *const IUnknownVTable = @ptrCast(@alignCast(this));
    return vtbl_ptr_ptr.*;
}

pub fn unknownQueryInterface(this: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) HRESULT {
    return unknownVTable(this).QueryInterface(this, riid, ppv);
}

pub fn unknownAddRef(this: *anyopaque) u32 {
    return unknownVTable(this).AddRef(this);
}

pub fn unknownRelease(this: *anyopaque) u32 {
    return unknownVTable(this).Release(this);
}

test "guidEql" {
    const testing = std.testing;
    const guid1 = GUID{
        .Data1 = 0x12345678,
        .Data2 = 0x9ABC,
        .Data3 = 0xDEF0,
        .Data4 = .{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 },
    };
    const guid2 = guid1;
    const guid3 = GUID{
        .Data1 = 0x00000000,
        .Data2 = 0x0000,
        .Data3 = 0x0000,
        .Data4 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    };

    try testing.expect(guidEql(&guid1, &guid2));
    try testing.expect(!guidEql(&guid1, &guid3));
    try testing.expect(guidEql(&IID_IUnknown, &IID_IUnknown));
}

test "IWindowNative IID matches WinUI3 oracle" {
    const testing = std.testing;
    const iid = com.IWindowNative.IID;
    try testing.expectEqual(@as(u32, 0xeecdbf0e), iid.Data1);
    try testing.expectEqual(@as(u16, 0xbae9), iid.Data2);
    try testing.expectEqual(@as(u16, 0x4cb6), iid.Data3);
    try testing.expect(std.mem.eql(u8, &iid.Data4, &[_]u8{ 0xa6, 0x8e, 0x95, 0x98, 0xe1, 0xcb, 0x57, 0xbb }));
}

test "ISwapChainPanelNative IID matches WinUI3 oracle" {
    const testing = std.testing;
    const iid = com.ISwapChainPanelNative.IID;
    try testing.expectEqual(@as(u32, 0x63aad0b8), iid.Data1);
    try testing.expectEqual(@as(u16, 0x7c24), iid.Data2);
    try testing.expectEqual(@as(u16, 0x40ff), iid.Data3);
    try testing.expect(std.mem.eql(u8, &iid.Data4, &[_]u8{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 }));
}

test "IResourceDictionary IID matches WinUI3 oracle" {
    const testing = std.testing;
    const iid = com.IResourceDictionary.IID;
    try testing.expectEqual(@as(u32, 0x1b690975), iid.Data1);
    try testing.expectEqual(@as(u16, 0xa710), iid.Data2);
    try testing.expectEqual(@as(u16, 0x5783), iid.Data3);
    try testing.expect(std.mem.eql(u8, &iid.Data4, &[_]u8{ 0xa6, 0xe1, 0x15, 0x83, 0x6f, 0x61, 0x86, 0xc2 }));
}

test "IPropertyValueStatics IID matches Windows.Foundation oracle" {
    const testing = std.testing;
    const iid = com.IPropertyValueStatics.IID;
    try testing.expectEqual(@as(u32, 0x629bdbc8), iid.Data1);
    try testing.expectEqual(@as(u16, 0xd932), iid.Data2);
    try testing.expectEqual(@as(u16, 0x4ff4), iid.Data3);
    try testing.expect(std.mem.eql(u8, &iid.Data4, &[_]u8{ 0x96, 0xb9, 0x8d, 0x96, 0xc5, 0xc1, 0xe8, 0x58 }));
}

test "IVector<IInspectable> IID matches Windows.Foundation.Collections oracle" {
    const testing = std.testing;
    const iid = com.IVector.IID;
    try testing.expectEqual(@as(u32, 0xb32bdca4), iid.Data1);
    try testing.expectEqual(@as(u16, 0x5e52), iid.Data2);
    try testing.expectEqual(@as(u16, 0x5b27), iid.Data3);
    try testing.expect(std.mem.eql(u8, &iid.Data4, &[_]u8{ 0xbc, 0x5d, 0xd6, 0x6a, 0x1a, 0x26, 0x8c, 0x2a }));
}

test "WinUI3 COM contract surface exists for critical interfaces" {
    const testing = std.testing;
    try testing.expect(@hasDecl(com, "IVector"));
    try testing.expect(@hasDecl(com, "IXamlMetadataProvider"));
    try testing.expect(@hasDecl(com, "ISolidColorBrush"));
    try testing.expect(@hasDecl(com, "IPropertyValueStatics"));
    try testing.expect(@hasDecl(com, "IApplicationFactory"));
    try testing.expect(@hasDecl(com, "ITabView"));
    try testing.expect(@hasDecl(com, "IPanel"));
    try testing.expect(@hasDecl(com.ISolidColorBrush, "Color"));
}

test "IXamlMetadataProvider.GetXmlnsDefinitions signature matches aggregation call-site" {
    const testing = std.testing;
    const Expected = *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT;
    const Actual = @TypeOf(@as(com.IXamlMetadataProvider.VTable, undefined).GetXmlnsDefinitions);
    try testing.expect(Actual == Expected);
}

test "IApplicationFactory.createInstance returns structured result" {
    const testing = std.testing;
    const Fn = @TypeOf(com.IApplicationFactory.createInstance);
    const info = @typeInfo(Fn).@"fn";
    const Ret = info.return_type.?;
    const ErrUnion = @typeInfo(Ret).error_union;
    const Payload = ErrUnion.payload;
    try testing.expect(@hasField(Payload, "inner"));
    try testing.expect(@hasField(Payload, "instance"));
}

test "ITabView surface methods required by App are present" {
    const testing = std.testing;
    try testing.expect(@hasDecl(com.ITabView, "getTabItems"));
    try testing.expect(@hasDecl(com.ITabView, "putSelectedIndex"));
    try testing.expect(@hasDecl(com.ITabView, "addTabCloseRequested"));
    try testing.expect(@hasDecl(com.ITabView, "addAddTabButtonClick"));
    try testing.expect(@hasDecl(com.ITabView, "addSelectionChanged"));
}

test "IPanel methods required by App are present" {
    const testing = std.testing;
    try testing.expect(@hasDecl(com.IPanel, "getChildren"));
    try testing.expect(@hasDecl(com.IPanel, "putBackground"));
}

test "delegate/event IID constants required by runtime are present" {
    const testing = std.testing;
    try testing.expect(@hasDecl(com, "IID_RoutedEventHandler"));
    try testing.expect(@hasDecl(com, "IID_SizeChangedEventHandler"));
    try testing.expect(@hasDecl(com, "IID_TypedEventHandler_TabCloseRequested"));
    try testing.expect(@hasDecl(com, "IID_TypedEventHandler_AddTabButtonClick"));
    try testing.expect(@hasDecl(com, "IID_SelectionChangedEventHandler"));
}
