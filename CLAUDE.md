# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`uber-graphen` — Zig scaffold combining **Raylib** (window + rendering, via `raylib-zig`) and **Flecs ECS** (via `zflecs`). `src/main.zig` renders a two-ball orbit demo driven by the ECS. Native desktop only for now (no web target).

## Toolchain

**Zig 0.17.x** (`minimum_zig_version = "0.17.0"`; CI pins 0.17.1). Both dependencies require 0.17. The 0.17 API differs from older tutorials: modules come from `b.createModule` + `exe_mod.linkLibrary(...)`; run args use `run_cmd.addPassthruArgs()` (there is no `b.args`); `zig init`'s `main` takes `std.process.Init`.

## Commands

```sh
zig build                    # compile → zig-out/bin/uber-graphen
zig build run                # compile and launch
zig build test               # headless unit tests (src/sim.zig); single test: zig build test -Dtest-filter="<name>"
zig fmt --check build.zig build.zig.zon src   # formatting check, as CI runs it
```

On Linux, raylib's GLFW backend needs X11/GL **dev headers** (`libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxi-dev libgl-dev`). `zig build test` does not link raylib, so it works without them.

CI (`.github/workflows/ci.yml`) runs fmt check → `zig build test` → `zig build` on pull requests (and manually via workflow_dispatch).

## Dependencies

Pinned by commit + content hash in `build.zig.zon`: `raylib_zig` (raylib-zig org — moved from Not-Nik/raylib-zig) and `zflecs` (zig-gamedev, bundles flecs v4.1.x). Update with `zig fetch --save git+https://github.com/<repo>#<commit>`. Zig 0.17 unpacks packages into a **project-local `zig-pkg/`** directory (gitignored), not only the global cache.

Transitive deps: raylib-zig → raylib, raygui, emsdk; zflecs → translate-c → arocc (both on **codeberg.org**). Fetching needs github.com and codeberg.org.

## Architecture

`build.zig` defines two modules:

- **`sim`** (`src/sim.zig`): components, systems, `register(world)` and `spawnDemo`. Imports only `zflecs`, never raylib (colours are `u32` 0xRRGGBBAA). This is the test root, so ECS logic stays testable without a window or GPU. Keep game state and systems here (or in files it imports).
- **exe root** (`src/main.zig`): imports `raylib`, `zflecs` and `sim`. Owns the window and the frame loop: `ecs.progress(world, dt)`, then draws every `Position + Ball` entity via `sim.ballQuery`. raylib's first-frame `dt` of 0 is replaced with 1/60 (flecs would otherwise measure its own); real frame times are never floored.

Current demo: a static `Attractor` ball and an `Orbits` ball circling it. `gravity` runs in `PreUpdate` and `move` in `OnUpdate`, which makes it semi-implicit Euler: the orbit stays bounded (radius wobbles ~±3% at 120 steps/orbit) instead of spiralling out. Keep that phase order if you add systems.

Keep that boundary: systems that change state go in `sim`. Rendering reads ECS data from the main/render side, so the renderer can be swapped later.

### ECS conventions (zflecs)

Components are plain Zig structs registered with `ecs.COMPONENT`. Systems are registered with `ecs.ADD_SYSTEM(world, name, phase, fn)`, where `fn` takes slices of components (optionally `*ecs.iter_t` first, e.g. for `it.delta_time`). The zflecs README and its `src/tests.zig` (in `zig-pkg/zflecs-*/`) are the best API reference.
