# Optimizing a Godot 4 game by hand, step by step

No Claude needed. This is the same method the skill follows, as a checklist you can work through yourself. The scripts
it mentions are in `plugins/godot-optimization/skills/godot-optimization/scripts/`; copy them into your project (for
example `res://tools/`).

The one rule: **a faster version must look and play the same.** Fewer lights, lower resolution, a lower physics tick or
a 30 fps mode are design changes, not optimizations.

## Step 1. Check your machine

Laptops lie. Before timing anything:
- Plug in the charger and use a high-performance power plan.
- Close heavy programs (browsers with many tabs, other game engines, video).
- Expect 1 to 2 ms of drift as the laptop warms up, so always compare old and new **alternated, at least twice each**.

## Step 2. Measure a baseline

1. Pick 3 to 5 levels (or scenes) that are heavy in different ways: many units, many lights, a big map.
2. Run the frame meter on each, windowed and silent:

   ```bash
   godot --path . --audio-driver Dummy --windowed --fixed-fps 60 --script res://tools/frame_meter.gd -- \
     scene=res://levels/level_3.tscn frames=900 warmup=120 log=user://bench.txt label=before
   ```

3. Write down **avg**, **p95**, **worst**, **draw calls**. The p95 matters more than the average: with V-Sync on, any
   frame over 16.7 ms is shown twice, so a game averaging 12 ms with a p95 of 20 feels like 30 to 40 fps.

## Step 3. Find what costs the frame

Do not guess. Guesses are usually wrong.

1. **Read the meter's split.** High `draw` with low `gpu`: too many commands or draw calls (go to step 4). High `gpu`:
   fill cost, lights and shadows (step 4, the lights item). Neither: scripts or physics (step 5).
2. **Time your scripts.** Commit first. Then put `Time.get_ticks_usec()` stopwatches round each `_process`,
   `_physics_process` and `_draw` you suspect, sum them per frame, and rank. Split the top one further.
3. **Switch things off.** Set `visible = false` on a group of nodes (drawing) or
   `process_mode = Node.PROCESS_MODE_DISABLED` (logic), rerun, and see if the cost moves. One group at a time.
4. **First time or every time?** Load the same level twice in one run. If a hitch disappears the second time, it is a
   first-time cost (shader compile, texture upload): do it during loading instead.

## Step 4. Fix drawing (Compatibility renderer, also the web)

- **Polygons are not batched.** `draw_polygon`, `draw_colored_polygon`, `draw_circle`, `draw_arc`, `draw_polyline`
  each cost a draw call every frame. 200 of them cost 29 ms in our test.
  - Redrawn every frame: use `Prim` (`prim.gd`), which draws the same shapes as batched `draw_primitive` quads.
  - Drawn once and kept, many shapes: use `TriBatch` (`tri_batch.gd`), one mesh and one draw call.
  - Drawn once and kept, a few shapes: leave the engine's calls alone.
- **Redraw only on change.** Don't call `queue_redraw()` every frame. Keep a small key of what the drawing shows and
  redraw only when it changes.
- **Batches break** on a texture, material, blend mode or clip change. Use atlases, and share one material instead of
  one per unit.
- **Cut huge drawings into screen-sized pieces.** Culling works per CanvasItem, so a level-sized `_draw` is never culled.
- **Lights cost per pixel**, shadowed ones much more. Keep cull masks tight and merge occluders.
- **Never read the GPU during play** (`get_texture().get_image()` stalls). Keep a CPU copy instead.
- **Bake what never changes** (floors, walls, decals) into textures or tile layers.

## Step 5. Fix scripts, physics and loading

- Use typed GDScript and packed arrays in hot code. Don't allocate per frame (no new Arrays or Dictionaries per entity,
  no `Color("#hex")` in loops).
- Find "who is near" with a grid or per-room lists, not by looping over every entity.
- Look for work done twice before making it faster.
- Keep physics at 60 Hz with physics interpolation on; use simple shapes and tight collision layers.
- Do heavy loading during a loading screen; pool things that spawn in bursts (bullets, waves).

## Step 6. Prove nothing changed

- **Screenshots:** snap the same frame of the same level and seed from the old build and the new one, then compare:

  ```bash
  godot --headless --script res://tools/img_diff.gd -- before.png after.png diff.png
  ```

  Also compare the old build against itself: anything that differs there (particles, randomness) is noise.
- **Single shapes:** draw the old call and the new one in two SubViewports and count the pixels that differ (see
  `references/measuring.md`). It should be zero.

## Step 7. Compare and keep it fast

1. Run the frame meter on old and new, alternated, twice each, with labels (`label=before`, `label=after`).
2. If any level got worse, fix it or explain it before shipping.
3. Write the before and after numbers in your changelog.
4. Rerun the benchmark whenever you change drawing or per-frame code.

## Web builds: load faster

- Exclude folders the game never loads (concept art, references, tests) in every export preset's `exclude_filter`.
- Measure the `.pck` by folder; one forgotten file is often a third of it.
- For a 2D game, build a web export template without 3D (`disable_3d=yes`): our engine went from 10.1 to 8.7 MB on the
  wire and the page loaded in 9 s instead of 21.
- Details: `references/web-export.md`.

More depth on every step: `plugins/godot-optimization/skills/godot-optimization/SKILL.md` (it is plain Markdown, readable
without Claude).
