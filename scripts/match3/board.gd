class_name M3Board
extends Node2D

# The board draws itself by replaying the model's Action list rather than by putting
# tweens on nodes: the model has already moved to the settled position, and each phase
# only tells the view how far it still owes the eye. That keeps exactly one answer to
# "where is every tile", which is the thing that rots first in a match-3.

const SWAP_T := 0.17
const POP_T := 0.26
const INVALID_T := 0.24
const SHUFFLE_T := 0.42
const FALL_BASE := 0.09
const FALL_PER := 0.045
const MAX_FALL_T := 0.34
const PAD := 0.14
const HINT_TTL := 3.4

var model := M3Model.new()
var level: Dictionary = {}
var cell := 76.0
var origin := Vector2.ZERO
var busy := false
var on_settled: Callable = Callable()

var _queue: Array[Dictionary] = []
var _phase: Dictionary = {}
var _pt := 0.0
var _t := 0.0
var _sel := -1
var _drag := -1
var _hint: Array[int] = []
var _hint_t := 0.0
var _pops: Array[Dictionary] = []
var _falls: Array[Dictionary] = []
var _spawns: Array[Dictionary] = []
var _wobble := 0.0
var _combo := 0
var _combo_at := Vector2.ZERO
var _combo_t := 0.0
var _vp := Vector2.ZERO


func setup(def: Dictionary, seed: int) -> void:
	level = def
	model.setup(def, seed)
	_queue.clear()
	_phase = {}
	_pops.clear()
	_falls.clear()
	_spawns.clear()
	_sel = -1
	_drag = -1
	_hint.clear()
	busy = false
	_layout()


func restart() -> void:
	setup(level, int(Time.get_ticks_msec()) + 7)


func finished() -> bool:
	return model.state != M3Model.ST_PLAY


func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp == _vp:
		return
	_vp = vp
	# The HUD owns the two side columns and the bottom button row, so the grid has to
	# fit the band between them instead of just being centred on the window.
	var band := Rect2(348.0, 96.0, maxf(120.0, vp.x - 696.0), maxf(120.0, vp.y - 204.0))
	cell = clampf(
		minf(band.size.x / maxf(1.0, float(model.w)), band.size.y / maxf(1.0, float(model.h))),
		40.0, 88.0
	)
	var board_w: float = cell * float(model.w)
	var board_h: float = cell * float(model.h)
	origin = Vector2(
		band.position.x + (band.size.x - board_w) * 0.5,
		band.position.y + (band.size.y - board_h) * 0.5
	)


func cell_rect(i: int) -> Rect2:
	var v := model.cell_xy(i)
	return Rect2(origin + Vector2(float(v.x), float(v.y)) * cell, Vector2(cell, cell))


func cell_at(pos: Vector2) -> int:
	if cell <= 0.0:
		return -1
	var vx := int((pos.x - origin.x) / cell)
	var vy := int((pos.y - origin.y) / cell)
	if vx < 0 or vy < 0 or vx >= model.w or vy >= model.h:
		return -1
	return model.at(Vector2i(vx, vy))


# --------------------------------------------------------------------------------
# Turn loop
# --------------------------------------------------------------------------------

func move(a: int, b: int) -> void:
	if busy or finished() or a < 0 or b < 0:
		return
	var acts: Array[Dictionary] = model.try_swap(model.cell_xy(a), model.cell_xy(b))
	if acts.is_empty():
		return
	_hint.clear()
	_sel = -1
	busy = true
	for act: Dictionary in acts:
		_queue.append(act)


func ask_hint() -> void:
	if busy or finished():
		return
	var m := model.find_move()
	if m.is_empty():
		return
	_hint = [model.at(m.a), model.at(m.b)]
	_hint_t = 0.0


func _process(delta: float) -> void:
	_layout()
	_t += delta
	_wobble = maxf(0.0, _wobble - delta * 3.2)
	_combo_t = maxf(0.0, _combo_t - delta)
	_hint_t += delta
	if _hint_t > HINT_TTL:
		_hint.clear()
	if _phase.is_empty():
		if _queue.is_empty():
			if busy:
				busy = false
				if on_settled.is_valid():
					on_settled.call()
			queue_redraw()
			return
		_phase = _queue.pop_front()
		_pt = 0.0
		_begin(_phase)
	else:
		_pt += delta
		if _pt >= float(_phase.get("dur", 0.0)):
			_end(_phase)
			_phase = {}
	queue_redraw()


