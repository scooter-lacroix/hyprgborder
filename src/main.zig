//! Enhanced command-line interface for HyprGBorder.
//!
//! This is the main entry point for the enhanced CLI that provides a comprehensive
//! interactive configuration system with live preview, multiple animation types,
//! preset management, and Hyprland environment validation.
//!
//! Usage:
//!   hyprgborder           - Run with last saved configuration
//!   hyprgborder --cli     - Open interactive configuration menu
//!   hyprgborder --help    - Show help information

const std = @import("std");
const hypr = @import("hyprgborder");
const config = @import("config");
const utils = @import("utils");
const tui = @import("tui");

/// Print help information
fn printHelp() void {
    std.debug.print(
        \\HyprGBorder - Enhanced Hyprland Border Animation
        \\
        \\Usage:
        \\  hyprgborder           Run with last saved configuration
        \\  hyprgborder --tui     Open Terminal User Interface
        \\  hyprgborder --cli     Open interactive configuration menu (legacy)
        \\  hyprgborder --help    Show this help information
        \\
        \\The Terminal User Interface (--tui) provides:
        \\  - Multiple animation types (rainbow, pulse, gradient, solid)
        \\  - Live preview of changes
        \\  - Preset management
        \\  - Fine-grained configuration options
        \\  - Hyprland environment validation
        \\  - Visual status indicators and real-time feedback
        \\
    , .{});
}

/// Run animation with saved configuration
fn runWithSavedConfig(allocator: std.mem.Allocator) !void {
    // Validate Hyprland environment first
    utils.environment.validateEnvironment(allocator) catch |err| {
        std.debug.print("Environment Error: {s}\n", .{@errorName(err)});
        std.debug.print("Use --cli to access system diagnostics and troubleshooting.\n", .{});
        return;
    };

    // Try to load saved configuration
    var animation_config = config.persistence.loadConfig(allocator) catch |err| switch (err) {
        config.persistence.PersistenceError.ConfigNotFound => blk: {
            std.debug.print("No saved configuration found. Using default settings.\n", .{});
            std.debug.print("Use --cli to configure your border animation.\n", .{});

            // Create and save default configuration
            var default_config = config.AnimationConfig.default();

            config.persistence.saveConfig(allocator, &default_config) catch |save_err| {
                std.debug.print("Warning: Could not save default configuration: {s}\n", .{@errorName(save_err)});
            };

            break :blk default_config;
        },
        else => blk: {
            std.debug.print("Error loading configuration: {s}\n", .{@errorName(err)});
            std.debug.print("Using default settings. Use --cli to reconfigure.\n", .{});
            break :blk config.AnimationConfig.default();
        },
    };
    defer animation_config.deinit(allocator);

    // Validate the loaded configuration
    animation_config.validate() catch |err| {
        std.debug.print("Invalid configuration: {s}\n", .{@errorName(err)});
        std.debug.print("Use --cli to fix the configuration.\n", .{});
        return;
    };

    // Get socket path
    const socket_path = utils.hyprland.getSocketPath(allocator) catch |err| {
        std.debug.print("Error getting Hyprland socket path: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(socket_path);

    // Test connection
    if (!utils.hyprland.testConnection(socket_path)) {
        std.debug.print("Cannot connect to Hyprland. Make sure Hyprland is running.\n", .{});
        return;
    }

    std.debug.print("Starting border animation with {s} type at {d} FPS...\n", .{ animation_config.animation_type.toString(), animation_config.fps });
    std.debug.print("Press Ctrl+C to stop.\n", .{});

    // Create and run animation
    var animation_provider = @import("animations").createAnimationProvider(allocator, animation_config.animation_type) catch |err| {
        std.debug.print("Error creating animation provider: {s}\n", .{@errorName(err)});
        return;
    };
    defer animation_provider.cleanup();

    try animation_provider.configure(animation_config);

    // Animation loop
    var timer = try std.time.Timer.start();
    const safe_fps = if (animation_config.fps >= 1) animation_config.fps else 1;
    const frame_time_ns = std.time.ns_per_s / safe_fps;

    while (true) {
        const elapsed = @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_s;

        animation_provider.update(allocator, socket_path, elapsed) catch |err| {
            std.debug.print("Animation error: {s}\n", .{@errorName(err)});
            std.debug.print("Retrying in 1 second...\n", .{});
            std.Thread.sleep(std.time.ns_per_s);
            continue;
        };

        std.Thread.sleep(frame_time_ns);
    }
}

/// Run Terminal User Interface
fn runTUI(allocator: std.mem.Allocator) !void {
    // Initialize crash logger
    utils.crash_logger.initCrashLogger(allocator) catch |err| {
        std.debug.print("Warning: Could not initialize crash logger: {s}\n", .{@errorName(err)});
    };
    // Register signal handlers so fatal signals flush logs
    utils.crash_logger.registerSignalHandlers();
    defer utils.crash_logger.deinitCrashLogger();
    // Check environment and show status
    const env_status = utils.environment.checkEnvironment(allocator) catch |err| {
        std.debug.print("Error checking environment: {s}\n", .{@errorName(err)});
        return;
    };
    defer {
        var mut_status = env_status;
        mut_status.deinit(allocator);
    }

    // Show environment status if there are critical issues
    if (!env_status.hyprland_running) {
        std.debug.print("Warning: Hyprland is not running. Live preview will be unavailable.\n", .{});
        std.debug.print("You can still configure settings and they will be saved for later use.\n", .{});
        std.debug.print("Press Enter to continue or Ctrl+C to exit...\n", .{});

        // Wait for user confirmation
        const stdin_file = std.fs.File{ .handle = 0 };
        var buffer: [1]u8 = undefined;
        _ = try stdin_file.read(buffer[0..]);
    }

    // Initialize and run TUI application
    var tui_app = tui.TUIApp.init(allocator) catch |err| {
        utils.crash_logger.logMessage("Error initializing TUI: {s}", .{@errorName(err)}) catch {};
        std.debug.print("Error initializing TUI: {s}\n", .{@errorName(err)});
        return;
    };
    defer tui_app.deinit();

    // Log TUI startup
    utils.crash_logger.logMessage("TUI application starting", .{}) catch {};

    // Run the TUI
    tui_app.run() catch |err| {
        utils.crash_logger.logMessage("TUI runtime error: {s}", .{@errorName(err)}) catch {};
        std.debug.print("TUI error: {s}\n", .{@errorName(err)});
        return err;
    };
}

/// Run interactive CLI configuration (legacy mode)
fn runInteractiveCLI(allocator: std.mem.Allocator) !void {
    std.debug.print("Legacy CLI mode. Use --tui for the enhanced Terminal User Interface.\n", .{});
    try runTUI(allocator);
}

/// Entry point for the CLI application
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command line arguments
    if (args.len > 1) {
        const arg1 = args[1];
        if (std.mem.eql(u8, arg1, "--tui")) {
            try runTUI(allocator);
            return;
        } else if (std.mem.eql(u8, arg1, "--cli")) {
            try runInteractiveCLI(allocator);
            return;
        } else if (std.mem.eql(u8, arg1, "--help") or std.mem.eql(u8, arg1, "-h")) {
            printHelp();
            return;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg1});
            std.debug.print("Use --help for usage information.\n", .{});
            return;
        }
    }

    // Run with saved configuration
    try runWithSavedConfig(allocator);
}
