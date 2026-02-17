//! Application logging utility
//! Logs application events and errors to a file for debugging

const std = @import("std");

var log_file: ?std.fs.File = null;
var registered_signals: bool = false;
var log_fd: c_int = -1;
// Import needed C symbols
const c = @cImport({
    @cInclude("signal.h");
    @cInclude("unistd.h");
    @cInclude("sys/types.h");
    @cInclude("sys/stat.h");
    @cInclude("fcntl.h");
});

pub fn registerSignalHandlers() void {
    if (registered_signals) return;
    // Register handler for SIGSEGV, SIGABRT, SIGINT
    // Use libc signal to set handler
    const SIGSEGV = c.SIGSEGV;
    const SIGABRT = c.SIGABRT;
    const SIGINT = c.SIGINT;
    _ = c.signal(SIGSEGV, signal_handler);
    _ = c.signal(SIGABRT, signal_handler);
    _ = c.signal(SIGINT, signal_handler);
    registered_signals = true;
}

pub fn initCrashLogger(allocator: std.mem.Allocator) !void {
    // Create log directory
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch {
        const log_dir_path = try std.fmt.allocPrint(allocator, "/tmp/.hyprgborder", .{});
        defer allocator.free(log_dir_path);

        std.fs.makeDirAbsolute(log_dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const timestamp = std.time.timestamp();
        const log_file_path = try std.fmt.allocPrint(allocator, "/tmp/.hyprgborder/app_{d}.log", .{timestamp});
        defer allocator.free(log_file_path);

        log_file = try std.fs.createFileAbsolute(log_file_path, .{});
        // Cache raw fd for use in signal handler (avoid accessing File in signal context)
        if (log_file) |f| log_fd = f.handle;

        // Log startup
        try logMessage("HyprGBorder logger initialized (fallback)", .{});
        try logMessage("Timestamp: {d}", .{timestamp});
        return;
    };
    defer allocator.free(home_dir);

    const log_dir_path = try std.fmt.allocPrint(allocator, "{s}/.hyprgborder", .{home_dir});
    defer allocator.free(log_dir_path);

    std.fs.makeDirAbsolute(log_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Create log file with timestamp
    const timestamp = std.time.timestamp();
    const log_file_path = try std.fmt.allocPrint(allocator, "{s}/app_{d}.log", .{ log_dir_path, timestamp });
    defer allocator.free(log_file_path);

    log_file = try std.fs.createFileAbsolute(log_file_path, .{});
    if (log_file) |f| log_fd = f.handle;

    // Log startup
    try logMessage("HyprGBorder logger initialized", .{});
    try logMessage("Timestamp: {d}", .{timestamp});
}

pub fn deinitCrashLogger() void {
    if (log_file) |file| {
        logMessage("Logger shutting down normally", .{}) catch {};
        file.close();
        log_file = null;
        log_fd = -1;
    }
}

pub fn logMessage(comptime fmt: []const u8, args: anytype) !void {
    if (log_file) |file| {
        const timestamp = std.time.timestamp();
        var buffer: [1024]u8 = undefined;
        const message = try std.fmt.bufPrint(buffer[0..], "[{d}] " ++ fmt ++ "\n", .{timestamp} ++ args);
        try file.writeAll(message);
        try file.sync();
    }
}

// Simple C signal handler that attempts to write a last log message and flush
pub fn signal_handler(sig: c_int) callconv(.c) void {
    // Avoid allocation here; write a simple message directly to the cached file descriptor if available
    if (log_fd >= 0) {
        const msg = "FATAL SIGNAL received\n";
        _ = c.write(log_fd, msg, msg.len);
        _ = c.fsync(log_fd);
    }
    // Re-raise default handler for the signal to terminate with default action
    _ = c.signal(sig, c.SIG_DFL);
    _ = c.raise(sig);
}
