//! Input field component - text input with validation and visual feedback
//! Provides a text input field with cursor, validation, and visual styling

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");

pub const ValidationResult = union(enum) {
    valid,
    invalid: []const u8, // Error message
};

pub const ValidatorFn = *const fn (text: []const u8) ValidationResult;

pub const InputField = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    x: u16,
    y: u16,
    width: u16,
    cursor_pos: usize = 0,
    scroll_offset: usize = 0,
    focused: bool = false,
    visible: bool = true,
    placeholder: []const u8 = "",
    validator: ?ValidatorFn = null,
    validation_result: ValidationResult = ValidationResult.valid,
    password_mode: bool = false,
    max_length: ?usize = null,

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16) InputField {
        return InputField{
            .allocator = allocator,
            .buffer = .{},
            .x = x,
            .y = y,
            .width = width,
        };
    }

    pub fn deinit(self: *InputField) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn setText(self: *InputField, text: []const u8) !void {
        self.buffer.clearRetainingCapacity();

        // Respect max_length when setting text
        const text_to_set = if (self.max_length) |max_len|
            if (text.len > max_len) text[0..max_len] else text
        else
            text;

        try self.buffer.appendSlice(self.allocator, text_to_set);
        self.cursor_pos = text_to_set.len;
        self.adjustScroll();
        self.validate();
    }

    pub fn getText(self: *const InputField) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *InputField) void {
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.scroll_offset = 0;
        self.validate();
    }

    pub fn setPlaceholder(self: *InputField, placeholder: []const u8) void {
        self.placeholder = placeholder;
    }

    pub fn setValidator(self: *InputField, validator: ValidatorFn) void {
        self.validator = validator;
        self.validate();
    }

    pub fn setPasswordMode(self: *InputField, password_mode: bool) void {
        self.password_mode = password_mode;
    }

    pub fn setMaxLength(self: *InputField, max_length: ?usize) void {
        self.max_length = max_length;
    }

    fn validate(self: *InputField) void {
        if (self.validator) |validator| {
            self.validation_result = validator(self.buffer.items);
        } else {
            self.validation_result = ValidationResult.valid;
        }
    }

    fn adjustScroll(self: *InputField) void {
        const display_width = self.width;

        // Ensure cursor is visible
        if (self.cursor_pos < self.scroll_offset) {
            self.scroll_offset = self.cursor_pos;
        } else if (self.cursor_pos >= self.scroll_offset + display_width) {
            self.scroll_offset = self.cursor_pos - display_width + 1;
        }
    }

    pub fn handleEvent(self: *InputField, event: events.Event) !bool {
        if (!self.focused or !self.visible) return false;

        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .left => {
                        if (self.cursor_pos > 0) {
                            self.cursor_pos -= 1;
                            self.adjustScroll();
                        }
                        return true;
                    },
                    .right => {
                        if (self.cursor_pos < self.buffer.items.len) {
                            self.cursor_pos += 1;
                            self.adjustScroll();
                        }
                        return true;
                    },
                    .backspace => {
                        if (self.cursor_pos > 0) {
                            _ = self.buffer.orderedRemove(self.cursor_pos - 1);
                            self.cursor_pos -= 1;
                            self.adjustScroll();
                            self.validate();
                        }
                        return true;
                    },
                    .char => {
                        if (key_event.char) |c| {
                            // Check max length
                            if (self.max_length) |max_len| {
                                if (self.buffer.items.len >= max_len) {
                                    return true; // Consume event but don't add character
                                }
                            }

                            // Insert character at cursor position
                            try self.buffer.insert(self.allocator, self.cursor_pos, c);
                            self.cursor_pos += 1;
                            self.adjustScroll();
                            self.validate();
                        }
                        return true;
                    },
                    else => {},
                }
            },
        }
        return false;
    }

    pub fn render(self: *const InputField, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Determine base style
        var base_style = renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
        };

        if (self.focused) {
            base_style.bg_color = renderer.Color{ .r = 32, .g = 32, .b = 64 };
        } else {
            base_style.bg_color = renderer.Color{ .r = 16, .g = 16, .b = 16 };
        }

        // Adjust style based on validation
        switch (self.validation_result) {
            .valid => {},
            .invalid => {
                base_style.fg_color = renderer.Color.RED;
            },
        }

        // Clear the input area
        try r.moveCursor(self.x, self.y);
        try r.setTextStyle(base_style);

        var i: u16 = 0;
        while (i < self.width) : (i += 1) {
            try r.stdout_file.writeAll(" ");
        }

        // Determine what to display
        const display_text = if (self.buffer.items.len == 0 and !self.focused)
            self.placeholder
        else if (self.password_mode) blk: {
            // Create password mask
            const mask_len = @min(self.buffer.items.len, self.width);
            var mask_buf: [256]u8 = undefined; // Static buffer for password mask
            for (0..mask_len) |j| {
                mask_buf[j] = '*';
            }
            break :blk mask_buf[0..mask_len];
        } else self.buffer.items[self.scroll_offset..@min(self.buffer.items.len, self.scroll_offset + self.width)];

        // Draw the text
        try r.moveCursor(self.x, self.y);

        if (self.buffer.items.len == 0 and !self.focused and self.placeholder.len > 0) {
            // Show placeholder
            var placeholder_style = base_style;
            placeholder_style.fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 };
            try r.setTextStyle(placeholder_style);

            const placeholder_text = if (self.placeholder.len > self.width)
                self.placeholder[0..self.width]
            else
                self.placeholder;

            try r.stdout_file.writeAll(placeholder_text);
        } else {
            // Show actual content
            try r.setTextStyle(base_style);
            try r.stdout_file.writeAll(display_text);
        }

        // Draw cursor if focused
        if (self.focused) {
            const cursor_x = self.x + @as(u16, @intCast(self.cursor_pos - self.scroll_offset));
            if (cursor_x < self.x + self.width) {
                try r.moveCursor(cursor_x, self.y);

                var cursor_style = base_style;
                cursor_style.bg_color = renderer.Color.WHITE;
                cursor_style.fg_color = renderer.Color.BLACK;

                try r.setTextStyle(cursor_style);

                // Show character under cursor or space
                const cursor_char = if (self.cursor_pos < self.buffer.items.len)
                    if (self.password_mode) "*" else self.buffer.items[self.cursor_pos .. self.cursor_pos + 1]
                else
                    " ";

                try r.stdout_file.writeAll(cursor_char);
            }
        }

        try r.resetStyle();
    }

    pub fn renderValidationMessage(self: *const InputField, r: *renderer.Renderer, msg_y: u16) !void {
        switch (self.validation_result) {
            .valid => {},
            .invalid => |msg| {
                const style = renderer.TextStyle{
                    .fg_color = renderer.Color.RED,
                };

                const display_msg = if (msg.len > self.width)
                    msg[0..self.width]
                else
                    msg;

                try r.drawText(self.x, msg_y, display_msg, style);
            },
        }
    }

    pub fn isValid(self: *const InputField) bool {
        return switch (self.validation_result) {
            .valid => true,
            .invalid => false,
        };
    }

    pub fn setFocus(self: *InputField, focused: bool) void {
        self.focused = focused;
    }

    pub fn setVisible(self: *InputField, visible: bool) void {
        self.visible = visible;
    }

    pub fn setPosition(self: *InputField, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
    }

    pub fn setWidth(self: *InputField, width: u16) void {
        self.width = width;
        self.adjustScroll();
    }
};

