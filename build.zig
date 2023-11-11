const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("fp", .{ .source_file = .{ .path = "src/main.zig" } });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
