//! Solid color animation provider
//! Provides static border colors without animation

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

const SolidAnimation = struct {
    colors: std.ArrayList(config.ColorFormat),
    current_color_index: usize = 0,
    allocator: std.mem.Allocator,
    last_applied_color: ?[]const u8 = null,
    border_set: bool = false,

    pub fn init(allocator: std.mem.Allocator) SolidAnimation {
        return SolidAnimation{
            .colors = .{},
            .allocator = allocator,
        };
    }

    pub fn update(self: *SolidAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time; // Time parameter not used for solid colors

        var target_color: []const u8 = undefined;
        var should_free_target = false;

        if (self.colors.items.len == 0) {
            // Default to white if no colors configured
            target_color = "#ffffff";
        } else {
            const color = self.colors.items[self.current_color_index];
            target_color = try color.toHex(allocator);
            should_free_target = true;
        }
        defer if (should_free_target) allocator.free(target_color);

        // Only update if color changed or not set yet
        const should_update = if (self.last_applied_color) |last_color|
            !std.mem.eql(u8, last_color, target_color)
        else
            true;

        if (should_update) {
            // Convert to Hyprland format
            const hypr_color = try convertToHyprlandColor(allocator, target_color);
            defer allocator.free(hypr_color);

            try utils.hyprland.updateSolidBorder(allocator, socket_path, hypr_color);

            // Update last applied color
            if (self.last_applied_color) |old_color| {
                allocator.free(old_color);
            }
            self.last_applied_color = try allocator.dupe(u8, target_color);
            self.border_set = true;
        }
    }

    pub fn configure(self: *SolidAnimation, animation_config: config.AnimationConfig) !void {
        // Clear existing colors and copy new ones
        self.colors.clearAndFree(self.allocator);
        for (animation_config.colors.items) |color| {
            try self.colors.append(self.allocator, color);
        }

        // Reset to first color and force update
        self.current_color_index = 0;
        if (self.last_applied_color) |old_color| {
            self.allocator.free(old_color);
            self.last_applied_color = null;
        }
        self.border_set = false;
    }

    pub fn cleanup(self: *SolidAnimation) void {
        self.colors.deinit(self.allocator);
        if (self.last_applied_color) |color| {
            self.allocator.free(color);
        }
    }

    pub fn setColorIndex(self: *SolidAnimation, index: usize) void {
        if (index < self.colors.items.len) {
            self.current_color_index = index;
        }
    }

    fn convertToHyprlandColor(allocator: std.mem.Allocator, hex_color: []const u8) ![]u8 {
        if (hex_color.len != 7 or hex_color[0] != '#') {
            return try std.fmt.allocPrint(allocator, "0xff{s}", .{hex_color});
        }

        return try std.fmt.allocPrint(allocator, "0xff{s}", .{hex_color[1..]});
    }
};

fn updateWrapper(ptr: *anyopaque, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
    const self = @as(*SolidAnimation, @ptrCast(@alignCast(ptr)));
    try self.update(allocator, socket_path, time);
}

fn configureWrapper(ptr: *anyopaque, animation_config: config.AnimationConfig) !void {
    const self = @as(*SolidAnimation, @ptrCast(@alignCast(ptr)));
    try self.configure(animation_config);
}

fn cleanupWrapper(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self = @as(*SolidAnimation, @ptrCast(@alignCast(ptr)));
    self.cleanup();
    allocator.destroy(self);
}

pub fn create(allocator: std.mem.Allocator) !AnimationProvider {
    const solid_anim = try allocator.create(SolidAnimation);
    solid_anim.* = SolidAnimation.init(allocator);

    return AnimationProvider{
        .ptr = solid_anim,
        .allocator = allocator,
        .updateFn = updateWrapper,
        .configureFn = configureWrapper,
        .cleanupFn = cleanupWrapper,
    };
}
