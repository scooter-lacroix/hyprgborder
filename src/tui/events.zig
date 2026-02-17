//! Simplified event handling for basic keyboard input
//! This version uses raw mode for immediate key responses

const std = @import("std");

pub const Key = enum {
    // Special keys
    escape,
    enter,
    tab,
    backspace,
    space,

    // Arrow keys (will be detected as escape sequences)
    up,
    down,
    left,
    right,

    // Function keys
    f1,
    f2,
    f3,
    f4,

    // Alphanumeric
    char,

    // Unknown/unsupported
    unknown,
};

pub const KeyEvent = struct {
    key: Key,
    char: ?u8 = null, // For Key.char events
};

pub const Event = union(enum) {
    key: KeyEvent,
};

pub const SimpleEventHandler = struct {
    stdin_file: std.fs.File,
    original_termios: ?std.c.termios = null,

    pub fn init() !SimpleEventHandler {
        const stdin_file = std.fs.File{ .handle = 0 }; // stdin file descriptor

        var handler = SimpleEventHandler{
            .stdin_file = stdin_file,
        };

        // Set terminal to raw mode for immediate input
        try handler.enableRawMode();

        return handler;
    }

    pub fn enableRawMode(self: *SimpleEventHandler) !void {
        const c = std.c;

        var termios: c.termios = undefined;
        if (c.tcgetattr(c.STDIN_FILENO, &termios) != 0) {
            return error.TerminalSetupFailed;
        }

        // Save original settings
        self.original_termios = termios;

        // Disable canonical mode and echo using the correct field names
        termios.lflag.ICANON = false;
        termios.lflag.ECHO = false;

        // Set minimum characters to read and timeout
        const VMIN: usize = 6;
        const VTIME: usize = 5;
        termios.cc[VMIN] = 1; // Wait for at least 1 character
        termios.cc[VTIME] = 0; // No timeout

        const linux = std.os.linux;
        _ = linux.tcsetattr(c.STDIN_FILENO, linux.TCSA.NOW, &termios);
    }

    pub fn disableRawMode(self: *SimpleEventHandler) !void {
        if (self.original_termios) |termios| {
            const c = std.c;
            const linux = std.os.linux;
            _ = linux.tcsetattr(c.STDIN_FILENO, linux.TCSA.NOW, &termios);
        }
    }

    pub fn waitForKeypress(self: *SimpleEventHandler) !Event {
        var buffer: [8]u8 = undefined;
        const bytes_read = try self.stdin_file.read(buffer[0..]);

        if (bytes_read == 0) return Event{ .key = KeyEvent{ .key = Key.unknown } };

        return try parseSimpleInput(buffer[0..bytes_read]);
    }

    pub fn deinit(self: *SimpleEventHandler) void {
        self.disableRawMode() catch {};
    }
};

pub fn parseSimpleInput(input: []const u8) !Event {
    if (input.len == 0) return error.EmptyInput;

    // In raw mode, we get cleaner input
    const first_char = input[0];

    // Handle escape sequences first
    if (first_char == 27) { // ESC
        if (input.len >= 3 and input[1] == '[') {
            // Arrow key escape sequence
            return Event{ .key = switch (input[2]) {
                'A' => KeyEvent{ .key = Key.up },
                'B' => KeyEvent{ .key = Key.down },
                'C' => KeyEvent{ .key = Key.right },
                'D' => KeyEvent{ .key = Key.left },
                else => KeyEvent{ .key = Key.unknown },
            } };
        } else if (input.len >= 3 and input[1] == 'O') {
            // Function key escape sequence (F1-F4)
            return Event{ .key = switch (input[2]) {
                'P' => KeyEvent{ .key = Key.f1 },
                'Q' => KeyEvent{ .key = Key.f2 },
                'R' => KeyEvent{ .key = Key.f3 },
                'S' => KeyEvent{ .key = Key.f4 },
                else => KeyEvent{ .key = Key.unknown },
            } };
        } else if (input.len >= 4 and input[1] == '[' and input[3] == '~') {
            // Alternative function key format [1~, [2~, etc.
            return Event{ .key = switch (input[2]) {
                '1' => KeyEvent{ .key = Key.f1 },
                '2' => KeyEvent{ .key = Key.f2 },
                '3' => KeyEvent{ .key = Key.f3 },
                '4' => KeyEvent{ .key = Key.f4 },
                else => KeyEvent{ .key = Key.unknown },
            } };
        } else if (input.len == 1) {
            // Plain ESC key (only if it's a single character)
            return Event{ .key = KeyEvent{ .key = Key.escape } };
        } else {
            // Unknown escape sequence
            return Event{ .key = KeyEvent{ .key = Key.unknown } };
        }
    }

    // Handle regular characters
    return Event{
        .key = switch (first_char) {
            13, 10 => KeyEvent{ .key = Key.enter }, // CR or LF
            9 => KeyEvent{ .key = Key.tab }, // TAB
            127, 8 => KeyEvent{ .key = Key.backspace }, // DEL or BS
            32 => KeyEvent{ .key = Key.space }, // SPACE
            'a'...'z', 'A'...'Z', '0'...'9' => KeyEvent{
                .key = Key.char,
                .char = first_char,
            },
            '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '-', '_', '=', '+', '[', ']', '{', '}', '\\', '|', ';', ':', '\'', '"', ',', '.', '<', '>', '/', '?', '`', '~' => KeyEvent{
                .key = Key.char,
                .char = first_char,
            },
            else => KeyEvent{ .key = Key.unknown },
        },
    };
}

// Test function
pub fn testSimpleEvents() !void {
    std.debug.print("Simple event test - press keys (ESC to exit):\n", .{});

    var handler = try SimpleEventHandler.init();
    defer handler.deinit();

    while (true) {
        const event = try handler.waitForKeypress();

        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .escape => {
                        std.debug.print("ESC pressed - exiting\n", .{});
                        break;
                    },
                    .enter => std.debug.print("ENTER\n", .{}),
                    .tab => std.debug.print("TAB\n", .{}),
                    .backspace => std.debug.print("BACKSPACE\n", .{}),
                    .space => std.debug.print("SPACE\n", .{}),
                    .up => std.debug.print("UP arrow\n", .{}),
                    .down => std.debug.print("DOWN arrow\n", .{}),
                    .left => std.debug.print("LEFT arrow\n", .{}),
                    .right => std.debug.print("RIGHT arrow\n", .{}),
                    .f1 => std.debug.print("F1\n", .{}),
                    .f2 => std.debug.print("F2\n", .{}),
                    .f3 => std.debug.print("F3\n", .{}),
                    .f4 => std.debug.print("F4\n", .{}),
                    .char => {
                        if (key_event.char) |c| {
                            std.debug.print("'{c}'\n", .{c});
                        }
                    },
                    .unknown => std.debug.print("Unknown key\n", .{}),
                }
            },
        }
    }
}
