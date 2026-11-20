const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const zflecs_dep = b.dependency("zflecs", .{ .target = target, .optimize = optimize });

    // ECS-only code (components + systems). No raylib here, so it tests headless.
    const sim_mod = b.createModule(.{
        .root_source_file = b.path("src/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_mod.addImport("zflecs", zflecs_dep.module("root"));
    sim_mod.linkLibrary(zflecs_dep.artifact("flecs"));

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("raylib", raylib_dep.module("raylib"));
    exe_mod.linkLibrary(raylib_dep.artifact("raylib"));
    exe_mod.addImport("zflecs", zflecs_dep.module("root"));
    exe_mod.addImport("sim", sim_mod);

    const exe = b.addExecutable(.{ .name = "uber-graphen", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Build and launch the app").dependOn(&run_cmd.step);

    const sim_tests = b.addTest(.{ .root_module = sim_mod });
    b.step("test", "Run unit tests (headless)").dependOn(&b.addRunArtifact(sim_tests).step);
}
