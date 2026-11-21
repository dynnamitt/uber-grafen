const std = @import("std");
const builtin = @import("builtin");
const rlz = @import("raylib_zig");

// emscripten's default 64 KiB stack overflows in Debug web builds (zig + flecs
// frames); release builds don't check, so an overflow there corrupts memory.
const web_stack_size = "1048576";
// Newcomer balls when -Dnewcomers isn't given; Pages and CI ship this.
const default_newcomers = 42;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const is_web = target.result.os.tag == .emscripten;

    // Debug builds still get an optimised raylib (ReleaseSafe keeps its UB
    // checks): its C code isn't what we debug, and unoptimised it costs frame time. zflecs stays at `optimize`
    // so its sanitize checks keep guarding the tests.
    const raylib_optimize: std.builtin.OptimizeMode = if (optimize == .debug) .safe else optimize;
    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = raylib_optimize });
    const zflecs_dep = b.dependency("zflecs", .{ .target = target, .optimize = optimize });
    const flecs_lib = zflecs_dep.artifact("flecs");

    // ECS-only code (components + systems). No raylib here, so it tests headless.
    const sim_mod = b.createModule(.{
        .root_source_file = b.path("src/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_mod.addImport("zflecs", zflecs_dep.module("root"));
    sim_mod.linkLibrary(flecs_lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("raylib", raylib_dep.module("raylib"));
    exe_mod.linkLibrary(raylib_dep.artifact("raylib"));
    exe_mod.addImport("zflecs", zflecs_dep.module("root"));
    exe_mod.addImport("sim", sim_mod);
    // Load test: zig build run -Dnewcomers=100000 -Dthreads=8
    const config = b.addOptions();
    config.addOption(u32, "newcomers", b.option(u32, "newcomers", "Newcomer balls to spawn") orelse default_newcomers);
    const threads = b.option(u8, "threads", "Flecs worker threads (native only)") orelse 0;
    if (is_web and threads > 0) return error.ThreadsNotOnWeb; // wasm threads need COOP/COEP, which Pages can't send
    config.addOption(u8, "threads", threads);
    exe_mod.addOptions("config", config);

    const run_step = b.step("run", "Build and launch the app (web: serve it with emrun)");

    if (is_web) {
        try addWebBuild(b, exe_mod, raylib_dep, flecs_lib, optimize, run_step);
    } else {
        const exe = b.addExecutable(.{ .name = "uber-graphen", .root_module = exe_mod });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addPassthruArgs();
        run_step.dependOn(&run_cmd.step);
    }

    // Filters are compile-time in Zig: zig build test -Dtest-filter="<substring>"
    const test_filters = b.option([]const []const u8, "test-filter", "Only run tests whose name contains this") orelse &.{};
    const sim_tests = b.addTest(.{ .root_module = sim_mod, .filters = test_filters });
    b.step("test", "Run unit tests (headless, native only)").dependOn(&b.addRunArtifact(sim_tests).step);
}

/// -Dtarget=wasm32-emscripten: compile the app as a static library, then let
/// emcc link it with raylib + flecs into zig-out/web/index.{html,js,wasm}.
fn addWebBuild(
    b: *std.Build,
    exe_mod: *std.Build.Module,
    raylib_dep: *std.Build.Dependency,
    flecs_lib: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
    run_step: *std.Build.Step,
) !void {
    const emsdk = rlz.emsdk;

    // zflecs knows nothing about emscripten: flecs.c needs the emscripten libc
    // headers (zig doesn't ship them) and the SDK must be installed first.
    // raylib's own build does the same for itself.
    // Reuse raylib's "Activate EMSDK" step rather than creating a second one:
    // two would run `emsdk update/install` concurrently in the same directory.
    const raylib_lib = raylib_dep.artifact("raylib");
    flecs_lib.root_module.addIncludePath(try emsdk.path(b, "upstream/emscripten/cache/sysroot/include"));
    flecs_lib.step.dependOn(findStep(&raylib_lib.step, "Activate EMSDK") orelse return error.EmsdkActivateStepNotFound);

    const app = b.addLibrary(.{ .name = "uber-graphen", .root_module = exe_mod });

    // No ASYNCIFY: main.zig hands frame() to emscripten_set_main_loop
    // (requestAnimationFrame), so nothing needs to unwind the stack per frame.
    var settings = emsdk.emccDefaultSettings(b.allocator, .{ .optimize = optimize });
    try settings.put("STACK_SIZE", web_stack_size);
    const emcc_step = try emsdk.emccStep(b, &.{}, &.{ raylib_lib, app }, .{
        .optimize = optimize,
        .flags = emsdk.emccDefaultFlags(b.allocator, .{ .optimize = optimize, .asyncify = false }),
        .settings = settings,
        .shell_file_path = b.path("web/shell.html"),
        .install_dir = .{ .custom = "web" },
        .out_file_name = "index.html", // index.* so the folder serves as-is (GitHub Pages)
    });
    if (builtin.os.tag == .windows) try useEmccBat(b, emcc_step);
    b.getInstallStep().dependOn(emcc_step);

    const emrun = try emsdk.emrunStep(b, b.graph.path(.install_prefix, "web/index.html"), &.{});
    emrun.dependOn(emcc_step);
    run_step.dependOn(emrun);
}

/// Depth-first search of `root`'s dependencies for a step named `name`.
fn findStep(root: *std.Build.Step, name: []const u8) ?*std.Build.Step {
    for (root.dependencies.items) |dep| {
        if (std.mem.eql(u8, dep.name, name)) return dep;
        if (findStep(dep, name)) |found| return found;
    }
    return null;
}

/// emcc.py can't be spawned directly on Windows: point emccStep's run step at
/// emcc.bat. Mirrors raylib-zig's (private) fixEmccOnWindows: patch only the
/// first Run step, and fail loudly if the layout ever changes.
fn useEmccBat(b: *std.Build, emcc_step: *std.Build.Step) !void {
    for (emcc_step.dependencies.items) |dep| {
        const run = dep.cast(std.Build.Step.Run) orelse continue;
        run.argv.items[0].lazy_path.lazy_path = try rlz.emsdk.path(b, "upstream/emscripten/emcc.bat");
        return;
    }
    return error.EmccRunStepNotFound;
}
