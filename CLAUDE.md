# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`uber-graphen` — Zig scaffold combining **Raylib** (window + rendering, via `raylib-zig`) and **Flecs ECS** (via `zflecs`). `src/main.zig` renders a two-ball orbit demo driven by the ECS. Builds natively and for the browser (`wasm32-emscripten`).

## Toolchain

**Zig 0.17.x** (`minimum_zig_version = "0.17.0"`; CI pins 0.17.1). Both dependencies require 0.17. The 0.17 API differs from older tutorials: modules come from `b.createModule` + `exe_mod.linkLibrary(...)`; run args use `run_cmd.addPassthruArgs()` (there is no `b.args`); `zig init`'s `main` takes `std.process.Init`.

Agent skills are not committed: `skills-lock.json` pins them and `npx skills experimental_install -a claude-code` restores them (gitignored, under `.agents/` and `.claude/skills/`). The tracked `zig-ray-flecs` skill checks which skills and ZLS (`zig-lsp` plugin) are missing and how to install them.

## Commands

```sh
zig build                    # compile → zig-out/bin/uber-graphen
zig build run                # compile and launch
zig build run -Dnewcomers=10000   # load test (default 42 newcomer balls)
zig build run -Dnewcomers=100000 -Dthreads=8   # + Flecs worker threads (native only; default 0)
zig build test               # headless unit tests (src/sim.zig); single test: zig build test -Dtest-filter="<name>"
zig fmt --check build.zig build.zig.zon src   # formatting check, as CI runs it
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall   # web → zig-out/web/index.{html,js,wasm}
zig build run -Dtarget=wasm32-emscripten                       # web build + serve with emrun
```

The web build installs the Emscripten SDK on first use, into `zig-pkg/<emsdk hash>/` via raylib's "Activate EMSDK" step. That needs network access to github.com and storage.googleapis.com, and no system emsdk or `EMSDK` variable.

On Linux, raylib's GLFW backend needs X11/GL **dev headers** (`libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxi-dev libgl-dev`). `zig build test` does not link raylib, so it works without them.

CI (`.github/workflows/ci.yml`) runs on pull requests (and manually via workflow_dispatch). Job `build-test` runs fmt check → `zig build test` → `zig build`. Job `web` runs the emscripten build and uploads `zig-out/web` as the `web` artifact. `.github/workflows/pages.yml` runs `zig build test` and then the same web build on every push to `main`, and deploys it (deploys are never cancelled midway) to GitHub Pages (`https://dynnamitt.github.io/uber-grafen/`). That needs Settings → Pages → Source: **GitHub Actions**. Both workflows key the Emscripten SDK cache on the `emsdk` and `raylib_zig` hashes in `build.zig.zon`, which they read with `sed`, so keep those entries in their `.name = .{ ... .hash = "..." }` form.

## Dependencies

Pinned by commit + content hash in `build.zig.zon`: `raylib_zig` (raylib-zig org — moved from Not-Nik/raylib-zig) and `zflecs` (zig-gamedev, bundles flecs v4.1.x). Update with `zig fetch --save git+https://github.com/<repo>#<commit>`. Zig 0.17 unpacks packages into a **project-local `zig-pkg/`** directory (gitignored), not only the global cache.

Transitive deps: raylib-zig → raylib, raygui, emsdk; zflecs → translate-c → arocc (both on **codeberg.org**). Fetching needs github.com and codeberg.org.

## Architecture

`build.zig` defines two modules:

- **`sim`** (`src/sim.zig`): components, systems, `register(world)` and `spawnDemo`. Imports only `zflecs`, never raylib (colours are `u32` 0xRRGGBBAA). This is the test root, so ECS logic stays testable without a window or GPU. Keep game state and systems here (or in files it imports).
- **exe root** (`src/main.zig`): imports `raylib`, `zflecs` and `sim`. Owns the window and `frame()`, which keeps its state in file-level globals. Natively a `while (!rl.windowShouldClose())` loop calls `frame()`. On web, `std.os.emscripten.emscripten_set_main_loop(frame, 0, 1)` runs it on requestAnimationFrame, with no `setTargetFPS` and no `windowShouldClose` (their sleeps aren't vsync-aligned). `sim.FixedClock` turns raylib's frame time into fixed `sim.step_dt` (1/60 s) steps, at most `max_steps_per_frame` per frame (any further backlog is dropped). Each step calls `ecs.progress(world, sim.step_dt)`, then the frame draws every `Position + Ball` entity via `sim.ballQuery`. Entities with `PrevPosition` (copied by the `snapshot` system in `OnLoad`) are drawn at `lerp(prev, cur, clock.alpha())`, so motion stays smooth when frames and steps don't line up. The top-right readout shows FPS and CPU work time: mean/max ms per frame over 0.5 s (`sim.FrameStats`), measured up to just before present (after flushing raylib's last batch). GPU time, swap and vsync waits are left out. Never pass raw frame time to `ecs.progress`: a long frame (hidden tab, dragged window) flings the orbiter out for good, and dt=0 makes flecs measure its own clock.

