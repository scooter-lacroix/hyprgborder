//! Core library for the HyprGBorder project.
//!
//! This module contains all of the building blocks required to animate
//! Hyprland window borders.  By separating the low‑level routines into a
//! library we make it easier to reuse the functionality from different
//! front‑ends (for example a CLI application or a GUI).  The exported
//! `runRainbow` function implements the same behaviour as the original
//! program in `src/main.zig`, but callers can control the hue step and
//! update interval themselves.

const std = @import("std");

/// Convert a hue/saturation/value triple into an RGB colour.  The return
/// value is an array of three bytes representing red, green and blue
/// components respectively.  This is the same implementation that was in
/// the original `main.zig`.
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

/// Format an RGB array as a string acceptable to Hyprland.  Colours are
/// encoded as `0xffRRGGBB` where `R`, `G` and `B` are hex digits.  Memory is
/// allocated from the provided allocator and must be freed by the caller.
pub fn fmtColor(allocator: std.mem.Allocator, rgb: [3]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "0xff{X:0>2}{X:0>2}{X:0>2}", .{
        rgb[0], rgb[1], rgb[2],
    });
}

/// Compute the path to the Hyprland UNIX socket using environment
/// variables.  Hyprland sets `XDG_RUNTIME_DIR` and
/// `HYPRLAND_INSTANCE_SIGNATURE` which together form the socket path.
pub fn getSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const runtime = try std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR");
    defer allocator.free(runtime);

    const his = try std.process.getEnvVarOwned(allocator, "HYPRLAND_INSTANCE_SIGNATURE");
    defer allocator.free(his);

    return std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket.sock", .{ runtime, his });
}

/// Send a colour update to Hyprland.  Given the current hue this function
/// computes two rainbow colours (opposite on the colour wheel), formats
/// them and writes the appropriate command to the provided UNIX socket.  The
/// socket path is passed in separately to avoid recomputing it on every
/// invocation.
pub fn updateBorderColors(
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    hue: f64,
) !void {
    // Compute two colours 180° apart on the hue wheel.
    const rgb1 = hsvToRgb(hue, 1.0, 1.0);
    const rgb2 = hsvToRgb(@mod(hue + 0.5, 1.0), 1.0, 1.0);

    const c1 = try fmtColor(allocator, rgb1);
    defer allocator.free(c1);
    const c2 = try fmtColor(allocator, rgb2);
    defer allocator.free(c2);

    const cmd = try std.fmt.allocPrint(
        allocator,
        "keyword general:col.active_border {s} {s} 270deg\n",
        .{ c1, c2 },
    );
    defer allocator.free(cmd);

    // Connect to Hyprland and send the command.  Note: we open a new
    // connection for each update because Hyprland expects short‑lived
    // messages.  If performance becomes an issue this could be optimised to
    // reuse a persistent connection.
    var sock = try std.net.connectUnixSocket(socket_path);
    defer sock.close();
    _ = try sock.writeAll(cmd);
}

/// Continuously animate the border by cycling through the rainbow.  The
/// `step` parameter controls how much the hue advances on each iteration
/// (e.g. `0.01` means a full cycle takes 100 updates).  The
/// `interval_ms` parameter defines the delay between updates in
/// milliseconds.  This function never returns under normal conditions; it
/// will only end if an error occurs.
pub fn runRainbow(
    allocator: std.mem.Allocator,
    step: f64,
    interval_ms: u64,
) !void {
    const socket_path = try getSocketPath(allocator);
    defer allocator.free(socket_path);

    var hue: f64 = 0.0;
    while (true) {
        try updateBorderColors(allocator, socket_path, hue);
        hue = @mod(hue + step, 1.0);
        std.Thread.sleep(std.time.ns_per_ms * interval_ms);
    }
}
