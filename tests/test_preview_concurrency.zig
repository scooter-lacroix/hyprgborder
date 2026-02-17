const std = @import("std");
const testing = std.testing;
const preview = @import("tui").preview;
const config = @import("config");

// Top-level reader function used by the concurrency test
fn concurrency_reader_fn(ptr: *anyopaque) anyerror!void {
    const m = @as(*preview.PreviewManager, @ptrCast(@alignCast(ptr)));
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const fps = m.current_config.fps;
        const sp = m.current_config.speed;
        if (fps == 0) _ = sp;
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }
    return;
}

// This test tries to reproduce concurrent access to PreviewManager.updateConfig
// by running a reader thread that reads current_config while the main thread
// repeatedly calls updateConfig. It doesn't require Hyprland; it only tests
// memory safety for concurrent reads/writes of the config structure.

test "PreviewManager concurrency smoke test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = preview.PreviewManager.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            std.log.warn("Skipping concurrency test - not in Hyprland environment", .{});
            return;
        },
        else => return err,
    };
    defer manager.deinit();

    // Start a reader thread that frequently reads current_config

    var reader_thread = try std.Thread.spawn(.{}, concurrency_reader_fn, .{&manager});

    // Writer: repeatedly update config with different colors and varying speeds
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        var colors: std.ArrayList(config.ColorFormat) = .{};
        // Use RGB entry to avoid rapid allocator.dupe of hex strings during tight loops
        const cf = config.ColorFormat{ .rgb = .{ @as(u8, @intCast(i % 256)), 0, 0 } };
        try colors.append(allocator, cf);

        // Vary speed using the project's float-from-int idiom
        const speed = @as(f64, @floatFromInt(i % 100)) * 0.001 + 0.01; // range ~0.01 .. 0.109

        // Create new config and call updateConfig
        const new_cfg = config.AnimationConfig{
            .animation_type = .pulse,
            .fps = 60,
            .speed = speed,
            .colors = colors,
            .direction = .clockwise,
        };
        try manager.updateConfig(new_cfg);
        // sleep a little
        std.Thread.sleep(2 * std.time.ns_per_ms);
        // cleanup colors we allocated inside new_cfg; manager should have duplicated or taken ownership
        colors.deinit(allocator);
    }

    reader_thread.join();
}
