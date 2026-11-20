//! ECS state and systems. Knows nothing about rendering, so it runs under
//! `zig build test` without a window or GPU.
const std = @import("std");
const ecs = @import("zflecs");

pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct { x: f32, y: f32 };

/// Registers components and systems on `world`.
pub fn register(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Velocity);
    _ = ecs.ADD_SYSTEM(world, "move", ecs.OnUpdate, move);
}

fn move(it: *ecs.iter_t, positions: []Position, velocities: []const Velocity) void {
    const dt = it.delta_time;
    for (positions, velocities) |*p, v| {
        p.x += v.x * dt;
        p.y += v.y * dt;
    }
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
    try std.testing.expectApproxEqAbs(@as(f32, 10), p.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -4), p.y, 1e-5);
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
