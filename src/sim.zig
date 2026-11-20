//! ECS state and systems. Knows nothing about rendering, so it runs under
//! `zig build test` without a window or GPU.
const std = @import("std");
const ecs = @import("zflecs");

pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct { x: f32, y: f32 };
/// Something to draw: a filled circle. `rgba` is 0xRRGGBBAA so this module
/// stays free of raylib types.
pub const Ball = struct { radius: f32, rgba: u32 };
/// Pulls `Orbits` entities toward it with acceleration `mu / r²`.
pub const Attractor = struct { mu: f32 };
/// Accelerates toward `center`, which must have `Position` + `Attractor`.
pub const Orbits = struct { center: ecs.entity_t };

/// Registers components and systems on `world`.
pub fn register(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Velocity);
    ecs.COMPONENT(world, Ball);
    ecs.COMPONENT(world, Attractor);
    ecs.COMPONENT(world, Orbits);
    // gravity (PreUpdate) updates velocity before move (OnUpdate) uses it:
    // semi-implicit Euler, which keeps a circular orbit from spiralling out.
    _ = ecs.ADD_SYSTEM(world, "gravity", ecs.PreUpdate, gravity);
    _ = ecs.ADD_SYSTEM(world, "move", ecs.OnUpdate, move);
}

fn gravity(it: *ecs.iter_t, positions: []const Position, velocities: []Velocity, orbits: []const Orbits) void {
    const dt = it.delta_time;
    for (positions, velocities, orbits) |p, *v, o| {
        const c = ecs.get(it.world, o.center, Position) orelse continue;
        const a = ecs.get(it.world, o.center, Attractor) orelse continue;
        const dx = c.x - p.x;
        const dy = c.y - p.y;
        const r2 = dx * dx + dy * dy;
        if (r2 == 0) continue;
        const r = @sqrt(r2);
        const accel = a.mu / r2;
        v.x += accel * dx / r * dt;
        v.y += accel * dy / r * dt;
    }
}

fn move(it: *ecs.iter_t, positions: []Position, velocities: []const Velocity) void {
    const dt = it.delta_time;
    for (positions, velocities) |*p, v| {
        p.x += v.x * dt;
        p.y += v.y * dt;
    }
}

/// Fixed simulation step. The sim always advances in these steps, whatever
/// the frame rate, so it behaves the same everywhere (and matches the tests).
pub const step_dt: f32 = 1.0 / 60.0;
/// Most steps one frame may run. A longer frame (tab hidden, window dragged,
/// debugger pause) drops the backlog instead of applying one huge `dt`, which
/// would fling the orbiter out of orbit for good.
pub const max_steps_per_frame: u32 = 5;

/// Turns variable frame times into a count of fixed `step_dt` steps.
pub const FixedClock = struct {
    acc: f32 = 0,

    /// Adds `frame_dt` seconds; returns how many `step_dt` steps to run now.
    pub fn advance(self: *FixedClock, frame_dt: f32) u32 {
        self.acc += @max(frame_dt, 0);
        var n: u32 = 0;
        while (self.acc >= step_dt and n < max_steps_per_frame) : (n += 1) self.acc -= step_dt;
        if (self.acc >= step_dt) self.acc = 0; // too far behind: drop it
        return n;
    }
};

pub const Demo = struct { center: ecs.entity_t, orbiter: ecs.entity_t };

/// A static ball at (`cx`, `cy`) and a second ball circling it at `radius`,
/// once every `period` seconds. Speed and pull are chosen so the orbit is an
/// exact circle: v = 2πr/T, mu = v²·r.
pub fn spawnDemo(world: *ecs.world_t, cx: f32, cy: f32, radius: f32, period: f32) Demo {
    const speed = 2 * std.math.pi * radius / period;

    const center = ecs.new_id(world);
    _ = ecs.set(world, center, Position, .{ .x = cx, .y = cy });
    _ = ecs.set(world, center, Attractor, .{ .mu = speed * speed * radius });
    _ = ecs.set(world, center, Ball, .{ .radius = 24, .rgba = 0xF5A623FF });

    const orbiter = ecs.new_id(world);
    _ = ecs.set(world, orbiter, Position, .{ .x = cx + radius, .y = cy });
    _ = ecs.set(world, orbiter, Velocity, .{ .x = 0, .y = speed });
    _ = ecs.set(world, orbiter, Orbits, .{ .center = center });
    _ = ecs.set(world, orbiter, Ball, .{ .radius = 10, .rgba = 0x4A90E2FF });

    return .{ .center = center, .orbiter = orbiter };
}

