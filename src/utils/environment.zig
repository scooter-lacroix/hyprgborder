//! Environment checking utilities
//! Validates Hyprland environment and system requirements

const std = @import("std");

pub const EnvironmentError = error{
    HyprlandNotRunning,
    MissingEnvironmentVariable,
    SocketNotAccessible,
    InvalidHyprlandVersion,
};

pub const EnvironmentStatus = struct {
    hyprland_running: bool,
    xdg_runtime_dir: ?[]const u8,
    hyprland_instance_signature: ?[]const u8,
    socket_accessible: bool,
    hyprland_version: ?[]const u8,

    pub fn deinit(self: *EnvironmentStatus, allocator: std.mem.Allocator) void {
        if (self.xdg_runtime_dir) |dir| allocator.free(dir);
        if (self.hyprland_instance_signature) |sig| allocator.free(sig);
        if (self.hyprland_version) |ver| allocator.free(ver);
    }
};

/// Check if Hyprland is running by looking for the process
pub fn isHyprlandRunning(allocator: std.mem.Allocator) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "pgrep", "-x", "Hyprland" },
    }) catch return false;

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term.Exited == 0 and result.stdout.len > 0;
}

/// Get required environment variables
pub fn getEnvironmentVariables(allocator: std.mem.Allocator) !struct { xdg_runtime_dir: []const u8, hyprland_instance_signature: []const u8 } {
    const xdg_runtime_dir = std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return EnvironmentError.MissingEnvironmentVariable,
        else => return err,
    };

    const hyprland_instance_signature = std.process.getEnvVarOwned(allocator, "HYPRLAND_INSTANCE_SIGNATURE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            allocator.free(xdg_runtime_dir);
            return EnvironmentError.MissingEnvironmentVariable;
        },
        else => {
            allocator.free(xdg_runtime_dir);
            return err;
        },
    };

    return .{
        .xdg_runtime_dir = xdg_runtime_dir,
        .hyprland_instance_signature = hyprland_instance_signature,
    };
}

/// Check if Hyprland socket is accessible
pub fn isSocketAccessible(socket_path: []const u8) bool {
    const file = std.fs.openFileAbsolute(socket_path, .{ .mode = .read_only }) catch return false;
    file.close();
    return true;
}

/// Get Hyprland version information
pub fn getHyprlandVersion(allocator: std.mem.Allocator) ?[]u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "hyprctl", "version" },
    }) catch return null;

    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return null;
    }

    // Extract version from first line
    var lines = std.mem.splitSequence(u8, result.stdout, "\n");
    if (lines.next()) |first_line| {
        const version = allocator.dupe(u8, std.mem.trim(u8, first_line, " \n\r\t")) catch {
            allocator.free(result.stdout);
            return null;
        };
        allocator.free(result.stdout);
        return version;
    }

    allocator.free(result.stdout);
    return null;
}

/// Perform comprehensive environment check
pub fn checkEnvironment(allocator: std.mem.Allocator) !EnvironmentStatus {
    var status = EnvironmentStatus{
        .hyprland_running = false,
        .xdg_runtime_dir = null,
        .hyprland_instance_signature = null,
        .socket_accessible = false,
        .hyprland_version = null,
    };

    // Check if Hyprland is running
    status.hyprland_running = isHyprlandRunning(allocator);

    // Get environment variables
    const env_vars = getEnvironmentVariables(allocator) catch |err| switch (err) {
        EnvironmentError.MissingEnvironmentVariable => {
            return status; // Return partial status
        },
        else => return err,
    };

    status.xdg_runtime_dir = env_vars.xdg_runtime_dir;
    status.hyprland_instance_signature = env_vars.hyprland_instance_signature;

    // Check socket accessibility
    const socket_path = try std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket.sock", .{ status.xdg_runtime_dir.?, status.hyprland_instance_signature.? });
    defer allocator.free(socket_path);

    status.socket_accessible = isSocketAccessible(socket_path);

    // Get Hyprland version
    status.hyprland_version = getHyprlandVersion(allocator);

    return status;
}

/// Validate environment and return specific error if validation fails
pub fn validateEnvironment(allocator: std.mem.Allocator) !void {
    const status = try checkEnvironment(allocator);
    defer {
        var mut_status = status;
        mut_status.deinit(allocator);
    }

    if (!status.hyprland_running) {
        return EnvironmentError.HyprlandNotRunning;
    }

    if (status.xdg_runtime_dir == null or status.hyprland_instance_signature == null) {
        return EnvironmentError.MissingEnvironmentVariable;
    }

    if (!status.socket_accessible) {
        return EnvironmentError.SocketNotAccessible;
    }
}

/// Get user-friendly error message for environment errors
pub fn getEnvironmentErrorMessage(err: EnvironmentError) []const u8 {
    return switch (err) {
        EnvironmentError.HyprlandNotRunning => "Hyprland is not running. Please start Hyprland first.",
        EnvironmentError.MissingEnvironmentVariable => "Required environment variables (XDG_RUNTIME_DIR, HYPRLAND_INSTANCE_SIGNATURE) are not set.",
        EnvironmentError.SocketNotAccessible => "Cannot access Hyprland IPC socket. Check if Hyprland is running properly.",
        EnvironmentError.InvalidHyprlandVersion => "Unsupported Hyprland version detected.",
    };
}

/// Print environment status report
pub fn printEnvironmentStatus(status: *const EnvironmentStatus) void {
    std.debug.print("\n=== Hyprland Environment Status ===\n", .{});
    std.debug.print("Hyprland Running: {s}\n", .{if (status.hyprland_running) "Yes" else "No"});
    std.debug.print("XDG_RUNTIME_DIR: {s}\n", .{if (status.xdg_runtime_dir) |dir| dir else "Not Set"});
    std.debug.print("HYPRLAND_INSTANCE_SIGNATURE: {s}\n", .{if (status.hyprland_instance_signature) |sig| sig else "Not Set"});
    std.debug.print("Socket Accessible: {s}\n", .{if (status.socket_accessible) "Yes" else "No"});
    std.debug.print("Hyprland Version: {s}\n", .{if (status.hyprland_version) |ver| ver else "Unknown"});
    std.debug.print("=====================================\n\n", .{});
}
