//! Configuration persistence layer
//! Handles saving and loading configuration to/from JSON files

const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils");

pub const PersistenceError = error{
    ConfigNotFound,
    InvalidFormat,
    WriteError,
    ReadError,
    PresetNotFound,
    PresetAlreadyExists,
};

// Configuration file structure
const ConfigFile = struct {
    version: []const u8,
    current_preset: []const u8,
    presets: std.StringHashMap(types.Preset),
    settings: Settings,

    const Settings = struct {
        auto_start: bool = false,
        preview_enabled: bool = true,
    };
};

pub fn getConfigDir(allocator: std.mem.Allocator) ![]u8 {
    const maybe_xdg = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
    if (maybe_xdg) |xdg_val| {
        return xdg_val;
    } else {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        return try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
    }
}

pub fn getConfigPath(allocator: std.mem.Allocator) ![]u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    return try std.fmt.allocPrint(allocator, "{s}/hyprgborder/config.json", .{config_dir});
}

pub fn ensureConfigDir(allocator: std.mem.Allocator) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const hypr_config_dir = try std.fmt.allocPrint(allocator, "{s}/hyprgborder", .{config_dir});
    defer allocator.free(hypr_config_dir);

    std.fs.makeDirAbsolute(hypr_config_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn saveConfig(allocator: std.mem.Allocator, config: *const types.AnimationConfig) !void {
    try ensureConfigDir(allocator);

    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // Create a simple JSON string manually for now
    var json_parts: std.ArrayList([]const u8) = .{};
    defer {
        for (json_parts.items) |part| {
            allocator.free(part);
        }
        json_parts.deinit(allocator);
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "{\n"));
    try json_parts.append(allocator, try allocator.dupe(u8, "  \"version\": \"1.0\",\n"));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"animation_type\": \"{s}\",\n", .{config.animation_type.toString()}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"fps\": {},\n", .{config.fps}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"speed\": {d},\n", .{config.speed}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"direction\": \"{s}\",\n", .{config.direction.toString()}));
    try json_parts.append(allocator, try allocator.dupe(u8, "  \"colors\": ["));

    for (config.colors.items, 0..) |color, i| {
        const hex_color = try color.toHex(allocator);
        defer allocator.free(hex_color);

        if (i > 0) try json_parts.append(allocator, try allocator.dupe(u8, ", "));
        try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "\"{s}\"", .{hex_color}));
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "]\n"));
    try json_parts.append(allocator, try allocator.dupe(u8, "}\n"));

    // Calculate total length and concatenate
    var total_len: usize = 0;
    for (json_parts.items) |part| {
        total_len += part.len;
    }

    const json_string = try allocator.alloc(u8, total_len);
    defer allocator.free(json_string);

    var pos: usize = 0;
    for (json_parts.items) |part| {
        @memcpy(json_string[pos .. pos + part.len], part);
        pos += part.len;
    }

    // Write to file
    const file = std.fs.createFileAbsolute(config_path, .{ .truncate = true }) catch {
        return PersistenceError.WriteError;
    };
    defer file.close();

    try file.writeAll(json_string);
}

pub fn loadConfig(allocator: std.mem.Allocator) !types.AnimationConfig {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return PersistenceError.ConfigNotFound,
        else => return PersistenceError.ReadError,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        return PersistenceError.InvalidFormat;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract configuration values
    const animation_type_str = root.get("animation_type").?.string;
    const animation_type = types.AnimationType.fromString(animation_type_str) orelse return PersistenceError.InvalidFormat;

    const fps = @as(u32, @intCast(root.get("fps").?.integer));
    const speed = root.get("speed").?.float;

    const direction_str = root.get("direction").?.string;
    const direction = types.AnimationDirection.fromString(direction_str) orelse return PersistenceError.InvalidFormat;

    // Parse colors
    var colors: std.ArrayList(types.ColorFormat) = .{};
    const colors_array = root.get("colors").?.array;

    for (colors_array.items) |color_value| {
        const color_str = color_value.string;
        const color = try types.ColorFormat.fromHex(color_str);
        try colors.append(allocator, color);
    }

    return types.AnimationConfig{
        .animation_type = animation_type,
        .fps = fps,
        .speed = speed,
        .colors = colors,
        .direction = direction,
    };
}

pub fn loadConfigOrDefault(allocator: std.mem.Allocator) !types.AnimationConfig {
    return loadConfig(allocator) catch |err| switch (err) {
        PersistenceError.ConfigNotFound => {
            // Return default configuration
            var default_config = types.AnimationConfig.default();
            default_config.colors = .{};
            return default_config;
        },
        else => return err,
    };
}

