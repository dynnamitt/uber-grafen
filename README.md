# zig-rayflecs

[![Zig 0.17](https://img.shields.io/badge/Zig-0.17-F7A41D?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![WebGL](https://img.shields.io/badge/WebGL-live_demo-990000?logo=webgl&logoColor=white)](https://dynnamitt.github.io/zig-rayflecs/)
[![WebAssembly](https://img.shields.io/badge/WebAssembly-emscripten-654FF0?logo=webassembly&logoColor=white)](https://emscripten.org/)

![rayzigflecs](tech-trio.svg)

Zig 0.17 scaffold: [raylib-zig](https://github.com/raylib-zig/raylib-zig) for window + rendering,
[zflecs](https://github.com/zig-gamedev/zflecs) for ECS. Both come in as Zig packages pinned in `build.zig.zon`.

```sh
zig build test   # headless ECS unit tests
zig build run    # launch (Linux needs X11/GL dev headers, see .github/workflows/ci.yml)
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall   # browser build → zig-out/web/
```

<!-- template -->
## Using this template

1. **Use this template** on GitHub, clone the new repo, run `./runme1st.sh` (or `./runme1st.sh my-game` for a name other than the repo's). It renames the package, binary, titles and Pages URLs and recomputes `.fingerprint` (needs `perl`), then deletes itself and this section. Review `git diff` and commit.
2. Settings → Pages → Source: **GitHub Actions**. Templates don't copy repo settings.
<!-- /template -->

## Updating deps

```sh
zig fetch --save git+https://github.com/raylib-zig/raylib-zig#<commit>
zig fetch --save git+https://github.com/zig-gamedev/zflecs#<commit>
```

Live demo, redeployed from `main` on every push: https://dynnamitt.github.io/zig-rayflecs/
