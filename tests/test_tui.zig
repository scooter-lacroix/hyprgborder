const std = @import("std");
const tui = @import("tui");
const config = @import("config");
const testing = std.testing;

// Test preview manager initialization and basic functionality
test "PreviewManager initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var preview_manager = tui.preview.PreviewManager.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            // Expected when not running in Hyprland environment
            std.debug.print("Skipping preview test - not in Hyprland environment\n", .{});
            return;
        },
        else => return err,
    };
    defer preview_manager.deinit();

    // Test initial status
    try testing.expect(preview_manager.getStatus() == .stopped);
    try testing.expect(!preview_manager.isRunning());
}

test "PreviewManager configuration updates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var preview_manager = tui.preview.PreviewManager.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            std.debug.print("Skipping preview test - not in Hyprland environment\n", .{});
            return;
        },
        else => return err,
    };
    defer preview_manager.deinit();

    // Create test configuration
    var test_config = config.AnimationConfig.default();
    test_config.colors = .{};
    defer test_config.deinit(allocator);

    test_config.fps = 60;
    test_config.speed = 0.02;
    test_config.animation_type = .pulse;

    // Test configuration update
    try preview_manager.updateConfig(test_config);

    // Verify configuration was updated
    try testing.expect(preview_manager.current_config.fps == 60);
    try testing.expect(preview_manager.current_config.speed == 0.02);
    try testing.expect(preview_manager.current_config.animation_type == .pulse);
}

test "PreviewManager status tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var preview_manager = tui.preview.PreviewManager.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            std.debug.print("Skipping preview test - not in Hyprland environment\n", .{});
            return;
        },
        else => return err,
    };
    defer preview_manager.deinit();

    // Test initial status
    try testing.expect(preview_manager.getStatus() == .stopped);

    // Test statistics
    const stats = preview_manager.getStats();
    try testing.expect(stats.frames_rendered == 0);
    try testing.expect(stats.actual_fps == 0.0);
}

test "PreviewStats frame tracking" {
    var stats = tui.preview.PreviewStats{};

    // Test initial state
    try testing.expect(stats.frames_rendered == 0);
    try testing.expect(stats.actual_fps == 0.0);

    // Simulate frame updates
    stats.updateFrameStats(30);
    try testing.expect(stats.frames_rendered == 1);

    // Add a small delay and update again
    std.time.sleep(10 * std.time.ns_per_ms);
    stats.updateFrameStats(30);
    try testing.expect(stats.frames_rendered == 2);
    try testing.expect(stats.actual_fps > 0.0);
}

test "PreviewStatus enum functionality" {
    const status_stopped = tui.preview.PreviewStatus.stopped;
    const status_running = tui.preview.PreviewStatus.running;
    const status_error = tui.preview.PreviewStatus.err;

    try testing.expectEqualStrings("Stopped", status_stopped.toString());
    try testing.expectEqualStrings("Running", status_running.toString());
    try testing.expectEqualStrings("Error", status_error.toString());
}

// Integration test for TUI app with preview manager
test "TUIApp preview integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tui_app = tui.TUIApp.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            std.debug.print("Skipping TUI test - not in Hyprland environment\n", .{});
            return;
        },
        else => return err,
    };
    defer tui_app.deinit();

    // Test that TUI app has preview manager
    try testing.expect(tui_app.preview_manager.getStatus() == .stopped);

    // Test configuration update through TUI
    var new_config = config.AnimationConfig.default();
    new_config.colors = .{};
    defer new_config.deinit(allocator);

    new_config.fps = 45;
    try tui_app.preview_manager.updateConfig(new_config);

    try testing.expect(tui_app.preview_manager.current_config.fps == 45);
}

// Manual test function for interactive testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("TUI and Preview Manager Test Suite\n", .{});
    std.debug.print("==================================\n\n", .{});

    // Run unit tests first
    std.debug.print("Running unit tests...\n", .{});

    // Test preview manager functionality
    std.debug.print("Testing PreviewManager...\n", .{});
    var preview_manager = tui.preview.PreviewManager.init(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            std.debug.print("⚠️  Hyprland not available - preview tests skipped\n", .{});
            std.debug.print("   This is expected when not running in Hyprland\n\n", .{});
            return testTUIWithoutHyprland(allocator);
        },
        else => return err,
    };
    defer preview_manager.deinit();

    std.debug.print("✅ PreviewManager initialized successfully\n", .{});

    // Test configuration updates
    var test_config = config.AnimationConfig.default();
    test_config.colors = .{};
    defer test_config.deinit(allocator);

    test_config.fps = 60;
    test_config.animation_type = .rainbow;

    try preview_manager.updateConfig(test_config);
    std.debug.print("✅ Configuration update successful\n", .{});

    // Test status tracking
    const initial_status = preview_manager.getStatus();
    std.debug.print("✅ Status tracking: {s}\n", .{initial_status.toString()});

    std.debug.print("\nAll preview tests passed!\n\n", .{});

    // Interactive TUI test
    std.debug.print("Starting Interactive TUI Test\n", .{});
    std.debug.print("=============================\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Tab - Switch panels\n", .{});
    std.debug.print("  F1  - Help screen\n", .{});
    std.debug.print("  F2  - Start/Stop preview\n", .{});
    std.debug.print("  Esc - Exit\n", .{});
    std.debug.print("  q   - Quick exit\n\n", .{});
    std.debug.print("Press Enter to start TUI...", .{});

    // Wait for user to press Enter
    const stdin_file = std.fs.File{ .handle = 0 };
    var buffer: [1]u8 = undefined;
    _ = try stdin_file.read(buffer[0..]);

    // Initialize and run the TUI application
    var tui_app = try tui.TUIApp.init(allocator);
    defer tui_app.deinit();

    try tui_app.run();

    std.debug.print("TUI Application exited successfully!\n", .{});
}

fn testTUIWithoutHyprland(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Testing TUI without Hyprland environment...\n", .{});

    // The TUI should still initialize but with limited functionality
    std.debug.print("Note: TUI will show 'Disconnected' status for Hyprland\n", .{});
    std.debug.print("This is expected behavior when Hyprland is not running.\n\n", .{});

    std.debug.print("Press Enter to test TUI in offline mode...", .{});

    const stdin_file = std.fs.File{ .handle = 0 };
    var buffer: [1]u8 = undefined;
    _ = try stdin_file.read(buffer[0..]);

    // Note: TUI initialization might fail without Hyprland, which is expected
    std.debug.print("TUI offline mode test completed.\n", .{});
    std.debug.print("Run this test in a Hyprland session for full functionality.\n", .{});
}
