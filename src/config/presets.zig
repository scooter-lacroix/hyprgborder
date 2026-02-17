//! Preset management functionality
//! Handles CRUD operations for named configuration presets

const std = @import("std");
const types = @import("types.zig");
const persistence = @import("persistence.zig");

pub const PresetError = error{
    PresetNotFound,
    PresetAlreadyExists,
    InvalidPresetName,
    InvalidConfig,
    WriteError,
    ReadError,
};

pub fn getPresetsPath(allocator: std.mem.Allocator) ![]u8 {
    const config_dir = try persistence.getConfigDir(allocator);
    defer allocator.free(config_dir);

    return try std.fmt.allocPrint(allocator, "{s}/hyprgborder/presets.json", .{config_dir});
}

pub fn loadPresets(allocator: std.mem.Allocator) !std.StringHashMap(types.Preset) {
    const presets_path = try getPresetsPath(allocator);
    defer allocator.free(presets_path);

    var presets = std.StringHashMap(types.Preset).init(allocator);

    // Try to open the presets file
    std.log.debug("Loading presets from: {s}", .{presets_path});

    const file = std.fs.openFileAbsolute(presets_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.info("No presets file found at {s}, creating new preset storage", .{presets_path});
            return presets;
        },
        error.AccessDenied => {
            std.log.err("Access denied while reading presets file: {s}", .{presets_path});
            return err;
        },
        else => {
            std.log.err("Error opening presets file: {s} ({s})", .{ presets_path, @errorName(err) });
            return err;
        },
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        // Invalid JSON, return empty map
        return presets;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    var iterator = root.iterator();
    while (iterator.next()) |entry| {
        const preset_name = entry.key_ptr.*;
        const preset_obj = entry.value_ptr.*.object;

        // Parse preset configuration
        const animation_type_str = preset_obj.get("animation_type").?.string;
        const animation_type = types.AnimationType.fromString(animation_type_str) orelse continue;

        const fps = @as(u32, @intCast(preset_obj.get("fps").?.integer));
        const speed = preset_obj.get("speed").?.float;

        const direction_str = preset_obj.get("direction").?.string;
        const direction = types.AnimationDirection.fromString(direction_str) orelse continue;

        const created_at = preset_obj.get("created_at").?.integer;

        // Parse colors
        var colors = std.ArrayList(types.ColorFormat){};
        const colors_array = preset_obj.get("colors").?.array;

        for (colors_array.items) |color_value| {
            const color_str = color_value.string;
            const color = types.ColorFormat{ .hex = try allocator.dupe(u8, color_str) };
            try colors.append(allocator, color);
        }

        const config = types.AnimationConfig{
            .animation_type = animation_type,
            .fps = fps,
            .speed = speed,
            .colors = colors,
            .direction = direction,
        };

        const preset = types.Preset{
            .name = try allocator.dupe(u8, preset_name),
            .config = config,
            .created_at = created_at,
        };

        try presets.put(preset.name, preset);
    }

    return presets;
}

pub fn savePresets(allocator: std.mem.Allocator, presets: *const std.StringHashMap(types.Preset)) !void {
    try persistence.ensureConfigDir(allocator);

    const presets_path = try getPresetsPath(allocator);
    defer allocator.free(presets_path);

    // Write to file using a simpler approach
    const file = std.fs.createFileAbsolute(presets_path, .{ .truncate = true }) catch {
        return error.WriteError;
    };
    defer file.close();

    // Write directly to the file
    _ = try file.write("{\n");

    var iterator = presets.iterator();
    var first = true;
    while (iterator.next()) |entry| {
        const preset = entry.value_ptr.*;

        if (!first) {
            _ = try file.write(",\n");
        }
        first = false;

        // Write preset entry
        var buf: [256]u8 = undefined;

        _ = try file.write("  \"");
        _ = try file.write(preset.name);
        _ = try file.write("\": {\n");
        _ = try file.write("    \"animation_type\": \"");
        _ = try file.write(preset.config.animation_type.toString());
        _ = try file.write("\",\n");

        const fps_str = try std.fmt.bufPrint(&buf, "    \"fps\": {},\n", .{preset.config.fps});
        _ = try file.write(fps_str);

        const speed_str = try std.fmt.bufPrint(&buf, "    \"speed\": {},\n", .{preset.config.speed});
        _ = try file.write(speed_str);

        _ = try file.write("    \"direction\": \"");
        _ = try file.write(preset.config.direction.toString());
        _ = try file.write("\",\n");

        const created_str = try std.fmt.bufPrint(&buf, "    \"created_at\": {},\n", .{preset.created_at});
        _ = try file.write(created_str);

        // Write colors array
        _ = try file.write("    \"colors\": [");
        for (preset.config.colors.items, 0..) |color, i| {
            if (i > 0) _ = try file.write(", ");
            const hex_color = try color.toHex(allocator);
            defer allocator.free(hex_color);
            _ = try file.write("\"");
            _ = try file.write(hex_color);
            _ = try file.write("\"");
        }
        _ = try file.write("]\n  }");
    }

    _ = try file.write("\n}\n");
    try file.sync(); // Ensure the data is written to disk
}

pub fn savePreset(allocator: std.mem.Allocator, name: []const u8, config: *const types.AnimationConfig) !void {
    // Validate preset name
    if (name.len == 0) {
        std.log.err("Cannot save preset: Empty preset name", .{});
        return PresetError.InvalidPresetName;
    }

    // Validate config
    if (config.colors.items.len == 0) {
        std.log.err("Cannot save preset '{s}': No colors defined", .{name});
        return error.InvalidConfig;
    }

    std.log.info("Saving preset '{s}' with type {s}", .{ name, config.animation_type.toString() });

    var presets = try loadPresets(allocator);
    defer {
        var iterator = presets.iterator();
        while (iterator.next()) |entry| {
            var preset = entry.value_ptr.*;
            preset.deinit(allocator);
        }
        presets.deinit();
    }

    const preset = try types.Preset.init(allocator, name, config.*);
    try presets.put(preset.name, preset);

    try savePresets(allocator, &presets);
}

pub fn loadPreset(allocator: std.mem.Allocator, name: []const u8) !types.AnimationConfig {
    var presets = try loadPresets(allocator);
    defer {
        var iterator = presets.iterator();
        while (iterator.next()) |entry| {
            var preset = entry.value_ptr.*;
            preset.deinit(allocator);
        }
        presets.deinit();
    }

    const preset = presets.get(name) orelse return PresetError.PresetNotFound;

    // Return a copy of the configuration
    var colors: std.ArrayList(types.ColorFormat) = .{};
    for (preset.config.colors.items) |color| {
        try colors.append(allocator, color);
    }

    return types.AnimationConfig{
        .animation_type = preset.config.animation_type,
        .fps = preset.config.fps,
        .speed = preset.config.speed,
        .colors = colors,
        .direction = preset.config.direction,
    };
}

pub fn deletePreset(allocator: std.mem.Allocator, name: []const u8) !void {
    var presets = try loadPresets(allocator);
    defer {
        var iterator = presets.iterator();
        while (iterator.next()) |entry| {
            var preset = entry.value_ptr.*;
            preset.deinit(allocator);
        }
        presets.deinit();
    }

    if (!presets.remove(name)) {
        return PresetError.PresetNotFound;
    }

    try savePresets(allocator, &presets);
}
