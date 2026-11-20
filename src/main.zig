const rl = @import("raylib");
const ecs = @import("zflecs");
const sim = @import("sim");

pub fn main() !void {
    rl.initWindow(800, 450, "uber-graphen");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const world = ecs.init();
    defer _ = ecs.fini(world);
    sim.register(world);

    while (!rl.windowShouldClose()) {
        // raylib reports 0 on the first frame; flecs treats 0 as "measure it
        // yourself", so clamp to keep the ECS on raylib's clock.
        _ = ecs.progress(world, @max(rl.getFrameTime(), 1.0 / 60.0));

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        rl.drawText("uber-graphen: raylib + flecs", 190, 200, 20, .light_gray);
    }
}
