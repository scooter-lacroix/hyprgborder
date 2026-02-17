//! Color picker component - RGB/HSV color selection with visual preview
//! Provides interactive color selection with multiple input modes

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");
const InputField = @import("input_field.zig").InputField;
const validateHexColor = @import("input_field.zig").validateHexColor;

pub const ColorMode = enum {
    rgb,
    hsv,
    hex,
};

pub const HSV = struct {
    h: f32, // 0-360
    s: f32, // 0-1
    v: f32, // 0-1
};

pub const ColorPicker = struct {
    allocator: std.mem.Allocator,
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    // Current color
    color: renderer.Color = renderer.Color.WHITE,

    // Input mode
    mode: ColorMode = ColorMode.hex,
    focused_input: usize = 0, // Which input field is focused

    // Input fields
    hex_input: InputField,
    r_input: InputField,
    g_input: InputField,
    b_input: InputField,
    h_input: InputField,
    s_input: InputField,
    v_input: InputField,

    // State
    focused: bool = false,
    visible: bool = true,

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16, height: u16) ColorPicker {
        var picker = ColorPicker{
            .allocator = allocator,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .hex_input = InputField.init(allocator, x, y + 1, 8),
            .r_input = InputField.init(allocator, x, y + 3, 4),
            .g_input = InputField.init(allocator, x + 5, y + 3, 4),
            .b_input = InputField.init(allocator, x + 10, y + 3, 4),
            .h_input = InputField.init(allocator, x, y + 5, 4),
            .s_input = InputField.init(allocator, x + 5, y + 5, 4),
            .v_input = InputField.init(allocator, x + 10, y + 5, 4),
        };

        // Set up input field properties
        picker.hex_input.setValidator(validateHexColor);
        picker.hex_input.setPlaceholder("#FFFFFF");
        picker.hex_input.setMaxLength(7);

        picker.r_input.setValidator(validateRgbComponent);
        picker.r_input.setPlaceholder("255");
        picker.r_input.setMaxLength(3);

        picker.g_input.setValidator(validateRgbComponent);
        picker.g_input.setPlaceholder("255");
        picker.g_input.setMaxLength(3);

        picker.b_input.setValidator(validateRgbComponent);
        picker.b_input.setPlaceholder("255");
        picker.b_input.setMaxLength(3);

        picker.h_input.setValidator(validateHueComponent);
        picker.h_input.setPlaceholder("360");
        picker.h_input.setMaxLength(3);

        picker.s_input.setValidator(validateSaturationComponent);
        picker.s_input.setPlaceholder("100");
        picker.s_input.setMaxLength(3);

        picker.v_input.setValidator(validateValueComponent);
        picker.v_input.setPlaceholder("100");
        picker.v_input.setMaxLength(3);

        picker.updateInputsFromColor();

        return picker;
    }

    pub fn deinit(self: *ColorPicker) void {
        self.hex_input.deinit();
        self.r_input.deinit();
        self.g_input.deinit();
        self.b_input.deinit();
        self.h_input.deinit();
        self.s_input.deinit();
        self.v_input.deinit();
    }

    pub fn setColor(self: *ColorPicker, color: renderer.Color) void {
        self.color = color;
        self.updateInputsFromColor();
    }

    pub fn getColor(self: *const ColorPicker) renderer.Color {
        return self.color;
    }

    pub fn setMode(self: *ColorPicker, mode: ColorMode) void {
        self.mode = mode;
        self.focused_input = 0;
        self.updateFocus();
    }

    fn updateInputsFromColor(self: *ColorPicker) void {
        // Update hex input
        var hex_buffer: [8]u8 = undefined;
        const hex_text = std.fmt.bufPrint(hex_buffer[0..], "#{X:0>2}{X:0>2}{X:0>2}", .{ self.color.r, self.color.g, self.color.b }) catch "#FFFFFF";
        self.hex_input.setText(hex_text) catch {};

        // Update RGB inputs
        var r_buffer: [4]u8 = undefined;
        var g_buffer: [4]u8 = undefined;
        var b_buffer: [4]u8 = undefined;

        const r_text = std.fmt.bufPrint(r_buffer[0..], "{d}", .{self.color.r}) catch "0";
        const g_text = std.fmt.bufPrint(g_buffer[0..], "{d}", .{self.color.g}) catch "0";
        const b_text = std.fmt.bufPrint(b_buffer[0..], "{d}", .{self.color.b}) catch "0";

        self.r_input.setText(r_text) catch {};
        self.g_input.setText(g_text) catch {};
        self.b_input.setText(b_text) catch {};

        // Update HSV inputs
        const hsv = rgbToHsv(self.color);

        var h_buffer: [4]u8 = undefined;
        var s_buffer: [4]u8 = undefined;
        var v_buffer: [4]u8 = undefined;

        const h_text = std.fmt.bufPrint(h_buffer[0..], "{d}", .{@as(u32, @intFromFloat(hsv.h))}) catch "0";
        const s_text = std.fmt.bufPrint(s_buffer[0..], "{d}", .{@as(u32, @intFromFloat(hsv.s * 100))}) catch "0";
        const v_text = std.fmt.bufPrint(v_buffer[0..], "{d}", .{@as(u32, @intFromFloat(hsv.v * 100))}) catch "0";

        self.h_input.setText(h_text) catch {};
        self.s_input.setText(s_text) catch {};
        self.v_input.setText(v_text) catch {};
    }

    fn updateColorFromInputs(self: *ColorPicker) void {
        switch (self.mode) {
            .hex => {
                const hex_text = self.hex_input.getText();
                if (hex_text.len == 7 and hex_text[0] == '#') {
                    const r = std.fmt.parseInt(u8, hex_text[1..3], 16) catch return;
                    const g = std.fmt.parseInt(u8, hex_text[3..5], 16) catch return;
                    const b = std.fmt.parseInt(u8, hex_text[5..7], 16) catch return;
                    self.color = renderer.Color{ .r = r, .g = g, .b = b };
                }
            },
            .rgb => {
                const r = std.fmt.parseInt(u8, self.r_input.getText(), 10) catch return;
                const g = std.fmt.parseInt(u8, self.g_input.getText(), 10) catch return;
                const b = std.fmt.parseInt(u8, self.b_input.getText(), 10) catch return;
                self.color = renderer.Color{ .r = r, .g = g, .b = b };
            },
            .hsv => {
                const h = std.fmt.parseFloat(f32, self.h_input.getText()) catch return;
                const s = (std.fmt.parseFloat(f32, self.s_input.getText()) catch return) / 100.0;
                const v = (std.fmt.parseFloat(f32, self.v_input.getText()) catch return) / 100.0;

                const hsv = HSV{ .h = h, .s = s, .v = v };
                self.color = hsvToRgb(hsv);
            },
        }
    }

    fn updateFocus(self: *ColorPicker) void {
        // Clear all focus
        self.hex_input.setFocus(false);
        self.r_input.setFocus(false);
        self.g_input.setFocus(false);
        self.b_input.setFocus(false);
        self.h_input.setFocus(false);
        self.s_input.setFocus(false);
        self.v_input.setFocus(false);

        if (!self.focused) return;

        // Set focus based on mode and focused_input
        switch (self.mode) {
            .hex => {
                self.hex_input.setFocus(true);
            },
            .rgb => {
                switch (self.focused_input) {
                    0 => self.r_input.setFocus(true),
                    1 => self.g_input.setFocus(true),
                    2 => self.b_input.setFocus(true),
                    else => self.r_input.setFocus(true),
                }
            },
            .hsv => {
                switch (self.focused_input) {
                    0 => self.h_input.setFocus(true),
                    1 => self.s_input.setFocus(true),
                    2 => self.v_input.setFocus(true),
                    else => self.h_input.setFocus(true),
                }
            },
        }
    }

    pub fn handleEvent(self: *ColorPicker, event: events.Event) !bool {
        if (!self.focused or !self.visible) return false;

        // Handle mode switching
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .tab => {
                        // If we're at the very last internal input (hsv mode, last field),
                        // allow the Tab to bubble up so the panel can move focus to the
                        // next component instead of wrapping inside the color picker.
                        if (self.mode == ColorMode.hsv and self.focused_input == 2) {
                            // Do not consume the Tab; let parent handle focus movement
                            return false;
                        }

                        switch (self.mode) {
                            .hex => {
                                self.mode = ColorMode.rgb;
                                self.focused_input = 0;
                            },
                            .rgb => {
                                if (self.focused_input < 2) {
                                    self.focused_input += 1;
                                } else {
                                    self.mode = ColorMode.hsv;
                                    self.focused_input = 0;
                                }
                            },
                            .hsv => {
                                if (self.focused_input < 2) {
                                    self.focused_input += 1;
                                } else {
                                    // Reached end of hsv inputs - cycle back to hex
                                    self.mode = ColorMode.hex;
                                    self.focused_input = 0;
                                }
                            },
                        }
                        self.updateFocus();
                        return true;
                    },
                    else => {},
                }
            },
        }

        // Handle input field events
        var handled = false;
        switch (self.mode) {
            .hex => {
                handled = try self.hex_input.handleEvent(event);
                if (handled) {
                    self.updateColorFromInputs();
                }
            },
            .rgb => {
                switch (self.focused_input) {
                    0 => {
                        handled = try self.r_input.handleEvent(event);
                        if (handled) {
                            self.updateColorFromInputs();
                        }
                    },
                    1 => {
                        handled = try self.g_input.handleEvent(event);
                        if (handled) {
                            self.updateColorFromInputs();
                        }
                    },
                    2 => {
                        handled = try self.b_input.handleEvent(event);
                        if (handled) {
                            self.updateColorFromInputs();
                        }
                    },
                    else => {},
                }
            },
            .hsv => {
                switch (self.focused_input) {
                    0 => {
                        handled = try self.h_input.handleEvent(event);
                        if (handled) {
                            self.updateColorFromInputs();
                        }
                    },
                    1 => {
                        handled = try self.s_input.handleEvent(event);
                        if (handled) {
                            self.updateColorFromInputs();
                        }
                    },
                    2 => {
                        handled = try self.v_input.handleEvent(event);
                        if (handled) {
                            self.updateColorFromInputs();
                        }
                    },
                    else => {},
                }
            },
        }

        return handled;
    }

    pub fn render(self: *const ColorPicker, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Draw color preview using renderer helper
        // Draw a block 3 rows high by 6 columns wide aligned to the right of the picker
        try r.drawColorPreview(self.x + self.width - 6, self.y + 0, self.color);
        try r.drawColorPreview(self.x + self.width - 6, self.y + 1, self.color);
        try r.drawColorPreview(self.x + self.width - 6, self.y + 2, self.color);

        // Draw mode labels and inputs
        const label_style = renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
            .bold = true,
        };

        // Hex mode
        try r.drawText(self.x, self.y, "Hex:", label_style);
        try self.hex_input.render(r);

        // RGB mode
        try r.drawText(self.x, self.y + 2, "RGB:", label_style);
        try r.drawText(self.x, self.y + 3, "R:", renderer.TextStyle{ .fg_color = renderer.Color.RED });
        try self.r_input.render(r);

        try r.drawText(self.x + 5, self.y + 3, "G:", renderer.TextStyle{ .fg_color = renderer.Color.GREEN });
        try self.g_input.render(r);

        try r.drawText(self.x + 10, self.y + 3, "B:", renderer.TextStyle{ .fg_color = renderer.Color.BLUE });
        try self.b_input.render(r);

        // HSV mode
        try r.drawText(self.x, self.y + 4, "HSV:", label_style);
        try r.drawText(self.x, self.y + 5, "H:", renderer.TextStyle{ .fg_color = renderer.Color.YELLOW });
        try self.h_input.render(r);

        try r.drawText(self.x + 5, self.y + 5, "S:", renderer.TextStyle{ .fg_color = renderer.Color.CYAN });
        try self.s_input.render(r);

        try r.drawText(self.x + 10, self.y + 5, "V:", renderer.TextStyle{ .fg_color = renderer.Color.MAGENTA });
        try self.v_input.render(r);

        // Draw mode indicator
        const mode_text = switch (self.mode) {
            .hex => "[HEX]",
            .rgb => "[RGB]",
            .hsv => "[HSV]",
        };

        const mode_style = renderer.TextStyle{
            .fg_color = renderer.Color.YELLOW,
            .bold = true,
        };

        try r.drawText(self.x, self.y + 7, mode_text, mode_style);
    }

    pub fn setFocus(self: *ColorPicker, focused: bool) void {
        self.focused = focused;
        self.updateFocus();
    }

    pub fn setVisible(self: *ColorPicker, visible: bool) void {
        self.visible = visible;
    }

    pub fn setPosition(self: *ColorPicker, x: u16, y: u16) void {
        self.x = x;
        self.y = y;

        // Update input field positions
        // Positions mirror those used in init()
        self.hex_input.setPosition(x, y + 1);
        self.r_input.setPosition(x, y + 3);
        self.g_input.setPosition(x + 5, y + 3);
        self.b_input.setPosition(x + 10, y + 3);
        self.h_input.setPosition(x, y + 5);
        self.s_input.setPosition(x + 5, y + 5);
        self.v_input.setPosition(x + 10, y + 5);
    }
};