// Common validators
pub fn validateNotEmpty(text: []const u8) ValidationResult {
    if (text.len == 0) {
        return ValidationResult{ .invalid = "Field cannot be empty" };
    }
    return ValidationResult.valid;
}

pub fn validateNumber(text: []const u8) ValidationResult {
    if (text.len == 0) {
        return ValidationResult{ .invalid = "Please enter a number" };
    }

    _ = std.fmt.parseInt(i32, text, 10) catch {
        return ValidationResult{ .invalid = "Invalid number format" };
    };

    return ValidationResult.valid;
}

pub fn validateFloat(text: []const u8) ValidationResult {
    if (text.len == 0) {
        return ValidationResult{ .invalid = "Please enter a number" };
    }

    _ = std.fmt.parseFloat(f64, text) catch {
        return ValidationResult{ .invalid = "Invalid number format" };
    };

    return ValidationResult.valid;
}

pub fn validateFpsInput(text: []const u8) ValidationResult {
    if (text.len == 0) {
        return ValidationResult{ .invalid = "Please enter a number" };
    }

    const value = std.fmt.parseInt(i32, text, 10) catch {
        return ValidationResult{ .invalid = "Invalid number format" };
    };

    if (value < 1 or value > 120) {
        return ValidationResult{ .invalid = "FPS must be 1-120" };
    }

    return ValidationResult.valid;
}

pub fn validateHexColor(text: []const u8) ValidationResult {
    if (text.len == 0) {
        return ValidationResult{ .invalid = "Please enter a color" };
    }

    if (text.len != 7 or text[0] != '#') {
        return ValidationResult{ .invalid = "Format: #RRGGBB" };
    }

    for (text[1..]) |c| {
        if (!std.ascii.isHex(c)) {
            return ValidationResult{ .invalid = "Invalid hex color" };
        }
    }

    return ValidationResult.valid;
}

pub fn createRangeValidator(min: i32, max: i32) ValidatorFn {
    // Note: This is a simplified approach. In a real implementation,
    // you'd want to store the range parameters with the validator.
    // For now, we'll use the existing validators.
    _ = min;
    _ = max;
    return validateNumber;
}
