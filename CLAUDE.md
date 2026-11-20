# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`uber-graphen` — Zig scaffold combining **Raylib** (window + rendering, via `raylib-zig`) and **Flecs ECS** (via vendored `zflecs`). Only the wiring exists: `src/main.zig` opens a window, creates a Flecs world, and runs an empty Raylib loop. No components, systems or game logic yet.

## Toolchain: Zig 0.11.x only

The build scripts (`build.zig`, `zflecs/build.zig`) use the **Zig 0.11** `std.Build` API: `std.zig.CrossTarget`, `std.Build.CompileStep`, `target.getOsTag()`, `exe.addModule(...)`, `.{ .path = ... }` LazyPaths, `createModule(.{ .source_file = ... })`. All of these were renamed or removed in 0.12+. Use a 0.11 compiler. Moving to a newer Zig means porting both build files **and** updating the `raylib-zig` submodule plus re-vendoring `zflecs` together, because they have to match the same API.

## Commands

```sh
zig build                        # compile → zig-out/bin/uber-graphen
zig build run                    # compile and launch
cd zflecs && zig build test      # zflecs binding tests (zflecs/src/zflecs.zig); the app itself has no tests
make web_target                  # WASM/HTML5: zig build run -Dtarget=wasm32-emscripten --sysroot $EMSDK/upstream/emscripten
make clean                       # rm -rf zig-cache zig-out
```

No lint step is configured (`zig fmt` is the conventional formatter).

## Dependencies — read before building

| Path | What | Notes |
|---|---|---|
| `raylib-zig/` | git submodule (Not-Nik/raylib-zig) pinned at `239d3a2` | `.gitmodules` sets `url = ./raylib-zig`, a self-referential relative path, so `git submodule update --init` **cannot fetch it** and the directory is empty in a fresh clone. To build, check out Not-Nik/raylib-zig at that commit into `raylib-zig/`, or fix the URL. `build.zig` does `@import("raylib-zig/build.zig")`, so the build fails at once without it. |
| `zflecs/` | plain copy of `libs/zflecs` from michal-z/zig-gamedev | Not a submodule. Compiles `libs/flecs/flecs.c` into a static lib with `-DFLECS_NO_CPP -DFLECS_USE_OS_ALLOC` (plus `-DFLECS_SANITIZE` in Debug). Updating it means copying it over again (see README). |
| `build.zig.zon` | pins the raylib **C** source tarball | Still carries the template's `.name = "raylib-zig"`. Its `raylib` dependency is what `raylib-zig/build.zig` resolves. |

## Build architecture

`build.zig` imports the helper `build.zig` files of both deps and branches on the target OS:

- **Native**: `rl.link` + `zflecs_pkg.link(exe)`, then exposes modules `raylib`, `raylib-math` and `zflecs` to `src/main.zig`.
- **Emscripten**: returns early on a separate path. `rl.compileForEmscripten` builds a static lib, and `rl.linkWithEmscripten` links it with the raylib artifact into HTML5/WASM. **zflecs is never linked on this path** (the known TODO). Because `main.zig` imports `zflecs`, the web build is broken until `zflecs_pkg.link(exe_lib)` is added and the flecs C lib is passed to `linkWithEmscripten`.

## ECS conventions (zflecs)

Components are plain Zig structs registered on the world. Systems are callbacks bound to a query and a phase (e.g. `ecs.OnUpdate`). Run the world each frame with `ecs.progress(world, delta_time)` inside the Raylib loop, between `beginDrawing`/`endDrawing` or before them. `zflecs/README.md` has API examples, and `zflecs/src/tests.zig` has working usage of the binding.
