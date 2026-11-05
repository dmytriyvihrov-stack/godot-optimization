---
name: godot-optimization
description: >
  Make a Godot 4 game faster without changing how it looks or plays, and keep it fast: check the machine, measure, split
  until the cost has a name, cut it, prove the picture is pixel-identical, compare with the old build. Covers the
  Compatibility (GLES3 / WebGL 2) renderer's 2D batching and draw calls (draw_polygon, draw_circle, draw_arc,
  draw_polyline vs draw_primitive vs one ArrayMesh), redraw on change, culling, cell-by-cell loops, 2D lights and
  shadows, GPU readback, GDScript hot paths, physics, loading hitches, V-Sync and frame pacing, benchmarks, and a smaller
  web export. Use for any Godot speed work: low FPS, stutter or hitches, slow level loads, too many draw calls, a review
  of code that draws or runs every frame, a slow web build. Triggers: godot performance, optimize godot, optimise, FPS,
  fps drops, stutter, hitch, frame time, draw calls, batching, vsync, slow web export, pck too big, лаги, тормозит,
  оптимизация, производительность, фпс.
---

# Godot 4 optimization: faster, and the same picture

Learned on a shipped-to-testers Godot 4.7 2D action roguelite (Compatibility renderer for the web export, an AMD Vega 11
laptop at 2496 x 1664, hundreds of enemies and effects): the heaviest level went from 38 to 19.5 ms a frame, the worst
frames from 120 to 170 ms down to 35 to 45, levels loaded 0.4 to 1 s sooner, the web build's load on itch.io from 21 s
to 9 s. Every cut was proven pixel-identical. Then checked against Godot's engine source and docs and against how
shipped games stayed fast (Halls of Torment, Cassette Beasts, Vampire Survivors, Noita, Factorio).

Files beside this one:
- `references/recipes.md`: code for the techniques that paid most.
- `references/measuring.md`: the frame meter, splitting a frame, the proof harness, a benchmark log.
- `references/web-export.md`: a smaller, faster-loading web build (what is in the pack, a slim engine without 3D).
- `scripts/prim.gd`, `scripts/tri_batch.gd`: drop-in batched drawing helpers. `scripts/frame_meter.gd`: a frame meter
  to adapt. `scripts/img_diff.gd`: two screenshots pixel against pixel.

**The rule above all: a cheaper way must look and play the same.** A cut that changes the picture or the feel (fewer
lights, softer shadows, lower resolution, enemies thinking less often, cheaper collision, fewer effects, a lower physics
tick, a 30 fps mode) is a design change: propose it with numbers, never ship it unasked.

## 1. Before measuring: check the machine

A slow number on a loaded or unplugged laptop sends you hunting a regression that is the machine. Before the first timed
run of a session, and again when a run looks off:

```powershell
Get-CimInstance Win32_Battery | Select-Object BatteryStatus,EstimatedChargeRemaining   # 2 = on the charger, 1 = battery
(Get-CimInstance Win32_Processor).LoadPercentage                                       # idle should be under ~15
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,CPU
powercfg /getactivescheme
```

(macOS: `pmset -g batt`, `top -l 1 -o cpu | head -20`; Linux: `cat /sys/class/power_supply/*/status`, `top -bn1 | head`.)

- On battery, a battery-saver plan, or something heavy running (a browser with many tabs, an AI app, another Godot, a
  video): say so and ask the user to plug in and close what they can. Never kill their programs. If they say go on,
  mark every number as taken under those conditions.
- A laptop drifts 1 to 2 ms a frame as it warms: compare old and new **alternated, at least twice each**, never one run
  against one.
- One Godot run at a time, each with a hard timeout; long batches in the background.
- Test runs silent (`--audio-driver Dummy`) and windowed. An unfocused test window is throttled by the OS when V-Sync is
  on: never judge V-Sync from a test window.
- Run on a throwaway save, never the player's own: games that deal content off saved progress lay something else every
  run otherwise, and a probe can corrupt real progress.

## 2. Finding the cost: split until it has a name

Never optimise by guessing. On the game this was learned on, the guesses (decals, shader compiles, physics, a fog layer)
were wrong every time; splitting found polygons, draw calls, a view built twice per level, and per-cell loops.

