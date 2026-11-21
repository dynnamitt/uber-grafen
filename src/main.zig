const rl = @import("raylib");
const ecs = @import("zflecs");
const sim = @import("sim");

const width = 800;
const height = 450;

pub fn main() !void {
    rl.initWindow(width, height, "uber-graphen");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const world = ecs.init();
    defer _ = ecs.fini(world);
    sim.register(world);
    const demo = sim.spawnDemo(world, width / 2, height / 2, 150, 4);

    const balls = try sim.ballQuery(world);
    defer ecs.query_fini(balls);

    var clock: sim.FixedClock = .{};
    while (!rl.windowShouldClose()) {
        // Fixed steps, never raylib's raw dt: a long frame would otherwise
        // throw the orbit off for good, and dt=0 (first frame) would make
        // flecs measure its own clock.
        for (0..clock.advance(rl.getFrameTime())) |_| _ = ecs.progress(world, sim.step_dt);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.getColor(0x14161AFF));

        // Orbit guide, then every Position + Ball entity.
        const c = ecs.get(world, demo.center, sim.Position).?;
        rl.drawCircleLinesV(.{ .x = c.x, .y = c.y }, demo.radius, rl.getColor(0x2E3440FF));

        var it = ecs.query_iter(world, balls);
        while (ecs.query_next(&it)) {
            const ps = ecs.field(&it, sim.Position, 0).?;
            const bs = ecs.field(&it, sim.Ball, 1).?;
            for (ps, bs) |p, b| rl.drawCircleV(.{ .x = p.x, .y = p.y }, b.radius, rl.getColor(b.rgba));
        }

        rl.drawText("uber-graphen: raylib + flecs", 16, 16, 20, rl.getColor(0x8892A0FF));
        rl.drawFPS(width - 96, 16);
    }
}
