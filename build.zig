const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("ZigKit", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.linkFramework("CoreFoundation");
    main_tests.linkFramework("Security");
    main_tests.addFrameworkPath("/System/Library/Frameworks");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
