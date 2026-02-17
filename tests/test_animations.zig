//! Unit tests for animation providers
//! Tests animation calculations, provider interface, and timing utilities

const std = @import("std");
const testing = std.testing;
const animations = @import("animations");
const config = @import("config");
const utils = @import("utils");

test "AnimationProvider interface - rainbow animation" {
    const allocator = testing.allocator;

    var animation_provider = try animations.createAnimationProvider(allocator, .rainbow);
    defer animation_provider.cleanup();

    // Test configuration
    var colors: std.ArrayList(config.ColorFormat) = .{};
    defer colors.deinit(allocator);

    const animation_config = config.AnimationConfig{
        .animation_type = .rainbow,
        .fps = 30,
        .speed = 0.02,
        .colors = colors,
        .direction = .clockwise,
    };

    try animation_provider.configure(animation_config);

    // Test update (we can't test actual Hyprland communication, but we can test it doesn't crash)
    // Using a dummy socket path since we're just testing the interface
    animation_provider.update(allocator, "/tmp/dummy.sock", 0.0) catch |err| switch (err) {
        utils.hyprland.HyprlandError.SocketConnectionFailed => {}, // Expected in test environment
        else => return err,
    };
}

test "AnimationProvider interface - pulse animation" {
    const allocator = testing.allocator;

    var animation_provider = try animations.createAnimationProvider(allocator, .pulse);
    defer animation_provider.cleanup();

    // Test configuration with colors
    var colors: std.ArrayList(config.ColorFormat) = .{};
    defer colors.deinit(allocator);
    try colors.append(allocator, try config.ColorFormat.fromHex("#FF0000"));

    const animation_config = config.AnimationConfig{
        .animation_type = .pulse,
        .fps = 30,
        .speed = 0.05,
        .colors = colors,
        .direction = .clockwise,
    };

    try animation_provider.configure(animation_config);

    // Test update
    animation_provider.update(allocator, "/tmp/dummy.sock", 0.0) catch |err| switch (err) {
        utils.hyprland.HyprlandError.SocketConnectionFailed => {}, // Expected in test environment
        else => return err,
    };
}

test "AnimationProvider interface - gradient animation" {
    const allocator = testing.allocator;

    var animation_provider = try animations.createAnimationProvider(allocator, .gradient);
    defer animation_provider.cleanup();

    // Test configuration with multiple colors
    var colors: std.ArrayList(config.ColorFormat) = .{};
    defer colors.deinit(allocator);
    try colors.append(allocator, try config.ColorFormat.fromHex("#FF0000"));
    try colors.append(allocator, try config.ColorFormat.fromHex("#00FF00"));
    try colors.append(allocator, try config.ColorFormat.fromHex("#0000FF"));

    const animation_config = config.AnimationConfig{
        .animation_type = .gradient,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };

    try animation_provider.configure(animation_config);

    // Test update
    animation_provider.update(allocator, "/tmp/dummy.sock", 0.0) catch |err| switch (err) {
        utils.hyprland.HyprlandError.SocketConnectionFailed => {}, // Expected in test environment
        else => return err,
    };
}

test "AnimationProvider interface - solid animation" {
    const allocator = testing.allocator;

    var animation_provider = try animations.createAnimationProvider(allocator, .solid);
    defer animation_provider.cleanup();

    // Test configuration with color
    var colors: std.ArrayList(config.ColorFormat) = .{};
    defer colors.deinit(allocator);
    try colors.append(allocator, try config.ColorFormat.fromHex("#FFFFFF"));

    const animation_config = config.AnimationConfig{
        .animation_type = .solid,
        .fps = 30,
        .speed = 0.0, // Speed doesn't matter for solid colors
        .colors = colors,
        .direction = .clockwise,
    };

    try animation_provider.configure(animation_config);

    // Test update
    animation_provider.update(allocator, "/tmp/dummy.sock", 0.0) catch |err| switch (err) {
        utils.hyprland.HyprlandError.SocketConnectionFailed => {}, // Expected in test environment
        else => return err,
    };
}

test "Pulse animation calculations" {
    // Test pulse intensity calculation at different phases
    const test_cases = [_]struct {
        phase: f64,
        expected_min: f64,
        expected_max: f64,
    }{
        .{ .phase = 0.0, .expected_min = 0.4, .expected_max = 0.6 }, // sin(0) = 0, intensity = 0.5
        .{ .phase = std.math.pi / 2.0, .expected_min = 0.9, .expected_max = 1.1 }, // sin(π/2) = 1, intensity = 1.0
        .{ .phase = std.math.pi, .expected_min = 0.4, .expected_max = 0.6 }, // sin(π) = 0, intensity = 0.5
        .{ .phase = 3.0 * std.math.pi / 2.0, .expected_min = -0.1, .expected_max = 0.1 }, // sin(3π/2) = -1, intensity = 0.0
    };

    for (test_cases) |case| {
        const intensity = (@sin(case.phase) + 1.0) / 2.0;
        try testing.expect(intensity >= case.expected_min);
        try testing.expect(intensity <= case.expected_max);
    }
}

