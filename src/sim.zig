//! ECS state and systems. Knows nothing about rendering, so it runs under
//! `zig build test` without a window or GPU.
const std = @import("std");
const ecs = @import("zflecs");

// Ball colours from the tech-trio.svg palette (0xRRGGBBAA); render-only
// colours live in main.zig and web/shell.html.
pub const orange: u32 = 0xC87137FF;
pub const teal: u32 = 0x2E7E7EFF;
pub const sand: u32 = 0xC8A878FF;

// Newcomer path, as fractions of the orbit radius: it flies straight past the
// attractor at `newcomer_offset` (the void between the two balls), and gravity
// takes it once it is `newcomer_capture` past the attractor. `newcomer_speed`
// is relative to orbital speed; with these the capture orbit stays on screen.
const newcomer_offset = 0.6;
const newcomer_capture = 0.4;
const newcomer_speed = 1.2;

pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct { x: f32, y: f32 };
/// `Position` at the start of the latest step, so rendering can interpolate
/// between fixed steps. Only moving entities need it.
pub const PrevPosition = struct { x: f32, y: f32 };
/// Something to draw: a filled circle. `rgba` is 0xRRGGBBAA so this module
/// stays free of raylib types.
pub const Ball = struct { radius: f32, rgba: u32 };
/// Pulls `Orbits` entities toward it with acceleration `mu / r²`.
pub const Attractor = struct { mu: f32 };
/// Accelerates toward `center`, which must have `Position` + `Attractor`.
pub const Orbits = struct { center: ecs.entity_t };
/// Flies straight until it is `after` past `center` along its velocity, then
/// trades this for `Orbits` on the same center.
pub const Capture = struct { center: ecs.entity_t, after: f32 };

// zflecs declares ecs_set_id as returning entity_t, but flecs 4.1 returns void.
// Native ABIs ignore the bogus return value; on wasm, wasm-ld replaces the call
// with a trap. So declare it correctly and avoid ecs.set.
extern fn ecs_set_id(world: *ecs.world_t, entity: ecs.entity_t, component: ecs.id_t, size: usize, ptr: ?*const anyopaque) void;

fn set(world: *ecs.world_t, entity: ecs.entity_t, comptime T: type, val: T) void {
    ecs_set_id(world, entity, ecs.id(T), @sizeOf(T), &val);
}

/// Registers components and systems on `world`.
pub fn register(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Velocity);
    ecs.COMPONENT(world, PrevPosition);
    ecs.COMPONENT(world, Ball);
    ecs.COMPONENT(world, Attractor);
    ecs.COMPONENT(world, Orbits);
    ecs.COMPONENT(world, Capture);
    _ = ecs.ADD_SYSTEM(world, "snapshot", ecs.OnLoad, snapshot);
    // gravity (PreUpdate) updates velocity before move (OnUpdate) uses it:
    // semi-implicit Euler, which keeps a circular orbit from spiralling out.
    _ = ecs.ADD_SYSTEM(world, "gravity", ecs.PreUpdate, gravity);
    _ = ecs.ADD_SYSTEM(world, "move", ecs.OnUpdate, move);
    _ = ecs.ADD_SYSTEM(world, "capture", ecs.PostUpdate, capture);
}

