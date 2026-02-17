//! Configuration data structures and types
//! Defines core data types for animation configuration and validation

const std = @import("std");
const utils = @import("utils");

// Re-export validation errors from utils
pub const ValidationError = utils.validation.ValidationError;

pub const AnimationType = enum {
    rainbow,
    pulse,
    none,
    gradient,
    solid,

    pub fn toString(self: AnimationType) []const u8 {
        return switch (self) {
            .rainbow => "rainbow",
            .pulse => "pulse",
            .none => "none",
            .gradient => "gradient",
            .solid => "solid",
        };
    }

    pub fn fromString(str: []const u8) ?AnimationType {
        if (std.mem.eql(u8, str, "rainbow")) return .rainbow;
        if (std.mem.eql(u8, str, "pulse")) return .pulse;
        if (std.mem.eql(u8, str, "none")) return .none;
        if (std.mem.eql(u8, str, "gradient")) return .gradient;
        if (std.mem.eql(u8, str, "solid")) return .solid;
        return null;
    }
};

pub const ColorFormat = union(enum) {
    hex: []const u8,
    rgb: [3]u8,
    hsv: [3]f64,

    pub fn toHex(self: ColorFormat, allocator: std.mem.Allocator) ![]u8 {
        switch (self) {
            .hex => |hex| return try allocator.dupe(u8, hex),
            .rgb => |rgb| return try utils.colors.formatHexColor(allocator, rgb[0], rgb[1], rgb[2]),
            .hsv => |hsv| {
                const rgb = utils.colors.hsvToRgb(hsv[0], hsv[1], hsv[2]);
                return try utils.colors.formatHexColor(allocator, rgb[0], rgb[1], rgb[2]);
            },
        }
    }

    pub fn fromHex(hex: []const u8) ValidationError!ColorFormat {
        try utils.validation.validateHexColor(hex);
        return ColorFormat{ .hex = hex };
    }

    pub fn fromRgb(r: u8, g: u8, b: u8) ValidationError!ColorFormat {
        try utils.validation.validateRgbColor(r, g, b);
        return ColorFormat{ .rgb = .{ r, g, b } };
    }

    pub fn fromHsv(h: f64, s: f64, v: f64) ValidationError!ColorFormat {
        try utils.validation.validateHsvColor(h, s, v);
        return ColorFormat{ .hsv = .{ h, s, v } };
    }

    pub fn toRgb(self: ColorFormat) [3]u8 {
        switch (self) {
            .hex => |hex| {
                return utils.colors.parseHexColor(hex) catch .{ 0, 0, 0 };
            },
            .rgb => |rgb| return rgb,
            .hsv => |hsv| return utils.colors.hsvToRgb(hsv[0], hsv[1], hsv[2]),
        }
    }
};

pub const AnimationDirection = enum {
    clockwise,
    counter_clockwise,

    pub fn toString(self: AnimationDirection) []const u8 {
        return switch (self) {
            .clockwise => "clockwise",
            .counter_clockwise => "counter_clockwise",
        };
    }

    pub fn fromString(str: []const u8) ?AnimationDirection {
        if (std.mem.eql(u8, str, "clockwise")) return .clockwise;
        if (std.mem.eql(u8, str, "counter_clockwise")) return .counter_clockwise;
        return null;
    }
};

pub const AnimationConfig = struct {
    animation_type: AnimationType,
    fps: u32,
    speed: f64,
    colors: std.ArrayList(ColorFormat),
    direction: AnimationDirection,

    pub fn default() AnimationConfig {
        return AnimationConfig{
            .animation_type = .rainbow,
            .fps = 30,
            .speed = 0.01,
            .colors = .{},
            .direction = .clockwise,
        };
    }

    pub fn validate(self: *const AnimationConfig) ValidationError!void {
        try utils.validation.validateFps(self.fps);
        try utils.validation.validateSpeed(self.speed);
        try utils.validation.validateColorCount(self.animation_type.toString(), self.colors.items.len);

        // Validate each color format
        for (self.colors.items) |color| {
            try validateColorFormat(color);
        }
    }

    pub fn validateColorFormat(color: ColorFormat) ValidationError!void {
        switch (color) {
            .hex => |hex| {
                try utils.validation.validateHexColor(hex);
            },
            .rgb => |rgb| {
                try utils.validation.validateRgbColor(rgb[0], rgb[1], rgb[2]);
            },
            .hsv => |hsv| {
                try utils.validation.validateHsvColor(hsv[0], hsv[1], hsv[2]);
            },
        }
    }

    pub fn deinit(self: *AnimationConfig, allocator: std.mem.Allocator) void {
        self.colors.deinit(allocator);
    }
};

pub const Preset = struct {
    name: []const u8,
    config: AnimationConfig,
    created_at: i64,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, config: AnimationConfig) !Preset {
        try utils.validation.validatePresetName(name);
        try config.validate();

        const owned_name = try allocator.dupe(u8, name);

        // Deep-copy the config.colors so the Preset owns any allocated strings
        var copied_colors: std.ArrayList(ColorFormat) = std.ArrayList(ColorFormat){};
        // Make a local copy of the source colors so we can free its backing storage
        var src_colors = config.colors;
        var success: bool = false;
        defer if (!success) copied_colors.deinit(allocator);

        for (src_colors.items) |color| {
            switch (color) {
                .hex => |hex| {
                    const dup = try allocator.dupe(u8, hex);
                    try copied_colors.append(allocator, ColorFormat{ .hex = dup });
                },
                .rgb => |rgb| {
                    try copied_colors.append(allocator, ColorFormat{ .rgb = rgb });
                },
                .hsv => |hsv| {
                    try copied_colors.append(allocator, ColorFormat{ .hsv = hsv });
                },
            }
        }

        success = true;

        // We've successfully copied the colors into our owned list. The caller
        // handed ownership of their colors list to us by convention, so free
        // the source backing storage now to avoid leaks of the array buffer.
        src_colors.deinit(allocator);

        const copied_config = AnimationConfig{
            .animation_type = config.animation_type,
            .fps = config.fps,
            .speed = config.speed,
            .colors = copied_colors,
            .direction = config.direction,
        };

        return Preset{
            .name = owned_name,
            .config = copied_config,
            .created_at = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Preset, allocator: std.mem.Allocator) void {
        // Free any hex strings that this Preset owns. Preset.init duplicates
        // hex strings when copying the config, so we must free them here.
        for (self.config.colors.items) |color| {
            switch (color) {
                .hex => |hex| allocator.free(hex),
                else => {},
            }
        }

        self.config.deinit(allocator);
        allocator.free(self.name);
    }
};
