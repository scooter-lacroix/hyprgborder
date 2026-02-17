//! Gradient animation provider
//! Creates animated gradients with Hyprland's native gradient support

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

const GradientAnimation = struct {
    phase: f64 = 0.0,
    speed: f64 = 0.01,
    colors: std.ArrayList(config.ColorFormat),
    angle: u32 = 270, // Default gradient angle
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GradientAnimation {
        return GradientAnimation{
            .colors = .{},
            .allocator = allocator,
        };
    }

    pub fn update(self: *GradientAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time; // Time parameter not used directly

        if (self.colors.items.len < 2) {
            // Default gradient if insufficient colors
            try utils.hyprland.updateGradientBorder(allocator, socket_path, "#ff0000", "#0000ff", self.angle);
            return;
        }

        // Cycle through color pairs
        const color_count = self.colors.items.len;
        const index1 = @as(usize, @intFromFloat(self.phase)) % color_count;
        const index2 = (index1 + 1) % color_count;

        const color1 = try self.colors.items[index1].toHex(allocator);
        defer allocator.free(color1);
        const color2 = try self.colors.items[index2].toHex(allocator);
        defer allocator.free(color2);

        // Convert to Hyprland format (0xAARRGGBB)
        const hypr_color1 = try convertToHyprlandColor(allocator, color1);
        defer allocator.free(hypr_color1);
        const hypr_color2 = try convertToHyprlandColor(allocator, color2);
        defer allocator.free(hypr_color2);

        try utils.hyprland.updateGradientBorder(allocator, socket_path, hypr_color1, hypr_color2, self.angle);

        self.phase += self.speed;
        if (self.phase >= @as(f64, @floatFromInt(color_count))) {
            self.phase = 0.0;
        }
    }

    pub fn configure(self: *GradientAnimation, animation_config: config.AnimationConfig) !void {
        self.speed = animation_config.speed;

        // Clear existing colors and copy new ones
        self.colors.clearAndFree(self.allocator);
        for (animation_config.colors.items) |color| {
            try self.colors.append(self.allocator, color);
        }
    }

    pub fn cleanup(self: *GradientAnimation) void {
        self.colors.deinit(self.allocator);
    }

    fn convertToHyprlandColor(allocator: std.mem.Allocator, hex_color: []const u8) ![]u8 {
        if (hex_color.len != 7 or hex_color[0] != '#') {
            return try std.fmt.allocPrint(allocator, "0xff{s}", .{hex_color});
        }

        return try std.fmt.allocPrint(allocator, "0xff{s}", .{hex_color[1..]});
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
