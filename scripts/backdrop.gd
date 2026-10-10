class_name Backdrop
extends Node2D

# Five depth planes behind the play field plus one hanging in front of it:
#   sky wash -> far ridge -> haze -> mid treeline -> haze -> near trees -> (play)
# Each plane is the same baked band image, stretched to exactly the span the camera
# can currently see at that parallax, so there is no seam to hide, no tiling rhythm
# to read and no empty corner at either end of the level.

var world_size := Vector2(1900.0, 760.0)
var sky_top := Color("3b2a6b")
var sky_bottom := Color("f7c8d8")
var biome: Dictionary = {}
var camera: Camera2D

var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	z_index = -20
	show_behind_parent = true
	_rng.seed = 20260925


func _ready() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	grad.set_color(0, sky_top)
	grad.set_color(1, sky_bottom.darkened(0.04))
	grad.set_color(2, sky_bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 384
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	var sky := Sprite2D.new()
	sky.texture = tex
	sky.centered = false
	sky.scale = world_size / Vector2(4.0, 384.0)
	sky.z_index = -1
	add_child(sky)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _cam() -> Vector2:
	return camera.global_position if camera != null else world_size * 0.5


func _view() -> Vector2:
	var z: float = maxf(0.05, camera.zoom.x if camera != null else 1.0)
	var vp := get_viewport_rect().size
	return Vector2(vp.x / z, vp.y / z)


# Left edge of a plane with parallax p, given that its world x drifts by
# (1 - p) per pixel of camera travel. The +40 of slack on each side is what keeps
# the far end of a long level covered while the camera is pinned against it.
func _span(p: float, cam: Vector2, view: Vector2) -> Rect2:
	var left: float = cam.x * (1.0 - p) - view.x * 0.5 - 20.0
	return Rect2(left, 0.0, p * world_size.x + view.x + 40.0, 0.0)


func _band(name: String, p: float, h_frac: float, foot: float, tint: Color) -> void:
	var tex := Art.env(name)
	if tex == null:
		return
	var cam := _cam()
	var view := _view()
	var r := _span(p, cam, view)
	var h: float = view.y * h_frac
	r.position = Vector2(r.position.x, foot - h)
	r.size.y = h
	draw_texture_rect(tex, r, false, tint)


func _haze(p: float, foot: float, h_frac: float, amount: float) -> void:
	var fog: Color = biome.get("fog", Color(1, 1, 1))
	var cam := _cam()
	var view := _view()
	var r := _span(p, cam, view)
	var h: float = view.y * h_frac
	r.position = Vector2(r.position.x, foot - h * 1.25)
	r.size.y = h * 1.5
	draw_texture_rect(Art.vgrad(Color(1, 1, 1, 0.0), Color(1, 1, 1, amount)), r, false, fog)


func _draw() -> void:
	var cam := _cam()
	var view := _view()
	var floor_y: float = world_size.y + 70.0
	_stars(cam, view)
	_body(cam, view)
	_band("bg_far", 0.05, 0.60, floor_y - view.y * 0.16, Color(biome.get("far", Color("b9a6d6"))))
	_haze(0.05, floor_y - view.y * 0.16, 0.34, 0.42)
	_band("bg_mid", 0.16, 0.52, floor_y - view.y * 0.05, Color(biome.get("mid", Color("8fb9a6"))))
	_haze(0.16, floor_y - view.y * 0.05, 0.26, 0.30)
	_band("bg_near", 0.30, 0.42, floor_y + 20.0, Color(biome.get("near", Color("4a6f5c"))))
	_ambient(cam, view)


func _stars(cam: Vector2, view: Vector2) -> void:
	var lum: float = 0.299 * sky_top.r + 0.587 * sky_top.g + 0.114 * sky_top.b
	if lum > 0.30:
		return
	for i: int in range(30):
		var s := _rng.randf()
		var x: float = cam.x + fposmod(s * 3000.0 + float(i) * 137.0 - cam.x * 0.96, view.x) - view.x * 0.5
		var y: float = cam.y - view.y * 0.5 + fposmod(_rng.randf() * 900.0 + float(i) * 61.0, view.y * 0.5)
		var tw: float = 0.45 + 0.55 * sin(_t * 1.7 + float(i) * 2.1)
		draw_circle(Vector2(x, y), 1.4 + tw * 1.2, Color(1, 1, 0.94, 0.12 + tw * 0.40))


func _body(cam: Vector2, view: Vector2) -> void:
	var col: Color = biome.get("sun", Color("fff3d6"))
	var at := Vector2(cam.x + view.x * 0.30, cam.y - view.y * 0.31)
	var r: float = view.y * 0.055 + 18.0
	draw_circle(at, r * 2.8, Color(col.r, col.g, col.b, 0.06))
	draw_circle(at, r * 1.8, Color(col.r, col.g, col.b, 0.10))
	draw_circle(at, r, Color(col.r, col.g, col.b, 0.80))

	for i: int in range(6):
		var cx: float = cam.x * 0.9 + fposmod(float(i) * 431.0 + _t * (5.0 + float(i)), view.x + 520.0) - 260.0
		var cy: float = cam.y - view.y * 0.40 + float(i % 3) * view.y * 0.07
		var amount := 0.9 + float(i % 2) * 0.5
		for k: int in range(5):
			var o := Vector2(float(k) * 24.0 * amount - 44.0 * amount, sin(float(k) * 1.7) * 6.0 * amount)
			draw_circle(Vector2(cx, cy) + o, (15.0 + float(k % 3) * 8.0) * amount, Color(col.r, col.g, col.b, 0.13))


# Ambient drift: 18-24 pieces placed relative to the current view so they are
# always on screen, without a particle box that has to be sized to the level.
func _ambient(cam: Vector2, view: Vector2) -> void:
	var kind: String = biome.get("ambient", "dust")
	var cols: Array = biome.get("ambient_col", [Color(1, 1, 1)])
	var n := 24 if kind == "snow" else 18
	for i: int in range(n):
		var s := _rng.randf()
		var ph := _rng.randf()
		var fall: float = fposmod(ph * view.y + _t * (30.0 + s * 46.0), view.y + 90.0)
		var rise: float = fposmod(view.y - fall, view.y + 90.0)
		var sway: float = sin(_t * (0.7 + s) + ph * 9.0) * (16.0 + s * 24.0)
		var x: float = cam.x - view.x * 0.5 + fposmod(s * 1700.0 + sway + float(i) * 71.0, view.x + 120.0) - 60.0
		var up: bool = kind == "mote" or kind == "dust"
		var y: float = cam.y - view.y * 0.5 + (rise if up else fall) - 40.0
		var col: Color = cols[i % cols.size()]
		match kind:
			"snow":
				draw_circle(Vector2(x, y), 1.6 + s * 2.4, Color(col.r, col.g, col.b, 0.55 + s * 0.35))
			"petal", "leaf":
				draw_set_transform(Vector2(x, y), _t * (0.8 + s) + ph * 6.0, Vector2.ONE)
				draw_rect(
					Rect2(-3.0 - s * 2.0, -1.4 - s, 6.0 + s * 4.0, 2.8 + s * 2.0),
					Color(col.r, col.g, col.b, 0.72)
				)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"firefly":
				var pulse: float = 0.35 + 0.65 * maxf(0.0, sin(_t * 2.2 + ph * 12.0))
				var at := Vector2(x, y + sin(_t * 0.9 + ph * 5.0) * 18.0)
				draw_circle(at, 4.6, Color(col.r, col.g, col.b, 0.10 * pulse))
				draw_circle(at, 1.8, Color(1, 1, 0.8, 0.85 * pulse))
			"mote":
				draw_circle(Vector2(x, y), 1.2 + s * 1.8, Color(col.r, col.g, col.b, 0.22 + s * 0.2))
			_:
				draw_circle(Vector2(x, y), 1.0 + s * 1.4, Color(col.r, col.g, col.b, 0.16 + s * 0.12))
