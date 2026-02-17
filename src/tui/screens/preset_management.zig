//! Preset Management Panel - Visual controls for preset operations
//! Provides interactive controls for creating, loading, deleting, and managing presets

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");
const components = @import("../components/mod.zig");
const config = @import("config");

pub const PresetAction = enum {
    none,
    load,
    save,
    delete,
    rename,
};

pub const PresetManagementPanel = struct {
    allocator: std.mem.Allocator,
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    // Preset data
    presets: std.ArrayList(config.Preset),
    current_preset_name: ?[]const u8 = null,

    // UI Components
    panel: components.Panel,
    preset_list: components.List,
    preset_name_input: components.InputField,
    action_dropdown: components.Dropdown,
    status_text: components.Text,

    // Dialog state
    dialog_mode: DialogMode = DialogMode.none,
    pending_action: PresetAction = PresetAction.none,
    selected_preset_index: ?usize = null,

    // Focus management
    focused_component: usize = 0,
    component_count: usize = 3, // list, input, dropdown
    visible: bool = true,

    // Current configuration for saving presets
    current_config: ?*const config.AnimationConfig = null,

    // Status and feedback
    last_status_message: []const u8 = "",
    status_color: renderer.Color = renderer.Color.WHITE,

    const DialogMode = enum {
        none,
        create_preset,
        delete_confirmation,
        rename_preset,
    };

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16, height: u16) !PresetManagementPanel {
        var panel = PresetManagementPanel{
            .allocator = allocator,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .presets = std.ArrayList(config.Preset){},
            .panel = components.Panel.init("Preset Management", x, y, width, height),
            .preset_list = components.List.init(allocator, x + 2, y + 2, width - 4, height - 10),
            .preset_name_input = components.InputField.init(allocator, x + 2, y + height - 6, width - 4),
            .action_dropdown = components.Dropdown.init(allocator, x + 2, y + height - 4, 20),
            .status_text = components.Text.init("Ready", x + 2, y + height - 2),
        };

        try panel.setupComponents();
        try panel.loadPresets();
        return panel;
    }

    pub fn deinit(self: *PresetManagementPanel) void {
        // Free any allocated preset names inside presets
        for (self.presets.items) |preset| {
            // Each preset is owned, free its name and deinit its config
            var p = preset;
            p.deinit(self.allocator);
        }
        self.presets.deinit(self.allocator);

        // Free list item texts (they may have been duplicated when adding to the list)
        for (self.preset_list.items.items) |item| {
            // item.text was allocated via allocator.dupe in loadPresets
            self.allocator.free(item.text);
        }
        self.preset_list.deinit();
        self.preset_name_input.deinit();
        self.action_dropdown.deinit();
    }

    fn setupComponents(self: *PresetManagementPanel) !void {
        // Setup action dropdown
        try self.action_dropdown.addOption("Load Preset", "load");
        try self.action_dropdown.addOption("Save New Preset", "save");
        try self.action_dropdown.addOption("Delete Preset", "delete");
        try self.action_dropdown.addOption("Rename Preset", "rename");

        // Setup input field
        self.preset_name_input.setValidator(components.validateNotEmpty);
        self.preset_name_input.setPlaceholder("Enter preset name...");
        self.preset_name_input.setVisible(false); // Hidden by default

        // Set initial focus
        self.updateFocus();
    }

    fn loadPresets(self: *PresetManagementPanel) !void {
        // Clear existing presets
        self.presets.clearRetainingCapacity();
        self.preset_list.clear();

        // Load presets from config system
        self.updateStatus("Loading presets...", .{}, renderer.Color.CYAN);

        var loaded_presets_map = config.presets.loadPresets(self.allocator) catch |err| {
            // Handle loading errors gracefully
            const error_msg = switch (err) {
                error.OutOfMemory => "Out of memory",
                error.AccessDenied => "Permission denied",
                error.FileNotFound => "Preset file not found (this is normal for first run)",
                else => @errorName(err),
            };
            self.updateStatus("Load error: {s}", .{error_msg}, renderer.Color.YELLOW);
            return; // Return with empty preset list
        };

        defer {
            var iterator = loaded_presets_map.iterator();
            while (iterator.next()) |entry| {
                var preset = entry.value_ptr.*;
                preset.deinit(self.allocator);
            }
            loaded_presets_map.deinit();
        }

        // Add presets to list
        var preset_count: usize = 0;
        var iterator = loaded_presets_map.iterator();
        while (iterator.next()) |entry| {
            const preset = entry.value_ptr.*;

            // Deep copy preset: duplicate name and colors so panel owns them
            const copied_name = try self.allocator.dupe(u8, preset.name);
            var copied_config: config.AnimationConfig = config.AnimationConfig{
                .animation_type = preset.config.animation_type,
                .fps = preset.config.fps,
                .speed = preset.config.speed,
                .colors = std.ArrayList(config.ColorFormat){},
                .direction = preset.config.direction,
            };

            // Copy colors
            for (preset.config.colors.items) |color| {
                const copied_color = config.ColorFormat{ .hex = try self.allocator.dupe(u8, color.hex) };
                try copied_config.colors.append(self.allocator, copied_color);
            }

            const owned_preset = config.Preset{
                .name = copied_name,
                .config = copied_config,
                .created_at = preset.created_at,
            };

            try self.presets.append(self.allocator, owned_preset);

            // Create display text with status indicator
            var display_buf: [128]u8 = undefined;
            const status_indicator = if (self.current_preset_name != null and
                std.mem.eql(u8, preset.name, self.current_preset_name.?)) " [ACTIVE]" else "";

            const display_text = try std.fmt.bufPrint(display_buf[0..], "{s}{s}", .{ owned_preset.name, status_indicator });

            // We need to allocate the display text since it goes out of scope
            const allocated_text = try self.allocator.dupe(u8, display_text);
            try self.preset_list.addItem(allocated_text);
            preset_count += 1;
        }

        if (preset_count == 0) {
            self.updateStatus("No presets found - create your first preset!", .{}, renderer.Color.CYAN);
        } else {
            self.updateStatus("Loaded {} presets", .{preset_count}, renderer.Color.GREEN);
        }
    }

    fn updateFocus(self: *PresetManagementPanel) void {
        // Clear all focus
        self.preset_list.setFocus(false);
        self.preset_name_input.setFocus(false);
        self.action_dropdown.setFocus(false);

        // Set focus based on dialog mode
        if (self.dialog_mode != DialogMode.none) {
            // In dialog mode, focus the input field
            self.preset_name_input.setFocus(true);
        } else {
            // Normal mode, focus based on focused_component
            switch (self.focused_component) {
                0 => self.preset_list.setFocus(true),
                1 => self.action_dropdown.setFocus(true),
                else => self.preset_list.setFocus(true),
            }
        }
    }

    fn updateStatus(self: *PresetManagementPanel, comptime fmt: []const u8, args: anytype, color: renderer.Color) void {
        var status_buf: [256]u8 = undefined;
        const status_text = std.fmt.bufPrint(status_buf[0..], fmt, args) catch "Status update failed";

        // We need to store this somewhere persistent since Text component doesn't own the string
        // For now, we'll use a simple approach
        self.last_status_message = status_text;
        self.status_color = color;
        self.status_text.setContent(self.last_status_message);
        self.status_text.setStyle(renderer.TextStyle{ .fg_color = color });
    }

    pub fn handleEvent(self: *PresetManagementPanel, event: events.Event) !bool {
        if (!self.visible) return false;

        // Handle dialog mode events
        if (self.dialog_mode != DialogMode.none) {
            return try self.handleDialogEvent(event);
        }

        // Handle global navigation
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .tab => {
                        // Move to next component
                        self.focused_component = (self.focused_component + 1) % self.component_count;
                        self.updateFocus();
                        return true;
                    },
                    .enter => {
                        // Execute selected action
                        if (self.focused_component == 1) { // Action dropdown focused
                            try self.executeAction();
                            return true;
                        }
                        return false;
                    },
                    .char => {
                        // Skip character handling if it's from an Enter key press
                        if (key_event.char) |c| {
                            if (c == '\r' or c == '\n') {
                                return false;
                            }
                            switch (c) {
                                'r', 'R' => {
                                    // Refresh preset list
                                    try self.loadPresets();
                                    return true;
                                },
                                't', 'T' => {
                                    // Test preset path (debug function)
                                    try self.testPresetPath();
                                    return true;
                                },
                                'l', 'L' => {
                                    // Quick load selected preset
                                    if (self.preset_list.getSelectedIndex()) |index| {
                                        try self.loadPreset(index);
                                    }
                                    return true;
                                },
                                'd', 'D' => {
                                    // Quick delete selected preset
                                    if (self.preset_list.getSelectedIndex()) |index| {
                                        self.startDeleteConfirmation(index);
                                    }
                                    return true;
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            },
        }

        // Handle component-specific events
        var handled = false;
        switch (self.focused_component) {
            0 => {
                handled = try self.preset_list.handleEvent(event);
            },
            1 => {
                handled = try self.action_dropdown.handleEvent(event);
            },
            else => {},
        }

        return handled;
    }

    fn handleDialogEvent(self: *PresetManagementPanel, event: events.Event) !bool {
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .escape => {
                        // Cancel dialog
                        self.cancelDialog();
                        return true;
                    },
                    .enter => {
                        // Confirm dialog action
                        try self.confirmDialog();
                        return true;
                    },
                    else => {
                        // Pass to input field if it's a text input dialog
                        if (self.dialog_mode == DialogMode.create_preset or
                            self.dialog_mode == DialogMode.rename_preset)
                        {
                            return try self.preset_name_input.handleEvent(event);
                        }
                    },
                }
            },
        }
        return false;
    }

    fn executeAction(self: *PresetManagementPanel) !void {
        const action_value = self.action_dropdown.getSelectedValue() orelse return;

        if (std.mem.eql(u8, action_value, "load")) {
            if (self.preset_list.getSelectedIndex()) |index| {
                try self.loadPreset(index);
            } else {
                self.updateStatus("No preset selected", .{}, renderer.Color.RED);
            }
        } else if (std.mem.eql(u8, action_value, "save")) {
            self.startCreatePreset();
        } else if (std.mem.eql(u8, action_value, "delete")) {
            if (self.preset_list.getSelectedIndex()) |index| {
                self.startDeleteConfirmation(index);
            } else {
                self.updateStatus("No preset selected", .{}, renderer.Color.RED);
            }
        } else if (std.mem.eql(u8, action_value, "rename")) {
            if (self.preset_list.getSelectedIndex()) |index| {
                self.startRenamePreset(index);
            } else {
                self.updateStatus("No preset selected", .{}, renderer.Color.RED);
            }
        }
    }

    fn loadPreset(self: *PresetManagementPanel, index: usize) !void {
        if (index >= self.presets.items.len) return;

        const preset = &self.presets.items[index];

        // Load the preset through the config system
        _ = try config.presets.loadPreset(self.allocator, preset.name);

        self.current_preset_name = preset.name;
        self.updateStatus("Loaded preset: {s}", .{preset.name}, renderer.Color.GREEN);

        // Refresh the list to show the active indicator
        try self.loadPresets();
    }

    fn startCreatePreset(self: *PresetManagementPanel) void {
        self.dialog_mode = DialogMode.create_preset;
        self.preset_name_input.clear();
        self.preset_name_input.setVisible(true);
        self.updateFocus();
        self.updateStatus("Enter name for new preset (Enter to confirm, Esc to cancel)", .{}, renderer.Color.CYAN);
    }

    fn startDeleteConfirmation(self: *PresetManagementPanel, index: usize) void {
        if (index >= self.presets.items.len) return;

        self.dialog_mode = DialogMode.delete_confirmation;
        self.selected_preset_index = index;
        self.preset_name_input.setVisible(false);
        self.updateFocus();

        const preset_name = self.presets.items[index].name;
        self.updateStatus("Delete preset '{s}'? (Enter to confirm, Esc to cancel)", .{preset_name}, renderer.Color.RED);
    }

    fn startRenamePreset(self: *PresetManagementPanel, index: usize) void {
        if (index >= self.presets.items.len) return;

        self.dialog_mode = DialogMode.rename_preset;
        self.selected_preset_index = index;

        // Pre-fill with current name
        const current_name = self.presets.items[index].name;
        self.preset_name_input.setText(current_name) catch {};
        self.preset_name_input.setVisible(true);
        self.updateFocus();

        self.updateStatus("Enter new name for preset (Enter to confirm, Esc to cancel)", .{}, renderer.Color.CYAN);
    }

    fn confirmDialog(self: *PresetManagementPanel) !void {
        switch (self.dialog_mode) {
            .create_preset => {
                if (self.preset_name_input.isValid() and self.preset_name_input.getText().len > 0) {
                    try self.createPreset(self.preset_name_input.getText());
                } else {
                    self.updateStatus("Invalid preset name", .{}, renderer.Color.RED);
                    return;
                }
            },
            .delete_confirmation => {
                if (self.selected_preset_index) |index| {
                    try self.deletePreset(index);
                }
            },
            .rename_preset => {
                if (self.selected_preset_index) |index| {
                    if (self.preset_name_input.isValid() and self.preset_name_input.getText().len > 0) {
                        try self.renamePreset(index, self.preset_name_input.getText());
                    } else {
                        self.updateStatus("Invalid preset name", .{}, renderer.Color.RED);
                        return;
                    }
                }
            },
            .none => return,
        }

        self.cancelDialog();
    }

    fn cancelDialog(self: *PresetManagementPanel) void {
        self.dialog_mode = DialogMode.none;
        self.selected_preset_index = null;
        self.preset_name_input.setVisible(false);
        self.updateFocus();
        self.updateStatus("Ready", .{}, renderer.Color.WHITE);
    }

    fn createPreset(self: *PresetManagementPanel, name: []const u8) !void {
        // Use the current config if available, otherwise create a default one
        var config_to_save: config.AnimationConfig = undefined;

        if (self.current_config) |current| {
            // Make a copy of the current config
            config_to_save = config.AnimationConfig{
                .animation_type = current.animation_type,
                .fps = current.fps,
                .speed = current.speed,
                .colors = std.ArrayList(config.ColorFormat){},
                .direction = current.direction,
            };

            // Copy colors
            for (current.colors.items) |color| {
                const copied_color = config.ColorFormat{ .hex = try self.allocator.dupe(u8, color.hex) };
                try config_to_save.colors.append(self.allocator, copied_color);
            }
        } else {
            // Create a default config with some colors
            config_to_save = config.AnimationConfig.default();
            config_to_save.colors = std.ArrayList(config.ColorFormat){};

            // Add some default colors
            const red_color = config.ColorFormat{ .hex = try self.allocator.dupe(u8, "#FF0000") };
            const blue_color = config.ColorFormat{ .hex = try self.allocator.dupe(u8, "#0000FF") };
            try config_to_save.colors.append(self.allocator, red_color);
            try config_to_save.colors.append(self.allocator, blue_color);
        }

        config.presets.savePreset(self.allocator, name, &config_to_save) catch |err| {
            // More detailed error reporting
            const error_msg = switch (err) {
                error.OutOfMemory => "Out of memory",
                error.AccessDenied => "Permission denied - check config directory permissions",
                error.FileNotFound => "Config directory not found",
                error.WriteError => "Failed to write preset file",
                else => @errorName(err),
            };
            self.updateStatus("Failed to save preset: {s}", .{error_msg}, renderer.Color.RED);
            return;
        };
        self.updateStatus("Created preset: {s}", .{name}, renderer.Color.GREEN);

        // Refresh the list
        try self.loadPresets();
    }

    fn deletePreset(self: *PresetManagementPanel, index: usize) !void {
        if (index >= self.presets.items.len) return;

        const preset_name = self.presets.items[index].name;

        try config.presets.deletePreset(self.allocator, preset_name);
        self.updateStatus("Deleted preset: {s}", .{preset_name}, renderer.Color.GREEN);

        // Refresh the list
        try self.loadPresets();
    }

    fn renamePreset(self: *PresetManagementPanel, index: usize, new_name: []const u8) !void {
        if (index >= self.presets.items.len) return;

        const old_name = self.presets.items[index].name;

        // Load the preset, delete the old one, save with new name
        const preset_config = try config.presets.loadPreset(self.allocator, old_name);
        try config.presets.deletePreset(self.allocator, old_name);
        try config.presets.savePreset(self.allocator, new_name, &preset_config);

        self.updateStatus("Renamed preset: {s} -> {s}", .{ old_name, new_name }, renderer.Color.GREEN);

        // Update current preset name if it was the active one
        if (self.current_preset_name != null and std.mem.eql(u8, self.current_preset_name.?, old_name)) {
            self.current_preset_name = new_name;
        }

        // Refresh the list
        try self.loadPresets();
    }

    pub fn render(self: *const PresetManagementPanel, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Render main panel
        try self.panel.render(r);

        // Render preset list
        try r.drawText(self.x + 2, self.y + 1, "Presets:", renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
            .bold = true,
        });
        try self.preset_list.render(r);

        // Render action dropdown
        try r.drawText(self.x + 2, self.y + self.height - 5, "Action:", renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
            .bold = true,
        });
        try self.action_dropdown.render(r);

        // Render input field if visible (dialog mode)
        if (self.preset_name_input.visible) {
            const input_label = switch (self.dialog_mode) {
                .create_preset => "New preset name:",
                .rename_preset => "Rename to:",
                else => "Input:",
            };

            try r.drawText(self.x + 2, self.y + self.height - 7, input_label, renderer.TextStyle{
                .fg_color = renderer.Color.CYAN,
                .bold = true,
            });
            try self.preset_name_input.render(r);
        }

        // Render status
        try self.status_text.render(r);

        // Render help text
        const help_text = if (self.dialog_mode != DialogMode.none)
            "Enter: Confirm | Esc: Cancel"
        else
            "Tab: Next | Enter: Execute | R: Refresh | L: Load | D: Delete | T: Test Path";

        try r.drawText(self.x + 2, self.y + self.height - 1, help_text, renderer.TextStyle{
            .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 },
        });

        // Render focus indicator
        if (self.dialog_mode == DialogMode.none) {
            const focus_indicator = ">";
            const indicator_style = renderer.TextStyle{
                .fg_color = renderer.Color.YELLOW,
                .bold = true,
            };

            const indicator_y = switch (self.focused_component) {
                0 => self.y + 2, // Preset list
                1 => self.y + self.height - 4, // Action dropdown
                else => self.y + 2,
            };

            try r.drawText(self.x, indicator_y, focus_indicator, indicator_style);
        }

        // Render dialog overlay if in dialog mode
        if (self.dialog_mode == DialogMode.delete_confirmation) {
            try self.renderDeleteConfirmationDialog(r);
        }
    }

    fn renderDeleteConfirmationDialog(self: *const PresetManagementPanel, r: *renderer.Renderer) !void {
        // Simple confirmation dialog overlay
        const dialog_width: u16 = 40;
        const dialog_height: u16 = 5;
        const dialog_x = self.x + (self.width - dialog_width) / 2;
        const dialog_y = self.y + (self.height - dialog_height) / 2;

        // Draw dialog background
        for (0..dialog_height) |row| {
            try r.moveCursor(dialog_x, dialog_y + @as(u16, @intCast(row)));
            try r.setTextStyle(renderer.TextStyle{
                .bg_color = renderer.Color{ .r = 32, .g = 32, .b = 32 },
                .fg_color = renderer.Color.WHITE,
            });

            var col: u16 = 0;
            while (col < dialog_width) : (col += 1) {
                try r.stdout_file.writeAll(" ");
            }
        }

        try r.resetStyle();

        // Draw dialog border
        try r.drawBox(dialog_x, dialog_y, dialog_width, dialog_height, renderer.BorderStyle.double);

        // Draw dialog content
        if (self.selected_preset_index) |index| {
            if (index < self.presets.items.len) {
                const preset_name = self.presets.items[index].name;

                try r.drawText(dialog_x + 2, dialog_y + 1, "Delete Preset?", renderer.TextStyle{
                    .fg_color = renderer.Color.RED,
                    .bold = true,
                });

                const name_text = if (preset_name.len > 30) preset_name[0..30] else preset_name;
                try r.drawText(dialog_x + 2, dialog_y + 2, name_text, renderer.TextStyle{
                    .fg_color = renderer.Color.WHITE,
                });

                try r.drawText(dialog_x + 2, dialog_y + 3, "Enter: Yes | Esc: No", renderer.TextStyle{
                    .fg_color = renderer.Color.CYAN,
                });
            }
        }
    }

    pub fn setVisible(self: *PresetManagementPanel, visible: bool) void {
        self.visible = visible;
        self.panel.setVisible(visible);
    }

    pub fn setCurrentPreset(self: *PresetManagementPanel, preset_name: ?[]const u8) !void {
        self.current_preset_name = preset_name;
        try self.loadPresets(); // Refresh to show active indicator
    }

    pub fn setCurrentConfig(self: *PresetManagementPanel, current_config: *const config.AnimationConfig) void {
        self.current_config = current_config;
    }

    pub fn getSelectedPresetName(self: *const PresetManagementPanel) ?[]const u8 {
        if (self.preset_list.getSelectedIndex()) |index| {
            if (index < self.presets.items.len) {
                return self.presets.items[index].name;
            }
        }
        return null;
    }

    fn testPresetPath(self: *PresetManagementPanel) !void {
        // Debug function to test preset path and directory
        const preset_path = config.presets.getPresetsPath(self.allocator) catch |err| {
            self.updateStatus("Error getting preset path: {s}", .{@errorName(err)}, renderer.Color.RED);
            return;
        };
        defer self.allocator.free(preset_path);

        // Check if directory exists
        const config_dir = config.persistence.getConfigDir(self.allocator) catch |err| {
            self.updateStatus("Error getting config dir: {s}", .{@errorName(err)}, renderer.Color.RED);
            return;
        };
        defer self.allocator.free(config_dir);

        const hypr_dir = try std.fmt.allocPrint(self.allocator, "{s}/hyprgborder", .{config_dir});
        defer self.allocator.free(hypr_dir);

        // Try to access the directory
        std.fs.accessAbsolute(hypr_dir, .{}) catch |err| {
            if (err == error.FileNotFound) {
                self.updateStatus("Config dir doesn't exist: {s}", .{hypr_dir}, renderer.Color.YELLOW);
                return;
            } else {
                self.updateStatus("Config dir error: {s}", .{@errorName(err)}, renderer.Color.RED);
                return;
            }
        };

        // Check if preset file exists
        std.fs.accessAbsolute(preset_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                self.updateStatus("Preset file doesn't exist yet: {s}", .{preset_path}, renderer.Color.CYAN);
                return;
            } else {
                self.updateStatus("Preset file error: {s}", .{@errorName(err)}, renderer.Color.RED);
                return;
            }
        };

        self.updateStatus("Preset path OK: {s}", .{preset_path}, renderer.Color.GREEN);
    }

    pub fn setPosition(self: *PresetManagementPanel, x: u16, y: u16) void {
        const dx = @as(i32, x) - @as(i32, self.x);
        const dy = @as(i32, y) - @as(i32, self.y);

        self.x = x;
        self.y = y;

        // Update all component positions
        self.panel.x = x;
        self.panel.y = y;

        self.preset_list.setPosition(@as(u16, @intCast(@as(i32, self.preset_list.x) + dx)), @as(u16, @intCast(@as(i32, self.preset_list.y) + dy)));

        self.preset_name_input.setPosition(@as(u16, @intCast(@as(i32, self.preset_name_input.x) + dx)), @as(u16, @intCast(@as(i32, self.preset_name_input.y) + dy)));

        self.action_dropdown.setPosition(@as(u16, @intCast(@as(i32, self.action_dropdown.x) + dx)), @as(u16, @intCast(@as(i32, self.action_dropdown.y) + dy)));

        self.status_text.setPosition(@as(u16, @intCast(@as(i32, self.status_text.x) + dx)), @as(u16, @intCast(@as(i32, self.status_text.y) + dy)));
    }
};
