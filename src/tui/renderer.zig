//! Terminal rendering engine for TUI
//! Provides low-level terminal control, colors, and drawing utilities

const std = @import("std");

pub const Position = struct {
    x: u16,
    y: u16,
};

pub const TerminalSize = struct {
    width: u16,
    height: u16,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const BLACK = Color{ .r = 0, .g = 0, .b = 0 };
    pub const WHITE = Color{ .r = 255, .g = 255, .b = 255 };
    pub const RED = Color{ .r = 255, .g = 0, .b = 0 };
    pub const GREEN = Color{ .r = 0, .g = 255, .b = 0 };
    pub const BLUE = Color{ .r = 0, .g = 0, .b = 255 };
    pub const YELLOW = Color{ .r = 255, .g = 255, .b = 0 };
    pub const CYAN = Color{ .r = 0, .g = 255, .b = 255 };
    pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255 };
};

pub const BorderStyle = enum {
    single,
    double,
    rounded,
    thick,

    pub fn getChars(self: BorderStyle) BorderChars {
        return switch (self) {
            .single => BorderChars{
                .top_left = "┌",
                .top_right = "┐",
                .bottom_left = "└",
                .bottom_right = "┘",
                .horizontal = "─",
                .vertical = "│",
            },
            .double => BorderChars{
                .top_left = "╔",
                .top_right = "╗",
                .bottom_left = "╚",
                .bottom_right = "╝",
                .horizontal = "═",
                .vertical = "║",
            },
            .rounded => BorderChars{
                .top_left = "╭",
                .top_right = "╮",
                .bottom_left = "╰",
                .bottom_right = "╯",
                .horizontal = "─",
                .vertical = "│",
            },
            .thick => BorderChars{
                .top_left = "┏",
                .top_right = "┓",
                .bottom_left = "┗",
                .bottom_right = "┛",
                .horizontal = "━",
                .vertical = "┃",
            },
        };
    }
};

