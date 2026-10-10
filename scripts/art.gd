class_name Art
extends RefCounted

const NAMES := ["一二", "布布"]
const FRAME_NAMES := ["idle", "run_a", "run_b", "jump", "fall", "blink"]
const F_IDLE := 0
const F_RUN_A := 1
const F_RUN_B := 2
const F_JUMP := 3
const F_FALL := 4
const F_BLINK := 5

# Geometry tools/sprite_bake.gd bakes every pose into: one cell, feet parked on
# the baseline, head size matched across poses by inter-eye distance.
const CELL_W := 256.0
const CELL_H := 272.0
const BASELINE := 266.0
const STAND_H := 240.0

# The pair are still head-heavy, so the sprite overhangs the 26x36 collision
# box a little; the feet sit on the box floor so landings read true, and the
# height is capped so the crown only just grazes a ceiling the hitbox bonks on.
const DRAW_H := 42.0
const FEET_Y := 18.5

# Only the tether and the menu highlight mix colours by hand now.
const ACCENT_COLORS := [Color("f58f95"), Color("e8a05c")]

const ENV_DIR := "res://assets/env/"

static var _tex: Array = []
static var _env: Dictionary = {}
static var _cap_body: Dictionary = {}
static var _grad: Dictionary = {}


static func env(name: String) -> Texture2D:
	if not _env.has(name):
		_env[name] = (
			load(ENV_DIR + name + ".png")
			if ResourceLoader.exists(ENV_DIR + name + ".png")
			else null
		)
	return _env[name]


# The bottom rows of a cap strip are a flat fill whose whole job is to continue
# into the slab below, so the body colour is measured off the art rather than
# hand-picked. Guessing it is how a terrain top ends up floating on a mismatch.
static func cap_body(name: String) -> Color:
	if _cap_body.has(name):
		return _cap_body[name]
	var out := Color("6a5a8f")
	var tex := env(name)
	if tex != null:
		var img := tex.get_image()
		var w := img.get_width()
		var sum := Vector3.ZERO
		var n := 0
		for y: int in range(maxi(0, img.get_height() - 10), img.get_height()):
			for x: int in range(0, w, 2):
				var c := img.get_pixel(x, y)
				if c.a < 0.75:
					continue
				sum += Vector3(c.r, c.g, c.b)
				n += 1
		if n > 0:
			out = Color(sum.x / n, sum.y / n, sum.z / n, 1.0)
	_cap_body[name] = out
	return out


static func vgrad(top: Color, bottom: Color) -> GradientTexture2D:
	var key := top.to_html() + bottom.to_html()
	if _grad.has(key):
		return _grad[key]
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 2
	t.height = 64
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	_grad[key] = t
	return t


