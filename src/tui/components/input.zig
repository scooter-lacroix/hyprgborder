//! Input handling and validation for CLI interface
//! Provides utilities for reading and validating user input

const std = @import("std");

pub const InputError = error{
    InvalidInput,
    OutOfRange,
    InvalidFormat,
};

pub fn readUserInput(allocator: std.mem.Allocator, max_len: usize) ![]u8 {
    const stdin = std.io.getStdIn().reader();

    const input_buf = try allocator.alloc(u8, max_len);
    defer allocator.free(input_buf);

    if (try stdin.readUntilDelimiterOrEof(input_buf, '\n')) |input| {
        const trimmed = std.mem.trim(u8, input, " \n\r\t");
        return try allocator.dupe(u8, trimmed);
    }

    return error.InvalidInput;
}

pub fn readSelection() !usize {
    const stdin = std.io.getStdIn().reader();

    var buf: [32]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
        const trimmed = std.mem.trim(u8, input, " \n\r\t");
        if (trimmed.len == 0) return error.InvalidInput;

        return std.fmt.parseInt(usize, trimmed, 10) catch error.InvalidInput;
    }

    return error.InvalidInput;
}

pub fn validateFps(fps: u32) InputError!void {
    if (fps < 1 or fps > 120) {
        return InputError.OutOfRange;
    }
}

pub fn validateSpeed(speed: f64) InputError!void {
    if (speed < 0.001 or speed > 1.0) {
        return InputError.OutOfRange;
    }
}

pub fn parseColor(color_str: []const u8) InputError![]const u8 {
    // Basic validation - should start with # for hex or be a valid format
    if (color_str.len == 0) return InputError.InvalidFormat;

    if (color_str[0] == '#' and color_str.len == 7) {
        // Validate hex format
        for (color_str[1..]) |c| {
            if (!std.ascii.isHex(c)) {
                return InputError.InvalidFormat;
            }
        }
        return color_str;
    }

    return InputError.InvalidFormat;
}
