# Recipes (Godot 4, GDScript, Compatibility renderer)

Each one was proven pixel-identical to what it replaces (see SKILL.md section 6 and `measuring.md`). Full working
versions of the first two are in `scripts/prim.gd` and `scripts/tri_batch.gd`.

## 1. Per-frame shapes as four-point primitives

```gdscript
## A quad or triangle with a colour a point, cut 0-1-3 / 1-2-3 as draw_polygon cuts it. Every primitive has four points
## (a batch breaks when the point count changes), so a triangle repeats its last point.
static func quad(ci: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	var none: PackedVector2Array = PackedVector2Array()
	if pts.size() == 3:
		ci.draw_primitive(PackedVector2Array([pts[0], pts[1], pts[2], pts[2]]), PackedColorArray([cols[0], cols[1], cols[2], cols[2]]), none)
		return
	ci.draw_primitive(PackedVector2Array([pts[0], pts[1], pts[3], pts[3]]), PackedColorArray([cols[0], cols[1], cols[3], cols[3]]), none)
	ci.draw_primitive(PackedVector2Array([pts[1], pts[2], pts[3], pts[3]]), PackedColorArray([cols[1], cols[2], cols[3], cols[3]]), none)

## Any simple polygon in one colour: the engine's triangulation, a primitive a triangle.
static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	var c4: PackedColorArray = PackedColorArray([col, col, col, col])
	for k: int in range(0, idx.size(), 3):
		ci.draw_primitive(PackedVector2Array([pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]], pts[idx[k + 2]]]), c4, PackedVector2Array())
```

- draw_circle: 64 points from angle 0, `at + Vector2(cos(TAU*k/64), sin(TAU*k/64)) * r`, as a fan off point 0.
- draw_arc: `points` points, `theta = (i / (points - 1.0)) * clamp(a1 - a0, -TAU, TAU) + a0`, then the polyline.
- thick draw_polyline: at each inner point `m = (n_prev + n_next).normalized()`, offset `m * (w/2) / max(0.1, m.dot(n_prev))`;
  end points offset by their segment's normal; a quad `[l0, r0, r1, l1]` a segment. Thin (width < 0): `draw_line` a segment.

## 2. A kept drawing of many shapes as one mesh

```gdscript
class_name TriBatch extends RefCounted
var ci: CanvasItem
var _v := PackedVector2Array(); var _c := PackedColorArray(); var _i := PackedInt32Array()
var _kept: Array[ArrayMesh] = []

func _init(on: CanvasItem) -> void: ci = on

func poly(pts: PackedVector2Array, col: Color) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	if idx.is_empty(): return
	var base: int = _v.size()
	_v.append_array(pts)
	for k: int in pts.size(): _c.append(col)
	for j: int in idx: _i.append(base + j)

func flush() -> void:   # also call before any texture draw, to keep the order
	if _i.is_empty(): return
	var a: Array = []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = _v; a[Mesh.ARRAY_COLOR] = _c; a[Mesh.ARRAY_INDEX] = _i
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	ci.draw_mesh(m, null)
	_kept.append(m); ci.set_meta(&"tri_meshes", _kept)   # the canvas holds only the RID: keep the mesh alive
	_v = PackedVector2Array(); _c = PackedColorArray(); _i = PackedInt32Array()
```

Route the drawing helpers through it with a static "current batch" checked in each helper, so the same helpers still
draw directly where they are used live.

## 3. Redraw on change

```gdscript
var _key: int = -1
func _process(_dt: float) -> void:
	if not on_screen(): return
	var k: int = floori(time * FPS + phase) * 4 + (2 if broken else 0) + (1 if lit else 0)
	if k != _key:
		_key = k
		queue_redraw()
```

## 4. Cells in a sector: box, unchanged test, row runs

```gdscript
# box of the sector: origin, both edge directions at r0 and r1, and each axis angle inside the span; one cell of margin
var run: int = 0
var in_run: bool = false          # never a sentinel like -1: cell indices go negative
for j: int in range(j0, j1 + 1):
	in_run = false
	for i: int in range(i0, i1 + 2):
		var on: bool = i <= i1 and cell_test(i, j)    # the original per-cell test, word for word
		if on and not in_run:
			run = i; in_run = true
		elif not on and in_run:
			ci.draw_rect(Rect2((o + Vector2(run, j)) * px, Vector2(px * (i - run), px)), col)
			in_run = false
```

## 5. The proof harness

A `extends SceneTree` script: for each case make two SubViewports (transparent, UPDATE_ALWAYS) each with a Node2D whose
`draw` calls the old or the new function; wait a few frames and `RenderingServer.frame_post_draw`; read both textures
back; count pixels whose max channel differs by more than 2/255. Print `SAME <case> <drawn> <differ> <worst>`. Run
windowed (`--audio-driver Dummy --windowed`), never headless.