/// Query over every drawable entity: term 0 = `Position`, term 1 = `Ball`.
/// Caller owns it (`ecs.query_fini`).
pub fn ballQuery(world: *ecs.world_t) !*ecs.query_t {
    return ecs.query_init(world, &.{
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(Position) },
            .{ .id = ecs.id(Ball) },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
    });
}

// ---------------------------------------------------------------- tests

const expect = std.testing.expect;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

fn step(world: *ecs.world_t, n: usize) void {
    for (0..n) |_| _ = ecs.progress(world, step_dt);
}

fn distance(a: Position, b: Position) f32 {
    return std.math.hypot(a.x - b.x, a.y - b.y);
}

test "move system integrates velocity over delta time" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);

    const e = ecs.new_id(world);
    _ = ecs.set(world, e, Position, .{ .x = 0, .y = 0 });
    _ = ecs.set(world, e, Velocity, .{ .x = 10, .y = -4 });

    _ = ecs.progress(world, 0.5);
    _ = ecs.progress(world, 0.5);

    const p = ecs.get(world, e, Position).?;
    try expectApproxEqAbs(@as(f32, 10), p.x, 1e-5);
    try expectApproxEqAbs(@as(f32, -4), p.y, 1e-5);
}

test "entities without Velocity are not moved" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);

    const e = ecs.new_id(world);
    _ = ecs.set(world, e, Position, .{ .x = 3, .y = 7 });
    _ = ecs.progress(world, 1.0);

    const p = ecs.get(world, e, Position).?;
    try std.testing.expectEqual(Position{ .x = 3, .y = 7 }, p.*);
}

// Semi-implicit Euler keeps the orbit bounded but slightly elliptical: at
// 120 steps per orbit the radius wobbles about ±3% and never drifts, and each
// full period returns close to the start. The tests check exactly that.

test "orbit radius stays bounded over many orbits" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    const d = spawnDemo(world, 0, 0, 100, 2);

    for (0..10 * 120) |_| { // 10 orbits at 60 steps/s
        step(world, 1);
        const o = ecs.get(world, d.orbiter, Position).?;
        try expectApproxEqAbs(@as(f32, 100), distance(.{ .x = 0, .y = 0 }, o.*), 100 * 0.03);
    }
}

test "attractor stays put" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    const d = spawnDemo(world, 400, 225, 150, 4);

    step(world, 240);
    const c = ecs.get(world, d.center, Position).?;
    try std.testing.expectEqual(Position{ .x = 400, .y = 225 }, c.*);
}

test "each period brings the orbiter back to its start" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    const d = spawnDemo(world, 0, 0, 100, 2);

    for (0..3) |_| {
        step(world, 120);
        const o = ecs.get(world, d.orbiter, Position).?.*;
        try expect(distance(o, .{ .x = 100, .y = 0 }) < 100 * 0.05);
    }
}

test "FixedClock: fractional frames carry over" {
    var clock: FixedClock = .{};
    try std.testing.expectEqual(@as(u32, 0), clock.advance(0)); // raylib's first frame
    try std.testing.expectEqual(@as(u32, 2), clock.advance(step_dt * 2.5));
    try std.testing.expectEqual(@as(u32, 1), clock.advance(step_dt * 0.6)); // 0.5 + 0.6 carried
}

test "FixedClock: a long stall is capped and its backlog dropped" {
    var clock: FixedClock = .{};
    try std.testing.expectEqual(max_steps_per_frame, clock.advance(3.0));
    try std.testing.expectEqual(@as(u32, 0), clock.advance(0));
}

test "orbit survives a 3 s frame stall" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    const d = spawnDemo(world, 0, 0, 100, 2);

    var clock: FixedClock = .{};
    step(world, 30);
    for (0..clock.advance(3.0)) |_| _ = ecs.progress(world, step_dt);
    for (0..120) |_| {
        for (0..clock.advance(step_dt)) |_| _ = ecs.progress(world, step_dt);
        const o = ecs.get(world, d.orbiter, Position).?;
        try expectApproxEqAbs(@as(f32, 100), distance(.{ .x = 0, .y = 0 }, o.*), 100 * 0.03);
    }
}

test "ballQuery yields both demo balls" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    _ = spawnDemo(world, 0, 0, 100, 2);

    const q = try ballQuery(world);
    defer ecs.query_fini(q);
    var n: usize = 0;
    var it = ecs.query_iter(world, q);
    while (ecs.query_next(&it)) n += it.count();
    try std.testing.expectEqual(@as(usize, 2), n);
}
