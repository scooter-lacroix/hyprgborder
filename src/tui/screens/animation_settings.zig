//! Animation Settings Panel - Visual controls for animation configuration
//! Provides interactive controls for animation type, speed, FPS, colors, and gradients

const std = @import("std");
const renderer = @import("../renderer.zig");
const events = @import("../events.zig");
const components = @import("../components/mod.zig");
const config = @import("config");
const animations = @import("animations");

pub const AnimationSettingsPanel = struct {
    allocator: std.mem.Allocator,
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    // Animation configuration
    animation_config: config.AnimationConfig,

    // UI Components
    panel: components.Panel,
    animation_type_dropdown: components.Dropdown,
    speed_input: components.InputField,
    fps_input: components.InputField,
    primary_color_picker: components.ColorPicker,
    secondary_color_picker: components.ColorPicker,
    gradient_angle_input: components.InputField,
    shadow_color_picker: components.ColorPicker,

    // Preview components
    preview_progress: components.AnimatedProgressBar,

    // Focus management
    focused_component: usize = 0,
    component_count: usize = 7,
    visible: bool = true,

    // Live preview state
    preview_enabled: bool = true,
    last_update_time: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, x: u16, y: u16, width: u16, height: u16) !AnimationSettingsPanel {
        var panel = AnimationSettingsPanel{
            .allocator = allocator,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .animation_config = config.AnimationConfig.default(),
            .panel = components.Panel.init("Animation Settings", x, y, width, height),
            .animation_type_dropdown = components.Dropdown.init(allocator, x + 2, y + 2, 20),
            .speed_input = components.InputField.init(allocator, x + 2, y + 4, 10),
            .fps_input = components.InputField.init(allocator, x + 2, y + 6, 10),
            .primary_color_picker = components.ColorPicker.init(allocator, x + 2, y + 8, 25, 8),
            .secondary_color_picker = components.ColorPicker.init(allocator, x + 30, y + 8, 25, 8),
            .gradient_angle_input = components.InputField.init(allocator, x + 2, y + 17, 10),
            .shadow_color_picker = components.ColorPicker.init(allocator, x + 2, y + 19, 25, 8),
            .preview_progress = components.AnimatedProgressBar.init(x + 2, y + height - 4, width - 4),
        };

        try panel.setupComponents();
        // Apply initial config values now that setup is complete
        try panel.updateComponentsFromConfig();
        return panel;
    }

    pub fn deinit(self: *AnimationSettingsPanel) void {
        self.animation_type_dropdown.deinit();
        self.speed_input.deinit();
        self.fps_input.deinit();
        self.primary_color_picker.deinit();
        self.secondary_color_picker.deinit();
        self.gradient_angle_input.deinit();
        self.shadow_color_picker.deinit();
        // Free any allocated strings in the animation config
        self.animation_config.deinit(self.allocator);
    }

    fn setupComponents(self: *AnimationSettingsPanel) !void {
        // Setup animation type dropdown
        try self.animation_type_dropdown.addOption("Rainbow", "rainbow");
        try self.animation_type_dropdown.addOption("Pulse", "pulse");
        try self.animation_type_dropdown.addOption("None", "none");
        try self.animation_type_dropdown.addOption("Gradient", "gradient");
        try self.animation_type_dropdown.addOption("Solid", "solid");

        // Setup input field validators and placeholders
        self.speed_input.setValidator(components.validateFloat);
        self.speed_input.setPlaceholder("1.0");

        self.fps_input.setValidator(components.validateFpsInput);
        self.fps_input.setPlaceholder("60");

        self.gradient_angle_input.setValidator(components.validateNumber);
        self.gradient_angle_input.setPlaceholder("45");

        // Set initial values from config will be performed by init after setup
        // Setup preview
        self.preview_progress.setLabel("Preview:");
        self.preview_progress.setShowPercentage(false);
        self.preview_progress.setTargetProgress(0.7);

        // Set initial focus (will be re-applied after config update)
        self.updateFocus();
    }

    fn updateComponentsFromConfig(self: *AnimationSettingsPanel) !void {
        // Set animation type
        const type_str = switch (self.animation_config.animation_type) {
            .rainbow => "rainbow",
            .pulse => "pulse",
            .none => "none",
            .gradient => "gradient",
            .solid => "solid",
        };
        _ = self.animation_type_dropdown.setSelectedByValue(type_str);

        // Set speed
        var speed_buf: [16]u8 = undefined;
        const speed_text = try std.fmt.bufPrint(speed_buf[0..], "{d:.2}", .{self.animation_config.speed});
        try self.speed_input.setText(speed_text);

        // Set FPS
        var fps_buf: [8]u8 = undefined;
        const fps_text = try std.fmt.bufPrint(fps_buf[0..], "{d}", .{self.animation_config.fps});
        try self.fps_input.setText(fps_text);

        // Set colors from the colors array
        if (self.animation_config.colors.items.len > 0) {
            // Convert first color to RGB for primary color picker
            const primary_hex = try self.animation_config.colors.items[0].toHex(self.allocator);
            defer self.allocator.free(primary_hex);
            if (primary_hex.len >= 7) {
                const r = std.fmt.parseInt(u8, primary_hex[1..3], 16) catch 255;
                const g = std.fmt.parseInt(u8, primary_hex[3..5], 16) catch 255;
                const b = std.fmt.parseInt(u8, primary_hex[5..7], 16) catch 255;
                self.primary_color_picker.setColor(renderer.Color{ .r = r, .g = g, .b = b });
            }
        }

        if (self.animation_config.colors.items.len > 1) {
            // Convert second color to RGB for secondary color picker
            const secondary_hex = try self.animation_config.colors.items[1].toHex(self.allocator);
            defer self.allocator.free(secondary_hex);
            if (secondary_hex.len >= 7) {
                const r = std.fmt.parseInt(u8, secondary_hex[1..3], 16) catch 255;
                const g = std.fmt.parseInt(u8, secondary_hex[3..5], 16) catch 255;
                const b = std.fmt.parseInt(u8, secondary_hex[5..7], 16) catch 255;
                self.secondary_color_picker.setColor(renderer.Color{ .r = r, .g = g, .b = b });
            }
        }

        // For shadow color, use a default or third color if available
        if (self.animation_config.colors.items.len > 2) {
            const shadow_hex = try self.animation_config.colors.items[2].toHex(self.allocator);
            defer self.allocator.free(shadow_hex);
            if (shadow_hex.len >= 7) {
                const r = std.fmt.parseInt(u8, shadow_hex[1..3], 16) catch 0;
                const g = std.fmt.parseInt(u8, shadow_hex[3..5], 16) catch 0;
                const b = std.fmt.parseInt(u8, shadow_hex[5..7], 16) catch 0;
                self.shadow_color_picker.setColor(renderer.Color{ .r = r, .g = g, .b = b });
            }
        } else {
            // Default shadow color
            self.shadow_color_picker.setColor(renderer.Color{ .r = 64, .g = 64, .b = 64 });
        }

        // Set gradient angle (placeholder - not in current config)
        try self.gradient_angle_input.setText("45");

        // Adjust visibility of color-related controls based on animation type
        switch (self.animation_config.animation_type) {
            .rainbow => {
                self.primary_color_picker.setVisible(false);
                self.secondary_color_picker.setVisible(false);
                self.gradient_angle_input.setVisible(false);
                self.shadow_color_picker.setVisible(true);
            },
            .pulse => {
                self.primary_color_picker.setVisible(true);
                self.secondary_color_picker.setVisible(false);
                self.gradient_angle_input.setVisible(false);
                self.shadow_color_picker.setVisible(true);
            },
            .gradient => {
                self.primary_color_picker.setVisible(true);
                self.secondary_color_picker.setVisible(true);
                self.gradient_angle_input.setVisible(true);
                self.shadow_color_picker.setVisible(true);
            },
            .solid => {
                self.primary_color_picker.setVisible(true);
                self.secondary_color_picker.setVisible(false);
                self.gradient_angle_input.setVisible(false);
                self.shadow_color_picker.setVisible(true);
            },
            .none => {
                // No animation: hide color and gradient controls
                self.primary_color_picker.setVisible(false);
                self.secondary_color_picker.setVisible(false);
                self.gradient_angle_input.setVisible(false);
                self.shadow_color_picker.setVisible(false);
            },
        }

        // Keep component_count static and let tab skip invisible components
        self.component_count = 7;

        // Reflow layout: compute y positions for controls based on visibility
        const base_top = self.y;
        const anim_type_y = base_top + 2;
        const speed_y = base_top + 4;
        const fps_y = base_top + 6;

        // Restore fixed positions (keep inputs within the panel bounds)
        self.primary_color_picker.setPosition(self.x + 2, self.y + 8);
        self.secondary_color_picker.setPosition(self.x + 30, self.y + 8);
        self.gradient_angle_input.setPosition(self.x + 2, self.y + 17);
        self.shadow_color_picker.setPosition(self.x + 2, self.y + 19);

        // Ensure dropdown, speed and fps stay at their anchor positions
        self.animation_type_dropdown.setPosition(self.x + 2, anim_type_y);
        self.speed_input.setPosition(self.x + 2, speed_y);
        self.fps_input.setPosition(self.x + 2, fps_y);

        // Ensure focused component is visible; if not, move to next visible
        if (!self.isComponentVisible(self.focused_component)) {
            var i: usize = 0;
            var found = false;
            while (i < self.component_count) : (i += 1) {
                if (self.isComponentVisible(i)) {
                    self.focused_component = i;
                    found = true;
                    break;
                }
            }
            if (!found) self.focused_component = 0;
        }

        self.updateFocus();
    }

    fn getIndicatorPosition(self: *const AnimationSettingsPanel, idx: usize) [2]u16 {
        const base_top = self.y;
        const anim_type_y = base_top + 2;
        const speed_y = base_top + 4;
        const fps_y = base_top + 6;
        return switch (idx) {
            0 => [2]u16{ self.x, anim_type_y },
            1 => [2]u16{ self.x, speed_y },
            2 => [2]u16{ self.x, fps_y },
            3 => [2]u16{ self.x, self.y + 8 },
            4 => [2]u16{ self.x + 28, self.y + 8 },
            5 => [2]u16{ self.x, self.y + 17 },
            6 => [2]u16{ self.x, self.y + 19 },
            else => [2]u16{ self.x, anim_type_y },
        };
    }

    fn isComponentVisible(self: *const AnimationSettingsPanel, idx: usize) bool {
        return switch (idx) {
            0 => true,
            1 => true,
            2 => true,
            3 => self.primary_color_picker.visible,
            4 => self.secondary_color_picker.visible,
            5 => self.gradient_angle_input.visible,
            6 => self.shadow_color_picker.visible,
            else => false,
        };
    }

    fn updateConfigFromComponents(self: *AnimationSettingsPanel) !void {
        // Update animation type
        if (self.animation_type_dropdown.getSelectedValue()) |type_str| {
            self.animation_config.animation_type = if (std.mem.eql(u8, type_str, "rainbow"))
                config.AnimationType.rainbow
            else if (std.mem.eql(u8, type_str, "pulse"))
                config.AnimationType.pulse
            else if (std.mem.eql(u8, type_str, "none"))
                config.AnimationType.none
            else if (std.mem.eql(u8, type_str, "gradient"))
                config.AnimationType.gradient
            else
                config.AnimationType.solid;
        }

        // Update speed
        if (self.speed_input.isValid()) {
            self.animation_config.speed = std.fmt.parseFloat(f64, self.speed_input.getText()) catch 1.0;
        }

        // Update FPS
        if (self.fps_input.isValid()) {
            self.animation_config.fps = std.fmt.parseInt(u32, self.fps_input.getText(), 10) catch 60;
        }

        // Update colors array - properly clean up old colors first
        for (self.animation_config.colors.items) |color| {
            switch (color) {
                .hex => |hex_str| self.allocator.free(hex_str),
                else => {},
            }
        }
        self.animation_config.colors.clearRetainingCapacity();

        // Add primary/secondary/shadow colors only for visible pickers
        if (self.primary_color_picker.visible) {
            const primary_color = self.primary_color_picker.getColor();
            var primary_hex_buf: [8]u8 = undefined;
            const primary_hex = std.fmt.bufPrint(primary_hex_buf[0..], "#{X:0>2}{X:0>2}{X:0>2}", .{ primary_color.r, primary_color.g, primary_color.b }) catch "#FF0000";
            const primary_color_format = config.ColorFormat{ .hex = try self.allocator.dupe(u8, primary_hex) };
            try self.animation_config.colors.append(self.allocator, primary_color_format);
        }

        if (self.secondary_color_picker.visible) {
            const secondary_color = self.secondary_color_picker.getColor();
            var secondary_hex_buf: [8]u8 = undefined;
            const secondary_hex = std.fmt.bufPrint(secondary_hex_buf[0..], "#{X:0>2}{X:0>2}{X:0>2}", .{ secondary_color.r, secondary_color.g, secondary_color.b }) catch "#00FF00";
            const secondary_color_format = config.ColorFormat{ .hex = try self.allocator.dupe(u8, secondary_hex) };
            try self.animation_config.colors.append(self.allocator, secondary_color_format);
        }

        if (self.shadow_color_picker.visible) {
            const shadow_color = self.shadow_color_picker.getColor();
            var shadow_hex_buf: [8]u8 = undefined;
            const shadow_hex = std.fmt.bufPrint(shadow_hex_buf[0..], "#{X:0>2}{X:0>2}{X:0>2}", .{ shadow_color.r, shadow_color.g, shadow_color.b }) catch "#404040";
            const shadow_color_format = config.ColorFormat{ .hex = try self.allocator.dupe(u8, shadow_hex) };
            try self.animation_config.colors.append(self.allocator, shadow_color_format);
        }

        // Update gradient angle (placeholder - not stored in current config)
        _ = self.gradient_angle_input.isValid(); // Just validate but don't store

        // Update preview colors based on current settings
        self.updatePreviewColors();
    }

    fn updatePreviewColors(self: *AnimationSettingsPanel) void {
        // Update preview progress bar colors based on animation type
        switch (self.animation_config.animation_type) {
            .rainbow => {
                // Use a rainbow-like color progression
                self.preview_progress.base.setColors(renderer.Color.RED, renderer.Color{ .r = 64, .g = 64, .b = 64 });
            },
            .pulse => {
                // Use primary color for pulse
                const primary_color = self.primary_color_picker.getColor();
                self.preview_progress.base.setColors(primary_color, renderer.Color{ .r = 32, .g = 32, .b = 32 });
            },
            .gradient => {
                // Use primary to secondary gradient
                const primary_color = self.primary_color_picker.getColor();
                const secondary_color = self.secondary_color_picker.getColor();
                self.preview_progress.base.setColors(primary_color, secondary_color);
            },
            .solid => {
                // Use primary color only
                const primary_color = self.primary_color_picker.getColor();
                self.preview_progress.base.setColors(primary_color, renderer.Color{ .r = 48, .g = 48, .b = 48 });
            },
            .none => {
                // Static / no animation: use neutral colors
                self.preview_progress.base.setColors(renderer.Color{ .r = 64, .g = 64, .b = 64 }, renderer.Color{ .r = 32, .g = 32, .b = 32 });
            },
        }
    }

    fn updateFocus(self: *AnimationSettingsPanel) void {
        // Clear all focus
        self.animation_type_dropdown.setFocus(false);
        self.speed_input.setFocus(false);
        self.fps_input.setFocus(false);
        self.primary_color_picker.setFocus(false);
        self.secondary_color_picker.setFocus(false);
        self.gradient_angle_input.setFocus(false);
        self.shadow_color_picker.setFocus(false);

        // Set focus on current component (only if visible)
        switch (self.focused_component) {
            0 => self.animation_type_dropdown.setFocus(true),
            1 => self.speed_input.setFocus(true),
            2 => self.fps_input.setFocus(true),
            3 => if (self.primary_color_picker.visible) self.primary_color_picker.setFocus(true),
            4 => if (self.secondary_color_picker.visible) self.secondary_color_picker.setFocus(true),
            5 => if (self.gradient_angle_input.visible) self.gradient_angle_input.setFocus(true),
            6 => if (self.shadow_color_picker.visible) self.shadow_color_picker.setFocus(true),
            else => self.animation_type_dropdown.setFocus(true),
        }
    }

    pub fn handleEvent(self: *AnimationSettingsPanel, event: events.Event) !bool {
        if (!self.visible) return false;

        // Try component-specific handling first for components that may want
        // to consume Tab (ColorPicker uses Tab to switch modes).
        var focused_handled = false;
        switch (self.focused_component) {
            3 => focused_handled = try self.primary_color_picker.handleEvent(event),
            4 => focused_handled = try self.secondary_color_picker.handleEvent(event),
            6 => focused_handled = try self.shadow_color_picker.handleEvent(event),
            else => focused_handled = false,
        }

        if (focused_handled) {
            try self.updateConfigFromComponents();
            // Also refresh UI components (visibility/positions) from the updated config
            try self.updateComponentsFromConfig();
            return true;
        }

        // Handle global navigation (Tab moves between visible components)
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .tab => {
                        // Move to next visible component
                        var next_idx = (self.focused_component + 1) % self.component_count;
                        var tries: usize = 0;
                        while (!self.isComponentVisible(next_idx) and tries < self.component_count) : (tries += 1) {
                            next_idx = (next_idx + 1) % self.component_count;
                        }
                        self.focused_component = next_idx;
                        self.updateFocus();
                        return true;
                    },
                    .char => {
                        if (key_event.char) |c| {
                            if (c == 'p' or c == 'P') {
                                // Toggle preview
                                self.preview_enabled = !self.preview_enabled;
                                return true;
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
                handled = try self.animation_type_dropdown.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                    // When the animation type changes, refresh component visibility and layout
                    try self.updateComponentsFromConfig();
                }
            },
            1 => {
                handled = try self.speed_input.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                }
            },
            2 => {
                handled = try self.fps_input.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                }
            },
            3 => {
                // primary was already attempted above for Tab; still forward other events
                handled = try self.primary_color_picker.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                }
            },
            4 => {
                handled = try self.secondary_color_picker.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                }
            },
            5 => {
                handled = try self.gradient_angle_input.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                }
            },
            6 => {
                handled = try self.shadow_color_picker.handleEvent(event);
                if (handled) {
                    try self.updateConfigFromComponents();
                }
            },
            else => {},
        }

        return handled;
    }

    pub fn update(self: *AnimationSettingsPanel, current_time: i64) void {
        if (!self.preview_enabled) return;

        const delta_time = if (self.last_update_time > 0)
            @as(f32, @floatFromInt(current_time - self.last_update_time)) / 1000.0
        else
            0.016; // ~60 FPS fallback

        self.last_update_time = current_time;

        // Update animated preview
        self.preview_progress.update(delta_time);

        // Animate the preview target based on animation type
        const time_factor = @as(f32, @floatFromInt(@mod(current_time, 3000))) / 3000.0; // 3 second cycle

        switch (self.animation_config.animation_type) {
            .pulse => {
                // Pulsing progress
                const pulse = (std.math.sin(time_factor * 2.0 * std.math.pi) + 1.0) / 2.0;
                self.preview_progress.setTargetProgress(0.3 + pulse * 0.4);
            },
            .rainbow => {
                // Steady progress with color changes (simulated)
                self.preview_progress.setTargetProgress(0.7);
            },
            .gradient => {
                // Gradient sweep effect
                const sweep = (std.math.sin(time_factor * std.math.pi) + 1.0) / 2.0;
                self.preview_progress.setTargetProgress(0.2 + sweep * 0.6);
            },
            .solid => {
                // Static progress
                self.preview_progress.setTargetProgress(0.5);
            },
            .none => {
                // No animation selected: keep preview static
                self.preview_progress.setTargetProgress(0.0);
            },
        }
    }

    pub fn render(self: *const AnimationSettingsPanel, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        // Render main panel
        try self.panel.render(r);

        // Render labels and components
        const label_style = renderer.TextStyle{
            .fg_color = renderer.Color.WHITE,
            .bold = true,
        };

        // Animation Type
        try r.drawText(self.x + 2, self.y + 1, "Animation Type:", label_style);
        try self.animation_type_dropdown.render(r);

        // Speed
        try r.drawText(self.x + 2, self.y + 3, "Speed:", label_style);
        try self.speed_input.render(r);
        try r.drawText(self.x + 14, self.y + 4, "(0.1 - 2.0)", renderer.TextStyle{ .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 } });

        // FPS
        try r.drawText(self.x + 2, self.y + 5, "FPS:", label_style);
        try self.fps_input.render(r);
        try r.drawText(self.x + 14, self.y + 6, "(1 - 120)", renderer.TextStyle{ .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 } });

        // Colors section (render only visible pickers)
        if (self.primary_color_picker.visible) {
            try r.drawText(self.x + 2, self.y + 7, "Primary Color:", label_style);
            try self.primary_color_picker.render(r);
        }
        if (self.secondary_color_picker.visible) {
            try r.drawText(self.x + 30, self.y + 7, "Secondary Color:", label_style);
            try self.secondary_color_picker.render(r);
        }

        // Gradient angle (only show for gradient animation)
        if (self.animation_config.animation_type == config.AnimationType.gradient) {
            try r.drawText(self.x + 2, self.y + 16, "Gradient Angle:", label_style);
            try self.gradient_angle_input.render(r);
            try r.drawText(self.x + 14, self.y + 17, "(0 - 360°)", renderer.TextStyle{ .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 } });
        }

        // Shadow color (may be hidden for some animation types)
        if (self.shadow_color_picker.visible) {
            try r.drawText(self.x + 2, self.y + 18, "Shadow Color:", label_style);
            try self.shadow_color_picker.render(r);
        }

        // Preview section
        if (self.preview_enabled) {
            try r.drawText(self.x + 2, self.y + self.height - 6, "Live Preview:", label_style);
            try self.preview_progress.render(r);

            // Preview status
            const status_text = if (self.preview_progress.isAnimating()) "Animating..." else "Static";
            try r.drawText(self.x + 2, self.y + self.height - 2, status_text, renderer.TextStyle{ .fg_color = renderer.Color.CYAN });
        }

        // Help text
        try r.drawText(self.x + 2, self.y + self.height - 1, "Tab: Next field | P: Toggle preview", renderer.TextStyle{ .fg_color = renderer.Color{ .r = 128, .g = 128, .b = 128 } });

        // Focus indicator
        const focus_indicator = ">";
        const indicator_style = renderer.TextStyle{
            .fg_color = renderer.Color.YELLOW,
            .bold = true,
        };

        // Only draw the indicator for visible components
        if (self.isComponentVisible(self.focused_component)) {
            const pos = self.getIndicatorPosition(self.focused_component);
            try r.drawText(pos[0], pos[1], focus_indicator, indicator_style);
        }

        // Render any dropdown overlays last so they appear above the panel content
        try self.animation_type_dropdown.renderOverlay(r);
    }

    pub fn getAnimationConfig(self: *const AnimationSettingsPanel) config.AnimationConfig {
        return self.animation_config;
    }

    pub fn setAnimationConfig(self: *AnimationSettingsPanel, animation_config: config.AnimationConfig) !void {
        self.animation_config = animation_config;
        try self.updateComponentsFromConfig();
    }

    pub fn setVisible(self: *AnimationSettingsPanel, visible: bool) void {
        self.visible = visible;
        self.panel.setVisible(visible);
    }

    pub fn setPosition(self: *AnimationSettingsPanel, x: u16, y: u16) void {
        const dx = @as(i32, x) - @as(i32, self.x);
        const dy = @as(i32, y) - @as(i32, self.y);

        self.x = x;
        self.y = y;

        // Update all component positions
        self.panel.x = x;
        self.panel.y = y;

        self.animation_type_dropdown.setPosition(@as(u16, @intCast(@as(i32, self.animation_type_dropdown.x) + dx)), @as(u16, @intCast(@as(i32, self.animation_type_dropdown.y) + dy)));

        self.speed_input.setPosition(@as(u16, @intCast(@as(i32, self.speed_input.x) + dx)), @as(u16, @intCast(@as(i32, self.speed_input.y) + dy)));

        self.fps_input.setPosition(@as(u16, @intCast(@as(i32, self.fps_input.x) + dx)), @as(u16, @intCast(@as(i32, self.fps_input.y) + dy)));

        self.primary_color_picker.setPosition(@as(u16, @intCast(@as(i32, self.primary_color_picker.x) + dx)), @as(u16, @intCast(@as(i32, self.primary_color_picker.y) + dy)));

        self.secondary_color_picker.setPosition(@as(u16, @intCast(@as(i32, self.secondary_color_picker.x) + dx)), @as(u16, @intCast(@as(i32, self.secondary_color_picker.y) + dy)));

        self.gradient_angle_input.setPosition(@as(u16, @intCast(@as(i32, self.gradient_angle_input.x) + dx)), @as(u16, @intCast(@as(i32, self.gradient_angle_input.y) + dy)));

        self.shadow_color_picker.setPosition(@as(u16, @intCast(@as(i32, self.shadow_color_picker.x) + dx)), @as(u16, @intCast(@as(i32, self.shadow_color_picker.y) + dy)));

        self.preview_progress.setPosition(@as(u16, @intCast(@as(i32, self.preview_progress.base.x) + dx)), @as(u16, @intCast(@as(i32, self.preview_progress.base.y) + dy)));
    }
};
