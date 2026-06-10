# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Zig graphics/game project combining **Raylib** (window + rendering) and **Flecs ECS** (`zflecs`). Currently a stub — the architecture is wired up but the actual application logic has not been written yet.

## Commands

```sh
zig build          # compile
zig build run      # compile and launch
make web_target    # WASM/HTML5 build (requires EMSDK env var pointing to Emscripten SDK)
make clean         # rm -rf zig-cache zig-out
```

No test or lint steps are configured yet.

## Architecture

### Dependency layout

| Path | Source | Role |
|---|---|---|
| `raylib-zig/` | git submodule (Not-Nik/raylib-zig) | Zig bindings + build helpers for Raylib |
| `zflecs/` | local copy from michal-z/zig-gamedev | Zig bindings for Flecs ECS (C) |
| `build.zig.zon` | Zig package manifest | pins the raylib C library version |

### Build targets

`build.zig` branches on `target.getOsTag()`:

- **Native** — links Raylib + zflecs into a standard executable (`zig-out/bin/uber-graphen`).
- **Emscripten** — compiles to a static lib, then calls `rl.linkWithEmscripten` to produce a WASM+HTML5 bundle. **zflecs linking is broken for this target** (open TODO).

### Application structure

`src/main.zig` is the sole source file right now. It:
1. Opens a Raylib window and sets 60 FPS target.
2. Creates a Flecs world (`ecs.init()`).
3. Runs the standard Raylib game loop (`while !windowShouldClose`).

All game logic, ECS components/systems, and rendering work goes here (or in files imported from here).

### ECS conventions (zflecs)

Components are plain Zig structs registered on the world. Systems are callbacks bound to a query and a phase (e.g. `ecs.OnUpdate`). Drive the world each frame with `ecs.progress(world, delta_time)`. See `zflecs/README.md` for full API examples.
