---
name: zig-ray-flecs
description: Setup check for this Zig + raylib + Flecs (zflecs) repo. Lists the agent skills and the Zig language server (ZLS via the zig-lsp plugin) that this project expects, and the commands that install them. Use it at the start of any Zig work here, before you edit .zig, build.zig or build.zig.zon, when you touch raylib or zflecs code, and whenever a skill named below (zig-0-17, zig-best-practices, zig-cinterop, zig-raylib-5.5) or the zig-lsp/ZLS tooling seems to be missing.
---

# zig-ray-flecs: skill and LSP sentinel

The repo doesn't commit the third-party skills it uses. `.claude/skills/*` is gitignored,
except for this skill. `skills-lock.json` pins each skill's source and commit, so every
machine installs the same versions. This skill checks what is missing and suggests the fix.
Suggest commands to the user. Don't install anything unasked: installs write to the user's
machine and pull third-party content.

## 1. Check the skills

Each skill is installed when `.claude/skills/<name>/SKILL.md` exists. A skill that shows up
in your available-skills list counts as installed too, even if it was installed globally.

| Skill | Why | In lock? |
|---|---|---|
| `zig-0-17` | Zig 0.17 API: this repo pins 0.17, and older tutorials mislead | yes |
| `zig-best-practices` | Zig idioms for any `.zig` file | yes |
| `zig-cinterop` | translate-c and C ABI work: zflecs and raylib wrap C | yes |
| `zig-raylib-5.5` | raylib-zig bindings API for drawing, input, textures, cameras | yes |

If any skill marked "yes" is missing, tell the user it is missing and suggest:

```sh
npx skills experimental_install -a claude-code   # restore everything pinned in skills-lock.json
```

`zig-raylib-5.5` targets Zig 0.15 and raylib 5.5. Where it disagrees with the zig-0-17 skill
or with `zig-pkg/raylib_zig-*/` sources, the sources win.

There is no Flecs skill on skills.sh (checked 2026-11). For zflecs, use the README and
`src/tests.zig` under `zig-pkg/zflecs-*/`, plus the ECS conventions in `CLAUDE.md`.

## 2. Check the Zig language server

The `zig-lsp` plugin connects ZLS to Claude Code's LSP tool: go-to-definition, references and
diagnostics without a full `zig build`. Its SessionStart hook installs the ZLS build that
matches `zig version` into `~/.local/share/zls/<ver>/` and links `~/.local/bin/zls`.

It is installed if the session started with a "Checking ZLS installation..." hook message,
or if `command -v zls` succeeds and `zls --version` matches `zig version`.

If it is missing, suggest the user run these two commands in Claude Code, then restart the
session:

```
/plugin marketplace add 4rgon4ut/cc-zig-lsp
/plugin install zig-lsp@cc-zig-lsp
```

`~/.local/bin` must be on `PATH`. If ZLS and Zig versions drift (Zig rolls forward on
Manjaro), restart the session so the hook fetches the matching ZLS.

## 3. Then get on with the task

Report missing pieces in one short line with the commands, then continue the user's actual
request. Don't block on the user installing anything.
