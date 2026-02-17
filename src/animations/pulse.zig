//! Pulse animation provider
//! Creates a pulsing effect by fading border colors in and out
//! Optimized for performance with persistent connection and buffer reuse

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

pub const PulseAnimation = struct {
    phase: f64 = 0.0,
    speed: f64 = 0.02,
    colors: std.ArrayList(config.ColorFormat),
    allocator: std.mem.Allocator,
    connection: ?utils.hyprland.PersistentConnection = null,
    color_buffer: [16]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator) PulseAnimation {
        return PulseAnimation{
            .colors = .{},
            .allocator = allocator,
        };
    }

    pub fn update(self: *PulseAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time;

        if (self.colors.items.len == 0) {
            if (self.connection) |*conn| {
                try utils.hyprland.updateSolidBorderOptimized(conn, "#ff0000");
            } else {
                try utils.hyprland.updateSolidBorder(allocator, socket_path, "#ff0000");
            }
            return;
        }

        const intensity = (@sin(self.phase) + 1.0) / 2.0;
        const base_color = self.colors.items[0];
        const pulsed_color = try modulateColorIntensityBuf(&self.color_buffer, base_color, intensity);

        if (self.connection) |*conn| {
            try utils.hyprland.updateSolidBorderOptimized(conn, pulsed_color);
        } else {
            try utils.hyprland.updateSolidBorder(allocator, socket_path, pulsed_color);
        }

        self.phase += self.speed;
        if (self.phase > 2.0 * std.math.pi) {
            self.phase -= 2.0 * std.math.pi;
        }
    }

    pub fn configure(self: *PulseAnimation, animation_config: config.AnimationConfig) !void {
        self.speed = animation_config.speed;

        self.colors.clearAndFree(self.allocator);
        for (animation_config.colors.items) |color| {
            try self.colors.append(self.allocator, color);
        }
    }

    pub fn cleanup(self: *PulseAnimation) void {
        self.colors.deinit(self.allocator);
        if (self.connection) |*conn| {
            conn.deinit();
            self.connection = null;
        }
    }

    pub fn enableOptimized(self: *PulseAnimation, allocator: std.mem.Allocator) !void {
        if (self.connection == null) {
            self.connection = try utils.hyprland.PersistentConnection.init(allocator);
            try self.connection.?.connect();
        }
    }

    fn modulateColorIntensityBuf(buffer: *[16]u8, color: config.ColorFormat, intensity: f64) ![]u8 {
        const rgb = color.toRgb();
        const mod_r = @as(u8, @intFromFloat(@as(f64, @floatFromInt(rgb[0])) * intensity));
        const mod_g = @as(u8, @intFromFloat(@as(f64, @floatFromInt(rgb[1])) * intensity));
        const mod_b = @as(u8, @intFromFloat(@as(f64, @floatFromInt(rgb[2])) * intensity));
        return std.fmt.bufPrint(buffer, "#{X:0>2}{X:0>2}{X:0>2}", .{ mod_r, mod_g, mod_b }) catch buffer[0..0];
    }
};

fn updateWrapper(ptr: *anyopaque, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
    const self = @as(*PulseAnimation, @ptrCast(@alignCast(ptr)));
    try self.update(allocator, socket_path, time);
}

fn configureWrapper(ptr: *anyopaque, animation_config: config.AnimationConfig) !void {
    const self = @as(*PulseAnimation, @ptrCast(@alignCast(ptr)));
    try self.configure(animation_config);
}

fn cleanupWrapper(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self = @as(*PulseAnimation, @ptrCast(@alignCast(ptr)));
    self.cleanup();
    allocator.destroy(self);
}

pub fn create(allocator: std.mem.Allocator) !AnimationProvider {
    const pulse_anim = try allocator.create(PulseAnimation);
    pulse_anim.* = PulseAnimation.init(allocator);

    return AnimationProvider{
        .ptr = pulse_anim,
        .allocator = allocator,
        .updateFn = updateWrapper,
        .configureFn = configureWrapper,
        .cleanupFn = cleanupWrapper,
    };
}
