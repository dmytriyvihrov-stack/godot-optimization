extends SceneTree
## A frame meter for any Godot 4 game. Runs a scene for a fixed number of frames with V-Sync off and no frame cap, and
## prints the average, p95 and worst frame, how many frames went over 17 / 33 / 50 ms, the draw step, GPU and render CPU
## time, draw calls and objects drawn, and the worst frames one by one.
##
## Copy it into your project (for example res://tools/frame_meter.gd) and run it windowed, silent, at a fixed tick:
##   godot --path . --audio-driver Dummy --windowed --fixed-fps 60 --script res://tools/frame_meter.gd -- \
##     scene=res://levels/level_3.tscn frames=900 warmup=120 log=user://bench.txt label=main
##
## Adapt `_setup_scene` if your game needs a seed, a save slot or a menu skipped before the level runs. Use a throwaway
## save: never point this at the player's own progress. Run old and new builds alternated, at least twice each.

var scene_path: String = ""
var frames: int = 600
var warmup: int = 60
var log_path: String = ""
var label: String = ""

var _n: int = 0
var _last_us: int = 0
var _pre_us: int = 0
var _draw_ms: float = 0.0
var _wall: PackedFloat64Array = PackedFloat64Array()
var _draw: PackedFloat64Array = PackedFloat64Array()
var _gpu: PackedFloat64Array = PackedFloat64Array()
var _cpu: PackedFloat64Array = PackedFloat64Array()
var _calls: PackedFloat64Array = PackedFloat64Array()
var _objs: PackedFloat64Array = PackedFloat64Array()


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"scene": scene_path = kv[1]
			"frames": frames = kv[1].to_int()
			"warmup": warmup = kv[1].to_int()
			"log": log_path = kv[1]
			"label": label = kv[1]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _draw_ms = (Time.get_ticks_usec() - _pre_us) / 1000.0)
	_setup_scene()


## Load the level to measure. Replace this with whatever your game needs to start a level on a fixed seed.
func _setup_scene() -> void:
	if scene_path == "":
		push_error("frame_meter: pass scene=res://...tscn")
		quit(2)
		return
	change_scene_to_file(scene_path)


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	_n += 1
	if _last_us > 0 and _n > warmup:
		var vp: RID = root.get_viewport_rid()
		_wall.append((now - _last_us) / 1000.0)
		_draw.append(_draw_ms)
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_last_us = now
	if _n >= warmup + frames:
		_report()
		quit(0)
	return false


func _report() -> void:
	var s: PackedFloat64Array = _wall.duplicate()
	s.sort()
	var count: int = s.size()
	if count == 0:
		print("frame_meter: no frames measured")
		return
	var p95: float = s[mini(count - 1, int(count * 0.95))]
	var over: Array[int] = [0, 0, 0]
	for v: float in _wall:
		if v > 17.0: over[0] += 1
		if v > 33.0: over[1] += 1
		if v > 50.0: over[2] += 1
	var line: String = "%s %s  avg %.2f  p95 %.2f  worst %.2f  >17 %d  >33 %d  >50 %d  draw %.2f  gpu %.2f  cpu %.2f  calls %.0f  objs %.0f" % [
		label, scene_path, _avg(_wall), p95, s[count - 1], over[0], over[1], over[2],
		_avg(_draw), _avg(_gpu), _avg(_cpu), _avg(_calls), _avg(_objs)]
	print(line)
	# The worst frames, with what the draw step and GPU did in them.
	var idx: Array[int] = []
	for i: int in count:
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return _wall[a] > _wall[b])
	for k: int in mini(5, count):
		var i: int = idx[k]
		print("  spike frame %d  %.2f ms  draw %.2f  gpu %.2f  calls %.0f" % [i + warmup, _wall[i], _draw[i], _gpu[i], _calls[i]])
	if log_path != "":
		var f: FileAccess = FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(Time.get_datetime_string_from_system() + "  " + line)


func _avg(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var t: float = 0.0
	for v: float in a:
		t += v
	return t / a.size()