1. **A frame meter** (`scripts/frame_meter.gd`, details in `references/measuring.md`): the real game on a fixed level
   and seed, `--fixed-fps 60`, V-Sync off, `Engine.max_fps = 0`. Per frame: wall time, the physics step, the draw step
   (`RenderingServer.frame_pre_draw` to `frame_post_draw`), GPU and render CPU
   (`viewport_set_measure_render_time`, a few frames late), draw calls and items drawn. Report average, p95, worst,
   frames over 17 / 33 / 50 ms, and each spike with what ran in it.
2. **Wrap every `_process`, `_physics_process`, `_draw`, `_integrate_forces`** with a stopwatch (a throwaway edit, on top
   of committed work so a revert cannot lose anything) and rank them per frame. Then wrap the parts inside the top one.
3. **Hide or switch off groups** (`visible = false`, `process_mode = PROCESS_MODE_DISABLED`) and see whether the cost
   moves. Print the path of what you hid: a name can match the wrong node. A cost that stays with everything hidden is
   not the content.
4. **First time, or content?** Load the same level twice in one process. Gone the second time: warm it during loading.
   Still there: it is what is drawn or run.
5. **A micro-benchmark settles an engine question** in a minute (200 `draw_polygon` against 200 `draw_primitive` a frame).

## 3. Drawing in the Compatibility renderer (GLES3, also WebGL 2)

- **Only rects, nine-patches and primitives batch.** `draw_polygon`, `draw_colored_polygon`, `draw_circle`, `draw_arc`,
  `draw_polyline` and `draw_multiline` each make their own GPU buffers when recorded and are a draw call of their own
  every frame after. 200 a frame cost 29 ms on OpenGL (40 on ANGLE), with frames stalled 50 to 250 ms.
- **Redrawn every frame: draw shapes as `draw_primitive`s** (`scripts/prim.gd`), all with four points: a batch breaks
  when the point count changes, so a triangle is a quad with its last point twice. The engine's shapes can be matched to
  the pixel: draw_polygon cuts a quad 0-1-3 / 1-2-3; draw_circle is a 64-sided fan; a thick polyline has mitred joints
  and square ends; any polygon is `Geometry2D.triangulate_polygon`.
- **Kept (drawn once, redrawn on change) with many shapes: one `ArrayMesh`** with vertex colours, one `draw_mesh`
  (`scripts/tri_batch.gd`); flush before any texture draw so the order holds. 2287 draw calls became 112.
- **Kept with a few shapes: the engine's calls are fine.** Primitives are batched again every frame, so primitives on a
  kept drawing cost more than polygons (it made a level 4 ms slower).
- **Batches break** on a change of texture, material, blend mode, filter, clip, lit or unlit, command type, primitive
  point count. Share textures (atlases) and materials; a unique `ShaderMaterial` per unit stops units batching.
- **Redraw only on change.** A `_draw` is recorded once and kept until `queue_redraw()`. Give it a key of what it shows
  (an int or a small array) and queue a redraw only when the key moves. A flame animated at 12 fps redrawn at 60 is
  five times the work for the same picture.
- **Culling is per CanvasItem, by the rect of its commands.** A level-sized custom drawing is never culled and every
  light touches it: cut big drawings into items about a screen across.
- **Cells on the floor** (telegraphs, cones, rings drawn in pixel cells): test only the cells of the shape's bounding
  box, keep the per-cell test exactly as it was, and lay each row's run of one colour as one rect. Parse colours outside
  the loop. A cone that tested 25 000 cells a frame cost 1.4 ms.
- **No GPU readback during play**: `Texture2D.get_image()` and `viewport.get_texture().get_image()` stall the pipeline.
  Keep a CPU copy when you make the texture; import a sheet you read pixels from as an Image.
- **Lights are per pixel**: each light, more so a shadowed one with PCF, costs every pixel it touches, and a shadowed
  light redraws every occluder in range four times a frame. Keep `item_cull_mask` and occluder masks tight, merge
  occluders.
- **Bake what does not change** (floors, walls, decals) into textures or tile layers once; animate only what moves.
- **Pre-warm first-time costs** during loading or on the title screen (bake effect frames, load the sheets a level needs).

## 4. Scripts (GDScript)

