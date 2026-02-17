//! Unit tests for configuration types and validation
//! Tests all configuration data structures and validation functions

const std = @import("std");
const testing = std.testing;
const config_mod = @import("config");
const utils = @import("utils");

const AnimationType = config_mod.AnimationType;
const ColorFormat = config_mod.ColorFormat;
const AnimationDirection = config_mod.AnimationDirection;
const AnimationConfig = config_mod.AnimationConfig;
const Preset = config_mod.Preset;
const ValidationError = config_mod.types.ValidationError;

test "AnimationType toString and fromString" {
    try testing.expectEqualStrings("rainbow", AnimationType.rainbow.toString());
    try testing.expectEqualStrings("pulse", AnimationType.pulse.toString());
    try testing.expectEqualStrings("gradient", AnimationType.gradient.toString());
    try testing.expectEqualStrings("solid", AnimationType.solid.toString());

    try testing.expectEqual(AnimationType.rainbow, AnimationType.fromString("rainbow").?);
    try testing.expectEqual(AnimationType.pulse, AnimationType.fromString("pulse").?);
    try testing.expectEqual(AnimationType.gradient, AnimationType.fromString("gradient").?);
    try testing.expectEqual(AnimationType.solid, AnimationType.fromString("solid").?);
    try testing.expectEqual(@as(?AnimationType, null), AnimationType.fromString("invalid"));
}

test "AnimationDirection toString and fromString" {
    try testing.expectEqualStrings("clockwise", AnimationDirection.clockwise.toString());
    try testing.expectEqualStrings("counter_clockwise", AnimationDirection.counter_clockwise.toString());

    try testing.expectEqual(AnimationDirection.clockwise, AnimationDirection.fromString("clockwise").?);
    try testing.expectEqual(AnimationDirection.counter_clockwise, AnimationDirection.fromString("counter_clockwise").?);
    try testing.expectEqual(@as(?AnimationDirection, null), AnimationDirection.fromString("invalid"));
}

test "ColorFormat creation and validation" {
    const hex_color = try ColorFormat.fromHex("#FF0000");
    try testing.expectEqualStrings("#FF0000", hex_color.hex);

    try testing.expectError(ValidationError.InvalidColorFormat, ColorFormat.fromHex("FF0000"));
    try testing.expectError(ValidationError.InvalidColorFormat, ColorFormat.fromHex("#FF00"));
    try testing.expectError(ValidationError.InvalidColorFormat, ColorFormat.fromHex("#GG0000"));

    const rgb_color = try ColorFormat.fromRgb(255, 0, 0);
    try testing.expectEqual(@as(u8, 255), rgb_color.rgb[0]);
    try testing.expectEqual(@as(u8, 0), rgb_color.rgb[1]);
    try testing.expectEqual(@as(u8, 0), rgb_color.rgb[2]);

    const hsv_color = try ColorFormat.fromHsv(0.0, 1.0, 1.0);
    try testing.expectEqual(@as(f64, 0.0), hsv_color.hsv[0]);
    try testing.expectEqual(@as(f64, 1.0), hsv_color.hsv[1]);
    try testing.expectEqual(@as(f64, 1.0), hsv_color.hsv[2]);

    try testing.expectError(ValidationError.InvalidColorFormat, ColorFormat.fromHsv(-0.1, 1.0, 1.0));
    try testing.expectError(ValidationError.InvalidColorFormat, ColorFormat.fromHsv(0.0, 1.1, 1.0));
    try testing.expectError(ValidationError.InvalidColorFormat, ColorFormat.fromHsv(0.0, 1.0, 1.1));
}

test "ColorFormat conversion" {
    const allocator = testing.allocator;

    const hex_color = try ColorFormat.fromHex("#FF0000");
    const hex_string = try hex_color.toHex(allocator);
    defer allocator.free(hex_string);
    try testing.expectEqualStrings("#FF0000", hex_string);

    const rgb_color = try ColorFormat.fromRgb(255, 0, 0);
    const rgb_hex_string = try rgb_color.toHex(allocator);
    defer allocator.free(rgb_hex_string);
    try testing.expectEqualStrings("#FF0000", rgb_hex_string);

    const hsv_color = try ColorFormat.fromHsv(0.0, 1.0, 1.0);
    const hsv_hex_string = try hsv_color.toHex(allocator);
    defer allocator.free(hsv_hex_string);
    try testing.expectEqualStrings("#FF0000", hsv_hex_string);

    const hex_rgb = hex_color.toRgb();
    try testing.expectEqual(@as(u8, 255), hex_rgb[0]);
    try testing.expectEqual(@as(u8, 0), hex_rgb[1]);
    try testing.expectEqual(@as(u8, 0), hex_rgb[2]);

    const hsv_rgb = hsv_color.toRgb();
    try testing.expectEqual(@as(u8, 255), hsv_rgb[0]);
    try testing.expectEqual(@as(u8, 0), hsv_rgb[1]);
    try testing.expectEqual(@as(u8, 0), hsv_rgb[2]);
}

