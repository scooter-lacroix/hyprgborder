//! Hyprland IPC communication and command formatting
//! Provides functions for communicating with Hyprland via IPC sockets
//! Optimized for performance with persistent connections and buffer reuse

const std = @import("std");
const colors = @import("colors.zig");

pub const HyprlandError = error{
    SocketConnectionFailed,
    CommandSendFailed,
    InvalidSocketPath,
    ConnectionLost,
    BufferOverflow,
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

/// Buffer size for command formatting (sufficient for border commands)
pub const COMMAND_BUFFER_SIZE: usize = 256;

/// Persistent connection to Hyprland socket for high-performance updates
pub const PersistentConnection = struct {
    socket_path: []const u8,
    socket: ?std.net.Stream,
    command_buffer: [COMMAND_BUFFER_SIZE]u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !PersistentConnection {
        const socket_path = try getSocketPath(allocator);
        errdefer allocator.free(socket_path);

        return PersistentConnection{
            .socket_path = socket_path,
            .socket = null,
            .command_buffer = undefined,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PersistentConnection) void {
        if (self.socket) |sock| {
            sock.close();
        }
        self.allocator.free(self.socket_path);
    }

    pub fn connect(self: *PersistentConnection) !void {
        if (self.socket != null) return;

        self.socket = std.net.connectUnixSocket(self.socket_path) catch |err| switch (err) {
            error.ConnectionRefused, error.FileNotFound => return HyprlandError.SocketConnectionFailed,
            else => return err,
        };
    }

    pub fn disconnect(self: *PersistentConnection) void {
        if (self.socket) |sock| {
            sock.close();
            self.socket = null;
        }
    }

    pub fn reconnect(self: *PersistentConnection) !void {
        self.disconnect();
        try self.connect();
    }

    pub fn sendCommand(self: *PersistentConnection, command: []const u8) !void {
        if (self.socket == null) {
            try self.connect();
        }

        const sock = self.socket.?;
        sock.writeAll(command) catch {
            self.disconnect();
            return HyprlandError.ConnectionLost;
        };
    }

    pub fn sendKeyword(self: *PersistentConnection, variable: []const u8, value: []const u8) !void {
        const cmd = std.fmt.bufPrint(&self.command_buffer, "keyword {s} {s}\n", .{ variable, value }) catch
            return HyprlandError.BufferOverflow;

        try self.sendCommand(cmd);
    }

    pub fn testConnection(self: *PersistentConnection) bool {
        self.connect() catch return false;
        const test_cmd = "version\n";
        self.sendCommand(test_cmd) catch {
            self.disconnect();
            return false;
        };
        return true;
    }
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

/// Send a keyword command to Hyprland (legacy, creates new connection each time)
pub fn sendKeywordCommand(socket_path: []const u8, variable: []const u8, value: []const u8) !void {
    var buffer: [COMMAND_BUFFER_SIZE]u8 = undefined;
    const cmd = std.fmt.bufPrint(&buffer, "keyword {s} {s}\n", .{ variable, value }) catch
        return HyprlandError.BufferOverflow;

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

/// Update rainbow border using persistent connection (optimized)
pub fn updateRainbowBorderOptimized(conn: *PersistentConnection, hue: f64) !void {
    const rgb1 = colors.hsvToRgb(hue, 1.0, 1.0);
    const rgb2 = colors.hsvToRgb(@mod(hue + 0.5, 1.0), 1.0, 1.0);

    var buffer1: [32]u8 = undefined;
    var buffer2: [32]u8 = undefined;
    const c1 = colors.formatHyprlandColorBuf(&buffer1, rgb1[0], rgb1[1], rgb1[2]);
    const c2 = colors.formatHyprlandColorBuf(&buffer2, rgb2[0], rgb2[1], rgb2[2]);

    var gradient_buffer: [96]u8 = undefined;
    const gradient_value = std.fmt.bufPrint(&gradient_buffer, "{s} {s} 270deg", .{ c1, c2 }) catch
        return HyprlandError.BufferOverflow;

    try conn.sendKeyword(HyprlandBorderVars.ACTIVE_BORDER, gradient_value);
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

/// Update solid color border using persistent connection (optimized)
pub fn updateSolidBorderOptimized(conn: *PersistentConnection, color: []const u8) !void {
    var buffer: [32]u8 = undefined;
    const hypr_color: []const u8 = if (color.len == 7 and color[0] == '#')
        std.fmt.bufPrint(&buffer, "0xff{s}", .{color[1..]}) catch return HyprlandError.BufferOverflow
    else if (std.mem.startsWith(u8, color, "0x"))
        color
    else
        std.fmt.bufPrint(&buffer, "0xff{s}", .{color}) catch return HyprlandError.BufferOverflow;

    try conn.sendKeyword(HyprlandBorderVars.ACTIVE_BORDER, hypr_color);
}

/// Update gradient border with two colors and angle
pub fn updateGradientBorder(allocator: std.mem.Allocator, socket_path: []const u8, color1: []const u8, color2: []const u8, angle: u32) !void {
    const gradient_value = try std.fmt.allocPrint(allocator, "{s} {s} {d}deg", .{ color1, color2, angle });
    defer allocator.free(gradient_value);

    try sendKeywordCommand(socket_path, HyprlandBorderVars.ACTIVE_BORDER, gradient_value);
}

/// Update gradient border using persistent connection (optimized)
pub fn updateGradientBorderOptimized(conn: *PersistentConnection, color1: []const u8, color2: []const u8, angle: u32) !void {
    var buffer: [96]u8 = undefined;
    const gradient_value = std.fmt.bufPrint(&buffer, "{s} {s} {d}deg", .{ color1, color2, angle }) catch
        return HyprlandError.BufferOverflow;

    try conn.sendKeyword(HyprlandBorderVars.ACTIVE_BORDER, gradient_value);
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
