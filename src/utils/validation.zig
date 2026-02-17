//! Input validation utilities
//! Provides validation functions for configuration parameters

const std = @import("std");

pub const ValidationError = error{
    InvalidColorFormat,
    FpsOutOfRange,
    SpeedOutOfRange,
    InvalidPresetName,
    InsufficientColors,
    PresetNameTooLong,
    EmptyPresetName,
};

/// Validate FPS value
pub fn validateFps(fps: u32) ValidationError!void {
    if (fps < 1 or fps > 120) {
        return ValidationError.FpsOutOfRange;
    }
}

/// Validate animation speed
pub fn validateSpeed(speed: f64) ValidationError!void {
    if (speed < 0.001 or speed > 1.0) {
        return ValidationError.SpeedOutOfRange;
    }
}

/// Validate preset name
pub fn validatePresetName(name: []const u8) ValidationError!void {
    if (name.len == 0) {
        return ValidationError.EmptyPresetName;
    }

    if (name.len > 64) {
        return ValidationError.PresetNameTooLong;
    }

    // Check for invalid characters
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != ' ') {
            return ValidationError.InvalidPresetName;
        }
    }
}

/// Validate hex color format
pub fn validateHexColor(color: []const u8) ValidationError!void {
    if (color.len != 7 or color[0] != '#') {
        return ValidationError.InvalidColorFormat;
    }

    for (color[1..]) |c| {
        if (!std.ascii.isHex(c)) {
            return ValidationError.InvalidColorFormat;
        }
    }
}

/// Validate RGB color values
pub fn validateRgbColor(r: u8, g: u8, b: u8) ValidationError!void {
    // RGB values are inherently valid as u8 (0-255)
    _ = r;
    _ = g;
    _ = b;
}

/// Validate HSV color values
pub fn validateHsvColor(h: f64, s: f64, v: f64) ValidationError!void {
    if (h < 0.0 or h > 1.0 or s < 0.0 or s > 1.0 or v < 0.0 or v > 1.0) {
        return ValidationError.InvalidColorFormat;
    }
}

/// Validate minimum color count for animation type
pub fn validateColorCount(animation_type_str: []const u8, color_count: usize) ValidationError!void {
    if (std.mem.eql(u8, animation_type_str, "rainbow")) {
        // Rainbow doesn't require specific colors, so always valid
        return;
    } else if (std.mem.eql(u8, animation_type_str, "pulse")) {
        if (color_count < 1) {
            return ValidationError.InsufficientColors;
        }
    } else if (std.mem.eql(u8, animation_type_str, "gradient")) {
        if (color_count < 2) {
            return ValidationError.InsufficientColors;
        }
    } else if (std.mem.eql(u8, animation_type_str, "solid")) {
        if (color_count < 1) {
            return ValidationError.InsufficientColors;
        }
    }
    // Unknown animation type - should not happen, but let it pass
}

/// Provide user-friendly error messages
pub fn getErrorMessage(err: ValidationError) []const u8 {
    return switch (err) {
        ValidationError.InvalidColorFormat => "Invalid color format. Use #RRGGBB hex format.",
        ValidationError.FpsOutOfRange => "FPS must be between 1 and 120.",
        ValidationError.SpeedOutOfRange => "Speed must be between 0.001 and 1.0.",
        ValidationError.InvalidPresetName => "Preset name contains invalid characters. Use alphanumeric, spaces, hyphens, or underscores only.",
        ValidationError.InsufficientColors => "This animation type requires more colors to be configured.",
        ValidationError.PresetNameTooLong => "Preset name must be 64 characters or less.",
        ValidationError.EmptyPresetName => "Preset name cannot be empty.",
    };
}
