//! Text component - displays text with styling
//! Provides text rendering with various styling options

const std = @import("std");
const renderer = @import("../renderer.zig");

pub const Text = struct {
    content: []const u8,
    x: u16,
    y: u16,
    style: renderer.TextStyle,
    visible: bool = true,
    max_width: ?u16 = null,

    pub fn init(content: []const u8, x: u16, y: u16) Text {
        return Text{
            .content = content,
            .x = x,
            .y = y,
            .style = renderer.TextStyle{},
        };
    }

    pub fn initWithStyle(content: []const u8, x: u16, y: u16, style: renderer.TextStyle) Text {
        return Text{
            .content = content,
            .x = x,
            .y = y,
            .style = style,
        };
    }

    pub fn render(self: *const Text, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        var display_content = self.content;

        // Truncate if max_width is set
        if (self.max_width) |max_w| {
            if (self.content.len > max_w) {
                display_content = self.content[0..max_w];
            }
        }

        try r.drawText(self.x, self.y, display_content, self.style);
    }

    pub fn setContent(self: *Text, content: []const u8) void {
        self.content = content;
    }

    pub fn setStyle(self: *Text, style: renderer.TextStyle) void {
        self.style = style;
    }

    pub fn setPosition(self: *Text, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
    }

    pub fn setVisible(self: *Text, visible: bool) void {
        self.visible = visible;
    }

    pub fn setMaxWidth(self: *Text, max_width: ?u16) void {
        self.max_width = max_width;
    }

    pub fn getWidth(self: *const Text) u16 {
        if (self.max_width) |max_w| {
            return @min(@as(u16, @intCast(self.content.len)), max_w);
        }
        return @as(u16, @intCast(self.content.len));
    }
};