// Preset management functions
pub fn savePreset(allocator: std.mem.Allocator, preset: *const types.Preset) !void {
    try ensureConfigDir(allocator);

    const preset_dir = try getPresetDir(allocator);
    defer allocator.free(preset_dir);

    // Ensure preset directory exists
    std.fs.makeDirAbsolute(preset_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const preset_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ preset_dir, preset.name });
    defer allocator.free(preset_path);

    // Check if preset already exists
    if (std.fs.openFileAbsolute(preset_path, .{ .mode = .read_only })) |file| {
        file.close();
        return PersistenceError.PresetAlreadyExists;
    } else |_| {}

    // Create JSON for preset
    var json_parts: std.ArrayList([]const u8) = .{};
    defer {
        for (json_parts.items) |part| {
            allocator.free(part);
        }
        json_parts.deinit(allocator);
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "{\n"));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"name\": \"{s}\",\n", .{preset.name}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"created_at\": {},\n", .{preset.created_at}));
    try json_parts.append(allocator, try allocator.dupe(u8, "  \"config\": {\n"));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"animation_type\": \"{s}\",\n", .{preset.config.animation_type.toString()}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"fps\": {},\n", .{preset.config.fps}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"speed\": {d},\n", .{preset.config.speed}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"direction\": \"{s}\",\n", .{preset.config.direction.toString()}));
    try json_parts.append(allocator, try allocator.dupe(u8, "    \"colors\": ["));

    for (preset.config.colors.items, 0..) |color, i| {
        const hex_color = try color.toHex(allocator);
        defer allocator.free(hex_color);

        if (i > 0) try json_parts.append(allocator, try allocator.dupe(u8, ", "));
        try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "\"{s}\"", .{hex_color}));
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "]\n"));
    try json_parts.append(allocator, try allocator.dupe(u8, "  }\n"));
    try json_parts.append(allocator, try allocator.dupe(u8, "}\n"));

    // Calculate total length and concatenate
    var total_len: usize = 0;
    for (json_parts.items) |part| {
        total_len += part.len;
    }

    const json_string = try allocator.alloc(u8, total_len);
    defer allocator.free(json_string);

    var pos: usize = 0;
    for (json_parts.items) |part| {
        @memcpy(json_string[pos .. pos + part.len], part);
        pos += part.len;
    }

    // Write to file
    const file = std.fs.createFileAbsolute(preset_path, .{ .truncate = true }) catch {
        return PersistenceError.WriteError;
    };
    defer file.close();

    try file.writeAll(json_string);
}

pub fn loadPreset(allocator: std.mem.Allocator, name: []const u8) !types.Preset {
    const preset_dir = try getPresetDir(allocator);
    defer allocator.free(preset_dir);

    const preset_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ preset_dir, name });
    defer allocator.free(preset_path);

    const file = std.fs.openFileAbsolute(preset_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return PersistenceError.PresetNotFound,
        else => return PersistenceError.ReadError,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        return PersistenceError.InvalidFormat;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract preset values
    const preset_name = root.get("name").?.string;
    const created_at = root.get("created_at").?.integer;
    const config_obj = root.get("config").?.object;

    // Parse config
    const animation_type_str = config_obj.get("animation_type").?.string;
    const animation_type = types.AnimationType.fromString(animation_type_str) orelse return PersistenceError.InvalidFormat;

    const fps = @as(u32, @intCast(config_obj.get("fps").?.integer));
    const speed = config_obj.get("speed").?.float;

    const direction_str = config_obj.get("direction").?.string;
    const direction = types.AnimationDirection.fromString(direction_str) orelse return PersistenceError.InvalidFormat;

    // Parse colors
    var colors: std.ArrayList(types.ColorFormat) = .{};
    const colors_array = config_obj.get("colors").?.array;

    for (colors_array.items) |color_value| {
        const color_str = color_value.string;
        const color = try types.ColorFormat.fromHex(color_str);
        try colors.append(allocator, color);
    }

    const config = types.AnimationConfig{
        .animation_type = animation_type,
        .fps = fps,
        .speed = speed,
        .colors = colors,
        .direction = direction,
    };

    return types.Preset{
        .name = try allocator.dupe(u8, preset_name),
        .config = config,
        .created_at = created_at,
    };
}

pub fn deletePreset(allocator: std.mem.Allocator, name: []const u8) !void {
    const preset_dir = try getPresetDir(allocator);
    defer allocator.free(preset_dir);

    const preset_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ preset_dir, name });
    defer allocator.free(preset_path);

    std.fs.deleteFileAbsolute(preset_path) catch |err| switch (err) {
        error.FileNotFound => return PersistenceError.PresetNotFound,
        else => return PersistenceError.WriteError,
    };
}

pub fn listPresets(allocator: std.mem.Allocator) ![][]const u8 {
    const preset_dir = try getPresetDir(allocator);
    defer allocator.free(preset_dir);

    var dir = std.fs.openDirAbsolute(preset_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            // No presets directory, return empty list
            return try allocator.alloc([]const u8, 0);
        },
        else => return err,
    };
    defer dir.close();

    var preset_names: std.ArrayList([]const u8) = .{};
    defer preset_names.deinit(allocator);

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
            // Remove .json extension
            const name_without_ext = entry.name[0 .. entry.name.len - 5];
            try preset_names.append(allocator, try allocator.dupe(u8, name_without_ext));
        }
    }

    return preset_names.toOwnedSlice();
}

fn getPresetDir(allocator: std.mem.Allocator) ![]u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    return try std.fmt.allocPrint(allocator, "{s}/hyprgborder/presets", .{config_dir});
}

// Error handling helpers
pub fn getErrorMessage(err: PersistenceError) []const u8 {
    return switch (err) {
        PersistenceError.ConfigNotFound => "Configuration file not found. Using default settings.",
        PersistenceError.InvalidFormat => "Configuration file format is invalid.",
        PersistenceError.WriteError => "Failed to write configuration file.",
        PersistenceError.ReadError => "Failed to read configuration file.",
        PersistenceError.PresetNotFound => "Preset not found.",
        PersistenceError.PresetAlreadyExists => "A preset with this name already exists.",
    };
}
