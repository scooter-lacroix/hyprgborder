//! Tests for TUI screens
//! Tests for animation settings and preset management panels

const std = @import("std");
const testing = std.testing;
const tui = @import("tui");
const config = @import("config");
const c = @cImport({
    @cInclude("stdlib.h");
});

test "AnimationSettingsPanel basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var panel = try tui.screens.AnimationSettingsPanel.init(allocator, 0, 0, 60, 30);
    defer panel.deinit();

    // Test initial state
    const initial_config = panel.getAnimationConfig();
    try testing.expect(initial_config.fps > 0);
    try testing.expect(initial_config.speed > 0.0);

    // Test setting configuration
    var new_config = config.AnimationConfig.default();
    new_config.animation_type = config.AnimationType.pulse;
    new_config.fps = 30;
    new_config.speed = 0.5;

    try panel.setAnimationConfig(new_config);
    const updated_config = panel.getAnimationConfig();
    try testing.expect(updated_config.animation_type == config.AnimationType.pulse);
    try testing.expect(updated_config.fps == 30);
    try testing.expect(updated_config.speed == 0.5);

    // Test visibility
    panel.setVisible(false);
    try testing.expect(!panel.visible);

    panel.setVisible(true);
    try testing.expect(panel.visible);
}

test "PresetManagementPanel basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Make the test hermetic by using a temporary XDG_CONFIG_HOME so we don't
    // read the user's real config/presets. This mirrors how the persistence
    // layer resolves the config path.
    const tmp_base = try std.fmt.allocPrint(allocator, "/tmp/hypring_test_{d}", .{std.time.timestamp()});
    defer allocator.free(tmp_base);

    // Create base temp dir
    std.fs.makeDirAbsolute(tmp_base) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Create hyprgborder subdir
    const hypr_dir = try std.fmt.allocPrint(allocator, "{s}/hyprgborder", .{tmp_base});
    defer allocator.free(hypr_dir);
    std.fs.makeDirAbsolute(hypr_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Set XDG_CONFIG_HOME for the test process (best-effort) using libc setenv
    const tmp_c = try allocator.alloc(u8, tmp_base.len + 1);
    defer allocator.free(tmp_c);
    @memcpy(tmp_c[0..tmp_base.len], tmp_base);
    tmp_c[tmp_base.len] = 0;
    // name must be a null-terminated C string as well
    const name_c = try allocator.alloc(u8, "XDG_CONFIG_HOME".len + 1);
    defer allocator.free(name_c);
    @memcpy(name_c[0.."XDG_CONFIG_HOME".len], "XDG_CONFIG_HOME");
    name_c["XDG_CONFIG_HOME".len] = 0;
    _ = c.setenv(name_c.ptr, tmp_c.ptr, 1);

    var panel = try tui.screens.PresetManagementPanel.init(allocator, 0, 0, 50, 25);
    defer panel.deinit();

    // Test initial state
    try testing.expect(panel.visible);
    try testing.expect(panel.getSelectedPresetName() == null);

    // Test visibility
    panel.setVisible(false);
    try testing.expect(!panel.visible);

    panel.setVisible(true);
    try testing.expect(panel.visible);

    // Test current preset setting
    try panel.setCurrentPreset("test_preset");
    // Note: This would normally update the display, but we can't easily test that without a full preset system
}

test "TUI screens integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that both screens can be created and work together
    var animation_panel = try tui.screens.AnimationSettingsPanel.init(allocator, 0, 0, 60, 30);
    defer animation_panel.deinit();

    var preset_panel = try tui.screens.PresetManagementPanel.init(allocator, 65, 0, 50, 25);
    defer preset_panel.deinit();

    // Test positioning
    animation_panel.setPosition(10, 5);
    preset_panel.setPosition(75, 5);

    // Both should be visible and functional
    try testing.expect(animation_panel.visible);
    try testing.expect(preset_panel.visible);

    // Test that they can be updated independently
    animation_panel.update(1000); // 1 second
    // Preset panel doesn't have an update method, which is fine

    // Test configuration sharing (conceptually)
    const config_from_animation = animation_panel.getAnimationConfig();
    try testing.expect(config_from_animation.fps > 0);
}
