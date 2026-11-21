const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const ecs = @import("zflecs");
const sim = @import("sim");

const width = 800;
const height = 450;
// Render-only colours (tech-trio.svg palette; ball colours are in sim.zig).
const background = 0x0E1414FF; // near-black teal
const orbit_guide = 0x1E5252FF; // deep teal
const newcomer_start_x = -16; // just off the left edge
// emscripten_set_main_loop args: fps 0 = requestAnimationFrame; nonzero
// simulate_infinite_loop = never return from main.
const web_loop_fps = 0;
const web_simulate_infinite_loop = 1;

// zflecs allocates through std.heap.page_allocator, which on wasm calls
// memory.grow behind emscripten's back. That fails on emscripten's fixed-size
// heap (panic: OOM in ecs.init), so take pages from emscripten's malloc.
pub const os = if (builtin.os.tag == .emscripten) struct {
    pub const heap = struct {
        pub const page_allocator: std.mem.Allocator = .{ .ptr = undefined, .vtable = &EmscriptenPages.vtable };
    };
} else struct {};

/// Aligned (no over-allocation) and zero-filled: zflecs' DebugAllocator
/// assumes its backing allocator returns zeroed memory, as real pages are.
const EmscriptenPages = struct {
    // std.c only exposes posix_memalign on some OSes; emscripten's libc has it.
    extern "c" fn posix_memalign(memptr: *?*anyopaque, alignment: usize, size: usize) c_int;

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = free,
    };

    fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        var p: ?*anyopaque = null;
        if (posix_memalign(&p, @max(alignment.toByteUnits(), @sizeOf(usize)), len) != 0) return null;
        const bytes: [*]u8 = @ptrCast(p orelse return null);
        @memset(bytes[0..len], 0);
        return bytes;
    }

    fn free(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
        std.c.free(memory.ptr);
    }
};

/// Globals, not locals in main: on web, emscripten_set_main_loop unwinds
/// main's stack and calls frame() later.
var world: *ecs.world_t = undefined;
var demo: sim.Demo = undefined;
var balls: *ecs.query_t = undefined;
var clock: sim.FixedClock = .{};

pub fn main() !void {
    rl.initWindow(width, height, "uber-graphen");
    defer rl.closeWindow();

    world = ecs.init();
    defer _ = ecs.fini(world);
    sim.register(world);
    demo = sim.spawnDemo(world, width / 2, height / 2, 150, 4);
    _ = sim.spawnNewcomer(world, demo, newcomer_start_x);

    balls = try sim.ballQuery(world);
    defer ecs.query_fini(balls);

    if (builtin.os.tag == .emscripten) {
        // raylib's web pacing (WindowShouldClose's emscripten_sleep, SetTargetFPS's
        // WaitTime) isn't vsync-aligned and needs Asyncify. Never returns, so
        // the defers above don't run.
        std.os.emscripten.emscripten_set_main_loop(frame, web_loop_fps, web_simulate_infinite_loop);
    } else {
        rl.setTargetFPS(60);
        while (!rl.windowShouldClose()) frame();
    }
}

fn frame() callconv(.c) void {
    // Fixed steps, never raylib's raw dt: a long frame would otherwise
    // throw the orbit off for good, and dt=0 (first frame) would make
    // flecs measure its own clock.
    for (0..clock.advance(rl.getFrameTime())) |_| _ = ecs.progress(world, sim.step_dt);
    const alpha = clock.alpha();

    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.getColor(background));

    // Orbit guide, then every Position + Ball entity.
    const c = ecs.get(world, demo.center, sim.Position).?;
    rl.drawCircleLinesV(.{ .x = c.x, .y = c.y }, demo.radius, rl.getColor(orbit_guide));

    var it = ecs.query_iter(world, balls);
    while (ecs.query_next(&it)) {
        const ps = ecs.field(&it, sim.Position, 0).?;
        const bs = ecs.field(&it, sim.Ball, 1).?;
        const prevs = ecs.field(&it, sim.PrevPosition, 2);
        for (ps, bs, 0..) |p, b, i| {
            // Draw between the last two steps, so motion stays smooth when
            // frames don't line up with steps (rAF jitter, 120/144 Hz screens).
            const at: rl.Vector2 = if (prevs) |pp|
                .{ .x = std.math.lerp(pp[i].x, p.x, alpha), .y = std.math.lerp(pp[i].y, p.y, alpha) }
            else
                .{ .x = p.x, .y = p.y };
            rl.drawCircleV(at, b.radius, rl.getColor(b.rgba));
        }
    }

    // Not rl.drawFPS: its lime/orange/red colours ignore the theme.
    var fps_buf: [16]u8 = undefined;
    const fps = std.fmt.bufPrintSentinel(&fps_buf, "{d} FPS", .{rl.getFPS()}, 0) catch unreachable;
    rl.drawText(fps, width - 96, 16, 20, rl.getColor(sim.sand));
}
