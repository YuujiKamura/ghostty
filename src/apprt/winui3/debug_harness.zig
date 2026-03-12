const std = @import("std");

pub const RuntimeDebugConfig = struct {
    enable_tabview: bool = true,
    use_ixaml_metadata_provider: bool = false,
    enable_xaml_resources: bool = true,
    tabview_empty: bool = false,
    tabview_item_no_content: bool = false,
    enable_tabview_handlers: bool = true,
    /// Individual handler control (only used when enable_tabview_handlers=true)
    enable_handler_close: bool = true,
    enable_handler_addtab: bool = true,
    enable_handler_selection: bool = true,
    probe_ime_comp_start_handler: bool = false,
    probe_ime_comp_change_handler: bool = false,
    probe_ime_comp_end_handler: bool = false,
    tabview_append_item: bool = true,
    tabview_select_first: bool = true,

    /// Test control extensions
    close_after_ms: ?u32 = null,
    close_tab_after_ms: ?u32 = null,
    new_tab_on_init: bool = false,
    test_resize: bool = false,

    pub fn load() RuntimeDebugConfig {
        return .{
            .enable_tabview = envBool("GHOSTTY_WINUI3_ENABLE_TABVIEW", true),
            .use_ixaml_metadata_provider = envBoolWithAlias(
                "GHOSTTY_WINUI3_USE_IXAML_METADATA_PROVIDER",
                "GHOSTTY_WINUI3_USE_METADATA_PROVIDER",
                true,
            ),
            .enable_xaml_resources = envBool("GHOSTTY_WINUI3_ENABLE_XAML_RESOURCES", true),
            .tabview_empty = envBool("GHOSTTY_WINUI3_TABVIEW_EMPTY", false),
            .tabview_item_no_content = envBool("GHOSTTY_WINUI3_TABVIEW_ITEM_NO_CONTENT", false),
            .enable_tabview_handlers = envBool("GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS", true),
            .enable_handler_close = envBool("GHOSTTY_WINUI3_HANDLER_CLOSE", true),
            .enable_handler_addtab = envBool("GHOSTTY_WINUI3_HANDLER_ADDTAB", true),
            .enable_handler_selection = envBool("GHOSTTY_WINUI3_HANDLER_SELECTION", true),
            .probe_ime_comp_start_handler = envBool("GHOSTTY_WINUI3_PROBE_IME_COMP_START_HANDLER", false),
            .probe_ime_comp_change_handler = envBool("GHOSTTY_WINUI3_PROBE_IME_COMP_CHANGE_HANDLER", false),
            .probe_ime_comp_end_handler = envBool("GHOSTTY_WINUI3_PROBE_IME_COMP_END_HANDLER", false),
            .tabview_append_item = envBool("GHOSTTY_WINUI3_TABVIEW_APPEND_ITEM", true),
            .tabview_select_first = envBool("GHOSTTY_WINUI3_TABVIEW_SELECT_FIRST", true),

            .close_after_ms = envInt(u32, "GHOSTTY_WINUI3_CLOSE_AFTER_MS"),
            .close_tab_after_ms = envInt(u32, "GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS"),
            .new_tab_on_init = envBool("GHOSTTY_WINUI3_NEW_TAB_ON_INIT", false),
            .test_resize = envBool("GHOSTTY_WINUI3_TEST_RESIZE", false),
        };
    }

    pub fn log(self: RuntimeDebugConfig, logger: anytype) void {
        logger.info(
            "winui3 debug config: tabview={} metadata_provider={} xaml_resources={} tabview_empty={} item_no_content={} handlers={} close={} addtab={} selection={} ime_probe_start={} ime_probe_change={} ime_probe_end={} append={} select={} close_after={}ms close_tab_after={}ms new_tab={} test_resize={}",
            .{
                self.enable_tabview,
                self.use_ixaml_metadata_provider,
                self.enable_xaml_resources,
                self.tabview_empty,
                self.tabview_item_no_content,
                self.enable_tabview_handlers,
                self.enable_handler_close,
                self.enable_handler_addtab,
                self.enable_handler_selection,
                self.probe_ime_comp_start_handler,
                self.probe_ime_comp_change_handler,
                self.probe_ime_comp_end_handler,
                self.tabview_append_item,
                self.tabview_select_first,
                self.close_after_ms orelse 0,
                self.close_tab_after_ms orelse 0,
                self.new_tab_on_init,
                self.test_resize,
            },
        );
    }
};

fn envInt(comptime T: type, name: [:0]const u8) ?T {
    const val = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return null;
    defer std.heap.page_allocator.free(val);
    return std.fmt.parseInt(T, val, 10) catch null;
}

fn envBool(name: [:0]const u8, default_value: bool) bool {
    const val = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return default_value;
    defer std.heap.page_allocator.free(val);

    if (std.ascii.eqlIgnoreCase(val, "1") or
        std.ascii.eqlIgnoreCase(val, "true") or
        std.ascii.eqlIgnoreCase(val, "yes") or
        std.ascii.eqlIgnoreCase(val, "on"))
    {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(val, "0") or
        std.ascii.eqlIgnoreCase(val, "false") or
        std.ascii.eqlIgnoreCase(val, "no") or
        std.ascii.eqlIgnoreCase(val, "off"))
    {
        return false;
    }
    return default_value;
}

fn envBoolWithAlias(primary: [:0]const u8, alias: [:0]const u8, default_value: bool) bool {
    const primary_value = std.process.getEnvVarOwned(std.heap.page_allocator, primary) catch null;
    if (primary_value) |v| {
        defer std.heap.page_allocator.free(v);
        if (std.ascii.eqlIgnoreCase(v, "1") or
            std.ascii.eqlIgnoreCase(v, "true") or
            std.ascii.eqlIgnoreCase(v, "yes") or
            std.ascii.eqlIgnoreCase(v, "on"))
        {
            return true;
        }
        if (std.ascii.eqlIgnoreCase(v, "0") or
            std.ascii.eqlIgnoreCase(v, "false") or
            std.ascii.eqlIgnoreCase(v, "no") or
            std.ascii.eqlIgnoreCase(v, "off"))
        {
            return false;
        }
        return default_value;
    }

    return envBool(alias, default_value);
}

test "RuntimeDebugConfig load" {
    const testing = std.testing;

    // Default values
    const config1 = RuntimeDebugConfig.load();
    try testing.expectEqual(true, config1.enable_tabview);

    // Overridden by env var
    if (comptime @import("builtin").os.tag == .windows) {
        const win = @import("std").os.windows;
        _ = win.kernel32.SetEnvironmentVariableW(
            @import("std").unicode.utf8ToUtf16LeStringLiteral("GHOSTTY_WINUI3_ENABLE_TABVIEW"),
            @import("std").unicode.utf8ToUtf16LeStringLiteral("0"),
        );
    }

    const config2 = RuntimeDebugConfig.load();
    try testing.expectEqual(false, config2.enable_tabview);
}
