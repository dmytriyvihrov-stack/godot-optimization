# Godot Optimization: a Claude skill

**Keywords:** AI game development, game optimization, Godot 4 performance, Claude Code plugin, Claude skill, GDScript, FPS, draw calls, web export.

A [Claude](https://claude.com) skill that makes a **Godot 4** game faster **without changing how it looks or plays**.
Claude checks the machine, measures, splits the frame until the cost has a name, cuts it, proves the new picture is
pixel-identical to the old one, and compares old and new builds before anything ships.

Learned on a real Godot 4.7 2D action game with hundreds of enemies and effects, using the Compatibility renderer for
the web export:

| | before | after |
|---|---|---|
| heaviest level, average frame | 38 ms | 19.5 ms |
| worst frames | 120 to 170 ms | 35 to 45 ms |
| draw calls on that level | 2287 | 112 |
| web build load on itch.io | 21 s | 9 s |

Every cut was proven pixel-identical. The rules were then checked against Godot's engine source and docs and against
how shipped games stayed fast (Halls of Torment, Cassette Beasts, Vampire Survivors, Noita, Factorio).

**Not using Claude?** The same method as a step-by-step checklist: [GUIDE.md](GUIDE.md).

## What it covers

- **Checking the machine first**: battery, CPU load and other programs fake slow runs, so it checks them before any timing.
- **Measuring**: a frame meter (average, p95, worst, frames over 17 / 33 / 50 ms, draw step, GPU, draw calls), wrapping
  `_process` / `_draw` with stopwatches, switching groups off until the cost moves, first-time cost or content.
- **2D drawing in the Compatibility renderer (GLES3 / WebGL 2)**: why `draw_polygon`, `draw_circle`, `draw_arc` and
  `draw_polyline` are a draw call each, when to use `draw_primitive`, when to use one `ArrayMesh`, what breaks
  batching, redrawing only on change, culling, cell-by-cell loops, lights and shadows, GPU readback.
- **GDScript hot paths**: typing, packed arrays, allocation, spatial lookups, work done twice.
- **Physics, loading and frame pacing**: physics interpolation, loading hitches, V-Sync and why the p95 matters more
  than the average, ANGLE on Windows.
- **Proving it looks the same**: shape-against-shape SubViewport diffs and whole-screen diffs.
- **Keeping it fast**: a benchmark log and a performance guideline in the repo.
- **Web export size**: what is really in the `.pck`, excluding folders, a slim engine build without 3D.

Included scripts (`plugins/godot-optimization/skills/godot-optimization/scripts/`):

| file | what it does |
|---|---|
| `prim.gd` | `Prim`: quads, polygons, discs, arcs and polylines as batched four-point `draw_primitive`s, matching the engine's pixels. For drawings redrawn every frame. |
| `tri_batch.gd` | `TriBatch`: many shapes of a kept drawing triangulated into one `ArrayMesh`, one `draw_mesh`. |
| `frame_meter.gd` | A frame meter for any scene; prints avg / p95 / worst / spikes and appends to a log. |
| `img_diff.gd` | Two screenshots pixel against pixel, with a diff image. |

## Install

### Claude Code: as a plugin (recommended)

In Claude Code, run:

```
/plugin marketplace add dmytriyvihrov-stack/godot-optimization
/plugin install godot-optimization@godot-optimization
```

Restart the session if the skill does not show up at once.

### Claude Code: copy the folder

For every project (your user skills):

```bash
git clone https://github.com/dmytriyvihrov-stack/godot-optimization.git
cp -r godot-optimization/plugins/godot-optimization/skills/godot-optimization ~/.claude/skills/
```

Or for one project only, copy it into that project's `.claude/skills/` folder instead. On Windows (PowerShell):

```powershell
git clone https://github.com/dmytriyvihrov-stack/godot-optimization.git
Copy-Item -Recurse godot-optimization\plugins\godot-optimization\skills\godot-optimization "$env:USERPROFILE\.claude\skills\"
```

### Claude.ai or the Claude desktop app

Zip the `plugins/godot-optimization/skills/godot-optimization` folder (the zip must contain the `godot-optimization`
folder with `SKILL.md` inside it), then upload it in **Settings → Capabilities → Skills**. Skills need to be enabled for
your plan.

## Use

You do not have to name the skill: Claude loads it when the task matches. Ask in your Godot project, for example:

- "My game drops to 40 FPS on level 3. Find out why."
- "This `_draw` runs every frame, review it for performance."
- "We have 2000 draw calls, cut them without changing the picture."
- "The web build takes 20 seconds to load on itch.io."
- "Set up a benchmark so we notice when a change makes the game slower."

To use a script, copy it into your project (for example `res://tools/`). The frame meter runs like this:

```bash
godot --path . --audio-driver Dummy --windowed --fixed-fps 60 --script res://tools/frame_meter.gd -- \
  scene=res://levels/level_3.tscn frames=900 warmup=120 log=user://bench.txt label=before
```

## What it will not do unasked

It never trades the look or feel for speed: fewer lights, softer shadows, a lower resolution, enemies thinking less
often, a lower physics tick or a 30 fps mode are design changes. Claude proposes those with numbers and leaves the
choice to you.

## Requirements

Godot 4.x (written against 4.7; most of it applies from 4.2). The drawing advice is about the Compatibility renderer
(OpenGL / WebGL 2); the measuring, scripting, physics and loading parts apply to every renderer.

## Privacy

This plugin collects, stores and sends no data. It is one skill (instructions for Claude) and four GDScript files you
copy into your own project and run yourself. It has no MCP servers, no hooks, no network calls and no telemetry.

## License

MIT, see [LICENSE](LICENSE).
