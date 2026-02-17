//! List component - scrollable list with selection and highlighting
//! Provides a scrollable list that can display items with selection support

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");

pub const ListItem = struct {
    text: []const u8,
    data: ?*anyopaque = null, // Optional user data
    enabled: bool = true,
};

pub const List = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(ListItem),
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    focused: bool = false,
    visible: bool = true,
    show_scrollbar: bool = true,

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16, height: u16) List {
        return List{
            .allocator = allocator,
            .items = .{},
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *List) void {
        self.items.deinit(self.allocator);
    }

    pub fn addItem(self: *List, text: []const u8) !void {
        try self.items.append(self.allocator, ListItem{ .text = text });
    }

    pub fn addItemWithData(self: *List, text: []const u8, data: *anyopaque) !void {
        try self.items.append(self.allocator, ListItem{ .text = text, .data = data });
    }

    pub fn removeItem(self: *List, index: usize) void {
        if (index < self.items.items.len) {
            _ = self.items.orderedRemove(index);

            // Adjust selection if needed
            if (self.selected_index >= self.items.items.len and self.items.items.len > 0) {
                self.selected_index = self.items.items.len - 1;
            }

            // Adjust scroll if needed
            self.adjustScroll();
        }
    }

    pub fn clear(self: *List) void {
        self.items.clearRetainingCapacity();
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    pub fn getSelectedItem(self: *const List) ?*const ListItem {
        if (self.selected_index < self.items.items.len) {
            return &self.items.items[self.selected_index];
        }
        return null;
    }

    pub fn getSelectedIndex(self: *const List) ?usize {
        if (self.selected_index < self.items.items.len) {
            return self.selected_index;
        }
        return null;
    }

    pub fn setSelectedIndex(self: *List, index: usize) void {
        if (index < self.items.items.len) {
            self.selected_index = index;
            self.adjustScroll();
        }
    }

    pub fn moveUp(self: *List) void {
        if (self.items.items.len == 0) return;

        if (self.selected_index > 0) {
            self.selected_index -= 1;
        } else {
            // Wrap to bottom
            self.selected_index = self.items.items.len - 1;
        }
        self.adjustScroll();
    }

    pub fn moveDown(self: *List) void {
        if (self.items.items.len == 0) return;

        if (self.selected_index < self.items.items.len - 1) {
            self.selected_index += 1;
        } else {
            // Wrap to top
            self.selected_index = 0;
        }
        self.adjustScroll();
    }

    pub fn pageUp(self: *List) void {
        if (self.items.items.len == 0) return;

        const page_size = self.height;
        if (self.selected_index >= page_size) {
            self.selected_index -= page_size;
        } else {
            self.selected_index = 0;
        }
        self.adjustScroll();
    }

    pub fn pageDown(self: *List) void {
        if (self.items.items.len == 0) return;

        const page_size = self.height;
        if (self.selected_index + page_size < self.items.items.len) {
            self.selected_index += page_size;
        } else {
            self.selected_index = self.items.items.len - 1;
        }
        self.adjustScroll();
    }

    fn adjustScroll(self: *List) void {
        if (self.items.items.len == 0) return;

        // Ensure selected item is visible
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + self.height) {
            self.scroll_offset = self.selected_index - self.height + 1;
        }
    }

    pub fn handleEvent(self: *List, event: events.Event) !bool {
        if (!self.focused or !self.visible) return false;

        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .up => {
                        self.moveUp();
                        return true;
                    },
                    .down => {
                        self.moveDown();
                        return true;
                    },
                    .char => {
                        if (key_event.char) |c| {
                            switch (c) {
                                'k', 'K' => {
                                    self.moveUp();
                                    return true;
                                },
                                'j', 'J' => {
                                    self.moveDown();
                                    return true;
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            },
        }
        return false;
    }

    pub fn render(self: *const List, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        const visible_items = @min(self.height, self.items.items.len);

        // Render items
        for (0..visible_items) |i| {
            const item_index = self.scroll_offset + i;
            if (item_index >= self.items.items.len) break;

            const item = &self.items.items[item_index];
            const is_selected = (item_index == self.selected_index);

            // Determine style
            var style = renderer.TextStyle{};
            if (is_selected and self.focused) {
                style.bg_color = renderer.Color.BLUE;
                style.fg_color = renderer.Color.WHITE;
                style.bold = true;
            } else if (is_selected) {
                style.bg_color = renderer.Color{ .r = 64, .g = 64, .b = 64 };
                style.fg_color = renderer.Color.WHITE;
            } else if (!item.enabled) {
                style.fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 };
            }

            // Truncate text if too long
            const max_text_width = if (self.show_scrollbar and self.needsScrollbar())
                self.width - 1
            else
                self.width;

            var display_text = item.text;
            if (item.text.len > max_text_width) {
                display_text = item.text[0..max_text_width];
            }

            // Clear the line first if selected (for full-width highlighting)
            if (is_selected) {
                try r.moveCursor(self.x, self.y + @as(u16, @intCast(i)));
                try r.setTextStyle(style);

                // Fill the entire width with background color
                var j: u16 = 0;
                while (j < max_text_width) : (j += 1) {
                    try r.stdout_file.writeAll(" ");
                }

                // Now draw the text
                try r.moveCursor(self.x, self.y + @as(u16, @intCast(i)));
                try r.stdout_file.writeAll(display_text);
                try r.resetStyle();
            } else {
                try r.drawText(self.x, self.y + @as(u16, @intCast(i)), display_text, style);
            }
        }

        // Draw scrollbar if needed
        if (self.show_scrollbar and self.needsScrollbar()) {
            try self.drawScrollbar(r);
        }
    }

    fn needsScrollbar(self: *const List) bool {
        return self.items.items.len > self.height;
    }

    fn drawScrollbar(self: *const List, r: *renderer.Renderer) !void {
        if (self.items.items.len == 0) return;

        const scrollbar_x = self.x + self.width - 1;
        const scrollbar_height = self.height;

        // Calculate scrollbar thumb position and size
        const total_items = self.items.items.len;
        const visible_ratio = @as(f32, @floatFromInt(self.height)) / @as(f32, @floatFromInt(total_items));
        const thumb_size = @max(1, @as(u16, @intFromFloat(@as(f32, @floatFromInt(scrollbar_height)) * visible_ratio)));

        const scroll_ratio = @as(f32, @floatFromInt(self.scroll_offset)) / @as(f32, @floatFromInt(total_items - self.height));
        const thumb_pos = @as(u16, @intFromFloat(@as(f32, @floatFromInt(scrollbar_height - thumb_size)) * scroll_ratio));

        // Draw scrollbar track and thumb
        for (0..scrollbar_height) |i| {
            const y = self.y + @as(u16, @intCast(i));
            const is_thumb = (i >= thumb_pos and i < thumb_pos + thumb_size);

            const char = if (is_thumb) "#" else ".";
            const style = renderer.TextStyle{
                .fg_color = if (is_thumb) renderer.Color.WHITE else renderer.Color{ .r = 64, .g = 64, .b = 64 },
            };

            try r.drawText(scrollbar_x, y, char, style);
        }
    }

    pub fn setFocus(self: *List, focused: bool) void {
        self.focused = focused;
    }

    pub fn setVisible(self: *List, visible: bool) void {
        self.visible = visible;
    }

    pub fn setPosition(self: *List, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
    }

    pub fn setSize(self: *List, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
        self.adjustScroll();
    }

    pub fn getItemCount(self: *const List) usize {
        return self.items.items.len;
    }
};