test "AnimationConfig validation - FPS" {
    const allocator = testing.allocator;
    var colors: std.ArrayList(ColorFormat) = .{};
    defer colors.deinit(allocator);

    var config = AnimationConfig{
        .animation_type = .rainbow,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };
    try config.validate();

    config.fps = 0;
    try testing.expectError(ValidationError.FpsOutOfRange, config.validate());

    config.fps = 121;
    try testing.expectError(ValidationError.FpsOutOfRange, config.validate());

    config.fps = 1;
    try config.validate();
    config.fps = 120;
    try config.validate();
}

test "AnimationConfig validation - Speed" {
    const allocator = testing.allocator;
    var colors: std.ArrayList(ColorFormat) = .{};
    defer colors.deinit(allocator);

    var config = AnimationConfig{
        .animation_type = .rainbow,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };

    try config.validate();

    config.speed = 0.0005;
    try testing.expectError(ValidationError.SpeedOutOfRange, config.validate());

    config.speed = 1.1;
    try testing.expectError(ValidationError.SpeedOutOfRange, config.validate());

    config.speed = 0.001;
    try config.validate();
    config.speed = 1.0;
    try config.validate();
}

test "AnimationConfig validation - Colors for animation types" {
    std.debug.print("[RUNNING] AnimationConfig validation - Colors for animation types\n", .{});

    const allocator = testing.allocator;
    var colors: std.ArrayList(ColorFormat) = .{};
    defer colors.deinit(allocator);

    var config = AnimationConfig{
        .animation_type = .rainbow,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };
    try config.validate();

    // Test pulse animation - requires at least 1 color
    config.animation_type = .pulse;
    try testing.expectError(ValidationError.InsufficientColors, config.validate());

    try colors.append(allocator, try ColorFormat.fromHex("#FF0000"));
    config.colors = colors; // Update config to point to the modified colors
    try config.validate();

    // Test gradient animation - requires at least 2 colors
    config.animation_type = .gradient;
    try testing.expectError(ValidationError.InsufficientColors, config.validate());

    try colors.append(allocator, try ColorFormat.fromHex("#00FF00"));
    config.colors = colors; // Update config to point to the modified colors
    try config.validate();

    // Test solid animation - requires at least 1 color
    colors.clearRetainingCapacity();
    config.colors = colors; // Update config to point to the cleared colors
    config.animation_type = .solid;
    try testing.expectError(ValidationError.InsufficientColors, config.validate());

    try colors.append(allocator, try ColorFormat.fromHex("#0000FF"));
    config.colors = colors; // Update config to point to the modified colors
    try config.validate();
}

test "AnimationConfig validation - Invalid colors" {
    const allocator = testing.allocator;
    var colors: std.ArrayList(ColorFormat) = .{};
    defer colors.deinit(allocator);

    try colors.append(allocator, try ColorFormat.fromHex("#FF0000"));

    const config = AnimationConfig{
        .animation_type = .pulse,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };

    try config.validate();
}

test "Preset creation and validation" {
    const allocator = testing.allocator;
    var colors: std.ArrayList(ColorFormat) = .{};
    // Don't defer colors.deinit here because Preset.init takes ownership

    try colors.append(allocator, try ColorFormat.fromHex("#FF0000"));

    const config = AnimationConfig{
        .animation_type = .pulse,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };

    var preset = try Preset.init(allocator, "My Preset", config);
    defer preset.deinit(allocator);

    try testing.expectEqualStrings("My Preset", preset.name);
    try testing.expectEqual(AnimationType.pulse, preset.config.animation_type);

    // Test invalid preset names - these should fail validation before taking ownership
    {
        var test_colors: std.ArrayList(ColorFormat) = .{};
        try test_colors.append(allocator, try ColorFormat.fromHex("#FF0000"));
        const test_config = AnimationConfig{
            .animation_type = .pulse,
            .fps = 30,
            .speed = 0.01,
            .colors = test_colors,
            .direction = .clockwise,
        };

        // This should fail validation and not take ownership
        if (Preset.init(allocator, "", test_config)) |_| {
            @panic("Expected error but got success");
        } else |err| {
            try testing.expectEqual(ValidationError.EmptyPresetName, err);
            // Since init failed, we need to clean up the colors ourselves
            test_colors.deinit(allocator);
        }
    }

    {
        var test_colors: std.ArrayList(ColorFormat) = .{};
        try test_colors.append(allocator, try ColorFormat.fromHex("#FF0000"));
        const test_config = AnimationConfig{
            .animation_type = .pulse,
            .fps = 30,
            .speed = 0.01,
            .colors = test_colors,
            .direction = .clockwise,
        };

        const long_name = "a" ** 65;
        if (Preset.init(allocator, long_name, test_config)) |_| {
            @panic("Expected error but got success");
        } else |err| {
            try testing.expectEqual(ValidationError.PresetNameTooLong, err);
            test_colors.deinit(allocator);
        }
    }

    {
        var test_colors: std.ArrayList(ColorFormat) = .{};
        try test_colors.append(allocator, try ColorFormat.fromHex("#FF0000"));
        const test_config = AnimationConfig{
            .animation_type = .pulse,
            .fps = 30,
            .speed = 0.01,
            .colors = test_colors,
            .direction = .clockwise,
        };

        if (Preset.init(allocator, "Invalid@Name", test_config)) |_| {
            @panic("Expected error but got success");
        } else |err| {
            try testing.expectEqual(ValidationError.InvalidPresetName, err);
            test_colors.deinit(allocator);
        }
    }

    // Test valid preset name
    {
        var test_colors: std.ArrayList(ColorFormat) = .{};
        try test_colors.append(allocator, try ColorFormat.fromHex("#FF0000"));
        const test_config = AnimationConfig{
            .animation_type = .pulse,
            .fps = 30,
            .speed = 0.01,
            .colors = test_colors,
            .direction = .clockwise,
        };

        var valid_preset = try Preset.init(allocator, "Valid_Name-123", test_config);
        defer valid_preset.deinit(allocator);
        try testing.expectEqualStrings("Valid_Name-123", valid_preset.name);
    }
}