pub const BorderChars = struct {
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

pub const TextStyle = struct {
    fg_color: ?Color = null,
    bg_color: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    stdout_file: std.fs.File,
    terminal_size: TerminalSize,
    cursor_pos: Position,

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        const stdout_file = std.fs.File{ .handle = 1 }; // stdout file descriptor
        const terminal_size = try getTerminalSizeInternal();

        return Renderer{
            .allocator = allocator,
            .stdout_file = stdout_file,
            .terminal_size = terminal_size,
            .cursor_pos = Position{ .x = 0, .y = 0 },
        };
    }

    pub fn clear(self: *Renderer) !void {
        try self.stdout_file.writeAll("\x1b[2J");
        try self.moveCursor(0, 0);
    }

    pub fn moveCursor(self: *Renderer, x: u16, y: u16) !void {
        var buffer: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(buffer[0..], "\x1b[{d};{d}H", .{ y + 1, x + 1 });
        try self.stdout_file.writeAll(text);
        self.cursor_pos = Position{ .x = x, .y = y };
    }

    pub fn hideCursor(self: *Renderer) !void {
        try self.stdout_file.writeAll("\x1b[?25l");
    }

    pub fn showCursor(self: *Renderer) !void {
        try self.stdout_file.writeAll("\x1b[?25h");
    }

    pub fn setTextStyle(self: *Renderer, style: TextStyle) !void {
        var buffer: [128]u8 = undefined;
        var pos: usize = 0;

        // Reset styles first
        const reset = "\x1b[0m";
        @memcpy(buffer[pos .. pos + reset.len], reset);
        pos += reset.len;

        // Apply foreground color
        if (style.fg_color) |fg| {
            const fg_text = try std.fmt.bufPrint(buffer[pos..], "\x1b[38;2;{d};{d};{d}m", .{ fg.r, fg.g, fg.b });
            pos += fg_text.len;
        }

        // Apply background color
        if (style.bg_color) |bg| {
            const bg_text = try std.fmt.bufPrint(buffer[pos..], "\x1b[48;2;{d};{d};{d}m", .{ bg.r, bg.g, bg.b });
            pos += bg_text.len;
        }

        // Apply text attributes
        if (style.bold) {
            const bold = "\x1b[1m";
            @memcpy(buffer[pos .. pos + bold.len], bold);
            pos += bold.len;
        }
        if (style.italic) {
            const italic = "\x1b[3m";
            @memcpy(buffer[pos .. pos + italic.len], italic);
            pos += italic.len;
        }
        if (style.underline) {
            const underline = "\x1b[4m";
            @memcpy(buffer[pos .. pos + underline.len], underline);
            pos += underline.len;
        }

        try self.stdout_file.writeAll(buffer[0..pos]);
    }

    pub fn resetStyle(self: *Renderer) !void {
        try self.stdout_file.writeAll("\x1b[0m");
    }

    pub fn drawText(self: *Renderer, x: u16, y: u16, text: []const u8, style: TextStyle) !void {
        try self.moveCursor(x, y);
        try self.setTextStyle(style);
        try self.stdout_file.writeAll(text);
        try self.resetStyle();
    }

    pub fn drawBox(self: *Renderer, x: u16, y: u16, width: u16, height: u16, style: BorderStyle) !void {
        if (width < 2 or height < 2) return;

        const chars = style.getChars();

        // Draw top border
        try self.moveCursor(x, y);
        try self.stdout_file.writeAll(chars.top_left);
        var i: u16 = 1;
        while (i < width - 1) : (i += 1) {
            try self.stdout_file.writeAll(chars.horizontal);
        }
        try self.stdout_file.writeAll(chars.top_right);

        // Draw sides
        var row: u16 = 1;
        while (row < height - 1) : (row += 1) {
            try self.moveCursor(x, y + row);
            try self.stdout_file.writeAll(chars.vertical);
            try self.moveCursor(x + width - 1, y + row);
            try self.stdout_file.writeAll(chars.vertical);
        }

        // Draw bottom border
        try self.moveCursor(x, y + height - 1);
        try self.stdout_file.writeAll(chars.bottom_left);
        i = 1;
        while (i < width - 1) : (i += 1) {
            try self.stdout_file.writeAll(chars.horizontal);
        }
        try self.stdout_file.writeAll(chars.bottom_right);
    }

    pub fn drawProgressBar(self: *Renderer, x: u16, y: u16, width: u16, progress: f32) !void {
        if (width == 0) return;

        const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(width)) * std.math.clamp(progress, 0.0, 1.0)));

        try self.moveCursor(x, y);

        // Draw filled portion
        var i: u16 = 0;
        while (i < filled_width) : (i += 1) {
            try self.stdout_file.writeAll("#");
        }

        // Draw empty portion
        while (i < width) : (i += 1) {
            try self.stdout_file.writeAll(".");
        }
    }

    pub fn drawColorPreview(self: *Renderer, x: u16, y: u16, color: Color) !void {
        try self.moveCursor(x, y);
        try self.setTextStyle(TextStyle{ .bg_color = color });
        try self.stdout_file.writeAll("  ");
        try self.resetStyle();
    }

    pub fn flush(self: *Renderer) !void {
        // stdout is typically line-buffered, but we can force a flush
        // In Zig, the writer automatically flushes for most operations
        // This is here for API completeness
        _ = self;
    }

    pub fn getTerminalSize(self: *const Renderer) TerminalSize {
        return self.terminal_size;
    }

    pub fn updateTerminalSize(self: *Renderer) !void {
        self.terminal_size = try getTerminalSizeInternal();
    }

    pub fn deinit(self: *Renderer) void {
        // Reset terminal state
        self.resetStyle() catch {};
        self.showCursor() catch {};
    }
};

fn getTerminalSizeInternal() !TerminalSize {
    // For now, use default terminal size
    // TODO: Implement proper terminal size detection
    return TerminalSize{ .width = 80, .height = 24 };
}

// Test functions
pub fn testTerminalOperations() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();

    // Test basic operations
    try renderer.clear();
    try renderer.hideCursor();

    // Test text rendering
    try renderer.drawText(5, 2, "Hello, Terminal!", TextStyle{ .fg_color = Color.GREEN, .bold = true });

    // Test box drawing
    try renderer.drawBox(10, 5, 20, 8, BorderStyle.single);
    try renderer.drawText(12, 6, "Box Content", TextStyle{});

    // Test progress bar
    try renderer.drawText(5, 15, "Progress:", TextStyle{});
    try renderer.drawProgressBar(15, 15, 20, 0.7);

    // Test color preview
    try renderer.drawText(5, 17, "Color:", TextStyle{});
    try renderer.drawColorPreview(12, 17, Color.RED);

    try renderer.showCursor();
    try renderer.moveCursor(0, 20);
}
