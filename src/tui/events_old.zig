//! Terminal event handling system
//! Provides keyboard input detection and event processing for TUI

const std = @import("std");

pub const Key = enum {
    // Special keys
    escape,
    enter,
    tab,
    backspace,
    delete,
    space,

    // Arrow keys
    up,
    down,
    left,
    right,

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    // Alphanumeric
    char,

    // Unknown/unsupported
    unknown,
};

pub const KeyModifiers = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

pub const KeyEvent = struct {
    key: Key,
    char: ?u8 = null, // For Key.char events
    modifiers: KeyModifiers = KeyModifiers{},
};

pub const MouseButton = enum {
    left,
    right,
    middle,
    wheel_up,
    wheel_down,
};

pub const MouseEvent = struct {
    button: MouseButton,
    x: u16,
    y: u16,
    pressed: bool, // true for press, false for release
};

pub const ResizeEvent = struct {
    width: u16,
    height: u16,
};

pub const Event = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: ResizeEvent,
};

pub const EventHandler = struct {
    stdin_file: std.fs.File,
    original_termios: ?std.c.termios = null,

    pub fn init() !EventHandler {
        const stdin_file = std.fs.File{ .handle = 0 }; // stdin file descriptor

        var handler = EventHandler{
            .stdin_file = stdin_file,
        };

        // Set terminal to raw mode for immediate input
        try handler.enableRawMode();

        return handler;
    }

    pub fn enableRawMode(self: *EventHandler) !void {
        const c = std.c;

        var termios: c.termios = undefined;
        if (c.tcgetattr(c.STDIN_FILENO, &termios) != 0) {
            return error.TerminalSetupFailed;
        }

        // Save original settings
        self.original_termios = termios;

        // Disable canonical mode and echo
        termios.c_lflag &= ~(@as(c_uint, c.ICANON) | @as(c_uint, c.ECHO));

        // Set minimum characters to read and timeout
        termios.c_cc[c.VMIN] = 0; // Non-blocking read
        termios.c_cc[c.VTIME] = 1; // 100ms timeout

        if (c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &termios) != 0) {
            return error.TerminalSetupFailed;
        }
    }

    pub fn disableRawMode(self: *EventHandler) !void {
        if (self.original_termios) |termios| {
            const c = std.c;
            if (c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &termios) != 0) {
                return error.TerminalRestoreFailed;
            }
        }
    }

    pub fn pollEvent(self: *EventHandler) !?Event {
        var buffer: [16]u8 = undefined;

        // Try to read input (non-blocking due to VMIN=0, VTIME=1)
        const bytes_read = self.stdin_file.read(buffer[0..]) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };

        if (bytes_read == 0) return null;

        return try parseInput(buffer[0..bytes_read]);
    }

    pub fn waitForEvent(self: *EventHandler) !Event {
        while (true) {
            if (try self.pollEvent()) |event| {
                return event;
            }
            // Small sleep to prevent busy waiting
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }

    pub fn deinit(self: *EventHandler) void {
        self.disableRawMode() catch {};
    }
};

