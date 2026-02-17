const std = @import("std");
const tui = @import("src/tui/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing Basic Terminal Rendering\n", .{});
    std.debug.print("================================\n\n", .{});

    var r = try tui.renderer.Renderer.init(allocator);
    defer r.deinit();

    // Clear screen and hide cursor
    try r.clear();
    try r.hideCursor();

    // Test terminal size detection
    const size = r.getTerminalSize();
    try r.drawText(2, 1, "Terminal Rendering Test", tui.renderer.TextStyle{ .fg_color = tui.renderer.Color.CYAN, .bold = true });

    var buffer: [100]u8 = undefined;
    const size_text = try std.fmt.bufPrint(buffer[0..], "Terminal size: {d}x{d}", .{ size.width, size.height });
    try r.drawText(2, 2, size_text, tui.renderer.TextStyle{ .fg_color = tui.renderer.Color.GREEN });

    // Test all border styles
    try r.drawBox(5, 4, 15, 5, tui.renderer.BorderStyle.single);
    try r.drawText(6, 5, "Single", tui.renderer.TextStyle{});

    try r.drawBox(25, 4, 15, 5, tui.renderer.BorderStyle.double);
    try r.drawText(26, 5, "Double", tui.renderer.TextStyle{ .fg_color = tui.renderer.Color.YELLOW });

    try r.drawBox(45, 4, 15, 5, tui.renderer.BorderStyle.rounded);
    try r.drawText(46, 5, "Rounded", tui.renderer.TextStyle{ .fg_color = tui.renderer.Color.MAGENTA });

    try r.drawBox(5, 10, 15, 5, tui.renderer.BorderStyle.thick);
    try r.drawText(6, 11, "Thick", tui.renderer.TextStyle{ .fg_color = tui.renderer.Color.CYAN });

    // Test progress bars
    try r.drawText(2, 16, "Progress bars:", tui.renderer.TextStyle{ .bold = true });
    try r.drawProgressBar(2, 17, 20, 0.25);
    try r.drawText(25, 17, "25%", tui.renderer.TextStyle{});

    try r.drawProgressBar(2, 18, 20, 0.75);
    try r.drawText(25, 18, "75%", tui.renderer.TextStyle{});

    try r.drawProgressBar(2, 19, 20, 1.0);
    try r.drawText(25, 19, "100%", tui.renderer.TextStyle{});

    // Test color previews
    try r.drawText(2, 21, "Colors:", tui.renderer.TextStyle{ .bold = true });
    try r.drawColorPreview(10, 21, tui.renderer.Color.RED);
    try r.drawText(13, 21, "Red", tui.renderer.TextStyle{});

    try r.drawColorPreview(20, 21, tui.renderer.Color.GREEN);
    try r.drawText(23, 21, "Green", tui.renderer.TextStyle{});

    try r.drawColorPreview(32, 21, tui.renderer.Color.BLUE);
    try r.drawText(35, 21, "Blue", tui.renderer.TextStyle{});

    // Show cursor and move to bottom
    try r.showCursor();
    try r.moveCursor(0, size.height - 1);

    std.debug.print("Rendering test completed!\n", .{});
}
