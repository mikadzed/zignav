const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zig-objc dependency
    const objc_dep = b.dependency("objc", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zignav",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "objc", .module = objc_dep.module("objc") },
            },
        }),
    });

    // Link macOS system frameworks
    exe.linkFramework("ApplicationServices");
    exe.linkFramework("AppKit");
    exe.linkFramework("CoreGraphics");
    exe.linkFramework("CoreFoundation");
    exe.linkFramework("QuartzCore");

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Bundle step - creates macOS .app bundle
    const bundle_step = b.step("bundle", "Create macOS app bundle");

    // Install executable into Contents/MacOS/
    const install_exe = b.addInstallFile(
        exe.getEmittedBin(),
        "ZigNav.app/Contents/MacOS/zignav",
    );
    install_exe.step.dependOn(&exe.step);

    // Install Info.plist into Contents/
    const install_plist = b.addInstallFile(
        b.path("resources/Info.plist"),
        "ZigNav.app/Contents/Info.plist",
    );

    // Install icon into Contents/Resources/
    const install_icon = b.addInstallFile(
        b.path("resources/ZigNav.icns"),
        "ZigNav.app/Contents/Resources/ZigNav.icns",
    );

    bundle_step.dependOn(&install_exe.step);
    bundle_step.dependOn(&install_plist.step);
    bundle_step.dependOn(&install_icon.step);

    // Test step
    const labels_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/labels.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_labels_tests = b.addRunArtifact(labels_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_labels_tests.step);
}