fn parseInput(input: []const u8) !Event {
    if (input.len == 0) return error.EmptyInput;

    // Single character inputs
    if (input.len == 1) {
        const char = input[0];

        return Event{
            .key = switch (char) {
                27 => KeyEvent{ .key = Key.escape }, // ESC
                13, 10 => KeyEvent{ .key = Key.enter }, // CR or LF
                9 => KeyEvent{ .key = Key.tab }, // TAB
                127, 8 => KeyEvent{ .key = Key.backspace }, // DEL or BS
                32 => KeyEvent{ .key = Key.space }, // SPACE
                1...26 => blk: {
                    // Ctrl+A through Ctrl+Z
                    const ctrl_char = char + 'a' - 1;
                    break :blk KeyEvent{
                        .key = Key.char,
                        .char = ctrl_char,
                        .modifiers = KeyModifiers{ .ctrl = true },
                    };
                },
                'a'...'z', 'A'...'Z', '0'...'9' => KeyEvent{
                    .key = Key.char,
                    .char = char,
                },
                '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '-', '_', '=', '+', '[', ']', '{', '}', '\\', '|', ';', ':', '\'', '"', ',', '.', '<', '>', '/', '?', '`', '~' => KeyEvent{
                    .key = Key.char,
                    .char = char,
                },
                else => KeyEvent{ .key = Key.unknown },
            },
        };
    }

    // Escape sequences
    if (input.len >= 2 and input[0] == 27) {
        if (input[1] == '[') {
            // CSI sequences
            if (input.len >= 3) {
                return Event{ .key = switch (input[2]) {
                    'A' => KeyEvent{ .key = Key.up },
                    'B' => KeyEvent{ .key = Key.down },
                    'C' => KeyEvent{ .key = Key.right },
                    'D' => KeyEvent{ .key = Key.left },
                    '3' => if (input.len >= 4 and input[3] == '~')
                        KeyEvent{ .key = Key.delete }
                    else
                        KeyEvent{ .key = Key.unknown },
                    else => KeyEvent{ .key = Key.unknown },
                } };
            }
        } else if (input[1] == 'O') {
            // Function keys (some terminals)
            if (input.len >= 3) {
                return Event{ .key = switch (input[2]) {
                    'P' => KeyEvent{ .key = Key.f1 },
                    'Q' => KeyEvent{ .key = Key.f2 },
                    'R' => KeyEvent{ .key = Key.f3 },
                    'S' => KeyEvent{ .key = Key.f4 },
                    else => KeyEvent{ .key = Key.unknown },
                } };
            }
        }
    }

    // Function keys (F1-F12) - different escape sequences
    if (input.len >= 4 and input[0] == 27 and input[1] == '[') {
        if (input[2] == '1' and input.len >= 5) {
            return Event{ .key = switch (input[3]) {
                '1' => if (input[4] == '~') KeyEvent{ .key = Key.f1 } else KeyEvent{ .key = Key.unknown },
                '2' => if (input[4] == '~') KeyEvent{ .key = Key.f2 } else KeyEvent{ .key = Key.unknown },
                '3' => if (input[4] == '~') KeyEvent{ .key = Key.f3 } else KeyEvent{ .key = Key.unknown },
                '4' => if (input[4] == '~') KeyEvent{ .key = Key.f4 } else KeyEvent{ .key = Key.unknown },
                '5' => if (input[4] == '~') KeyEvent{ .key = Key.f5 } else KeyEvent{ .key = Key.unknown },
                '7' => if (input[4] == '~') KeyEvent{ .key = Key.f6 } else KeyEvent{ .key = Key.unknown },
                '8' => if (input[4] == '~') KeyEvent{ .key = Key.f7 } else KeyEvent{ .key = Key.unknown },
                '9' => if (input[4] == '~') KeyEvent{ .key = Key.f8 } else KeyEvent{ .key = Key.unknown },
                else => KeyEvent{ .key = Key.unknown },
            } };
        } else if (input[2] == '2') {
            return Event{ .key = switch (input[3]) {
                '0' => if (input.len >= 5 and input[4] == '~') KeyEvent{ .key = Key.f9 } else KeyEvent{ .key = Key.unknown },
                '1' => if (input.len >= 5 and input[4] == '~') KeyEvent{ .key = Key.f10 } else KeyEvent{ .key = Key.unknown },
                '3' => if (input.len >= 5 and input[4] == '~') KeyEvent{ .key = Key.f11 } else KeyEvent{ .key = Key.unknown },
                '4' => if (input.len >= 5 and input[4] == '~') KeyEvent{ .key = Key.f12 } else KeyEvent{ .key = Key.unknown },
                else => KeyEvent{ .key = Key.unknown },
            } };
        }
    }

    return Event{ .key = KeyEvent{ .key = Key.unknown } };
}

// Test functions
pub fn testEventHandling() !void {
    std.debug.print("Testing event handling...\n", .{});
    std.debug.print("Press keys (ESC to exit):\n", .{});

    var event_handler = try EventHandler.init();
    defer event_handler.deinit();

    while (true) {
        if (try event_handler.pollEvent()) |event| {
            switch (event) {
                .key => |key_event| {
                    switch (key_event.key) {
                        .escape => {
                            std.debug.print("ESC pressed - exiting\n", .{});
                            break;
                        },
                        .enter => std.debug.print("ENTER pressed\n", .{}),
                        .tab => std.debug.print("TAB pressed\n", .{}),
                        .up => std.debug.print("UP arrow pressed\n", .{}),
                        .down => std.debug.print("DOWN arrow pressed\n", .{}),
                        .left => std.debug.print("LEFT arrow pressed\n", .{}),
                        .right => std.debug.print("RIGHT arrow pressed\n", .{}),
                        .f1 => std.debug.print("F1 pressed\n", .{}),
                        .f2 => std.debug.print("F2 pressed\n", .{}),
                        .char => {
                            if (key_event.char) |c| {
                                if (key_event.modifiers.ctrl) {
                                    std.debug.print("Ctrl+{c} pressed\n", .{c});
                                } else {
                                    std.debug.print("'{c}' pressed\n", .{c});
                                }
                            }
                        },
                        else => std.debug.print("Other key pressed\n", .{}),
                    }
                },
                else => {},
            }
        }

        // Small delay to prevent busy waiting
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}
