# Measuring a Godot 4 frame

## The frame meter

`scripts/frame_meter.gd` is a `SceneTree` script: it loads a scene, turns V-Sync off and the frame cap to 0, skips a
warm-up, records every frame, and prints one line plus the five worst frames. Run it:

```bash
godot --path . --audio-driver Dummy --windowed --fixed-fps 60 --script res://tools/frame_meter.gd -- \
  scene=res://levels/level_3.tscn frames=900 warmup=120 log=user://bench.txt label=before
```

- `--fixed-fps 60` makes every run step the game the same way, so two builds see the same frames.
- Windowed, never `--headless`: the headless renderer draws nothing, so drawing costs vanish.
- `--audio-driver Dummy`: silent, and audio threads out of the numbers.
- Wrap the command in a timeout (PowerShell `Start-Process ... -Wait` with a job timeout, or `timeout 300` on Unix) so a
  hung run cannot block the next.
- If the game starts from a menu or deals a level from a seed, change `_setup_scene` to start that level directly with a
  fixed seed and a throwaway save.

Read it like this:
- **avg** says how heavy the level is; **p95** and **worst** say how it feels. With V-Sync on, every frame over 16.7 ms
  is shown for two refreshes.
- **draw** (frame_pre_draw to frame_post_draw) is the CPU cost of submitting the picture; **gpu** is the GPU's.
  A high draw with a low gpu means too many commands or draw calls; a high gpu means fill (lights, shadows, overdraw).
- **calls** is draw calls in the frame. Hundreds to low thousands in 2D usually means unbatched polygons or one
  material per unit.

## Splitting a frame

1. Commit first. Then add a stopwatch round every `_process`, `_physics_process` and `_draw` you suspect:

```gdscript
static var acc: Dictionary = {}
static func t0() -> int: return Time.get_ticks_usec()
static func t1(name: StringName, from: int) -> void: acc[name] = acc.get(name, 0) + Time.get_ticks_usec() - from
```

   and print `acc` divided by the frame count at the end of the run. Rank, then split the top one further.
2. Switch groups off (`visible = false` for drawing, `process_mode = Node.PROCESS_MODE_DISABLED` for logic) one at a
   time and rerun. Print the node paths you switched off.
3. Load the level twice in one process: if a cost disappears the second time it is a first-time cost (shader compile,
   a bake, a texture upload): warm it during loading instead.
4. Revert the stopwatches when done (`git checkout -- <files>` of the throwaway edit only).

## The pixel proof for a drawing change

A `SceneTree` script that draws the old call and the new one side by side and counts pixels that differ:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := _view(func(ci: CanvasItem) -> void: ci.draw_circle(Vector2(64, 64), 40, Color.RED))
	var b := _view(func(ci: CanvasItem) -> void: Prim.disc(ci, Vector2(64, 64), 40, Color.RED))
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var x: Image = a.get_texture().get_image()
	var y: Image = b.get_texture().get_image()
	var differ := 0
	for j in x.get_height():
		for i in x.get_width():
			var p := x.get_pixel(i, j); var q := y.get_pixel(i, j)
			if maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))) * 255.0 > 2.0:
				differ += 1
	print("SAME disc differ=%d" % differ)
	quit(0 if differ == 0 else 1)

func _view(draw: Callable) -> SubViewport:
	var v := SubViewport.new()
	v.size = Vector2i(128, 128); v.transparent_bg = true; v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var n := Node2D.new(); n.draw.connect(func() -> void: draw.call(n))
	v.add_child(n); root.add_child(v)
	return v
```

Run windowed (`--audio-driver Dummy --windowed`). Test every shape size and colour case the game uses, not one.

## The whole-screen proof

Snap the same frame of the same level and seed from both builds (`get_viewport().get_texture().get_image().save_png()`
after a fixed number of frames at `--fixed-fps 60`), then:

```bash
godot --headless --script res://tools/img_diff.gd -- before.png after.png diff.png
```

Snap the old build twice and diff those too: whatever differs there (particles, a random flicker) is noise; only
differences outside it count.

## A benchmark log

Pick three to five fixed levels and seeds that stress different things (many units, many lights, a big map). A small
script (Python, PowerShell or bash) runs the frame meter on each with `log=` pointing at one text file, so every build
appends its lines with a label. Before shipping a change that touches drawing or per-frame code, run old and new
alternated twice and compare. A level that got worse is fixed or explained before the change ships.
