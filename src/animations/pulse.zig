//! Pulse animation provider
//! Creates a pulsing effect by fading border colors in and out

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

const PulseAnimation = struct {
    phase: f64 = 0.0,
    speed: f64 = 0.02,
    colors: std.ArrayList(config.ColorFormat),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PulseAnimation {
        return PulseAnimation{
            .colors = .{},
            .allocator = allocator,
        };
    }

    pub fn update(self: *PulseAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time; // Time parameter not used directly

        if (self.colors.items.len == 0) {
            // Default to red pulse if no colors configured
            try utils.hyprland.updateSolidBorder(allocator, socket_path, "#ff0000");
            return;
        }

        // Calculate pulse intensity (0.0 to 1.0)
        const intensity = (@sin(self.phase) + 1.0) / 2.0;

        // Use first color for pulse, modulate alpha/brightness
        const base_color = self.colors.items[0];
        const pulsed_color = try modulateColorIntensity(allocator, base_color, intensity);
        defer allocator.free(pulsed_color);

        try utils.hyprland.updateSolidBorder(allocator, socket_path, pulsed_color);

        self.phase += self.speed;
        if (self.phase > 2.0 * std.math.pi) {
            self.phase -= 2.0 * std.math.pi;
        }
    }

    pub fn configure(self: *PulseAnimation, animation_config: config.AnimationConfig) !void {
        self.speed = animation_config.speed;

        // Clear existing colors and copy new ones
        self.colors.clearAndFree(self.allocator);
        for (animation_config.colors.items) |color| {
            try self.colors.append(self.allocator, color);
        }
    }

    pub fn cleanup(self: *PulseAnimation) void {
        self.colors.deinit(self.allocator);
    }

    fn modulateColorIntensity(allocator: std.mem.Allocator, color: config.ColorFormat, intensity: f64) ![]u8 {
        const hex_color = try color.toHex(allocator);
        defer allocator.free(hex_color);

        // Parse hex color and modulate intensity
        if (hex_color.len != 7 or hex_color[0] != '#') {
            return try allocator.dupe(u8, hex_color);
        }

        const r = try std.fmt.parseInt(u8, hex_color[1..3], 16);
        const g = try std.fmt.parseInt(u8, hex_color[3..5], 16);
        const b = try std.fmt.parseInt(u8, hex_color[5..7], 16);

        const mod_r = @as(u8, @intFromFloat(@as(f64, @floatFromInt(r)) * intensity));
        const mod_g = @as(u8, @intFromFloat(@as(f64, @floatFromInt(g)) * intensity));
        const mod_b = @as(u8, @intFromFloat(@as(f64, @floatFromInt(b)) * intensity));

        return try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ mod_r, mod_g, mod_b });
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
