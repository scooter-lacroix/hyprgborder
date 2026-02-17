//! Dropdown/Select component - selection from a list of options
//! Provides a dropdown menu for selecting from predefined options

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");

pub const DropdownOption = struct {
    text: []const u8,
    value: []const u8,
    enabled: bool = true,
};

pub const Dropdown = struct {
    allocator: std.mem.Allocator,
    options: std.ArrayList(DropdownOption),
    x: u16,
    y: u16,
    width: u16,
    selected_index: usize = 0,
    is_open: bool = false,
    focused: bool = false,
    visible: bool = true,
    max_visible_options: usize = 5,
    scroll_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16) Dropdown {
        return Dropdown{
            .allocator = allocator,
            .options = .{},
            .x = x,
            .y = y,
            .width = width,
        };
    }

    pub fn deinit(self: *Dropdown) void {
        self.options.deinit(self.allocator);
    }

    pub fn addOption(self: *Dropdown, text: []const u8, value: []const u8) !void {
        try self.options.append(self.allocator, DropdownOption{
            .text = text,
            .value = value,
        });
    }

    pub fn addOptionWithEnabled(self: *Dropdown, text: []const u8, value: []const u8, enabled: bool) !void {
        try self.options.append(self.allocator, DropdownOption{
            .text = text,
            .value = value,
            .enabled = enabled,
        });
    }

    pub fn removeOption(self: *Dropdown, index: usize) void {
        if (index < self.options.items.len) {
            _ = self.options.orderedRemove(index);

            // Adjust selection if needed
            if (self.selected_index >= self.options.items.len and self.options.items.len > 0) {
                self.selected_index = self.options.items.len - 1;
            }
        }
    }

    pub fn clear(self: *Dropdown) void {
        self.options.clearRetainingCapacity();
        self.selected_index = 0;
        self.is_open = false;
        self.scroll_offset = 0;
    }

    pub fn getSelectedOption(self: *const Dropdown) ?*const DropdownOption {
        if (self.selected_index < self.options.items.len) {
            return &self.options.items[self.selected_index];
        }
        return null;
    }

    pub fn getSelectedValue(self: *const Dropdown) ?[]const u8 {
        if (self.getSelectedOption()) |option| {
            return option.value;
        }
        return null;
    }

    pub fn getSelectedText(self: *const Dropdown) ?[]const u8 {
        if (self.getSelectedOption()) |option| {
            return option.text;
        }
        return null;
    }

    pub fn setSelectedIndex(self: *Dropdown, index: usize) void {
        if (index < self.options.items.len) {
            self.selected_index = index;
            self.adjustScroll();
        }
    }

    pub fn setSelectedByValue(self: *Dropdown, value: []const u8) bool {
        for (self.options.items, 0..) |option, i| {
            if (std.mem.eql(u8, option.value, value)) {
                self.selected_index = i;
                self.adjustScroll();
                return true;
            }
        }
        return false;
    }

    pub fn open(self: *Dropdown) void {
        self.is_open = true;
        self.adjustScroll();
    }

    pub fn close(self: *Dropdown) void {
        self.is_open = false;
    }

    pub fn toggle(self: *Dropdown) void {
        self.is_open = !self.is_open;
        if (self.is_open) {
            self.adjustScroll();
        }
    }

    fn adjustScroll(self: *Dropdown) void {
        if (self.options.items.len == 0) return;

        // Ensure selected item is visible when dropdown is open
        if (self.is_open) {
            if (self.selected_index < self.scroll_offset) {
                self.scroll_offset = self.selected_index;
            } else if (self.selected_index >= self.scroll_offset + self.max_visible_options) {
                self.scroll_offset = self.selected_index - self.max_visible_options + 1;
            }
        }
    }

    fn moveUp(self: *Dropdown) void {
        if (self.options.items.len == 0) return;

        if (self.selected_index > 0) {
            self.selected_index -= 1;
        } else {
            // Wrap to bottom
            self.selected_index = self.options.items.len - 1;
        }
        self.adjustScroll();
    }

    fn moveDown(self: *Dropdown) void {
        if (self.options.items.len == 0) return;

        if (self.selected_index < self.options.items.len - 1) {
            self.selected_index += 1;
        } else {
            // Wrap to top
            self.selected_index = 0;
        }
        self.adjustScroll();
    }

    pub fn handleEvent(self: *Dropdown, event: events.Event) !bool {
        if (!self.focused or !self.visible) return false;

        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .enter, .space => {
                        if (self.is_open) {
                            // Select current option and close
                            self.close();
                        } else {
                            // Open dropdown
                            self.open();
                        }
                        return true;
                    },
                    .escape => {
                        if (self.is_open) {
                            self.close();
                            return true;
                        }
                    },
                    .up => {
                        if (self.is_open) {
                            self.moveUp();
                        } else {
                            // Navigate without opening
                            self.moveUp();
                        }
                        return true;
                    },
                    .down => {
                        if (self.is_open) {
                            self.moveDown();
                        } else {
                            // Navigate without opening
                            self.moveDown();
                        }
                        return true;
                    },
                    .char => {
                        if (key_event.char) |c| {
                            // Quick selection by first letter
                            for (self.options.items, 0..) |option, i| {
                                if (option.text.len > 0 and
                                    std.ascii.toLower(option.text[0]) == std.ascii.toLower(c))
                                {
                                    self.selected_index = i;
                                    self.adjustScroll();
                                    return true;
                                }
                            }
                        }
                    },
                    else => {},
                }
            },
        }
        return false;
    }

    pub fn render(self: *const Dropdown, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Render the main dropdown button
        try self.renderButton(r);

        // Render the dropdown list if open
        if (self.is_open) {
            try self.renderDropdownList(r);
        }
    }

    fn renderButton(self: *const Dropdown, r: *renderer.Renderer) !void {
        // Determine button style
        var button_style = renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
        };

        if (self.focused) {
            button_style.bg_color = if (self.is_open)
                renderer.Color{ .r = 0, .g = 64, .b = 128 }
            else
                renderer.Color{ .r = 32, .g = 32, .b = 64 };
        } else {
            button_style.bg_color = renderer.Color{ .r = 16, .g = 16, .b = 16 };
        }

        // Clear button area
        try r.moveCursor(self.x, self.y);
        try r.setTextStyle(button_style);

        var i: u16 = 0;
        while (i < self.width) : (i += 1) {
            try r.stdout_file.writeAll(" ");
        }

        // Draw button text
        try r.moveCursor(self.x, self.y);

        const button_text = if (self.getSelectedText()) |text| text else "Select...";
        const max_text_width = if (self.width > 3) self.width - 3 else 1; // Reserve space for arrow

        const display_text = if (button_text.len > max_text_width)
            button_text[0..max_text_width]
        else
            button_text;

        try r.stdout_file.writeAll(display_text);

        // Draw dropdown arrow
        const arrow_x = self.x + self.width - 2;
        try r.moveCursor(arrow_x, self.y);

        const arrow = if (self.is_open) "^" else "v";
        try r.stdout_file.writeAll(arrow);

        try r.resetStyle();
    }

    fn renderDropdownList(self: *const Dropdown, r: *renderer.Renderer) !void {
        const list_y = self.y + 1;
        const visible_options = @min(self.max_visible_options, self.options.items.len);

        // Draw dropdown background
        for (0..visible_options) |i| {
            const option_index = self.scroll_offset + i;
            if (option_index >= self.options.items.len) break;

            const option = &self.options.items[option_index];
            const is_selected = (option_index == self.selected_index);

            // Determine option style
            var option_style = renderer.TextStyle{};

            if (!option.enabled) {
                option_style.fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 };
                option_style.bg_color = renderer.Color{ .r = 24, .g = 24, .b = 24 };
            } else if (is_selected) {
                option_style.fg_color = renderer.Color.WHITE;
                option_style.bg_color = renderer.Color.BLUE;
                option_style.bold = true;
            } else {
                option_style.fg_color = renderer.Color.WHITE;
                option_style.bg_color = renderer.Color{ .r = 24, .g = 24, .b = 24 };
            }

            // Clear option area
            try r.moveCursor(self.x, list_y + @as(u16, @intCast(i)));
            try r.setTextStyle(option_style);

            var j: u16 = 0;
            while (j < self.width) : (j += 1) {
                try r.stdout_file.writeAll(" ");
            }

            // Draw option text
            try r.moveCursor(self.x, list_y + @as(u16, @intCast(i)));

            const display_text = if (option.text.len > self.width)
                option.text[0..self.width]
            else
                option.text;

            try r.stdout_file.writeAll(display_text);
        }

        // Draw scrollbar if needed
        if (self.options.items.len > self.max_visible_options) {
            try self.drawScrollbar(r, list_y, visible_options);
        }

        try r.resetStyle();
    }

    fn drawScrollbar(self: *const Dropdown, r: *renderer.Renderer, list_y: u16, visible_height: usize) !void {
        const scrollbar_x = self.x + self.width - 1;

        // Calculate scrollbar thumb position and size
        const total_options = self.options.items.len;
        const visible_ratio = @as(f32, @floatFromInt(visible_height)) / @as(f32, @floatFromInt(total_options));
        const thumb_size = @max(1, @as(usize, @intFromFloat(@as(f32, @floatFromInt(visible_height)) * visible_ratio)));

        const scroll_ratio = @as(f32, @floatFromInt(self.scroll_offset)) / @as(f32, @floatFromInt(total_options - visible_height));
        const thumb_pos = @as(usize, @intFromFloat(@as(f32, @floatFromInt(visible_height - thumb_size)) * scroll_ratio));

        // Draw scrollbar track and thumb
        for (0..visible_height) |i| {
            const y = list_y + @as(u16, @intCast(i));
            const is_thumb = (i >= thumb_pos and i < thumb_pos + thumb_size);

            const char = if (is_thumb) "#" else ".";
            const style = renderer.TextStyle{
                .fg_color = if (is_thumb) renderer.Color.WHITE else renderer.Color{ .r = 64, .g = 64, .b = 64 },
            };

            try r.drawText(scrollbar_x, y, char, style);
        }
    }

    pub fn setFocus(self: *Dropdown, focused: bool) void {
        self.focused = focused;
        if (!focused) {
            self.is_open = false;
        }
    }

    pub fn setVisible(self: *Dropdown, visible: bool) void {
        self.visible = visible;
        if (!visible) {
            self.is_open = false;
        }
    }

    pub fn setPosition(self: *Dropdown, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
    }

    pub fn setWidth(self: *Dropdown, width: u16) void {
        self.width = width;
    }

    pub fn setMaxVisibleOptions(self: *Dropdown, max_visible: usize) void {
        self.max_visible_options = max_visible;
        self.adjustScroll();
    }

    pub fn getOptionCount(self: *const Dropdown) usize {
        return self.options.items.len;
    }

    pub fn isOpen(self: *const Dropdown) bool {
        return self.is_open;
    }

    pub fn renderOverlay(self: *const Dropdown, r: *renderer.Renderer) !void {
        if (!self.visible) return;
        if (self.is_open) {
            try self.renderDropdownList(r);
        }
    }
};
