//! Configuration module exports
//! Provides configuration management, persistence, and preset handling

pub const types = @import("types.zig");
pub const persistence = @import("persistence.zig");
pub const presets = @import("presets.zig");

// Re-export commonly used types
pub const AnimationType = types.AnimationType;
pub const ColorFormat = types.ColorFormat;
pub const AnimationConfig = types.AnimationConfig;
pub const AnimationDirection = types.AnimationDirection;
pub const Preset = types.Preset;
