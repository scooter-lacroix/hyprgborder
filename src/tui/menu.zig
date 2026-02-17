//! Interactive menu system for CLI configuration
//! Provides hierarchical menu navigation with live preview integration

const std = @import("std");
const config = @import("config");
const preview = @import("preview.zig");

pub const MenuAction = union(enum) {
    submenu: []MenuItem,
    config_change: ConfigChange,
    preset_action: PresetAction,
    system_action: SystemAction,
};

pub const ConfigChange = struct {
    field: []const u8,
    value: []const u8,
};

pub const PresetAction = enum {
    load,
    save,
    delete,
    list,
};

pub const SystemAction = enum {
    environment_check,
    install_autostart,
    remove_autostart,
    help,
};

pub const MenuItem = struct {
    label: []const u8,
    action: MenuAction,
    preview_fn: ?*const fn (*const MenuItem) void = null,
};

pub const MenuSystem = struct {
    allocator: std.mem.Allocator,
    current_menu: []MenuItem,
    menu_stack: std.ArrayList([]MenuItem),
    preview_manager: ?*preview.PreviewManager = null,

    pub fn init(allocator: std.mem.Allocator) MenuSystem {
        return MenuSystem{
            .allocator = allocator,
            .current_menu = &[_]MenuItem{},
            .menu_stack = .{},
        };
    }

    pub fn setPreviewManager(self: *MenuSystem, preview_mgr: *preview.PreviewManager) void {
        self.preview_manager = preview_mgr;
    }

    pub fn navigate(self: *MenuSystem, selection: usize) !void {
        if (selection >= self.current_menu.len) return error.InvalidSelection;

        const item = &self.current_menu[selection];

        // Execute preview function if available
        if (item.preview_fn) |preview_fn| {
            preview_fn(item);
        }

        switch (item.action) {
            .submenu => |submenu| {
                try self.menu_stack.append(self.allocator, self.current_menu);
                self.current_menu = submenu;
            },
            .config_change => |change| {
                // Handle configuration changes
                _ = change; // TODO: Implement config change handling
            },
            .preset_action => |action| {
                // Handle preset actions
                _ = action; // TODO: Implement preset action handling
            },
            .system_action => |action| {
                // Handle system actions
                _ = action; // TODO: Implement system action handling
            },
        }
    }

    pub fn goBack(self: *MenuSystem) !void {
        if (self.menu_stack.items.len == 0) return error.NoParentMenu;

        self.current_menu = self.menu_stack.pop();
    }

    pub fn render(self: *const MenuSystem) !void {
        std.debug.print("\n=== HyprGBorder Configuration ===\n\n", .{});

        for (self.current_menu, 0..) |item, i| {
            std.debug.print("  {d}) {s}\n", .{ i + 1, item.label });
        }

        if (self.menu_stack.items.len > 0) {
            std.debug.print("  0) Back\n");
        }

        std.debug.print("\nSelect an option: ", .{});
    }

    pub fn deinit(self: *MenuSystem) void {
        self.menu_stack.deinit(self.allocator);
    }
};
