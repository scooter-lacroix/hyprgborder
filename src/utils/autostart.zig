//! Autostart management for HyprGBorder
//! Handles installing and removing XDG autostart desktop entries

const std = @import("std");

pub const AutostartError = error{
    DesktopEntryWriteFailed,
    DesktopEntryRemovalFailed,
    HomeDirectoryNotFound,
    OutOfMemory,
};

/// Get the XDG autostart directory path (~/.config/autostart/)
pub fn getAutostartDir(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return AutostartError.HomeDirectoryNotFound;
    };
    defer allocator.free(home);

    // Check for XDG_CONFIG_HOME first
    const xdg_config = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
    if (xdg_config) |config_path| {
        defer allocator.free(config_path);
        return try std.fmt.allocPrint(allocator, "{s}/autostart", .{config_path});
    }

    return try std.fmt.allocPrint(allocator, "{s}/.config/autostart", .{home});
}

/// Get the desktop entry file path
pub fn getDesktopEntryPath(allocator: std.mem.Allocator) ![]u8 {
    const autostart_dir = try getAutostartDir(allocator);
    defer allocator.free(autostart_dir);

    return try std.fmt.allocPrint(allocator, "{s}/hyprgborder.desktop", .{autostart_dir});
}

/// Check if autostart is currently enabled
pub fn isAutostartEnabled(allocator: std.mem.Allocator) bool {
    const desktop_path = getDesktopEntryPath(allocator) catch return false;
    defer allocator.free(desktop_path);

    std.fs.accessAbsolute(desktop_path, .{}) catch return false;
    return true;
}

/// Get the path to the hyprgborder executable
fn getExecutablePath(allocator: std.mem.Allocator) ![]u8 {
    // Try to read /proc/self/exe on Linux
    const self_exe = "/proc/self/exe";
    var buffer: [std.fs.max_path_bytes]u8 = undefined;

    const path = std.fs.readLinkAbsolute(self_exe, &buffer) catch {
        // Fallback: assume it's in zig-out/bin or in PATH
        return try allocator.dupe(u8, "hyprgborder");
    };

    return try allocator.dupe(u8, path);
}

/// Install autostart desktop entry
pub fn installAutostart(allocator: std.mem.Allocator) AutostartError!void {
    const autostart_dir = getAutostartDir(allocator) catch |err| {
        return switch (err) {
            AutostartError.HomeDirectoryNotFound => AutostartError.HomeDirectoryNotFound,
            else => AutostartError.DesktopEntryWriteFailed,
        };
    };
    defer allocator.free(autostart_dir);

    // Ensure autostart directory exists
    std.fs.makeDirAbsolute(autostart_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return AutostartError.DesktopEntryWriteFailed,
    };

    const desktop_path = getDesktopEntryPath(allocator) catch return AutostartError.DesktopEntryWriteFailed;
    defer allocator.free(desktop_path);

    // Get executable path
    const exe_path = getExecutablePath(allocator) catch return AutostartError.DesktopEntryWriteFailed;
    defer allocator.free(exe_path);

    // Create desktop entry content
    const desktop_content = try std.fmt.allocPrint(allocator,
        \\[Desktop Entry]
        \\Type=Application
        \\Name=HyprGBorder
        \\Comment=Hyprland Border Animation
        \\Exec={s}
        \\Terminal=false
        \\Categories=Utility;
        \\StartupNotify=false
        \\X-GNOME-Autostart-enabled=true
    , .{exe_path});
    defer allocator.free(desktop_content);

    // Write desktop entry file
    const file = std.fs.createFileAbsolute(desktop_path, .{ .truncate = true }) catch {
        return AutostartError.DesktopEntryWriteFailed;
    };
    defer file.close();

    file.writeAll(desktop_content) catch {
        return AutostartError.DesktopEntryWriteFailed;
    };
}

/// Remove autostart desktop entry
pub fn removeAutostart(allocator: std.mem.Allocator) AutostartError!void {
    const desktop_path = getDesktopEntryPath(allocator) catch return AutostartError.DesktopEntryRemovalFailed;
    defer allocator.free(desktop_path);

    std.fs.deleteFileAbsolute(desktop_path) catch |err| switch (err) {
        error.FileNotFound => {}, // Already removed, that's fine
        else => return AutostartError.DesktopEntryRemovalFailed,
    };
}

/// Toggle autostart status
pub fn toggleAutostart(allocator: std.mem.Allocator) !bool {
    if (isAutostartEnabled(allocator)) {
        try removeAutostart(allocator);
        return false;
    } else {
        try installAutostart(allocator);
        return true;
    }
}

/// Get user-friendly error message
pub fn getErrorMessage(err: AutostartError) []const u8 {
    return switch (err) {
        AutostartError.DesktopEntryWriteFailed => "Failed to create autostart entry",
        AutostartError.DesktopEntryRemovalFailed => "Failed to remove autostart entry",
        AutostartError.HomeDirectoryNotFound => "Could not find home directory",
        AutostartError.OutOfMemory => "Out of memory",
    };
}