- Typed GDScript everywhere; packed arrays over typed arrays over untyped; int enums over strings.
- "Who is near" from a grid or per-room lists, never a scan of every entity; rooms far from the player sleep.
- Cache per physics frame (`Engine.get_physics_frames()`), never per wall time.
- No allocation in hot paths: no `str(array)` as a cache key, no `Color("#hex")` per frame or per cell, no new Arrays or
  Dictionaries per entity per frame, no lambda called per tile; read a string row once and compare `unicode_at` codes.
- Throttle what nobody needs every frame (an interval in data); spread heavy passes over several frames.
- **Look for work done twice before making it faster** (a level view built by two callers cost 0.4 to 1 s a level).
- Native code (C++ / GDExtension) only for one proven hot spot, as Halls of Torment and Cassette Beasts did.

## 5. Physics, loading, pacing

- Physics at 60 Hz with physics interpolation on; never lower the tick for speed. After a teleport or spawn call
  `reset_physics_interpolation()`. Simple shapes, tight layers and masks, sleeping bodies. `TileMapLayer` (4.5+) merges
  cell shapes per physics quadrant.
- Loading holds the main thread, and a loading animation freezes for every second of it. Time each step of a level's
  load; what comes in bursts (a wave, bullets) is made ahead and pooled; `ResourceLoader.load_threaded_request` for big
  resources (not on a single-threaded web build).
- **V-Sync** (`DisplayServer.window_set_vsync_mode`; Compatibility has only enabled or disabled): with it on, a frame
  that misses one refresh (16.7 ms at 60 Hz) waits for the next and shows at 33 ms. A game averaging 12 ms with a p95 of
  20 reads as 30 to 40 fps. To hold 60, the **p95 and the hitches** must fall under 16.7 ms, not the average. Off, cap
  with `Engine.max_fps` at the refresh rate.
- On Windows, ANGLE (`--rendering-driver opengl3_angle`, D3D11) can remove OpenGL driver stalls at some average cost:
  measure both, offer, do not switch the default unasked.

## 6. Proving it looks the same (never skip)

- **Shape against shape**: draw the engine's call and the cheap version into two SubViewports (a windowed run: the dummy
  renderer of `--headless` draws nothing), read both back, count pixels that differ by more than 2/255. Zero, or it does
  not ship. Harness in `references/measuring.md`.
- **The whole screen**: snap the same frame of the same level and seed from the old build and the new one and diff them
  (`scripts/img_diff.gd`). Diff the old build against itself too: animated parts differ run to run, and only differences
  outside that area count.
- **Logic**: the same outputs over many cases (a byte-for-byte comparison, many seeds).
- The proof catches real bugs: a row-run rewrite once used -1 as "no run" and lost every run at negative cell indices.

## 7. Keeping it fast

- Write a short performance guideline into the repo and point at it from the project's instructions (CLAUDE.md or
  AGENTS.md): new code that draws, runs every frame or runs while loading follows it.
- A benchmark script on fixed levels and seeds at the target resolution, each run capped, on a throwaway save, appending
  one line a level (avg, p95, worst, frames over 17 / 33, GPU, draw calls) to a text log. Not a `.csv` inside the Godot
  project: Godot imports it as a translation. Every change that touches drawing or per-frame code adds its lines.
- Ship each cut with before and after numbers in the changelog, and the machine's conditions beside them.

## Done when

The machine was checked before the first timed number; the cost was named by splitting, not guessed; each cut is proven
the same (picture and logic); old and new were compared alternated at least twice; the numbers and their conditions
are written down.

## Sources

- Engine: `drivers/gles3/rasterizer_canvas_gles3.cpp`, `servers/rendering/renderer_canvas_cull.cpp`,
  `drivers/gles3/shader_gles3.cpp` (https://github.com/godotengine/godot)
- Docs: https://docs.godotengine.org/en/stable/tutorials/performance/ (CPU, GPU, general, servers), 2D lights and
  shadows, jitter and stutter, physics interpolation, exporting for the web; `CanvasItem`, `Texture2D`, `TileMapLayer`
- https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/ ; https://benchmarks.godotengine.org/
- Halls of Torment: https://fullcleared.com/features/inside-halls-of-torment-an-interview-with-chasing-carrots/
- Cassette Beasts: https://godotengine.org/article/godot-showcase-cassette-beasts/
- Noita: https://80.lv/articles/noita-a-game-based-on-falling-sand-simulation/ ; Factorio Friday Facts #204
