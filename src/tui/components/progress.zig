//! Progress bar component - customizable progress indicator
//! Provides a visual progress bar with customizable styling and labels

const std = @import("std");
const renderer = @import("../renderer.zig");

pub const ProgressStyle = enum {
    blocks, // █████░░░░░
    bars, // ||||||||--
    dots, // ●●●●●○○○○○
    ascii, // ========--
};

pub const ProgressBar = struct {
    x: u16,
    y: u16,
    width: u16,
    progress: f32 = 0.0, // 0.0 to 1.0
    style: ProgressStyle = ProgressStyle.blocks,
    show_percentage: bool = true,
    show_label: bool = true,
    label: []const u8 = "",
    visible: bool = true,

    // Colors
    filled_color: renderer.Color = renderer.Color.GREEN,
    empty_color: renderer.Color = renderer.Color{ .r = 64, .g = 64, .b = 64 },
    text_color: renderer.Color = renderer.Color.WHITE,

    pub fn init(x: u16, y: u16, width: u16) ProgressBar {
        return ProgressBar{
            .x = x,
            .y = y,
            .width = width,
        };
    }

    pub fn setProgress(self: *ProgressBar, progress: f32) void {
        self.progress = std.math.clamp(progress, 0.0, 1.0);
    }

    pub fn setStyle(self: *ProgressBar, style: ProgressStyle) void {
        self.style = style;
    }

    pub fn setLabel(self: *ProgressBar, label: []const u8) void {
        self.label = label;
    }

    pub fn setColors(self: *ProgressBar, filled: renderer.Color, empty: renderer.Color) void {
        self.filled_color = filled;
        self.empty_color = empty;
    }

    pub fn setShowPercentage(self: *ProgressBar, show: bool) void {
        self.show_percentage = show;
    }

    pub fn setShowLabel(self: *ProgressBar, show: bool) void {
        self.show_label = show;
    }

    pub fn render(self: *const ProgressBar, r: *renderer.Renderer) !void {
        if (!self.visible) return;

        var bar_width = self.width;
        var bar_x = self.x;

        // Reserve space for percentage if shown
        if (self.show_percentage) {
            bar_width = if (bar_width > 5) bar_width - 5 else 1; // " 100%"
        }

        // Reserve space for label if shown
        if (self.show_label and self.label.len > 0) {
            const label_space = @min(self.label.len + 1, bar_width / 2); // Label + space
            if (bar_width > label_space) {
                bar_width -= @as(u16, @intCast(label_space));
                bar_x += @as(u16, @intCast(label_space));
            }
        }

        // Draw label if enabled
        if (self.show_label and self.label.len > 0) {
            const label_style = renderer.TextStyle{
                .fg_color = self.text_color,
            };
            try r.drawText(self.x, self.y, self.label, label_style);
        }

        // Calculate filled width
        const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * self.progress));

        // Draw progress bar
        try r.moveCursor(bar_x, self.y);

        // Draw filled portion
        const filled_style = renderer.TextStyle{
            .fg_color = self.filled_color,
        };
        try r.setTextStyle(filled_style);

        var i: u16 = 0;
        while (i < filled_width) : (i += 1) {
            try r.stdout_file.writeAll(self.getFilledChar());
        }

        // Draw empty portion
        const empty_style = renderer.TextStyle{
            .fg_color = self.empty_color,
        };
        try r.setTextStyle(empty_style);

        while (i < bar_width) : (i += 1) {
            try r.stdout_file.writeAll(self.getEmptyChar());
        }

        try r.resetStyle();

        // Draw percentage if enabled
        if (self.show_percentage) {
            const percentage = @as(u32, @intFromFloat(self.progress * 100));

            var buffer: [8]u8 = undefined;
            const percentage_text = try std.fmt.bufPrint(buffer[0..], " {d}%%", .{percentage});

            const percentage_style = renderer.TextStyle{
                .fg_color = self.text_color,
            };

            try r.drawText(bar_x + bar_width, self.y, percentage_text, percentage_style);
        }
    }

    fn getFilledChar(self: *const ProgressBar) []const u8 {
        return switch (self.style) {
            .blocks => "#",
            .bars => "|",
            .dots => "*",
            .ascii => "=",
        };
    }

    fn getEmptyChar(self: *const ProgressBar) []const u8 {
        return switch (self.style) {
            .blocks => ".",
            .bars => "-",
            .dots => "o",
            .ascii => "-",
        };
    }

    pub fn setVisible(self: *ProgressBar, visible: bool) void {
        self.visible = visible;
    }

    pub fn setPosition(self: *ProgressBar, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
    }

    pub fn setWidth(self: *ProgressBar, width: u16) void {
        self.width = width;
    }

    pub fn getProgress(self: *const ProgressBar) f32 {
        return self.progress;
    }
};

// Animated progress bar that can update over time
pub const AnimatedProgressBar = struct {
    base: ProgressBar,
    target_progress: f32 = 0.0,
    animation_speed: f32 = 2.0, // units per second

    pub fn init(x: u16, y: u16, width: u16) AnimatedProgressBar {
        return AnimatedProgressBar{
            .base = ProgressBar.init(x, y, width),
        };
    }

    pub fn setTargetProgress(self: *AnimatedProgressBar, target: f32) void {
        self.target_progress = std.math.clamp(target, 0.0, 1.0);
    }

    pub fn setAnimationSpeed(self: *AnimatedProgressBar, speed: f32) void {
        self.animation_speed = speed;
    }

    pub fn update(self: *AnimatedProgressBar, delta_time: f32) void {
        const diff = self.target_progress - self.base.progress;
        if (@abs(diff) < 0.001) {
            self.base.progress = self.target_progress;
            return;
        }

        const step = self.animation_speed * delta_time;
        if (diff > 0) {
            self.base.progress = @min(self.base.progress + step, self.target_progress);
        } else {
            self.base.progress = @max(self.base.progress - step, self.target_progress);
        }
    }

    pub fn render(self: *const AnimatedProgressBar, r: *renderer.Renderer) !void {
        try self.base.render(r);
    }

    pub fn isAnimating(self: *const AnimatedProgressBar) bool {
        return @abs(self.target_progress - self.base.progress) > 0.001;
    }

    // Delegate methods to base
    pub fn setStyle(self: *AnimatedProgressBar, style: ProgressStyle) void {
        self.base.setStyle(style);
    }

    pub fn setLabel(self: *AnimatedProgressBar, label: []const u8) void {
        self.base.setLabel(label);
    }

    pub fn setColors(self: *AnimatedProgressBar, filled: renderer.Color, empty: renderer.Color) void {
        self.base.setColors(filled, empty);
    }

    pub fn setShowPercentage(self: *AnimatedProgressBar, show: bool) void {
        self.base.setShowPercentage(show);
    }

    pub fn setShowLabel(self: *AnimatedProgressBar, show: bool) void {
        self.base.setShowLabel(show);
    }

    pub fn setVisible(self: *AnimatedProgressBar, visible: bool) void {
        self.base.setVisible(visible);
    }

    pub fn setPosition(self: *AnimatedProgressBar, x: u16, y: u16) void {
        self.base.setPosition(x, y);
    }

    pub fn setWidth(self: *AnimatedProgressBar, width: u16) void {
        self.base.setWidth(width);
    }

    pub fn getProgress(self: *const AnimatedProgressBar) f32 {
        return self.base.getProgress();
    }
};
