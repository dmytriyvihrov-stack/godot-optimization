class_name Prim
extends RefCounted
## Shapes drawn every frame as batched primitives (Godot 4, Compatibility renderer). There every draw_polygon,
## draw_colored_polygon, draw_circle, draw_arc and draw_polyline is a polygon of its own: GPU buffers made the frame it is
## drawn and freed the frame after. Measured on a Vega 11 laptop, 200 such quads a frame cost 29 ms on OpenGL and 40 on
## ANGLE; the same quads as draw_primitive 1.8 and 2.2 ms. The shapes here are the same points cut into triangles and
## quads of at most four points (draw_primitive's limit), matching the engine's pixels.
##
## Every primitive has four points: the GLES3 renderer starts a new batch when the point count changes between two
## primitives (rasterizer_canvas_gles3.cpp), so a triangle is sent as a quad with its last point twice.
##
## Only for what is redrawn every frame. A kept drawing (drawn once, redrawn on change) renders its polygons cheaply after
## the first frame, while primitives are batched again every frame: there use the engine's calls, or TriBatch for many shapes.


## A quad, or a triangle, with a colour at each point: draw_polygon's picture to the pixel (prove it with a two-SubViewport diff, see SKILL.md). Its
## quad is cut 0-1-3, 1-2-3, as draw_polygon cuts it; draw_primitive's own cut (0-2) shades a gradient another way.
static func quad(ci: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if pts.size() == 3:
		ci.draw_primitive(PackedVector2Array([pts[0], pts[1], pts[2], pts[2]]), PackedColorArray([cols[0], cols[1], cols[2], cols[2]]), PackedVector2Array())
		return
	if pts.size() != 4:
		ci.draw_primitive(pts, cols, PackedVector2Array())
		return
	var none: PackedVector2Array = PackedVector2Array()
	ci.draw_primitive(PackedVector2Array([pts[0], pts[1], pts[3], pts[3]]), PackedColorArray([cols[0], cols[1], cols[3], cols[3]]), none)
	ci.draw_primitive(PackedVector2Array([pts[1], pts[2], pts[3], pts[3]]), PackedColorArray([cols[1], cols[2], cols[3], cols[3]]), none)


## A convex polygon in one colour (draw_colored_polygon's), cut into a fan off its first point, two triangles a quad.
static func fan(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var n: int = pts.size()
	if n < 3:
		return
	var c4: PackedColorArray = PackedColorArray([col, col, col, col])
	var i: int = 1
	while i + 2 < n:
		ci.draw_primitive(PackedVector2Array([pts[0], pts[i], pts[i + 1], pts[i + 2]]), c4, PackedVector2Array())
		i += 2
	if i + 1 < n:
		ci.draw_primitive(PackedVector2Array([pts[0], pts[i], pts[i + 1], pts[i + 1]]), c4, PackedVector2Array())


## Any simple polygon in one colour (draw_colored_polygon's, convex or not): triangulated as the engine triangulates it
## (Geometry2D.triangulate_polygon), a primitive a triangle. One the engine cannot triangulate draws nothing here either.
## With `cols`, a colour a point (draw_polygon's), shaded across each triangle as the engine's are.
static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, cols: PackedColorArray = PackedColorArray()) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	var c4: PackedColorArray = PackedColorArray([col, col, col, col])
	var none: PackedVector2Array = PackedVector2Array()
	var each: bool = cols.size() == pts.size()
	for k: int in range(0, idx.size(), 3):
		if each:
			c4 = PackedColorArray([cols[idx[k]], cols[idx[k + 1]], cols[idx[k + 2]], cols[idx[k + 2]]])
		ci.draw_primitive(PackedVector2Array([pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]], pts[idx[k + 2]]]), c4, none)


## A filled circle (draw_circle's): the engine's 64 sides, pixel for pixel.
static func disc(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	if r <= 0.0 or col.a <= 0.0:
		return
	if _unit.is_empty():
		_unit.resize(64)
		for k: int in 64:
			_unit[k] = Vector2(cos(TAU * k / 64.0), sin(TAU * k / 64.0))
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(64)
	for k: int in 64:
		pts[k] = at + _unit[k] * r
	fan(ci, pts, col)


static var _unit: PackedVector2Array = PackedVector2Array()


## draw_arc's line, its points as draw_arc lays them (`points` of them from `a0` to `a1`, the turn clamped to a whole one),
## through `polyline`.
static func arc(ci: CanvasItem, at: Vector2, r: float, a0: float, a1: float, points: int, col: Color, width: float = -1.0) -> void:
	if r <= 0.0 or col.a <= 0.0 or points < 2:
		return
	var d: float = clampf(a1 - a0, -TAU, TAU)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(points)
	for i: int in points:
		var th: float = (i / (points - 1.0)) * d + a0
		pts[i] = at + Vector2(cos(th), sin(th)) * r
	polyline(ci, pts, col, width)


## draw_polyline's line. Thin (width under 0): a line a piece. Thick: a quad a piece between mitred joints, each point
## pushed out both ways by half the width over the cosine of half its turn, the ends square: the engine's line to the
## pixel, opaque or not (prove it with a two-SubViewport diff, see SKILL.md).
static func polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float = -1.0) -> void:
	var n: int = pts.size()
	if n < 2 or col.a <= 0.0:
		return
	if width < 0.0:
		for i: int in n - 1:
			ci.draw_line(pts[i], pts[i + 1], col, -1.0)
		return
	var cols: PackedColorArray = PackedColorArray([col, col, col, col])
	var none: PackedVector2Array = PackedVector2Array()
	var hw: float = width * 0.5
	var l0: Vector2 = Vector2.ZERO
	var r0: Vector2 = Vector2.ZERO
	for i: int in n:
		var off: Vector2
		if i == 0:
			off = (pts[1] - pts[0]).normalized().orthogonal() * hw
		elif i == n - 1:
			off = (pts[i] - pts[i - 1]).normalized().orthogonal() * hw
		else:
			var na: Vector2 = (pts[i] - pts[i - 1]).normalized().orthogonal()
			var m: Vector2 = (na + (pts[i + 1] - pts[i]).normalized().orthogonal()).normalized()
			off = m * (hw / maxf(0.1, m.dot(na)))
		var l1: Vector2 = pts[i] + off
		var r1: Vector2 = pts[i] - off
		if i > 0:
			ci.draw_primitive(PackedVector2Array([l0, r0, r1, l1]), cols, none)
		l0 = l1
		r0 = r1