# An environment sprite drawn `h` tall with its feet on `at`. Everything in
# assets/env is bottom-anchored by the baker, so this is the only call sites need.
static func draw_env(
	ci: CanvasItem, name: String, at: Vector2, h: float, flip: bool = false, alpha: float = 1.0
) -> void:
	var tex := env(name)
	if tex == null or alpha <= 0.002:
		return
	var w: float = h * float(tex.get_width()) / float(tex.get_height())
	ci.draw_set_transform(at, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect(
		tex, Rect2(-w * 0.5, -h, w, h), false, Color(1, 1, 1, alpha)
	)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Same, but spun about its own middle — the saw blade and the cog are baked
# square-padded by tools/env_bake.gd precisely so this centre is the axle.
static func draw_env_spin(
	ci: CanvasItem, name: String, at: Vector2, h: float, rot: float, alpha: float = 1.0
) -> void:
	var tex := env(name)
	if tex == null or alpha <= 0.002:
		return
	var r: float = h * 0.5
	ci.draw_set_transform(at, rot, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-r, -r, h, h), false, Color(1, 1, 1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func env_w(name: String, h: float) -> float:
	var tex := env(name)
	if tex == null or tex.get_height() == 0:
		return 0.0
	return h * float(tex.get_width()) / float(tex.get_height())


# Crust repeated along a slab top. Alternate cells come from the mirrored bake: a
# mirrored neighbour continues the silhouette instead of cutting across it, which
# is what makes one 340 px strip enough for a 1500 px floor.
static func draw_cap(
	ci: CanvasItem, name: String, x0: float, y: float, width: float, h: float
) -> void:
	var tex := env(name)
	if tex == null or width <= 1.0 or h <= 1.0:
		return
	var mir := env(name + "_m")
	var full := float(tex.get_width())
	var tw: float = h * full / float(tex.get_height())
	if tw <= 1.0:
		return
	var i := 0
	var x := x0
	while x < x0 + width - 0.5:
		var w: float = minf(tw, x0 + width - x)
		var t: Texture2D = mir if (i % 2 == 1 and mir != null) else tex
		# A partial last cell samples the same left edge it would have drawn whole.
		if w + 0.5 >= tw:
			ci.draw_texture_rect(t, Rect2(x, y - h * 0.38, w, h), false)
		else:
			ci.draw_texture_rect_region(
				t, Rect2(x, y - h * 0.38, w, h), Rect2(0.0, 0.0, w / tw * full, float(t.get_height()))
			)
		x += w
		i += 1


static func frame_tex(index: int, frame: int) -> Texture2D:
	if _tex.is_empty():
		for dir: String in ["yier", "bubu"]:
			var row: Array[Texture2D] = []
			for f: String in FRAME_NAMES:
				row.append(load("res://assets/sprites/%s/%s.png" % [dir, f]))
			_tex.append(row)
	var row: Array = _tex[clampi(index, 0, 1)]
	return row[clampi(frame, 0, FRAME_NAMES.size() - 1)]


# `t` only drives the idle breathing; walking and airborne motion lives in the
# frames themselves now, so nothing is jittered on top of them.
static func draw_buddy(
	ci: CanvasItem,
	index: int,
	at: Vector2,
	facing: float,
	frame: int,
	press: float,
	t: float
) -> void:
	var tex := frame_tex(index, frame)
	if tex == null:
		return
	var s: float = DRAW_H / STAND_H
	var w: float = CELL_W * s
	var h: float = CELL_H * s
	var still: bool = frame == F_IDLE or frame == F_BLINK
	var bob: float = sin(t * 2.4) * 0.9 if still else 0.0
	ci.draw_set_transform(Vector2(at.x, at.y - bob), 0.0, Vector2(facing, 1.0))
	ci.draw_texture_rect(tex, Rect2(-w * 0.5, FEET_Y - BASELINE * s, w, h), false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if press > 0.0:
		var f: float = press / 0.34
		for k: int in range(3):
			var a: float = float(k) / 3.0 * TAU + (1.0 - f) * 3.2
			ci.draw_circle(
				at + Vector2(cos(a) * 15.0, -27.0 + sin(a) * 4.0), 2.6 * f, Color(1, 0.86, 0.3, f)
			)


static func rounded_points(r: Rect2, rad: float, steps: int = 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# Kept strictly under half the box: at exactly half, the two corner arcs on a
	# side share a centre, the closing vertex duplicates the opening one, and
	# draw_colored_polygon refuses to triangulate the result.
	var rr: float = minf(rad, minf(r.size.x, r.size.y) * 0.499)
	if rr <= 0.5:
		pts.append(r.position)
		pts.append(Vector2(r.end.x, r.position.y))
		pts.append(r.end)
		pts.append(Vector2(r.position.x, r.end.y))
		return pts
	var corners := [
		[Vector2(r.position.x + rr, r.position.y + rr), PI],
		[Vector2(r.end.x - rr, r.position.y + rr), -PI * 0.5],
		[Vector2(r.end.x - rr, r.end.y - rr), 0.0],
		[Vector2(r.position.x + rr, r.end.y - rr), PI * 0.5],
	]
	for c: Array in corners:
		var center: Vector2 = c[0]
		var start: float = c[1]
		for i: int in range(steps + 1):
			var a: float = start + (PI * 0.5) * float(i) / float(steps)
			pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts


static func round_rect(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	ci.draw_colored_polygon(rounded_points(r, rad), col)


static func round_rect_outline(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := rounded_points(r, rad, 8)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


static func ellipse(ci: CanvasItem, at: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(rx, ry))
	ci.draw_circle(Vector2.ZERO, 1.0, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func shade(c: Color, amount: float) -> Color:
	if amount < 0.0:
		return Color(c.r * (1.0 + amount), c.g * (1.0 + amount), c.b * (1.0 + amount), c.a)
	return Color(
		c.r + (1.0 - c.r) * amount,
		c.g + (1.0 - c.g) * amount,
		c.b + (1.0 - c.b) * amount,
		c.a
	)
