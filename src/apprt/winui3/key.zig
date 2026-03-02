const std = @import("std");
const input = @import("../../input.zig");

const Key = input.Key;
const Mods = input.Mods;

extern "user32" fn GetKeyState(nVirtKey: c_int) callconv(.winapi) c_short;

/// Win32 Virtual Key codes.
const VK_BACK = 0x08;
const VK_TAB = 0x09;
const VK_RETURN = 0x0D;
const VK_SHIFT = 0x10;
const VK_CONTROL = 0x11;
const VK_MENU = 0x12;
const VK_PAUSE = 0x13;
const VK_CAPITAL = 0x14;
const VK_ESCAPE = 0x1B;
const VK_SPACE = 0x20;
const VK_PRIOR = 0x21;
const VK_NEXT = 0x22;
const VK_END = 0x23;
const VK_HOME = 0x24;
const VK_LEFT = 0x25;
const VK_UP = 0x26;
const VK_RIGHT = 0x27;
const VK_DOWN = 0x28;
const VK_SNAPSHOT = 0x2C;
const VK_INSERT = 0x2D;
const VK_DELETE = 0x2E;
const VK_LWIN = 0x5B;
const VK_RWIN = 0x5C;
const VK_APPS = 0x5D;
const VK_NUMPAD0 = 0x60;
const VK_NUMPAD1 = 0x61;
const VK_NUMPAD2 = 0x62;
const VK_NUMPAD3 = 0x63;
const VK_NUMPAD4 = 0x64;
const VK_NUMPAD5 = 0x65;
const VK_NUMPAD6 = 0x66;
const VK_NUMPAD7 = 0x67;
const VK_NUMPAD8 = 0x68;
const VK_NUMPAD9 = 0x69;
const VK_MULTIPLY = 0x6A;
const VK_ADD = 0x6B;
const VK_SUBTRACT = 0x6D;
const VK_DECIMAL = 0x6E;
const VK_DIVIDE = 0x6F;
const VK_F1 = 0x70;
const VK_F2 = 0x71;
const VK_F3 = 0x72;
const VK_F4 = 0x73;
const VK_F5 = 0x74;
const VK_F6 = 0x75;
const VK_F7 = 0x76;
const VK_F8 = 0x77;
const VK_F9 = 0x78;
const VK_F10 = 0x79;
const VK_F11 = 0x7A;
const VK_F12 = 0x7B;
const VK_F13 = 0x7C;
const VK_F14 = 0x7D;
const VK_F15 = 0x7E;
const VK_F16 = 0x7F;
const VK_F17 = 0x80;
const VK_F18 = 0x81;
const VK_F19 = 0x82;
const VK_F20 = 0x83;
const VK_F21 = 0x84;
const VK_F22 = 0x85;
const VK_F23 = 0x86;
const VK_F24 = 0x87;
const VK_NUMLOCK = 0x90;
const VK_SCROLL = 0x91;
const VK_LSHIFT = 0xA0;
const VK_RSHIFT = 0xA1;
const VK_LCONTROL = 0xA2;
const VK_RCONTROL = 0xA3;
const VK_LMENU = 0xA4;
const VK_RMENU = 0xA5;
const VK_OEM_1 = 0xBA;
const VK_OEM_PLUS = 0xBB;
const VK_OEM_COMMA = 0xBC;
const VK_OEM_MINUS = 0xBD;
const VK_OEM_PERIOD = 0xBE;
const VK_OEM_2 = 0xBF;
const VK_OEM_3 = 0xC0;
const VK_OEM_4 = 0xDB;
const VK_OEM_5 = 0xDC;
const VK_OEM_6 = 0xDD;
const VK_OEM_7 = 0xDE;