Current demo: a static `Attractor` ball and a ball circling it via the `(Orbits, center)` relationship, plus newcomers (`spawnNewcomers` in sim, entry ring in `main.zig`): 42 by default, which Pages ships; load-test with `-Dnewcomers=N`. Each starts off-screen at a random angle, flies straight past the attractor through the void on its left or right, and carries the pair `(Capture, center)`. Side, speed, capture point and colour (one of four sand shades) are random per ball, within ranges at the top of `sim.zig` that keep every captured orbit on screen; the `capture` system (`PostUpdate`) swaps it for `(Orbits, center)` once it is its capture distance past the attractor. Colours come from `tech-trio.svg`: ball colours at the top of `sim.zig`, render-only ones in `main.zig` and `web/shell.html`. `gravity` runs in `PreUpdate` and `move` in `OnUpdate`, which makes it semi-implicit Euler: the orbit stays bounded (radius wobbles ~±3% at 120 steps/orbit) instead of spiralling out. Keep that phase order if you add systems. `gravity` and `capture` read the center's components by following the relationship `up` (`onCenter`), so their queries stay fully cached. Worker threads (`-Dthreads`) only pay off far beyond the default ball count, so they are off by default and rejected for web (wasm threads need COOP/COEP headers, which Pages can't send).

Keep that boundary: systems that change state go in `sim`. Rendering reads ECS data from the main/render side, so the renderer can be swapped later.

### Web build (`addWebBuild` in build.zig)

- The app is compiled as a static library. raylib-zig's `emsdk.emccStep` then links it with raylib and flecs (it picks up libraries linked into the module graph) into `zig-out/web/index.*`, using `web/shell.html` as the page template.
- **zflecs has no emscripten support**, so `build.zig` adds the emsdk sysroot include path to the `flecs` artifact. It also makes that artifact depend on **raylib's existing** "Activate EMSDK" step, found with `findStep`. Do not call `emsdk.activateEmsdkStep(b)` a second time: two activations run `emsdk update/install` concurrently in the same directory.
- `emsdk` must stay in **our** `build.zig.zon` (lazy). raylib-zig's helpers resolve it from the root build.
- Asyncify is off (`.asyncify = false`): the browser drives `frame()` through `emscripten_set_main_loop`. That keeps the wasm about 40% smaller. Don't reintroduce blocking loops or `emscripten_sleep` on web.
- `main.zig` overrides `std.heap.page_allocator` on emscripten (`pub const os`): zflecs allocates through it, and Zig's wasm default calls `memory.grow`, which fails on emscripten's fixed heap (`panic: OOM`). The replacement must return aligned, zero-filled memory (zflecs' `DebugAllocator` relies on zeroed pages).
- `STACK_SIZE` is raised from emscripten's 64 KiB (`web_stack_size` in build.zig); Debug web builds overflow the default.
- CI fails the web build on any `wasm-ld: function signature mismatch` warning: wasm-ld turns such calls into runtime traps.

### ECS conventions (zflecs)

Components are plain Zig structs registered with `ecs.COMPONENT`. Relationships with no data (`Orbits`) are registered with `ecs.TAG`. Systems are registered with `addSystem(world, name, phase, fn, extra_terms)` in `sim.zig`, where `fn` takes slices of components (optionally `*ecs.iter_t` first, e.g. for `it.delta_time`); read extra terms with `ecs.field` at the named indices at the top of `sim.zig`. Systems must stay safe to split across workers: write only the iterated entities, and make structural changes through `it.world`. The zflecs README and its `src/tests.zig` (in `zig-pkg/zflecs-*/`) are the best API reference, except: **never use `ecs.set`, `ecs.set_pair` or `ecs.set_id`.** zflecs declares `ecs_set_id` with a wrong return type, so these trap on web; use `set` in `sim.zig`.
