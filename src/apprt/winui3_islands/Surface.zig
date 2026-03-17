//! WinUI 3 XAML Islands surface implementation for Ghostty.
const App = @import("App.zig");
const Surface_generic = @import("../winui3/Surface_generic.zig");

pub const Surface = Surface_generic.Surface(App);
