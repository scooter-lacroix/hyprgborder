//! Gradient animation provider
//! Creates animated gradients with Hyprland's native gradient support
//! Optimized for performance with persistent connection and buffer reuse

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

pub const GradientAnimation = struct {
    phase: f64 = 0.0,
    speed: f64 = 0.01,
    colors: std.ArrayList(config.ColorFormat),
    angle: u32 = 270,
    allocator: std.mem.Allocator,
    connection: ?utils.hyprland.PersistentConnection = null,
    color_buffer1: [16]u8 = undefined,
    color_buffer2: [16]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator) GradientAnimation {
        return GradientAnimation{
            .colors = .{},
            .allocator = allocator,
        };
    }

    pub fn update(self: *GradientAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time;

        if (self.colors.items.len < 2) {
            if (self.connection) |*conn| {
                try utils.hyprland.updateGradientBorderOptimized(conn, "0xffff0000", "0xff0000ff", self.angle);
            } else {
                try utils.hyprland.updateGradientBorder(allocator, socket_path, "#ff0000", "#0000ff", self.angle);
            }
            return;
        }

        const color_count = self.colors.items.len;
        const index1 = @as(usize, @intFromFloat(self.phase)) % color_count;
        const index2 = (index1 + 1) % color_count;

        const rgb1 = self.colors.items[index1].toRgb();
        const rgb2 = self.colors.items[index2].toRgb();

        const hypr_color1 = utils.colors.formatHyprlandColorBuf(&self.color_buffer1, rgb1[0], rgb1[1], rgb1[2]);
        const hypr_color2 = utils.colors.formatHyprlandColorBuf(&self.color_buffer2, rgb2[0], rgb2[1], rgb2[2]);

        if (self.connection) |*conn| {
            try utils.hyprland.updateGradientBorderOptimized(conn, hypr_color1, hypr_color2, self.angle);
        } else {
            try utils.hyprland.updateGradientBorder(allocator, socket_path, hypr_color1, hypr_color2, self.angle);
        }

        self.phase += self.speed;
        if (self.phase >= @as(f64, @floatFromInt(color_count))) {
            self.phase = 0.0;
        }
    }

    pub fn configure(self: *GradientAnimation, animation_config: config.AnimationConfig) !void {
        self.speed = animation_config.speed;

        self.colors.clearAndFree(self.allocator);
        for (animation_config.colors.items) |color| {
            try self.colors.append(self.allocator, color);
        }
    }

    pub fn cleanup(self: *GradientAnimation) void {
        self.colors.deinit(self.allocator);
        if (self.connection) |*conn| {
            conn.deinit();
            self.connection = null;
        }
    }

    pub fn enableOptimized(self: *GradientAnimation, allocator: std.mem.Allocator) !void {
        if (self.connection == null) {
            self.connection = try utils.hyprland.PersistentConnection.init(allocator);
            try self.connection.?.connect();
        }
    }
};

fn updateWrapper(ptr: *anyopaque, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
    const self = @as(*GradientAnimation, @ptrCast(@alignCast(ptr)));
    try self.update(allocator, socket_path, time);
}

fn configureWrapper(ptr: *anyopaque, animation_config: config.AnimationConfig) !void {
    const self = @as(*GradientAnimation, @ptrCast(@alignCast(ptr)));
    try self.configure(animation_config);
}

fn cleanupWrapper(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self = @as(*GradientAnimation, @ptrCast(@alignCast(ptr)));
    self.cleanup();
    allocator.destroy(self);
}

pub fn create(allocator: std.mem.Allocator) !AnimationProvider {
    const gradient_anim = try allocator.create(GradientAnimation);
    gradient_anim.* = GradientAnimation.init(allocator);

    return AnimationProvider{
        .ptr = gradient_anim,
        .allocator = allocator,
        .updateFn = updateWrapper,
        .configureFn = configureWrapper,
        .cleanupFn = cleanupWrapper,
    };
}
