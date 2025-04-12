const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const adk = b.addModule("adk", .{
        .root_source_file = b.path("src/init.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(adk);
}
