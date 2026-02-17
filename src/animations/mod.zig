//! Animation module exports
//! Provides different animation providers and the animation interface

pub const rainbow = @import("rainbow.zig");
pub const pulse = @import("pulse.zig");
pub const gradient = @import("gradient.zig");
pub const solid = @import("solid.zig");

const std = @import("std");
const config = @import("config");

fn noop_update(_ptr: *anyopaque, _allocator: std.mem.Allocator, _socket_path: []const u8, _time: f64) anyerror!void {
    _ = _ptr;
    _ = _allocator;
    _ = _socket_path;
    _ = _time;
    return;
}

fn noop_configure(_ptr: *anyopaque, _animation_config: config.AnimationConfig) anyerror!void {
    _ = _ptr;
    _ = _animation_config;
    return;
}

fn noop_cleanup(_ptr: *anyopaque, _allocator: std.mem.Allocator) void {
    _ = _ptr;
    _ = _allocator;
}

fn noop_enable_optimized(_ptr: *anyopaque, _allocator: std.mem.Allocator) anyerror!void {
    _ = _ptr;
    _ = _allocator;
    return;
}

/// Animation provider interface for different animation types
pub const AnimationProvider = struct {
    const Self = @This();

    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    updateFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) anyerror!void,
    configureFn: *const fn (ptr: *anyopaque, animation_config: config.AnimationConfig) anyerror!void,
    cleanupFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    enableOptimizedFn: ?*const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void = null,

    pub fn update(self: *Self, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        try self.updateFn(self.ptr, allocator, socket_path, time);
    }

    pub fn configure(self: *Self, animation_config: config.AnimationConfig) !void {
        try self.configureFn(self.ptr, animation_config);
    }

    pub fn cleanup(self: *Self) void {
        self.cleanupFn(self.ptr, self.allocator);
    }

    pub fn enableOptimized(self: *Self, allocator: std.mem.Allocator) !void {
        if (self.enableOptimizedFn) |fn_ptr| {
            try fn_ptr(self.ptr, allocator);
        }
    }
};

fn rainbow_enable_optimized(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
    const self = @as(*rainbow.RainbowAnimation, @ptrCast(@alignCast(ptr)));
    try self.enableOptimized(allocator);
}

fn pulse_enable_optimized(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
    const self = @as(*pulse.PulseAnimation, @ptrCast(@alignCast(ptr)));
    try self.enableOptimized(allocator);
}

fn gradient_enable_optimized(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
    const self = @as(*gradient.GradientAnimation, @ptrCast(@alignCast(ptr)));
    try self.enableOptimized(allocator);
}

fn solid_enable_optimized(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
    const self = @as(*solid.SolidAnimation, @ptrCast(@alignCast(ptr)));
    try self.enableOptimized(allocator);
}

pub fn createAnimationProvider(allocator: std.mem.Allocator, animation_type: config.AnimationType) !AnimationProvider {
    switch (animation_type) {
        .rainbow => {
            const provider = try rainbow.create(allocator);
            return AnimationProvider{
                .ptr = provider.ptr,
                .allocator = provider.allocator,
                .updateFn = provider.updateFn,
                .configureFn = provider.configureFn,
                .cleanupFn = provider.cleanupFn,
                .enableOptimizedFn = rainbow_enable_optimized,
            };
        },
        .pulse => {
            const provider = try pulse.create(allocator);
            return AnimationProvider{
                .ptr = provider.ptr,
                .allocator = provider.allocator,
                .updateFn = provider.updateFn,
                .configureFn = provider.configureFn,
                .cleanupFn = provider.cleanupFn,
                .enableOptimizedFn = pulse_enable_optimized,
            };
        },
        .none => {
            const stub = try allocator.create(u8);
            return AnimationProvider{
                .ptr = stub,
                .allocator = allocator,
                .updateFn = noop_update,
                .configureFn = noop_configure,
                .cleanupFn = noop_cleanup,
                .enableOptimizedFn = noop_enable_optimized,
            };
        },
        .gradient => {
            const provider = try gradient.create(allocator);
            return AnimationProvider{
                .ptr = provider.ptr,
                .allocator = provider.allocator,
                .updateFn = provider.updateFn,
                .configureFn = provider.configureFn,
                .cleanupFn = provider.cleanupFn,
                .enableOptimizedFn = gradient_enable_optimized,
            };
        },
        .solid => {
            const provider = try solid.create(allocator);
            return AnimationProvider{
                .ptr = provider.ptr,
                .allocator = provider.allocator,
                .updateFn = provider.updateFn,
                .configureFn = provider.configureFn,
                .cleanupFn = provider.cleanupFn,
                .enableOptimizedFn = solid_enable_optimized,
            };
        },
    }
}
