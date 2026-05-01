//! D3D11-specific shader constant definitions.
//!
//! This file defines the layout of dynamic data passed to shaders that
//! changes frequently (per-frame), such as time, FPS, or animation state.
//! Separating these from the static terminal uniforms allows for a cleaner
//! data flow between the UI layer and the rendering layer.

const std = @import("std");

/// Dynamic constants passed to terminal shaders.
/// This matches the layout of the constant buffer at slot 1 in HLSL.
pub const TerminalShaderConstants = extern struct {
    /// Time in seconds since the application started.
    time: f32,

    /// Current average frames per second.
    fps: f32,

    /// Pad to 16-byte alignment as required by D3D11 constant buffers.
    _padding: [2]f32 = .{ 0, 0 },
};
