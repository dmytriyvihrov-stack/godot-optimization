class_name TriBatch
extends RefCounted
## A kept drawing's shapes as one mesh (Godot 4, Compatibility renderer). Every draw_colored_polygon is a draw call of its
## own, frame after frame, however long the drawing is kept: a level's decor of ~2000 shapes went from 2287 draw calls to
## 112 and from 38 to 19.5 ms a frame. The shapes are triangulated as the engine does (Geometry2D.triangulate_polygon, a
## circle a 64-sided fan off its first point) into one ArrayMesh with a colour per vertex, drawn once with draw_mesh. A
## texture between shapes must flush the run first, so what lies over what never changes.

var ci: CanvasItem
var _v: PackedVector2Array = PackedVector2Array()
var _c: PackedColorArray = PackedColorArray()
var _i: PackedInt32Array = PackedInt32Array()
## The meshes drawn, kept on the CanvasItem (meta `tri_meshes`): its commands hold only their RIDs.
var _kept: Array[ArrayMesh] = []


func _init(on: CanvasItem) -> void:
	ci = on


## draw_colored_polygon's shape. One the engine cannot triangulate (it then draws nothing) is left out here too.
func poly(pts: PackedVector2Array, col: Color) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var base: int = _v.size()
	_v.append_array(pts)
	for k: int in pts.size():
		_c.append(col)
	for j: int in idx:
		_i.append(base + j)


## draw_rect's filled rect.
func rect(r: Rect2, col: Color) -> void:
	var base: int = _v.size()
	_v.append_array(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	_c.append_array(PackedColorArray([col, col, col, col]))
	_i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## draw_circle's disc: the engine's 64 sides.
func disc(at: Vector2, r: float, col: Color) -> void:
	if r <= 0.0:
		return
	var base: int = _v.size()
	for k: int in 64:
		_v.append(at + Vector2(cos(TAU * k / 64.0), sin(TAU * k / 64.0)) * r)
		_c.append(col)
	for k: int in range(1, 63):
		_i.append_array(PackedInt32Array([base, base + k, base + k + 1]))


## The shapes so far, drawn now as one mesh.
func flush() -> void:
	if _i.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_INDEX] = _i
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ci.draw_mesh(mesh, null)
	_kept.append(mesh)
	ci.set_meta(&"tri_meshes", _kept)
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()
