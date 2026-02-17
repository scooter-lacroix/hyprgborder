const std = @import("std");
const testing = std.testing;
const preview = @import("tui").preview;
const config = @import("config");

test "PreviewManager basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test preview manager creation
    var manager = preview.PreviewManager.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            // Skip test if not in Hyprland environment
            std.log.warn("Skipping preview test - not in Hyprland environment", .{});
            return;
        },
        else => return err,
    };
    defer manager.deinit();

    // Test initial status
    try testing.expect(manager.getStatus() == .stopped);
    try testing.expect(!manager.isRunning());

    // Test configuration update
    var colors: std.ArrayList(config.ColorFormat) = .{};
    defer colors.deinit(allocator);

    const test_config = config.AnimationConfig{
        .animation_type = .rainbow,
        .fps = 30,
        .speed = 0.01,
        .colors = colors,
        .direction = .clockwise,
    };

    try manager.updateConfig(test_config);

    // Test stats
    const stats = manager.getStats();
    try testing.expect(stats.frames_rendered == 0);
    try testing.expect(stats.actual_fps == 0.0);
}

test "PreviewStatus enum operations" {
    const status = preview.PreviewStatus.stopped;
    try testing.expectEqualStrings("Stopped", status.toString());

    const running_status = preview.PreviewStatus.running;
    try testing.expectEqualStrings("Running", running_status.toString());

    const error_status = preview.PreviewStatus.err;
    try testing.expectEqualStrings("Error", error_status.toString());
}