// Validation functions
fn validateRgbComponent(text: []const u8) @import("input_field.zig").ValidationResult {
    if (text.len == 0) {
        return @import("input_field.zig").ValidationResult{ .invalid = "0-255" };
    }

    const value = std.fmt.parseInt(u32, text, 10) catch {
        return @import("input_field.zig").ValidationResult{ .invalid = "Invalid number" };
    };

    if (value > 255) {
        return @import("input_field.zig").ValidationResult{ .invalid = "Max 255" };
    }

    return @import("input_field.zig").ValidationResult.valid;
}

fn validateHueComponent(text: []const u8) @import("input_field.zig").ValidationResult {
    if (text.len == 0) {
        return @import("input_field.zig").ValidationResult{ .invalid = "0-360" };
    }

    const value = std.fmt.parseInt(u32, text, 10) catch {
        return @import("input_field.zig").ValidationResult{ .invalid = "Invalid number" };
    };

    if (value > 360) {
        return @import("input_field.zig").ValidationResult{ .invalid = "Max 360" };
    }

    return @import("input_field.zig").ValidationResult.valid;
}

fn validateSaturationComponent(text: []const u8) @import("input_field.zig").ValidationResult {
    if (text.len == 0) {
        return @import("input_field.zig").ValidationResult{ .invalid = "0-100" };
    }

    const value = std.fmt.parseInt(u32, text, 10) catch {
        return @import("input_field.zig").ValidationResult{ .invalid = "Invalid number" };
    };

    if (value > 100) {
        return @import("input_field.zig").ValidationResult{ .invalid = "Max 100" };
    }

    return @import("input_field.zig").ValidationResult.valid;
}

