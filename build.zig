const std = @import("std");

pub fn build(b: *std.Build) void {
    const mode = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary(.{
        .name = "ZigKit",
        .root_source_file = b.path("src/main.zig"),
        .optimize = mode,
        .target = target,
    });
    b.installArtifact(lib);

    _ = b.addModule("ZigKit", .{
        .root_source_file = b.path("src/main.zig"),
    });

    if (std.zig.system.darwin.getSdk(b.allocator, target.result)) |sdk| {
        const main_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = mode,
            .target = target,
        });
        main_tests.linkFramework("CoreFoundation");
        main_tests.linkFramework("Security");
        main_tests.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/Frameworks" }) });

        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&b.addRunArtifact(main_tests).step);
    }
}
