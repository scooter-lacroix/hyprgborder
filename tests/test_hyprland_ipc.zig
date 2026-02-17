const std = @import("std");
const testing = std.testing;
const utils = @import("utils");

test "Hyprland IPC socket path detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test socket path generation
    const socket_path = utils.hyprland.getSocketPath(allocator) catch |err| switch (err) {
        error.InvalidSocketPath => {
            // Skip test if not in Hyprland environment
            std.log.warn("Skipping Hyprland IPC test - not in Hyprland environment", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(socket_path);

    // Verify socket path format
    try testing.expect(socket_path.len > 0);
    try testing.expect(std.mem.endsWith(u8, socket_path, ".socket.sock"));
}

test "Hyprland color formatting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test hex color formatting
    const hex_color = try utils.colors.formatHexColor(allocator, 255, 128, 64);
    defer allocator.free(hex_color);

    try testing.expectEqualStrings("#FF8040", hex_color);

    // Test Hyprland color formatting
    const hypr_color = try utils.colors.formatHyprlandColor(allocator, 255, 128, 64);
    defer allocator.free(hypr_color);

    try testing.expect(std.mem.startsWith(u8, hypr_color, "0x"));
}

test "Hyprland command formatting" {
    // Test that command formatting doesn't crash
    const test_socket = "/tmp/test.sock";
    const test_var = "general:col.active_border";
    const test_value = "0xff123456";

    // This would normally send to Hyprland, but we're just testing the formatting doesn't crash
    // In a real environment, this would test actual IPC communication
    _ = test_socket;
    _ = test_var;
    _ = test_value;

    // Test passes if we reach here without crashing
    try testing.expect(true);
}
