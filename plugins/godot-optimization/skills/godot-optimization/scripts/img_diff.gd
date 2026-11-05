extends SceneTree
## Two pictures pixel against pixel: how many differ by more than 2 of 255 on a channel, and
## the box they lie in; with a third path, the first picture with them painted magenta.
##   godot --headless --script res://img_diff.gd -- a.png b.png [diff.png]

func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var x: Image = Image.load_from_file(a[0])
	var y: Image = Image.load_from_file(a[1])
	var out: Image = x.duplicate() as Image
	var d: int = 0
	var box: Rect2i = Rect2i()
	for j: int in x.get_height():
		for i: int in x.get_width():
			var p: Color = x.get_pixel(i, j)
			var q: Color = y.get_pixel(i, j)
			if maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), absf(p.b - q.b)) * 255.0 > 2.0:
				d += 1
				out.set_pixel(i, j, Color(1, 0, 1))
				box = Rect2i(i, j, 1, 1) if box.size == Vector2i.ZERO else box.expand(Vector2i(i, j))
	print("DIFF %d px differ  in %s" % [d, str(box)])
	if a.size() > 2:
		out.save_png(a[2])
	quit(0)
