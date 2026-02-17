//! Solid color animation provider
//! Provides static border colors without animation
//! Optimized with persistent connection and minimal updates

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const AnimationProvider = @import("mod.zig").AnimationProvider;

pub const SolidAnimation = struct {
    colors: std.ArrayList(config.ColorFormat),
    current_color_index: usize = 0,
    allocator: std.mem.Allocator,
    last_applied_color: [7]u8 = [_]u8{0} ** 7,
    last_applied_len: usize = 0,
    border_set: bool = false,
    connection: ?utils.hyprland.PersistentConnection = null,

    pub fn init(allocator: std.mem.Allocator) SolidAnimation {
        return SolidAnimation{
            .colors = .{},
            .allocator = allocator,
        };
    }

    pub fn update(self: *SolidAnimation, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        _ = time;

        var target_buffer: [7]u8 = undefined;
        var target_color: []const u8 = undefined;

        if (self.colors.items.len == 0) {
            target_color = "#ffffff";
        } else {
            const color = self.colors.items[self.current_color_index];
            const hex = try color.toHex(allocator);
            defer allocator.free(hex);
            @memcpy(target_buffer[0..hex.len], hex);
            target_color = target_buffer[0..hex.len];
        }

        const should_update = if (self.last_applied_len > 0)
            !std.mem.eql(u8, self.last_applied_color[0..self.last_applied_len], target_color)
        else
            true;

        if (should_update) {
            if (self.connection) |*conn| {
                try utils.hyprland.updateSolidBorderOptimized(conn, target_color);
            } else {
                try utils.hyprland.updateSolidBorder(allocator, socket_path, target_color);
            }

            @memcpy(self.last_applied_color[0..target_color.len], target_color);
            self.last_applied_len = target_color.len;
            self.border_set = true;
        }
    }

    pub fn configure(self: *SolidAnimation, animation_config: config.AnimationConfig) !void {
        self.colors.clearAndFree(self.allocator);
        for (animation_config.colors.items) |color| {
            try self.colors.append(self.allocator, color);
        }

        self.current_color_index = 0;
        self.last_applied_len = 0;
        self.border_set = false;
    }

    pub fn cleanup(self: *SolidAnimation) void {
        self.colors.deinit(self.allocator);
        if (self.connection) |*conn| {
            conn.deinit();
            self.connection = null;
        }
    }

    pub fn setColorIndex(self: *SolidAnimation, index: usize) void {
        if (index < self.colors.items.len) {
            self.current_color_index = index;
        }
    }

    pub fn enableOptimized(self: *SolidAnimation, allocator: std.mem.Allocator) !void {
        if (self.connection == null) {
            self.connection = try utils.hyprland.PersistentConnection.init(allocator);
            try self.connection.?.connect();
        }
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
