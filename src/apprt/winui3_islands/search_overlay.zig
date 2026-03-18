//! WinUI 3 Islands Search Overlay for Ghostty.
const App = @import("App.zig");
const Surface = @import("Surface.zig").Surface(App);
const SearchOverlay_generic = @import("../winui3/SearchOverlay_generic.zig");

pub const SearchOverlay = SearchOverlay_generic.SearchOverlay(Surface);
