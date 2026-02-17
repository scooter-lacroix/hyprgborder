//! Color parsing and conversion utilities
//! Provides functions for converting between different color formats

const std = @import("std");

pub const ColorError = error{
    InvalidFormat,
    InvalidHexDigit,
    InvalidRange,
};

/// Convert HSV color to RGB
pub fn hsvToRgb(h: f64, s: f64, v: f64) [3]u8 {
    const i = @as(u8, @intFromFloat(@floor(h * 6.0))) % 6;
    const f = h * 6.0 - @floor(h * 6.0);
    const p = v * (1.0 - s);
    const q = v * (1.0 - f * s);
    const t = v * (1.0 - (1.0 - f) * s);

    var r: f64 = 0;
    var g: f64 = 0;
    var b: f64 = 0;

    switch (i) {
        0 => {
            r = v;
            g = t;
            b = p;
        },
        1 => {
            r = q;
            g = v;
            b = p;
        },
        2 => {
            r = p;
            g = v;
            b = t;
        },
        3 => {
            r = p;
            g = q;
            b = v;
        },
        4 => {
            r = t;
            g = p;
            b = v;
        },
        else => {
            r = v;
            g = p;
            b = q;
        },
    }

    return .{
        @as(u8, @intFromFloat(r * 255.0)),
        @as(u8, @intFromFloat(g * 255.0)),
        @as(u8, @intFromFloat(b * 255.0)),
    };
}

/// Convert RGB color to HSV
pub fn rgbToHsv(r: u8, g: u8, b: u8) [3]f64 {
    const rf = @as(f64, @floatFromInt(r)) / 255.0;
    const gf = @as(f64, @floatFromInt(g)) / 255.0;
    const bf = @as(f64, @floatFromInt(b)) / 255.0;

    const max_val = @max(@max(rf, gf), bf);
    const min_val = @min(@min(rf, gf), bf);
    const delta = max_val - min_val;

    var h: f64 = 0;
    var s: f64 = 0;
    const v: f64 = max_val;

    if (delta != 0) {
        s = delta / max_val;

        if (max_val == rf) {
            h = @mod((gf - bf) / delta, 6.0);
        } else if (max_val == gf) {
            h = (bf - rf) / delta + 2.0;
        } else {
            h = (rf - gf) / delta + 4.0;
        }

        h /= 6.0;
        if (h < 0) h += 1.0;
    }

    return .{ h, s, v };
}

/// Parse hex color string to RGB values
pub fn parseHexColor(hex_str: []const u8) ColorError![3]u8 {
    if (hex_str.len != 7 or hex_str[0] != '#') {
        return ColorError.InvalidFormat;
    }

    const r = std.fmt.parseInt(u8, hex_str[1..3], 16) catch return ColorError.InvalidHexDigit;
    const g = std.fmt.parseInt(u8, hex_str[3..5], 16) catch return ColorError.InvalidHexDigit;
    const b = std.fmt.parseInt(u8, hex_str[5..7], 16) catch return ColorError.InvalidHexDigit;

    return .{ r, g, b };
}

/// Format RGB values as hex color string
pub fn formatHexColor(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ r, g, b });
}

/// Format RGB values as Hyprland color string (0xffRRGGBB)
pub fn formatHyprlandColor(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "0xff{X:0>2}{X:0>2}{X:0>2}", .{ r, g, b });
}

/// Parse RGB color string "r,g,b" to RGB values
pub fn parseRgbColor(rgb_str: []const u8) ColorError![3]u8 {
    var parts = std.mem.splitSequence(u8, rgb_str, ",");

    const r_str = parts.next() orelse return ColorError.InvalidFormat;
    const g_str = parts.next() orelse return ColorError.InvalidFormat;
    const b_str = parts.next() orelse return ColorError.InvalidFormat;

    if (parts.next() != null) return ColorError.InvalidFormat; // Too many parts

    const r = std.fmt.parseInt(u8, std.mem.trim(u8, r_str, " "), 10) catch return ColorError.InvalidRange;
    const g = std.fmt.parseInt(u8, std.mem.trim(u8, g_str, " "), 10) catch return ColorError.InvalidRange;
    const b = std.fmt.parseInt(u8, std.mem.trim(u8, b_str, " "), 10) catch return ColorError.InvalidRange;

    return .{ r, g, b };
}

/// Interpolate between two colors
pub fn interpolateColors(color1: [3]u8, color2: [3]u8, t: f64) [3]u8 {
    const t_clamped = @max(0.0, @min(1.0, t));

    const r = @as(u8, @intFromFloat(@as(f64, @floatFromInt(color1[0])) * (1.0 - t_clamped) + @as(f64, @floatFromInt(color2[0])) * t_clamped));
    const g = @as(u8, @intFromFloat(@as(f64, @floatFromInt(color1[1])) * (1.0 - t_clamped) + @as(f64, @floatFromInt(color2[1])) * t_clamped));
    const b = @as(u8, @intFromFloat(@as(f64, @floatFromInt(color1[2])) * (1.0 - t_clamped) + @as(f64, @floatFromInt(color2[2])) * t_clamped));

    return .{ r, g, b };
}