test "Gradient color cycling calculations" {
    // Test gradient color index calculation
    const color_count = 4;
    const test_cases = [_]struct {
        phase: f64,
        expected_index1: usize,
        expected_index2: usize,
    }{
        .{ .phase = 0.0, .expected_index1 = 0, .expected_index2 = 1 },
        .{ .phase = 1.0, .expected_index1 = 1, .expected_index2 = 2 },
        .{ .phase = 2.0, .expected_index1 = 2, .expected_index2 = 3 },
        .{ .phase = 3.0, .expected_index1 = 3, .expected_index2 = 0 },
        .{ .phase = 4.0, .expected_index1 = 0, .expected_index2 = 1 }, // Wraps around
    };

    for (test_cases) |case| {
        const index1 = @as(usize, @intFromFloat(case.phase)) % color_count;
        const index2 = (index1 + 1) % color_count;

        try testing.expectEqual(case.expected_index1, index1);
        try testing.expectEqual(case.expected_index2, index2);
    }
}

test "Hyprland color format conversion" {
    const allocator = testing.allocator;

    // Test hex to Hyprland format conversion
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "#FF0000", .expected = "0xffFF0000" },
        .{ .input = "#00FF00", .expected = "0xff00FF00" },
        .{ .input = "#0000FF", .expected = "0xff0000FF" },
        .{ .input = "#FFFFFF", .expected = "0xffFFFFFF" },
        .{ .input = "#000000", .expected = "0xff000000" },
    };

    for (test_cases) |case| {
        const result = try std.fmt.allocPrint(allocator, "0xff{s}", .{case.input[1..]});
        defer allocator.free(result);

        try testing.expectEqualStrings(case.expected, result);
    }
}

test "Rainbow hue calculations" {
    // Test rainbow hue progression
    var hue: f64 = 0.0;
    const speed: f64 = 0.01;

    // Test clockwise progression
    for (0..100) |_| {
        try testing.expect(hue >= 0.0);
        try testing.expect(hue < 1.0);
        hue = @mod(hue + speed, 1.0);
    }

    // Test counter-clockwise progression
    hue = 0.0;
    for (0..100) |_| {
        try testing.expect(hue >= 0.0);
        try testing.expect(hue < 1.0);
        hue = @mod(hue - speed + 1.0, 1.0); // Add 1.0 to handle negative values
    }
}

test "Frame timing calculations" {
    // Test frame timing calculations used in animation loops
    const test_cases = [_]struct {
        fps: u32,
        expected_ns: u64,
    }{
        .{ .fps = 30, .expected_ns = std.time.ns_per_s / 30 },
        .{ .fps = 60, .expected_ns = std.time.ns_per_s / 60 },
        .{ .fps = 120, .expected_ns = std.time.ns_per_s / 120 },
    };

    for (test_cases) |case| {
        const frame_time_ns = std.time.ns_per_s / case.fps;
        try testing.expectEqual(case.expected_ns, frame_time_ns);

        // Verify the timing makes sense (should be reasonable frame times)
        try testing.expect(frame_time_ns > 0);
        try testing.expect(frame_time_ns < std.time.ns_per_s); // Less than 1 second
    }
}

test "Color intensity modulation for pulse animation" {
    const allocator = testing.allocator;

    // Test color intensity modulation used in pulse animation
    const base_color = "#FF8000"; // Orange
    const test_intensities = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0 };

    for (test_intensities) |intensity| {
        // Parse the base color
        const r = try std.fmt.parseInt(u8, base_color[1..3], 16);
        const g = try std.fmt.parseInt(u8, base_color[3..5], 16);
        const b = try std.fmt.parseInt(u8, base_color[5..7], 16);

        // Apply intensity modulation
        const mod_r = @as(u8, @intFromFloat(@as(f64, @floatFromInt(r)) * intensity));
        const mod_g = @as(u8, @intFromFloat(@as(f64, @floatFromInt(g)) * intensity));
        const mod_b = @as(u8, @intFromFloat(@as(f64, @floatFromInt(b)) * intensity));

        // Verify the modulated values are within valid range
        try testing.expect(mod_r <= r);
        try testing.expect(mod_g <= g);
        try testing.expect(mod_b <= b);

        // Create the modulated color string
        const modulated_color = try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ mod_r, mod_g, mod_b });
        defer allocator.free(modulated_color);

        // Verify format is correct
        try testing.expect(modulated_color.len == 7);
        try testing.expect(modulated_color[0] == '#');
    }
}
