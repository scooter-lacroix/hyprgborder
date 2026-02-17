//! System Settings Panel - System configuration options including autostart
//! Provides controls for autostart toggle and system status display

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");
const components = @import("../components/mod.zig");
const config = @import("config");
const utils = @import("utils");

pub const SystemSettingsPanel = struct {
    allocator: std.mem.Allocator,
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    // UI Components
    panel: components.Panel,
    status_text: components.Text,

    // State
    autostart_enabled: bool,
    status_message: ?[]const u8 = null,
    status_color: renderer.Color = renderer.Color.WHITE,

    // Focus management
    focused_item: usize = 0,
    item_count: usize = 3, // Autostart toggle, Apply, Back
    visible: bool = true,

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16, height: u16) !SystemSettingsPanel {
        return SystemSettingsPanel{
            .allocator = allocator,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .panel = components.Panel.init("System Settings", x, y, width, height),
            .status_text = components.Text.init("Configure system options", x + 2, y + height - 3),
            .autostart_enabled = utils.autostart.isAutostartEnabled(allocator),
        };
    }

    pub fn deinit(self: *SystemSettingsPanel) void {
        if (self.status_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn handleEvent(self: *SystemSettingsPanel, event: events.Event) !bool {
        if (!self.visible) return false;

        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .up => {
                        if (self.focused_item > 0) {
                            self.focused_item -= 1;
                        }
                        return true;
                    },
                    .down => {
                        if (self.focused_item < self.item_count - 1) {
                            self.focused_item += 1;
                        }
                        return true;
                    },
                    .tab => {
                        self.focused_item = (self.focused_item + 1) % self.item_count;
                        return true;
                    },
                    .enter => {
                        return try self.activateItem();
                    },
                    .char => {
                        if (key_event.char) |c| {
                            switch (c) {
                                'a', 'A' => {
                                    // Quick toggle autostart
                                    try self.toggleAutostart();
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

        return false;
    }

    fn activateItem(self: *SystemSettingsPanel) !bool {
        switch (self.focused_item) {
            0 => try self.toggleAutostart(),
            1 => try self.applySettings(),
            2 => {
                // Back - handled by parent
                return false;
            },
            else => {},
        }
        return true;
    }

    fn toggleAutostart(self: *SystemSettingsPanel) !void {
        const new_state = utils.autostart.toggleAutostart(self.allocator) catch |err| {
            self.setStatus("Error: {s}", .{utils.autostart.getErrorMessage(err)}, renderer.Color.RED);
            return;
        };

        self.autostart_enabled = new_state;

        if (new_state) {
            self.setStatus("Autostart enabled - will start on login", .{}, renderer.Color.GREEN);
        } else {
            self.setStatus("Autostart disabled", .{}, renderer.Color.YELLOW);
        }
    }

    fn applySettings(self: *SystemSettingsPanel) !void {
        // Settings are applied immediately, but this can be used for batch operations
        self.setStatus("Settings saved!", .{}, renderer.Color.GREEN);
    }

    fn setStatus(self: *SystemSettingsPanel, comptime fmt: []const u8, args: anytype, color: renderer.Color) void {
        if (self.status_message) |msg| {
            self.allocator.free(msg);
        }

        self.status_message = std.fmt.allocPrint(self.allocator, fmt, args) catch null;
        self.status_color = color;

        if (self.status_message) |msg| {
            self.status_text.setContent(msg);
            self.status_text.setStyle(renderer.TextStyle{ .fg_color = color });
        }
    }

    pub fn render(self: *const SystemSettingsPanel, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Render main panel
        try self.panel.render(r);

        var y = self.y + 2;

        // Title
        try r.drawText(self.x + 2, y, "System Configuration", renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
            .bold = true,
        });
        y += 2;

        // Autostart option
        const autostart_label = "Autostart";
        const autostart_status = if (self.autostart_enabled) " [ENABLED]" else " [DISABLED]";
        const autostart_color = if (self.autostart_enabled) renderer.Color.GREEN else renderer.Color.RED;

        // Draw focus indicator
        if (self.focused_item == 0) {
            try r.drawText(self.x, y, ">", renderer.TextStyle{
                .fg_color = renderer.Color.YELLOW,
                .bold = true,
            });
        }

        try r.drawText(self.x + 2, y, autostart_label, renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
        });
        const status_x = self.x + 2 + @as(u16, @intCast(autostart_label.len)) + 1;
        try r.drawText(status_x, y, autostart_status, renderer.TextStyle{
            .fg_color = autostart_color,
            .bold = true,
        });
        y += 1;

        try r.drawText(self.x + 4, y, "(Toggle: Enter or A)", renderer.TextStyle{
            .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 },
        });
        y += 2;

        // Description
        try r.drawText(self.x + 2, y, "When enabled, HyprGBorder will automatically", renderer.TextStyle{
            .fg_color = renderer.Color{ .r = 160, .g = 160, .b = 160 },
        });
        y += 1;
        try r.drawText(self.x + 2, y, "start when you log in to your desktop.", renderer.TextStyle{
            .fg_color = renderer.Color{ .r = 160, .g = 160, .b = 160 },
        });
        y += 3;

        // Apply button
        if (self.focused_item == 1) {
            try r.drawText(self.x, y, ">", renderer.TextStyle{
                .fg_color = renderer.Color.YELLOW,
                .bold = true,
            });
        }
        try r.drawText(self.x + 2, y, "[ Apply Settings ]", renderer.TextStyle{
            .fg_color = if (self.focused_item == 1) renderer.Color.CYAN else renderer.Color.WHITE,
        });
        y += 2;

        // Back button
        if (self.focused_item == 2) {
            try r.drawText(self.x, y, ">", renderer.TextStyle{
                .fg_color = renderer.Color.YELLOW,
                .bold = true,
            });
        }
        try r.drawText(self.x + 2, y, "[ Back to Main Menu ]", renderer.TextStyle{
            .fg_color = if (self.focused_item == 2) renderer.Color.CYAN else renderer.Color.WHITE,
        });
        y += 3;

        // Current status section
        try r.drawText(self.x + 2, y, "System Status:", renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
            .bold = true,
        });
        y += 1;

        // Check Hyprland status
        const hypr_running = utils.environment.isHyprlandRunning(self.allocator);
        const hypr_status = if (hypr_running) "Running" else "Not Running";
        const hypr_color = if (hypr_running) renderer.Color.GREEN else renderer.Color.RED;

        const hypr_text = try std.fmt.allocPrint(self.allocator, "  Hyprland: {s}", .{hypr_status});
        defer self.allocator.free(hypr_text);
        try r.drawText(self.x + 2, y, hypr_text, renderer.TextStyle{
            .fg_color = hypr_color,
        });
        y += 1;

        // Autostart file location
        const autostart_dir = utils.autostart.getAutostartDir(self.allocator) catch "Unknown";
        defer if (autostart_dir.len > 0 and autostart_dir[0] != 'U') self.allocator.free(autostart_dir);

        const dir_text = try std.fmt.allocPrint(self.allocator, "  Autostart dir: {s}", .{autostart_dir});
        defer self.allocator.free(dir_text);
        try r.drawText(self.x + 2, y, dir_text, renderer.TextStyle{
            .fg_color = renderer.Color{ .r = 160, .g = 160, .b = 160 },
        });

        // Status bar
        try self.status_text.render(r);

        // Help text
        try r.drawText(self.x + 2, self.y + self.height - 1, "↑↓: Navigate | Enter: Select | A: Toggle Autostart | Esc: Back", renderer.TextStyle{
            .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 },
        });
    }

    pub fn setVisible(self: *SystemSettingsPanel, visible: bool) void {
        self.visible = visible;
        self.panel.setVisible(visible);
    }

    pub fn refresh(self: *SystemSettingsPanel) void {
        self.autostart_enabled = utils.autostart.isAutostartEnabled(self.allocator);
    }

    pub fn setPosition(self: *SystemSettingsPanel, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
        self.panel.x = x;
        self.panel.y = y;
        self.status_text.setPosition(self.x + 2, self.y + self.height - 3);
    }

    pub fn shouldGoBack(self: *const SystemSettingsPanel) bool {
        return self.focused_item == 2;
    }
};
