//! WinUI 3 Islands Search Overlay for Ghostty.
const Surface = @import("Surface.zig");
const SearchOverlay_generic = @import("../winui3/SearchOverlay_generic.zig");

pub const SearchOverlay = SearchOverlay_generic.SearchOverlay(Surface);
