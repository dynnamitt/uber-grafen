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
        _ = ecs.progress(world, rl.getFrameTime());

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        rl.drawText("uber-graphen: raylib + flecs", 190, 200, 20, .light_gray);
    }
}