func _begin(p: Dictionary) -> void:
	match int(p.type):
		M3Model.A_POP:
			_pops.clear()
			var cells: Array = p.cells
			var kinds: Array = p.kinds
			var specs: Array = p.specs
			var centroid := Vector2.ZERO
			for n: int in range(cells.size()):
				_pops.append({"i": int(cells[n]), "kind": int(kinds[n]), "spec": int(specs[n])})
				centroid += cell_rect(int(cells[n])).get_center()
			for i: int in (p.ice as Array):
				_pops.append({"i": i, "kind": -2, "spec": 0})
				centroid += cell_rect(i).get_center()
			var total: float = maxf(1.0, float(_pops.size()))
			_combo_at = centroid / total
			_combo = int(p.chain)
			if _combo > 1:
				_combo_t = 0.9
			_phase["dur"] = POP_T
		M3Model.A_FALL:
			_falls = (p.moves as Array).duplicate()
			_spawns = (p.spawns as Array).duplicate()
			var far := 1.0
			for m: Dictionary in _falls:
				far = maxf(far, absf(float(m.to.y) - float(m.from.y)))
			for s: Dictionary in _spawns:
				far = maxf(far, float(s.dist))
			_phase["dur"] = minf(MAX_FALL_T, FALL_BASE + FALL_PER * far)
		M3Model.A_INVALID:
			_wobble = 1.0
			_phase["dur"] = INVALID_T
		M3Model.A_SHUFFLE:
			_pops.clear()
			_phase["dur"] = SHUFFLE_T
		M3Model.A_SWAP:
			_phase["dur"] = SWAP_T


func _end(p: Dictionary) -> void:
	match int(p.type):
		M3Model.A_POP:
			_pops.clear()
		M3Model.A_FALL:
			_falls.clear()
			_spawns.clear()


func _phase_t() -> float:
	var d: float = float(_phase.get("dur", 1.0))
	return clampf(_pt / maxf(0.001, d), 0.0, 1.0)


func _phase_type() -> int:
	return int(_phase.get("type", -1))


# --------------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------------

func _draw() -> void:
	var board := Rect2(origin, Vector2(cell * float(model.w), cell * float(model.h)))
	var biome: Dictionary = Biomes.get_def(String(level.get("biome", "meadow")))
	var fog: Color = biome.get("fog", Color(1, 1, 1))
	Art.round_rect(self, board.grow(12.0), 20.0, Color(0.13, 0.09, 0.21, 0.6))
	Art.round_rect_outline(self, board.grow(13.0), 21.0, Color(1, 1, 1, 0.16), 2.0)
	for y: int in range(model.h):
		for x: int in range(model.w):
			var r := Rect2(origin + Vector2(float(x), float(y)) * cell, Vector2(cell, cell))
			Art.round_rect(self, r.grow(-2.0), 9.0, Color(fog.r, fog.g, fog.b, 0.055 if (x + y) % 2 == 0 else 0.02))
	for i: int in range(model.w * model.h):
		if model.ice_of(i) > 0:
			_ice(cell_rect(i), model.ice_of(i))
	var gone := {}
	for p: Dictionary in _pops:
		gone[int(p.i)] = true
	for i: int in range(model.w * model.h):
		if model.kind_of(i) < 0 or gone.has(i):
			continue
		_tile(i)
	for p: Dictionary in _pops:
		if int(p.kind) == -2:
			_shatter(cell_rect(int(p.i)))
		else:
			_popped(p)
	if _hint.size() == 2:
		var blink: float = 0.3 + 0.4 * absf(sin(_hint_t * 5.0))
		for i: int in _hint:
			Art.round_rect_outline(self, cell_rect(i).grow(-5.0), 11.0, Color(1, 1, 1, blink), 3.0)
	if _sel >= 0:
		Art.round_rect_outline(self, cell_rect(_sel).grow(-3.0), 12.0, UI.tint(_t), 3.4)
	if _combo_t > 0.0 and _combo > 1:
		var a: float = clampf(_combo_t / 0.9, 0.0, 1.0)
		var cy: float = _combo_at.y - (1.0 - a) * 30.0
		# The label lands on top of whatever tiles caused the chain, and those tiles are
		# often pale cream, so white-on-white needs a dark twin behind it.
		UI.label(self, "连锁 x%d" % _combo, _combo_at.x + 2.0, cy + 2.0, 26, Color(0.1, 0.06, 0.18, a * 0.75))
		UI.label(self, "连锁 x%d" % _combo, _combo_at.x, cy, 26, Color(1, 1, 1, a * 0.92))


