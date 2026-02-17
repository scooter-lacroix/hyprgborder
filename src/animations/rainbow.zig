//! Rainbow animation provider
//! Refactored from the original core animation logic
//! Optimized for performance with persistent connection and zero-allocation updates

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

pub const RainbowAnimation = struct {
    hue: f64 = 0.0,
    speed: f64 = 0.01,
    direction: config.AnimationDirection = .clockwise,
    connection: ?utils.hyprland.PersistentConnection = null,

    pub fn update(self: *RainbowAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time;

        if (self.connection) |*conn| {
            try utils.hyprland.updateRainbowBorderOptimized(conn, self.hue);
        } else {
            try utils.hyprland.updateRainbowBorder(allocator, socket_path, self.hue);
        }

        const step = if (self.direction == .clockwise) self.speed else -self.speed;
        self.hue = @mod(self.hue + step, 1.0);
    }

    pub fn configure(self: *RainbowAnimation, animation_config: config.AnimationConfig) !void {
        self.speed = animation_config.speed;
        self.direction = animation_config.direction;
    }

    pub fn cleanup(self: *RainbowAnimation) void {
        if (self.connection) |*conn| {
            conn.deinit();
            self.connection = null;
        }
    }

    pub fn enableOptimized(self: *RainbowAnimation, allocator: std.mem.Allocator) !void {
        if (self.connection == null) {
            self.connection = try utils.hyprland.PersistentConnection.init(allocator);
            try self.connection.?.connect();
        }
    }
};

fn updateWrapper(ptr: *anyopaque, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
    const self = @as(*RainbowAnimation, @ptrCast(@alignCast(ptr)));
    try self.update(allocator, socket_path, time);
}

fn configureWrapper(ptr: *anyopaque, animation_config: config.AnimationConfig) !void {
    const self = @as(*RainbowAnimation, @ptrCast(@alignCast(ptr)));
    try self.configure(animation_config);
}

fn cleanupWrapper(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self = @as(*RainbowAnimation, @ptrCast(@alignCast(ptr)));
    self.cleanup();
    allocator.destroy(self);
}

pub fn create(allocator: std.mem.Allocator) !AnimationProvider {
    const rainbow_anim = try allocator.create(RainbowAnimation);
    rainbow_anim.* = RainbowAnimation{};

    return AnimationProvider{
        .ptr = rainbow_anim,
        .allocator = allocator,
        .updateFn = updateWrapper,
        .configureFn = configureWrapper,
        .cleanupFn = cleanupWrapper,
    };
}