/// Maps a Win32 Virtual Key code to a Ghostty input.Key.
/// Returns null if the VK code has no mapping.
pub fn vkToKey(vk: u16) ?Key {
    return switch (vk) {
        VK_BACK => .backspace,
        VK_TAB => .tab,
        VK_RETURN => .enter,
        VK_SHIFT, VK_LSHIFT => .shift_left,
        VK_RSHIFT => .shift_right,
        VK_CONTROL, VK_LCONTROL => .control_left,
        VK_RCONTROL => .control_right,
        VK_MENU, VK_LMENU => .alt_left,
        VK_RMENU => .alt_right,
        VK_PAUSE => .pause,
        VK_CAPITAL => .caps_lock,
        VK_ESCAPE => .escape,
        VK_SPACE => .space,
        VK_PRIOR => .page_up,
        VK_NEXT => .page_down,
        VK_END => .end,
        VK_HOME => .home,
        VK_LEFT => .arrow_left,
        VK_UP => .arrow_up,
        VK_RIGHT => .arrow_right,
        VK_DOWN => .arrow_down,
        VK_SNAPSHOT => .print_screen,
        VK_INSERT => .insert,
        VK_DELETE => .delete,

        // 0-9
        0x30 => .digit_0,
        0x31 => .digit_1,
        0x32 => .digit_2,
        0x33 => .digit_3,
        0x34 => .digit_4,
        0x35 => .digit_5,
        0x36 => .digit_6,
        0x37 => .digit_7,
        0x38 => .digit_8,
        0x39 => .digit_9,

        // A-Z
        0x41 => .key_a,
        0x42 => .key_b,
        0x43 => .key_c,
        0x44 => .key_d,
        0x45 => .key_e,
        0x46 => .key_f,
        0x47 => .key_g,
        0x48 => .key_h,
        0x49 => .key_i,
        0x4A => .key_j,
        0x4B => .key_k,
        0x4C => .key_l,
        0x4D => .key_m,
        0x4E => .key_n,
        0x4F => .key_o,
        0x50 => .key_p,
        0x51 => .key_q,
        0x52 => .key_r,
        0x53 => .key_s,
        0x54 => .key_t,
        0x55 => .key_u,
        0x56 => .key_v,
        0x57 => .key_w,
        0x58 => .key_x,
        0x59 => .key_y,
        0x5A => .key_z,

        VK_LWIN => .meta_left,
        VK_RWIN => .meta_right,
        VK_APPS => .context_menu,

        // Numpad
        VK_NUMPAD0 => .numpad_0,
        VK_NUMPAD1 => .numpad_1,
        VK_NUMPAD2 => .numpad_2,
        VK_NUMPAD3 => .numpad_3,
        VK_NUMPAD4 => .numpad_4,
        VK_NUMPAD5 => .numpad_5,
        VK_NUMPAD6 => .numpad_6,
        VK_NUMPAD7 => .numpad_7,
        VK_NUMPAD8 => .numpad_8,
        VK_NUMPAD9 => .numpad_9,
        VK_MULTIPLY => .numpad_multiply,
        VK_ADD => .numpad_add,
        VK_SUBTRACT => .numpad_subtract,
        VK_DECIMAL => .numpad_decimal,
        VK_DIVIDE => .numpad_divide,

        // Function keys
        VK_F1 => .f1,
        VK_F2 => .f2,
        VK_F3 => .f3,
        VK_F4 => .f4,
        VK_F5 => .f5,
        VK_F6 => .f6,
        VK_F7 => .f7,
        VK_F8 => .f8,
        VK_F9 => .f9,
        VK_F10 => .f10,
        VK_F11 => .f11,
        VK_F12 => .f12,
        VK_F13 => .f13,
        VK_F14 => .f14,
        VK_F15 => .f15,
        VK_F16 => .f16,
        VK_F17 => .f17,
        VK_F18 => .f18,
        VK_F19 => .f19,
        VK_F20 => .f20,
        VK_F21 => .f21,
        VK_F22 => .f22,
        VK_F23 => .f23,
        VK_F24 => .f24,

        // Lock keys
        VK_NUMLOCK => .num_lock,
        VK_SCROLL => .scroll_lock,

        // OEM keys (US layout)
        VK_OEM_1 => .semicolon,
        VK_OEM_PLUS => .equal,
        VK_OEM_COMMA => .comma,
        VK_OEM_MINUS => .minus,
        VK_OEM_PERIOD => .period,
        VK_OEM_2 => .slash,
        VK_OEM_3 => .backquote,
        VK_OEM_4 => .bracket_left,
        VK_OEM_5 => .backslash,
        VK_OEM_6 => .bracket_right,
        VK_OEM_7 => .quote,

        else => null,
    };
}

/// Maps a Win32 Virtual Key code to the unshifted Unicode codepoint.
/// This is needed for keybinding matching: bindings like ctrl+shift+v use
/// `.unicode = 'v'`, so we must provide the unshifted codepoint alongside
/// the physical key.
pub fn vkToUnshiftedCodepoint(vk: u16) u21 {
    return switch (vk) {
        // A-Z → lowercase a-z
        0x41...0x5A => @as(u21, vk) | 0x20,
        // 0-9 → '0'-'9'
        0x30...0x39 => @as(u21, vk),
        // Space
        VK_SPACE => ' ',
        // Common OEM keys (US layout)
        VK_OEM_1 => ';',
        VK_OEM_PLUS => '=',
        VK_OEM_COMMA => ',',
        VK_OEM_MINUS => '-',
        VK_OEM_PERIOD => '.',
        VK_OEM_2 => '/',
        VK_OEM_3 => '`',
        VK_OEM_4 => '[',
        VK_OEM_5 => '\\',
        VK_OEM_6 => ']',
        VK_OEM_7 => '\'',
        else => 0,
    };
}

/// Reads the current modifier key state from Win32 and returns a Ghostty Mods bitfield.
/// Uses GetKeyState to check shift, ctrl, alt, and super (Win key).
pub fn getModifiers() Mods {
    var mods: Mods = .{};

    // GetKeyState returns a SHORT; if the high bit is set, the key is down.
    // Shift
    if (GetKeyState(VK_SHIFT) < 0) {
        mods.shift = true;
        if (GetKeyState(VK_RSHIFT) < 0) {
            mods.sides.shift = .right;
        }
    }

    // Ctrl
    if (GetKeyState(VK_CONTROL) < 0) {
        mods.ctrl = true;
        if (GetKeyState(VK_RCONTROL) < 0) {
            mods.sides.ctrl = .right;
        }
    }

    // Alt
    if (GetKeyState(VK_MENU) < 0) {
        mods.alt = true;
        if (GetKeyState(VK_RMENU) < 0) {
            mods.sides.alt = .right;
        }
    }

    // Super (Win key)
    if (GetKeyState(VK_LWIN) < 0 or GetKeyState(VK_RWIN) < 0) {
        mods.super = true;
        if (GetKeyState(VK_RWIN) < 0) {
            mods.sides.super = .right;
        }
    }

    // Caps Lock (toggled = odd parity in low bit)
    if (GetKeyState(VK_CAPITAL) & 1 != 0) {
        mods.caps_lock = true;
    }

    // Num Lock (toggled)
    if (GetKeyState(VK_NUMLOCK) & 1 != 0) {
        mods.num_lock = true;
    }

    return mods;
}
