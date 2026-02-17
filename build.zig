const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    const hypr_mod = b.addModule("hyprgborder", .{
        .root_source_file = b.path("src/hyprgborder.zig"),
        .target = target,
    });
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .target = target,
    });
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
        },
    });
    const animations_mod = b.addModule("animations", .{
        .root_source_file = b.path("src/animations/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "utils", .module = utils_mod },
        },
    });
    const tui_mod = b.addModule("tui", .{
        .root_source_file = b.path("src/tui/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "animations", .module = animations_mod },
        },
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "hyprgborder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hyprgborder", .module = hypr_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "animations", .module = animations_mod },
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "tui", .module = tui_mod },
            },
            .link_libc = true,
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the main executable");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // --- Unit tests (explicit list) ---
    const unit_test_files = &[_][]const u8{
        "src/main.zig",
        "tests/test_config.zig",
        "tests/test_animations.zig",
        "tests/test_preview_concurrency.zig",
        "tests/test_preview.zig",
        "tests/test_hyprland_ipc.zig",
        "tests/test_tui_components.zig",
        "tests/test_tui_screens.zig",
    };

    const test_step = b.step("test", "Run all unit tests (use --summary all for detailed output)");

    for (unit_test_files) |file| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "hyprgborder", .module = hypr_mod },
                    .{ .name = "config", .module = config_mod },
                    .{ .name = "animations", .module = animations_mod },
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "tui", .module = tui_mod },
                },
                .link_libc = true,
            }),
        });

        // Wrap the test in a run step so it always executes
        const run_t = b.addRunArtifact(t);
        run_t.has_side_effects = true;

        // Depend on the run step, not the compile step
        test_step.dependOn(&run_t.step);
    }

    // --- Interactive TUI runner ---
    const test_tui_exe = b.addExecutable(.{
        .name = "test_tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_tui.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tui", .module = tui_mod },
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "animations", .module = animations_mod },
                .{ .name = "hyprgborder", .module = hypr_mod },
            },
            .link_libc = true,
        }),
    });
    const run_tui_test = b.step("run-tui-test", "Run the interactive TUI test");
    const run_tui_cmd = b.addRunArtifact(test_tui_exe);
    run_tui_test.dependOn(&run_tui_cmd.step);

    // --- Config module’s interactive tests (if any) ---
    const test_config_exe = b.addExecutable(.{
        .name = "test_config",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_config.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_mod },
                .{ .name = "utils", .module = utils_mod },
            },
            .link_libc = true,
        }),
    });
    const run_config_test = b.step("run-config-test", "Run the config validation tests");
    const run_config_cmd = b.addRunArtifact(test_config_exe);
    run_config_test.dependOn(&run_config_cmd.step);
}