fn validateValueComponent(text: []const u8) @import("input_field.zig").ValidationResult {
    return validateSaturationComponent(text); // Same validation as saturation
}

// Color conversion utilities
fn rgbToHsv(color: renderer.Color) HSV {
    const r = @as(f32, @floatFromInt(color.r)) / 255.0;
    const g = @as(f32, @floatFromInt(color.g)) / 255.0;
    const b = @as(f32, @floatFromInt(color.b)) / 255.0;

    const max_val = @max(@max(r, g), b);
    const min_val = @min(@min(r, g), b);
    const delta = max_val - min_val;

    var h: f32 = 0;
    var s: f32 = 0;
    const v: f32 = max_val;

    if (delta != 0) {
        s = delta / max_val;

        if (max_val == r) {
            h = 60 * (((g - b) / delta) + if (g < b) @as(f32, 6) else @as(f32, 0));
        } else if (max_val == g) {
            h = 60 * (((b - r) / delta) + 2);
        } else {
            h = 60 * (((r - g) / delta) + 4);
        }
    }

    return HSV{ .h = h, .s = s, .v = v };
}

fn hsvToRgb(hsv: HSV) renderer.Color {
    const c = hsv.v * hsv.s;
    const x = c * (1 - @abs(@mod(hsv.h / 60.0, 2) - 1));
    const m = hsv.v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (hsv.h >= 0 and hsv.h < 60) {
        r = c;
        g = x;
        b = 0;
    } else if (hsv.h >= 60 and hsv.h < 120) {
        r = x;
        g = c;
        b = 0;
    } else if (hsv.h >= 120 and hsv.h < 180) {
        r = 0;
        g = c;
        b = x;
    } else if (hsv.h >= 180 and hsv.h < 240) {
        r = 0;
        g = x;
        b = c;
    } else if (hsv.h >= 240 and hsv.h < 300) {
        r = x;
        g = 0;
        b = c;
    } else if (hsv.h >= 300 and hsv.h < 360) {
        r = c;
        g = 0;
        b = x;
    }

    return renderer.Color{
        .r = @as(u8, @intFromFloat((r + m) * 255)),
        .g = @as(u8, @intFromFloat((g + m) * 255)),
        .b = @as(u8, @intFromFloat((b + m) * 255)),
    };
}