func _tile_center(i: int) -> Vector2:
	var v := model.cell_xy(i)
	var at := Vector2(float(v.x), float(v.y))
	for m: Dictionary in _falls:
		if Vector2i(int(m.to.x), int(m.to.y)) == v:
			var from := Vector2(float(m.from.x), float(m.from.y))
			return from.lerp(at, _phase_t())
	for s: Dictionary in _spawns:
		if Vector2i(int(s.at.x), int(s.at.y)) == v:
			var above := Vector2(float(v.x), float(v.y) - float(s.dist))
			return above.lerp(at, _phase_t())
	if _phase_type() == M3Model.A_SWAP:
		var a: Vector2i = _phase.a
		var b: Vector2i = _phase.b
		if v == a:
			return Vector2(float(b.x), float(b.y)).lerp(at, _phase_t())
		if v == b:
			return Vector2(float(a.x), float(a.y)).lerp(at, _phase_t())
	if _phase_type() == M3Model.A_INVALID and (v == _phase.a or v == _phase.b):
		at += Vector2(sin(_wobble * 28.0) * 0.13 * _wobble, 0.0)
	return origin + at * cell + Vector2(cell, cell) * 0.5


func _tile(i: int) -> void:
	var at := _tile_center(i)
	# A tile still above the frame has not entered the board yet: drawing it there let
	# the refill animation crawl across the HUD.
	if at.y + cell * 0.5 < origin.y:
		return
	var size := cell * (1.0 - PAD * 2.0)
	var alpha := 1.0
	if _phase_type() == M3Model.A_SHUFFLE:
		alpha = 0.45 + 0.55 * _phase_t()
		at += Vector2(sin(_t * 9.0 + float(i)) * 2.5, cos(_t * 8.0 + float(i)) * 2.5)
	_art(model.id_of(i), at, size, Color(1, 1, 1, alpha))
	var sp := model.spec_of(i)
	if sp != M3Model.SP_NONE:
		_special(at, sp, alpha)


func _popped(p: Dictionary) -> void:
	var f := _phase_t()
	var r := cell_rect(int(p.i))
	var at := r.get_center() + Vector2(0.0, -f * 7.0)
	var sc: float = maxf(0.05, 1.0 + 0.3 * f - 1.15 * f * f)
	var a: float = clampf(1.0 - f * f, 0.0, 1.0)
	_art(model.tile_id(int(p.kind)), at, cell * (1.0 - PAD * 2.0) * sc, Color(1, 1, 1, a))
	if int(p.spec) != M3Model.SP_NONE:
		_special(at, int(p.spec), a)
	for k: int in range(5):
		var ang := float(k) * TAU / 5.0 + f * 2.0
		var d := cell * (0.18 + f * 0.5)
		draw_circle(at + Vector2(cos(ang), sin(ang)) * d, 2.4 * (1.0 - f), Color(1, 1, 0.85, 0.55 * a))


func _art(id: String, at: Vector2, size: float, col: Color) -> void:
	if id.is_empty():
		return
	if M3Levels.is_face(id):
		var tex := Art.frame_tex(M3Levels.face_index(id), Art.F_IDLE)
		if tex == null:
			return
		var s := size / Art.STAND_H
		var w: float = Art.CELL_W * s
		var hh: float = Art.CELL_H * s
		# The baked cell parks the feet far below the middle of the square, so the
		# sprite has to be pulled up by its own baseline or every bear sits low.
		draw_texture_rect(tex, Rect2(at - Vector2(w, hh) * 0.5 + Vector2(0, hh * 0.08), Vector2(w, hh)), false, col)
		return
	var tex2 := M3Levels.art_tex(id)
	if tex2 == null:
		return
	var ratio := float(tex2.get_width()) / maxf(1.0, float(tex2.get_height()))
	var hh2 := size
	var ww2 := size * ratio
	if ww2 > size:
		ww2 = size
		hh2 = size / maxf(0.05, ratio)
	draw_texture_rect(tex2, Rect2(at - Vector2(ww2, hh2) * 0.5, Vector2(ww2, hh2)), false, col)


