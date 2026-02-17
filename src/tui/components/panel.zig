//! Panel component - container with border and title
//! Provides a bordered container that can hold other content

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");

pub const Panel = struct {
    title: []const u8,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    border_style: renderer.BorderStyle,
    focused: bool = false,
    visible: bool = true,

    pub fn init(title: []const u8, x: u16, y: u16, width: u16, height: u16) Panel {
        return Panel{
            .title = title,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .border_style = renderer.BorderStyle.single,
        };
    }

    pub fn render(self: *const Panel, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Draw the border
        try r.drawBox(self.x, self.y, self.width, self.height, self.border_style);

        // Draw the title if there's space
        if (self.title.len > 0 and self.width > 4) {
            const title_x = self.x + 2;
            const title_y = self.y;

            // Truncate title if it's too long
            const max_title_len = self.width - 4;
            const display_title = if (self.title.len > max_title_len)
                self.title[0..max_title_len]
            else
                self.title;

            const title_style = renderer.TextStyle{
                .fg_color = if (self.focused) renderer.Color.YELLOW else renderer.Color.WHITE,
                .bold = self.focused,
            };

            try r.drawText(title_x, title_y, display_title, title_style);
        }
    }

    pub fn getContentArea(self: *const Panel) ContentArea {
        return ContentArea{
            .x = self.x + 1,
            .y = self.y + 1,
            .width = if (self.width > 2) self.width - 2 else 0,
            .height = if (self.height > 2) self.height - 2 else 0,
        };
    }

    pub fn setFocus(self: *Panel, focused: bool) void {
        self.focused = focused;
    }

    pub fn setVisible(self: *Panel, visible: bool) void {
        self.visible = visible;
    }

    pub fn setBorderStyle(self: *Panel, style: renderer.BorderStyle) void {
        self.border_style = style;
    }

    pub fn contains(self: *const Panel, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }
};

pub const ContentArea = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};
