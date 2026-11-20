# zig/raylib/flecs

![rayzigflecs](tech-trio.svg)

Zig 0.17 scaffold: [raylib-zig](https://github.com/raylib-zig/raylib-zig) for window + rendering,
[zflecs](https://github.com/zig-gamedev/zflecs) for ECS. Both come in as Zig packages pinned in `build.zig.zon`.

```sh
zig build test   # headless ECS unit tests
zig build run    # launch (Linux needs X11/GL dev headers, see .github/workflows/ci.yml)
```

## Updating deps

```sh
zig fetch --save git+https://github.com/raylib-zig/raylib-zig#<commit>
zig fetch --save git+https://github.com/zig-gamedev/zflecs#<commit>
```

## TODO
- real `main` (current one is a placeholder window)
- web target (raylib-zig ships emsdk helpers: `@import("raylib_zig").emsdk`)