fn snapshot(positions: []const Position, prevs: []PrevPosition) void {
    for (positions, prevs) |p, *prev| prev.* = .{ .x = p.x, .y = p.y };
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

fn capture(it: *ecs.iter_t, positions: []const Position, velocities: []const Velocity, captures: []const Capture) void {
    for (it.entities(), positions, velocities, captures) |e, p, v, cap| {
        const c = ecs.get(it.world, cap.center, Position) orelse continue;
        // Distance past center along v, scaled by |v| on both sides.
        if ((p.x - c.x) * v.x + (p.y - c.y) * v.y < cap.after * std.math.hypot(v.x, v.y)) continue;
        set(it.world, e, Orbits, .{ .center = cap.center });
        ecs.remove(it.world, e, Capture);
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

    /// How far the frame is past the latest step.
    /// @returns {f32} 0..1, the weight rendering gives the current `Position`
    /// over `PrevPosition`.
    pub fn alpha(self: FixedClock) f32 {
        return self.acc / step_dt;
    }
};

/// `speed` is the orbiter's (circular) orbital speed.
pub const Demo = struct { center: ecs.entity_t, orbiter: ecs.entity_t, radius: f32, speed: f32 };

/// A static ball at (`cx`, `cy`) and a second ball circling it at `radius`,
/// once every `period` seconds. Speed and pull are chosen so the orbit is an
/// exact circle: v = 2πr/T, mu = v²·r.
pub fn spawnDemo(world: *ecs.world_t, cx: f32, cy: f32, radius: f32, period: f32) Demo {
    const speed = 2 * std.math.pi * radius / period;

    const center = ecs.new_id(world);
    set(world, center, Position, .{ .x = cx, .y = cy });
    set(world, center, Attractor, .{ .mu = speed * speed * radius });
    set(world, center, Ball, .{ .radius = 24, .rgba = orange });

    const orbiter = ecs.new_id(world);
    const start: Position = .{ .x = cx + radius, .y = cy };
    set(world, orbiter, Position, start);
    set(world, orbiter, PrevPosition, .{ .x = start.x, .y = start.y });
    set(world, orbiter, Velocity, .{ .x = 0, .y = speed });
    set(world, orbiter, Orbits, .{ .center = center });
    set(world, orbiter, Ball, .{ .radius = 10, .rgba = teal });

    return .{ .center = center, .orbiter = orbiter, .radius = radius, .speed = speed };
}

/// A third ball entering from `start_x` (left of the attractor) heading +x,
/// aimed through the gap between the attractor and the orbit ring. Gravity
/// catches it once it is past the attractor. Returns the new entity.
pub fn spawnNewcomer(world: *ecs.world_t, demo: Demo, start_x: f32) ecs.entity_t {
    const c = ecs.get(world, demo.center, Position).?;
    const start: Position = .{ .x = start_x, .y = c.y - demo.radius * newcomer_offset };

    const e = ecs.new_id(world);
    set(world, e, Position, start);
    set(world, e, PrevPosition, .{ .x = start.x, .y = start.y });
    set(world, e, Velocity, .{ .x = newcomer_speed * demo.speed, .y = 0 });
    set(world, e, Capture, .{ .center = demo.center, .after = demo.radius * newcomer_capture });
    set(world, e, Ball, .{ .radius = 8, .rgba = sand });
    return e;
}

/// Query over every drawable entity: term 0 = `Position`, term 1 = `Ball`,
/// term 2 = optional `PrevPosition` (null field for static entities).
/// Caller owns it (`ecs.query_fini`).
pub fn ballQuery(world: *ecs.world_t) !*ecs.query_t {
    return ecs.query_init(world, &.{
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(Position) },
            .{ .id = ecs.id(Ball) },
            .{ .id = ecs.id(PrevPosition), .oper = .Optional },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 3),
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
    set(world, e, Position, .{ .x = 0, .y = 0 });
    set(world, e, Velocity, .{ .x = 10, .y = -4 });

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
    set(world, e, Position, .{ .x = 3, .y = 7 });
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

test "FixedClock: alpha is the leftover fraction of a step" {
    var clock: FixedClock = .{};
    _ = clock.advance(step_dt * 1.25);
    try expectApproxEqAbs(@as(f32, 0.25), clock.alpha(), 1e-4);
}

test "snapshot keeps the position from before the step" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    const d = spawnDemo(world, 0, 0, 100, 2);

    step(world, 10);
    const before = ecs.get(world, d.orbiter, Position).?.*;
    step(world, 1);
    const prev = ecs.get(world, d.orbiter, PrevPosition).?;
    try std.testing.expectEqual(PrevPosition{ .x = before.x, .y = before.y }, prev.*);
    try expect(distance(before, ecs.get(world, d.orbiter, Position).?.*) > 0);
}

test "newcomer flies straight past the attractor, then stays captured" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);
    const d = spawnDemo(world, 400, 225, 150, 4);
    const n = spawnNewcomer(world, d, -8);
    const c: Position = .{ .x = 400, .y = 225 };

    var steps: usize = 0;
    while (ecs.has_id(world, n, ecs.id(Capture))) : (steps += 1) {
        try expect(steps < 600);
        step(world, 1);
        try std.testing.expectEqual(@as(f32, 225 - 90), ecs.get(world, n, Position).?.y);
    }
    try expect(ecs.get(world, n, Position).?.x >= 400 + 60);
    try expect(ecs.has_id(world, n, ecs.id(Orbits)));

    for (0..20 * 240) |_| { // ~20 orbiter periods
        step(world, 1);
        const r = distance(c, ecs.get(world, n, Position).?.*);
        try expect(r > 30 and r < 200);
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
    var with_prev: usize = 0; // only the orbiter has PrevPosition
    var it = ecs.query_iter(world, q);
    while (ecs.query_next(&it)) {
        n += it.count();
        if (ecs.field(&it, PrevPosition, 2) != null) with_prev += it.count();
    }
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(usize, 1), with_prev);
}
