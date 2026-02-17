//! Hyprland IPC communication and command formatting
//! Provides functions for communicating with Hyprland via IPC sockets

const std = @import("std");
const colors = @import("colors.zig");

pub const HyprlandError = error{
    SocketConnectionFailed,
    CommandSendFailed,
    InvalidSocketPath,
};

/// Hyprland IPC socket paths
pub const SOCKET_1 = ".socket.sock"; // For dispatchers/keywords
pub const SOCKET_2 = ".socket2.sock"; // For events (future use)

/// Hyprland border configuration variables
pub const HyprlandBorderVars = struct {
    pub const ACTIVE_BORDER = "general:col.active_border";
    pub const INACTIVE_BORDER = "general:col.inactive_border";
    pub const BORDER_SIZE = "general:border_size";
    pub const NO_BORDER_ON_FLOATING = "general:no_border_on_floating";
    pub const ROUNDING = "decoration:rounding";
    pub const DROP_SHADOW = "decoration:drop_shadow";
    pub const SHADOW_RANGE = "decoration:shadow_range";
    pub const SHADOW_RENDER_POWER = "decoration:shadow_render_power";
    pub const COL_SHADOW = "decoration:col.shadow";
    pub const COL_SHADOW_INACTIVE = "decoration:col.shadow_inactive";
};

/// Get Hyprland socket path using environment variables
pub fn getSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const runtime = std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return HyprlandError.InvalidSocketPath,
        else => return err,
    };
    defer allocator.free(runtime);

    const his = std.process.getEnvVarOwned(allocator, "HYPRLAND_INSTANCE_SIGNATURE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return HyprlandError.InvalidSocketPath,
        else => return err,
    };
    defer allocator.free(his);

    return try std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket.sock", .{ runtime, his });
}

/// Send a keyword command to Hyprland
pub fn sendKeywordCommand(socket_path: []const u8, variable: []const u8, value: []const u8) !void {
    const cmd = try std.fmt.allocPrint(std.heap.page_allocator, "keyword {s} {s}\n", .{ variable, value });
    defer std.heap.page_allocator.free(cmd);

    var sock = std.net.connectUnixSocket(socket_path) catch |err| switch (err) {
        error.ConnectionRefused, error.FileNotFound => return HyprlandError.SocketConnectionFailed,
        else => return err,
    };
    defer sock.close();

    _ = sock.writeAll(cmd) catch return HyprlandError.CommandSendFailed;
}

/// Update rainbow border colors (original functionality)
pub fn updateRainbowBorder(allocator: std.mem.Allocator, socket_path: []const u8, hue: f64) !void {
    // Compute two colors 180° apart on the hue wheel
    const rgb1 = colors.hsvToRgb(hue, 1.0, 1.0);
    const rgb2 = colors.hsvToRgb(@mod(hue + 0.5, 1.0), 1.0, 1.0);

    const c1 = try colors.formatHyprlandColor(allocator, rgb1[0], rgb1[1], rgb1[2]);
    defer allocator.free(c1);
    const c2 = try colors.formatHyprlandColor(allocator, rgb2[0], rgb2[1], rgb2[2]);
    defer allocator.free(c2);

    const gradient_value = try std.fmt.allocPrint(allocator, "{s} {s} 270deg", .{ c1, c2 });
    defer allocator.free(gradient_value);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.ACTIVE_BORDER, gradient_value);
}

/// Update solid color border
pub fn updateSolidBorder(allocator: std.mem.Allocator, socket_path: []const u8, color: []const u8) !void {
    // Convert hex color to Hyprland format if needed
    var hypr_color: []u8 = undefined;
    var should_free = false;

    if (color.len == 7 and color[0] == '#') {
        hypr_color = try std.fmt.allocPrint(allocator, "0xff{s}", .{color[1..]});
        should_free = true;
    } else if (std.mem.startsWith(u8, color, "0x")) {
        hypr_color = @constCast(color);
    } else {
        hypr_color = try std.fmt.allocPrint(allocator, "0xff{s}", .{color});
        should_free = true;
    }

    defer if (should_free) allocator.free(hypr_color);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.ACTIVE_BORDER, hypr_color);
}