func _special(at: Vector2, spec: int, alpha: float) -> void:
	var col := Color(1, 1, 1, 0.92 * alpha)
	match spec:
		M3Model.SP_ROW:
			for k: int in [-1, 1]:
				draw_line(at + Vector2(-cell * 0.36, k * 5.0), at + Vector2(cell * 0.3, k * 5.0), col, 2.6, true)
			draw_line(at + Vector2(cell * 0.3, -5.0), at + Vector2(cell * 0.38, 0.0), col, 2.6, true)
			draw_line(at + Vector2(cell * 0.3, 5.0), at + Vector2(cell * 0.38, 0.0), col, 2.6, true)
		M3Model.SP_COL:
			for k: int in [-1, 1]:
				draw_line(at + Vector2(k * 5.0, -cell * 0.3), at + Vector2(k * 5.0, cell * 0.36), col, 2.6, true)
			draw_line(at + Vector2(-5.0, cell * 0.3), at + Vector2(0.0, cell * 0.38), col, 2.6, true)
			draw_line(at + Vector2(5.0, cell * 0.3), at + Vector2(0.0, cell * 0.38), col, 2.6, true)
		M3Model.SP_BOMB:
			draw_arc(at, cell * 0.3, 0.0, TAU, 22, Color(0.1, 0.07, 0.15, 0.85 * alpha), 5.5, true)
			draw_arc(at, cell * 0.3, 0.0, TAU, 22, col, 2.0, true)
			for k: int in range(4):
				var ang := _t * 4.0 + float(k) * TAU / 4.0
				draw_line(
					at + Vector2(cos(ang), sin(ang)) * cell * 0.33,
					at + Vector2(cos(ang), sin(ang)) * cell * 0.45,
					col, 2.2, true
				)
		M3Model.SP_RAINBOW:
			for k: int in range(9):
				var f: float = float(k) / 9.0
				var c := Color.from_hsv(fposmod(f + _t * 0.22, 1.0), 0.62, 1.0, 0.9 * alpha)
				draw_circle(at, cell * (0.32 - f * 0.024), c)
			draw_circle(at, cell * 0.06, Color(1, 1, 1, 0.95 * alpha))


func _ice(r: Rect2, layers: int) -> void:
	var at := r.get_center()
	var s := cell * 0.45
	var box := Rect2(at - Vector2(s, s), Vector2(s * 2.0, s * 2.0))
	# An ice cell holds no tile, so it has to read as something solid sitting in the
	# square rather than as an empty one: a filled frost body, a lit top edge, and one
	# sheen instead of crossing strokes, which looked like a cancelled cell.
	Art.round_rect(self, box, 11.0, Color(0.55, 0.78, 0.98, 0.72))
	Art.round_rect(
		self, Rect2(box.position, Vector2(box.size.x, box.size.y * 0.34)), 11.0,
		Color(0.78, 0.93, 1.0, 0.55)
	)
	Art.round_rect_outline(self, box, 11.0, Color(1, 1, 1, 0.7), 2.0)
	draw_line(at + Vector2(-s * 0.5, s * 0.55), at + Vector2(s * 0.5, -s * 0.45), Color(1, 1, 1, 0.34), 3.0, true)
	for k: int in range(layers):
		draw_circle(at + Vector2(float(k - layers + 1) * 10.0, s * 0.62), 3.4, Color(1, 1, 1, 0.95))


func _shatter(r: Rect2) -> void:
	var f := _phase_t()
	var at := r.get_center()
	for k: int in range(7):
		var ang := float(k) * TAU / 7.0 + f
		var d := cell * (0.18 + f * 0.55)
		draw_circle(at + Vector2(cos(ang), sin(ang)) * d, 3.4 * (1.0 - f), Color(0.85, 0.96, 1.0, 0.75 * (1.0 - f)))


# --------------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if finished() or busy:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var i := cell_at(mb.position)
		if mb.pressed:
			if i < 0 or not model.playable(model.cell_xy(i)):
				_sel = -1
				return
			if _sel >= 0 and _sel != i:
				if model.adjacent(model.cell_xy(_sel), model.cell_xy(i)):
					var from := _sel
					_sel = -1
					move(from, i)
					return
			_sel = i
			_drag = i
			Sfx.play("select")
		else:
			_drag = -1
	elif event is InputEventMouseMotion and _drag >= 0:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		var from_v := model.cell_xy(_drag)
		var d := pos - (origin + (Vector2(from_v) + Vector2(0.5, 0.5)) * cell)
		if d.length() < cell * 0.42:
			return
		var horiz: bool = absf(d.x) > absf(d.y)
		var step := Vector2i(1 if d.x > 0.0 else -1, 0) if horiz else Vector2i(0, 1 if d.y > 0.0 else -1)
		var target := model.at(from_v + step)
		_drag = -1
		_sel = -1
		if target >= 0 and model.playable(model.cell_xy(target)):
			move(model.at(from_v), target)