test "AnimationConfig default values" {
    const default_config = AnimationConfig.default();

    try testing.expectEqual(AnimationType.rainbow, default_config.animation_type);
    try testing.expectEqual(@as(u32, 30), default_config.fps);
    try testing.expectEqual(@as(f64, 0.01), default_config.speed);
    try testing.expectEqual(AnimationDirection.clockwise, default_config.direction);
    try testing.expectEqual(@as(usize, 0), default_config.colors.items.len);
}

test "ColorFormat validateColorFormat function" {
    const hex_color = ColorFormat{ .hex = "#FF0000" };
    try AnimationConfig.validateColorFormat(hex_color);

    const rgb_color = ColorFormat{ .rgb = .{ 255, 0, 0 } };
    try AnimationConfig.validateColorFormat(rgb_color);

    const hsv_color = ColorFormat{ .hsv = .{ 0.0, 1.0, 1.0 } };
    try AnimationConfig.validateColorFormat(hsv_color);

    const invalid_hex = ColorFormat{ .hex = "FF0000" };
    try testing.expectError(ValidationError.InvalidColorFormat, AnimationConfig.validateColorFormat(invalid_hex));

    const invalid_hsv = ColorFormat{ .hsv = .{ 1.1, 1.0, 1.0 } };
    try testing.expectError(ValidationError.InvalidColorFormat, AnimationConfig.validateColorFormat(invalid_hsv));
}

test "Configuration persistence - save and load" {
    const allocator = testing.allocator;
    var colors: std.ArrayList(ColorFormat) = .{};
    defer colors.deinit(allocator);

    try colors.append(allocator, try ColorFormat.fromHex("#FF0000"));
    try colors.append(allocator, try ColorFormat.fromHex("#00FF00"));

    const config = AnimationConfig{
        .animation_type = .gradient,
        .fps = 60,
        .speed = 0.02,
        .colors = colors,
        .direction = .counter_clockwise,
    };

    const persistence = config_mod.persistence;

    persistence.saveConfig(allocator, &config) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => return,
        else => return err,
    };

    var loaded_config = persistence.loadConfig(allocator) catch |err| switch (err) {
        persistence.PersistenceError.ConfigNotFound => return,
        else => return err,
    };
    defer loaded_config.deinit(allocator);

    try testing.expectEqual(config.animation_type, loaded_config.animation_type);
    try testing.expectEqual(config.fps, loaded_config.fps);
    try testing.expectEqual(config.speed, loaded_config.speed);
    try testing.expectEqual(config.direction, loaded_config.direction);
    try testing.expectEqual(config.colors.items.len, loaded_config.colors.items.len);

    // Clean up the config file so it doesn't interfere with other tests
    const config_path = persistence.getConfigPath(allocator) catch return;
    defer allocator.free(config_path);
    std.fs.deleteFileAbsolute(config_path) catch {};
}

test "Configuration persistence - load default when not found" {
    const allocator = testing.allocator;
    const persistence = config_mod.persistence;

    var config = try persistence.loadConfigOrDefault(allocator);
    defer config.deinit(allocator);

    try testing.expectEqual(AnimationType.rainbow, config.animation_type);
    try testing.expectEqual(@as(u32, 30), config.fps);
    try testing.expectEqual(@as(f64, 0.01), config.speed);
    try testing.expectEqual(AnimationDirection.clockwise, config.direction);
}