/// Update gradient border with two colors and angle
pub fn updateGradientBorder(allocator: std.mem.Allocator, socket_path: []const u8, color1: []const u8, color2: []const u8, angle: u32) !void {
    const gradient_value = try std.fmt.allocPrint(allocator, "{s} {s} {d}deg", .{ color1, color2, angle });
    defer allocator.free(gradient_value);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.ACTIVE_BORDER, gradient_value);
}

/// Update border with multiple gradient colors
pub fn updateMultiGradientBorder(allocator: std.mem.Allocator, socket_path: []const u8, colors_list: []const []const u8, angle: u32) !void {
    if (colors_list.len < 2) {
        return error.InsufficientColors;
    }

    var gradient_parts: std.ArrayList([]const u8) = .{};
    defer gradient_parts.deinit(allocator);

    for (colors_list) |color| {
        try gradient_parts.append(allocator, color);
    }

    const colors_joined = try std.mem.join(allocator, " ", gradient_parts.items);
    defer allocator.free(colors_joined);

    const gradient_value = try std.fmt.allocPrint(allocator, "{s} {d}deg", .{ colors_joined, angle });
    defer allocator.free(gradient_value);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.ACTIVE_BORDER, gradient_value);
}

/// Set border size
pub fn setBorderSize(socket_path: []const u8, size: u32) !void {
    const size_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{size});
    defer std.heap.page_allocator.free(size_str);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.BORDER_SIZE, size_str);
}

/// Set border rounding
pub fn setBorderRounding(socket_path: []const u8, rounding: u32) !void {
    const rounding_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{rounding});
    defer std.heap.page_allocator.free(rounding_str);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.ROUNDING, rounding_str);
}

/// Enable/disable drop shadow
pub fn setDropShadow(socket_path: []const u8, enabled: bool) !void {
    const enabled_str = if (enabled) "true" else "false";
    try sendKeywordCommand(socket_path, HyprlandBorderVars.DROP_SHADOW, enabled_str);
}

/// Set shadow color to coordinate with border
pub fn setShadowColor(allocator: std.mem.Allocator, socket_path: []const u8, color: []const u8) !void {
    // Convert hex color to Hyprland format if needed
    var hypr_color: []u8 = undefined;
    var should_free = false;

    if (color.len == 7 and color[0] == '#') {
        hypr_color = try std.fmt.allocPrint(allocator, "0xff{s}", .{color[1..]});
        should_free = true;
    } else if (std.mem.startsWith(u8, color, "0x")) {
        hypr_color = @constCast(color);
    } else {
        hypr_color = try std.fmt.allocPrint(allocator, "0xff{s}", .{color});
        should_free = true;
    }

    defer if (should_free) allocator.free(hypr_color);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.COL_SHADOW, hypr_color);
}

/// Test Hyprland connection
pub fn testConnection(socket_path: []const u8) bool {
    var sock = std.net.connectUnixSocket(socket_path) catch return false;
    defer sock.close();

    // Send a simple version command to test connectivity
    const test_cmd = "version\n";
    _ = sock.writeAll(test_cmd) catch return false;

    return true;
}

/// Get current border configuration from Hyprland
pub fn getCurrentBorderConfig(allocator: std.mem.Allocator, socket_path: []const u8) ![]const u8 {
    var sock = std.net.connectUnixSocket(socket_path) catch return HyprlandError.SocketConnectionFailed;
    defer sock.close();

    // Send command to get current border configuration
    const command = "j/getoption general:col.active_border\n";
    _ = sock.writeAll(command) catch return HyprlandError.CommandSendFailed;

    // Read response
    var buffer: [1024]u8 = undefined;
    const bytes_read = sock.read(buffer[0..]) catch return HyprlandError.CommandSendFailed;

    return try allocator.dupe(u8, buffer[0..bytes_read]);
}

/// Set border configuration in Hyprland (simplified restore) - This may not even need to be used with current design.
pub fn setBorderConfig(socket_path: []const u8, config: []const u8) !void {
    // For now, just send a simple border reset command
    // In a full implementation, this would parse and restore the exact config
    _ = config; // Unused for now

    // Reset to a neutral border state
    try sendKeywordCommand(socket_path, HyprlandBorderVars.ACTIVE_BORDER, "0xffffffff");
}
