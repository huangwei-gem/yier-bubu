class_name LevelBase
extends Node2D

const OUTLINE := Color(0.24, 0.17, 0.31)
const GLOW := Color(1.06, 1.05, 1.03)
const DARK := Color(0.55, 0.5, 0.62)

var data: Dictionary = {}
var players: Array[Player] = []
var plates: Array = []
var pulleys: Array[Node2D] = []
var tether: Tether
var door: GoalDoor
var camera: Camera2D
var spawn_points: Array[Vector2] = []
var finished := false
var coins_total := 0
var coins_taken := 0
var biome_id := "meadow"
var biome: Dictionary = {}
var preview := false

var _respawn_wait := 0.0
var _shake := 0.0
var _celebrate := 0.0
var _unlocked := false
var _confetti: CPUParticles2D
var _crumbles: Array = []
var _canopy: Node2D


# --------------------------------------------------------------------------------
# Terrain. One baked crust strip is mirrored along the length of a slab, the body
# under it is shaded procedurally from a colour measured off that same strip, and
# the plants at its ends are what stop it reading as a floating rectangle.
# --------------------------------------------------------------------------------
class Platform extends StaticBody2D:
	var board := Vector2(100.0, 40.0)
	var cap := "cap_grass"
	var flags := ""
	var slippery := false
	var props: Array[Dictionary] = []
	var hangs: Array[Dictionary] = []
	var crumble := false
	var broken := 0.0
	var shake := 0.0
	var trigger: Area2D
	var _rng := RandomNumberGenerator.new()

	func _init(r: Rect2, f: String, biome: Dictionary) -> void:
		board = r.size
		flags = f
		slippery = f.contains("i")
		cap = String(biome.get("cap", "cap_grass"))
		position = r.position
		collision_layer = 1
		collision_mask = 0
		_rng.seed = int(hash(position) + board.x * 7.0)
		crumble = f.contains("c")
		if r.size.x < 46.0 or r.size.y < 12.0:
			return
		var list: Array = biome.get("props", [])
		var room: int = int(board.x / 190.0)
		for i: int in range(mini(room + 1, 3)):
			if list.is_empty() or board.y < 18.0:
				break
			var edge: float = 26.0 + _rng.randf() * 34.0
			var at: float = edge if i % 2 == 0 else board.x - edge
			if board.x < 150.0 and i > 0:
				break
			props.append({
				"name": String(list[_rng.randi() % list.size()]),
				"x": at,
				"h": 24.0 + _rng.randf() * 22.0,
				"flip": _rng.randf() > 0.5,
			})
		if f.contains("n"):
			props.clear()
		var hang: String = String(biome.get("hang", ""))
		if board.y > 52.0 and board.x > 120.0 and not hang.is_empty():
			for k: int in range(2):
				hangs.append({
					"name": hang,
					"x": 40.0 + _rng.randf() * (board.x - 80.0),
					"h": 30.0 + _rng.randf() * 26.0,
					"flip": _rng.randf() > 0.5,
				})

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = board
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = board * 0.5
		cs.one_way_collision = flags.contains("o")
		cs.one_way_collision_margin = 14.0 if flags.contains("o") else 0.0
		add_child(cs)
		if not crumble:
			return
		trigger = Area2D.new()
		trigger.collision_layer = 0
		trigger.collision_mask = 2
		var tr := RectangleShape2D.new()
		tr.size = Vector2(board.x, 14.0)
		var ts := CollisionShape2D.new()
		ts.shape = tr
		ts.position = Vector2(board.x * 0.5, -6.0)
		trigger.add_child(ts)
		trigger.body_entered.connect(_stepped)
		add_child(trigger)

	func _stepped(body: Node) -> void:
		if body is Player and (body as Player).alive and broken <= 0.0 and shake <= 0.0:
			shake = 0.42
			Sfx.play("press")

	func _is_solid() -> bool:
		return broken <= 0.0

	func step(delta: float) -> void:
		if not crumble:
			return
		if shake > 0.0:
			shake = maxf(0.0, shake - delta)
			if shake <= 0.0 and broken <= 0.0:
				broken = 1.9
				collision_layer = 0
				Sfx.play("land")
			queue_redraw()
			return
		if broken > 0.0:
			broken = maxf(0.0, broken - delta)
			if broken <= 0.0:
				collision_layer = 1
			queue_redraw()

	func _draw() -> void:
		var ice: bool = flags.contains("i")
		var thin: bool = flags.contains("o")
		var at := Vector2.ZERO
		if shake > 0.0:
			at = Vector2(sin(shake * 70.0) * 1.6, 0.0)
		var gone: float = 1.0 if broken <= 0.0 else clampf(1.0 - broken / 0.6, 0.0, 1.0)
		if gone <= 0.005:
			return
		var col := Art.cap_body(cap)
		var rad: float = minf(12.0, board.y * 0.4)
		var r := Rect2(at, board)
		if not thin:
			Art.round_rect(self, r.grow(3.0), rad + 3.0, OUTLINE)
		var cap_h: float = clampf(board.y * 0.5 if not thin else board.y * 1.05, 24.0, 40.0)
		if not thin:
			Art.round_rect(self, r, rad, col)
			draw_texture_rect(Art.vgrad(GLOW, DARK), r, false, col)
			if board.y > 40.0:
				var lines := int(board.y / 34.0)
				for i: int in range(lines):
					var y: float = cap_h + 10.0 + float(i) * 30.0 + _rng.randf_range(-4.0, 4.0)
					if y > board.y - 12.0:
						break
					var w: float = board.x * (0.35 + _rng.randf() * 0.5)
					var x0: float = _rng.randf_range(4.0, maxf(5.0, board.x - w - 4.0))
					draw_line(
						at + Vector2(x0, y), at + Vector2(x0 + w, y + _rng.randf_range(-2.0, 2.0)),
						Color(0, 0, 0, 0.10), 4.0, true
					)
					draw_line(
						at + Vector2(x0, y - 3.0), at + Vector2(x0 + w, y - 3.0),
						Color(1, 1, 1, 0.07), 2.0, true
					)
				for i: int in range(int(board.x * board.y / 900.0)):
					var p := at + Vector2(_rng.randf() * board.x, cap_h + _rng.randf() * (board.y - cap_h))
					draw_circle(p, 1.0 + _rng.randf() * 1.6, Color(0, 0, 0, 0.09))
			Art.round_rect(
				self, Rect2(at.x, board.y - 11.0, board.x, 11.0), rad * 0.6, Color(0.06, 0.03, 0.12, 0.20)
			)
		if ice:
			draw_texture_rect(Art.vgrad(Color(1.3, 1.35, 1.4, 1), Color(0.7, 0.85, 1.05, 1)), r, false, col)
			for i: int in range(3):
				var x0: float = board.x * (0.12 + float(i) * 0.3) + at.x
				draw_line(Vector2(x0, cap_h * 0.6), Vector2(x0 + 26.0, board.y * 0.8), Color(1, 1, 1, 0.30), 2.5, true)
		Art.draw_cap(self, cap, at.x, at.y, board.x, cap_h)
		for h: Dictionary in hangs:
			Art.draw_env(
				self, String(h.name), at + Vector2(float(h.x), board.y + 2.0), float(h.h), bool(h.flip), gone
			)
		for p: Dictionary in props:
			Art.draw_env(
				self, String(p.name), at + Vector2(float(p.x), 1.0), float(p.h), bool(p.flip), gone
			)
		if crumble and broken <= 0.0:
			for i: int in range(3):
				var x0: float = board.x * (0.22 + float(i) * 0.28)
				draw_line(
					at + Vector2(x0, 6.0), at + Vector2(x0 + 5.0, 22.0), Color(0.10, 0.05, 0.16, 0.35), 2.0, true
				)


class MovingHazard extends Area2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var size := 46.0
	var speed := 92.0
	var sprite := "saw"
	var offset := 0.0
	var spin := 0.0
	var col := Color(1, 1, 1)

	var _axis := Vector2.RIGHT
	var _span := 0.0
	var _dist := 0.0
	var _dir := 1.0

	func _init(d: Dictionary, spike: String) -> void:
		from = d.a
		to = d.b
		size = float(d.get("size", 46.0))
		speed = float(d.get("speed", 92.0))
		sprite = String(d.get("sprite", "saw"))
		offset = float(d.get("offset", 0.0))
		col = d.get("col", Color(1, 1, 1))
		position = from
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		_axis = to - from
		_span = _axis.length()
		if _span > 0.001:
			_axis /= _span
		_dist = fposmod(offset, 2.0 * _span)
		if _dist > _span:
			_dist = 2.0 * _span - _dist
			_dir = -1.0
		global_position = from + _axis * _dist
		var circ := CircleShape2D.new()
		circ.radius = size * 0.38
		var cs := CollisionShape2D.new()
		cs.shape = circ
		add_child(cs)
		body_entered.connect(_on_body)

	func _on_body(body: Node) -> void:
		if body is Player:
			(body as Player).die()

	func _physics_process(delta: float) -> void:
		if not Game.playing():
			return
		_dist += _dir * speed * delta
		if _dist >= _span:
			_dist = _span
			_dir = -1.0
		elif _dist <= 0.0:
			_dist = 0.0
			_dir = 1.0
		global_position = from + _axis * _dist
		spin += delta * 6.0 * _dir
		queue_redraw()

	func _draw() -> void:
		var rail := to - from
		draw_line(Vector2.ZERO, rail, Color(0.10, 0.06, 0.16, 0.22), 3.0, true)
		Art.draw_env_spin(self, sprite, Vector2.ZERO, size, spin, 1.0)


class Sweeper extends Area2D:
	var pivot := Vector2.ZERO
	var arm := 180.0
	var amp := 0.7
	var period := 3.4
	var phase := 0.0
	var _t := 0.0
	var bob := Vector2.ZERO

	func _init(d: Dictionary) -> void:
		pivot = d.at
		arm = float(d.get("arm", 180.0))
		amp = float(d.get("amp", 0.7))
		period = float(d.get("period", 3.4))
		phase = float(d.get("phase", 0.0))
		position = pivot
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		var circ := CircleShape2D.new()
		circ.radius = 20.0
		var cs := CollisionShape2D.new()
		cs.shape = circ
		cs.position = Vector2(0.0, arm)
		add_child(cs)
		body_entered.connect(_on_body)

	func _on_body(body: Node) -> void:
		if body is Player:
			(body as Player).die()

	func _physics_process(delta: float) -> void:
		if not Game.playing():
			return
		_t += delta
		var a: float = sin(_t * TAU / period + phase) * amp
		bob = Vector2(sin(a), cos(a)) * arm
		for c: Node in get_children():
			if c is CollisionShape2D:
				(c as CollisionShape2D).position = bob
		queue_redraw()

	func _draw() -> void:
		draw_line(Vector2.ZERO, bob, Color(0.16, 0.11, 0.22, 0.85), 4.0, true)
		draw_circle(Vector2.ZERO, 7.0, Color("6a5a8f"))
		Art.draw_env_spin(self, "saw", bob, 52.0, _t * 5.0, 1.0)


class Fan extends Area2D:
	var box := Vector2(150.0, 300.0)
	var lift := 2400.0
	var side := 0.0
	var spin := 0.0

	func _init(d: Dictionary) -> void:
		position = d.at
		box = d.get("box", Vector2(150.0, 300.0))
		lift = float(d.get("lift", 2400.0))
		side = float(d.get("side", 0.0))
		collision_layer = 0
		collision_mask = 2
		z_index = 2

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = box
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = box * 0.5
		add_child(cs)

	func _physics_process(delta: float) -> void:
		if not Game.playing():
			return
		spin += delta * 9.0
		queue_redraw()
		for body: Node in get_overlapping_bodies():
			if not (body is Player) or not (body as Player).alive:
				continue
			var p := body as Player
			p.velocity = Vector2(
				clampf(p.velocity.x + side * delta, -Player.SWING_MAX_X, Player.SWING_MAX_X),
				maxf(p.velocity.y - lift * delta, -520.0)
			)

	func _draw() -> void:
		var col: Color = Color("8fe8c8")
		for i: int in range(7):
			var t: float = fposmod(float(i) / 7.0 + spin * 0.06, 1.0)
			var x: float = box.x * (0.16 + 0.68 * t)
			var a: float = 0.18 * (1.0 - absf(t - 0.5) * 1.6)
			draw_line(
				Vector2(x, box.y), Vector2(x + side * 0.05 - 6.0, box.y * 0.55), Color(col.r, col.g, col.b, a), 3.0, true
			)
			draw_line(
				Vector2(x, box.y), Vector2(x + side * 0.05 + 6.0, box.y * 0.55), Color(col.r, col.g, col.b, a), 3.0, true
			)
		var hub := Vector2(box.x * 0.5, box.y - 8.0)
		draw_circle(hub, 26.0, Color(0.12, 0.09, 0.20, 0.55))
		for k: int in range(3):
			var ang := spin + float(k) / 3.0 * TAU
			draw_line(hub, hub + Vector2(cos(ang), sin(ang)) * 20.0, col, 6.0, true)


class Conveyor extends AnimatableBody2D:
	var board := Vector2(220.0, 26.0)
	var speed := 120.0
	var dir := 1.0
	var step_delta := Vector2.ZERO
	var _t := 0.0

	func _init(d: Dictionary) -> void:
		position = d.at
		board = d.get("box", Vector2(220.0, 26.0))
		speed = float(d.get("speed", 120.0))
		dir = float(d.get("dir", 1.0))
		collision_layer = 1
		collision_mask = 0

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = board
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = board * 0.5
		add_child(cs)

	func _physics_process(delta: float) -> void:
		if not Game.playing():
			return
		_t += delta
		step_delta = Vector2(dir * speed * delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var col := Color("4c3f63")
		Art.round_rect(self, Rect2(-3.0, -3.0, board.x + 6.0, board.y + 6.0), 14.0, OUTLINE)
		Art.round_rect(self, Rect2(Vector2.ZERO, board), 11.0, col)
		var off: float = fposmod(_t * speed * dir, 34.0)
		for i: int in range(int(board.x / 34.0) + 2):
			var x: float = float(i) * 34.0 + off - 34.0
			if x < 2.0 or x > board.x - 12.0:
				continue
			draw_line(Vector2(x, board.y * 0.75), Vector2(x + 9.0 * dir, board.y * 0.4), Color(1, 1, 1, 0.4), 3.0, true)
			draw_line(Vector2(x + 9.0 * dir, board.y * 0.4), Vector2(x, board.y * 0.15), Color(1, 1, 1, 0.4), 3.0, true)
		for k: int in range(2):
			draw_circle(Vector2(13.0 if k == 0 else board.x - 13.0, board.y * 0.5), 7.0, Color("8f86a6"))
			Art.draw_env_spin(self, "pulley", Vector2(13.0 if k == 0 else board.x - 13.0, board.y * 0.5), 20.0, _t * 4.0 * dir)


class Barrier extends StaticBody2D:
	var board := Vector2(30.0, 150.0)
	var cap := "cap_grass"
	var srcs: Array = []
	var open := 0.0
	var shape: CollisionShape2D

	func _init(r: Rect2, who: Array, crust: String) -> void:
		board = r.size
		srcs = who
		cap = crust
		position = r.position
		collision_layer = 1
		collision_mask = 0

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = board
		shape = CollisionShape2D.new()
		shape.shape = rect
		shape.position = board * 0.5
		add_child(shape)

	# Any one of the wired switches lifts the gate: that is what lets the first bear
	# across hold it open for the second one from the far side.
	func holding() -> bool:
		for s in srcs:
			if s != null and s.pressed():
				return true
		return false

	func _physics_process(delta: float) -> void:
		var want: float = 1.0 if holding() else 0.0
		var was := open
		open = move_toward(open, want, delta * 2.6)
		if open > 0.85 and collision_layer != 0:
			collision_layer = 0
			shape.set_deferred("disabled", true)
		elif open < 0.2 and collision_layer == 0:
			collision_layer = 1
			shape.set_deferred("disabled", false)
		if absf(was - open) > 0.001:
			queue_redraw()

	func _draw() -> void:
		var lift: float = open * board.y
		var body: Color = Art.cap_body(cap)
		var n := maxi(2, int(board.x / 16.0))
		for i: int in range(n):
			var x: float = board.x * (float(i) + 0.5) / float(n)
			var top: float = 8.0 - lift
			draw_line(Vector2(x, top), Vector2(x, board.y), Color(0.16, 0.11, 0.24, 0.95), 8.0, true)
			draw_line(Vector2(x, top), Vector2(x, board.y), body, 4.5, true)
		for k: int in range(3):
			var y: float = board.y * (0.22 + float(k) * 0.3) - lift
			if y > 2.0:
				draw_line(Vector2(2.0, y), Vector2(board.x - 2.0, y), Color(0.16, 0.11, 0.24, 0.8), 4.0, true)
		# The leading edge wears the chapter's own crust, so a lifted gate looks like
		# a slab of its own floor that has been pulled up out of the ground.
		var beam := Rect2(-4.0, -14.0 - lift, board.x + 8.0, 16.0)
		Art.round_rect(self, beam, 7.0, body)
		Art.draw_cap(self, cap, beam.position.x, beam.position.y + beam.size.y, beam.size.x, 13.0)


class Hazard extends Area2D:
	var board := Vector2(100.0, 26.0)
	var sprite := "spike_candy"
	var col := Color(1, 1, 1)

	func _init(r: Rect2, spike: String) -> void:
		board = r.size
		sprite = spike
		position = r.position
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(board.x, board.y * 0.72)
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = Vector2(board.x * 0.5, board.y * 0.66)
		add_child(cs)
		body_entered.connect(_on_body)

	func _on_body(body: Node) -> void:
		if body is Player:
			(body as Player).die()

	func _draw() -> void:
		# Spikes tile from a unit derived from their own height, so a long shelf of
		# them keeps the same silhouette as a short one and the tips stay pointed.
		var unit: float = board.y * 1.4
		var n: int = maxi(1, int(ceil(board.x / unit)))
		var step: float = board.x / float(n)
		for i: int in range(n):
			Art.draw_env(
				self,
				sprite,
				Vector2(step * (float(i) + 0.5), board.y + 2.0),
				minf(board.y, step * 1.05),
				i % 2 == 1,
				1.0
			)


class Plate extends Area2D:
	var occupants: Array[Player] = []
	var weights: Array[Node] = []
	var board := Vector2(86.0, 20.0)
	var col := Color("ffd166")
	var sink := 0.0
	var sticky := false
	var latched := false

	func _init(at: Vector2, c: Color, hold := false) -> void:
		position = at
		col = c
		sticky = hold
		collision_layer = 0
		collision_mask = 2 | 4

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(board.x, 26.0)
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = Vector2(board.x * 0.5, board.y * 0.5)
		add_child(cs)
		body_entered.connect(_on_in)
		body_exited.connect(_on_out)

	func _on_in(body: Node) -> void:
		var was := pressed()
		if body is Player:
			if not occupants.has(body):
				occupants.append(body as Player)
		elif body is RigidBody2D:
			if not weights.has(body):
				weights.append(body)
		if not was and pressed():
			Sfx.play("plate")

	func _on_out(body: Node) -> void:
		# occupants is typed Array[Player], so a crate leaving must not be erased
		# from it — Godot errors on a wrong-typed erase rather than ignoring it.
		if body is Player:
			occupants.erase(body)
		elif body is RigidBody2D:
			weights.erase(body)

	func pressed() -> bool:
		return latched or (not occupants.is_empty() or not weights.is_empty())

	func _process(delta: float) -> void:
		if pressed() and sticky and not latched:
			latched = true
			Sfx.play("door")
		sink = move_toward(sink, 1.0 if pressed() else 0.0, delta * 8.0)
		queue_redraw()

	func _draw() -> void:
		var y: float = sink * 6.0
		Art.round_rect(self, Rect2(Vector2(0.0, 8.0 + y), Vector2(board.x, board.y + 6.0)), 8.0, OUTLINE)
		Art.draw_env(self, "plate", Vector2(board.x * 0.5, 12.0 + y), board.x * 0.36)
		if latched:
			draw_circle(Vector2(board.x * 0.5, 6.0 + y), 5.0, Color("63d9a6"))
		var glow: float = 0.2 + sink * 0.8
		Art.round_rect(
			self, Rect2(Vector2(10.0, 2.0 + y), Vector2(board.x - 20.0, 4.0)), 2.0, Color(1, 1, 1, glow)
		)


class GoalDoor extends Area2D:
	var frame := Vector2(150.0, 196.0)
	var cap := "cap_grass"
	var want_open := false
	var open_amount := 0.0
	var inside: Array[Player] = []
	var _t := 0.0

	func _init(at: Vector2, crust: String) -> void:
		position = at
		cap = crust
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(frame.x * 0.62, frame.y - 16.0)
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = Vector2(frame.x * 0.5, frame.y - 16.0)
		add_child(cs)
		body_entered.connect(_on_in)
		body_exited.connect(_on_out)

	func _on_in(body: Node) -> void:
		if body is Player and not inside.has(body):
			inside.append(body as Player)

	func _on_out(body: Node) -> void:
		inside.erase(body)

	func _process(delta: float) -> void:
		_t += delta
		open_amount = move_toward(open_amount, 1.0 if want_open else 0.0, delta * 1.7)
		queue_redraw()

	func _draw() -> void:
		var frame_r := Rect2(Vector2.ZERO, frame)
		var light := Color("ffe9a8")
		var body: Color = Art.cap_body(cap)
		# The arch is baked art but the shutter is cut from the same material the
		# chapter's floors are, so the last thing in the level reads as part of the
		# world instead of a purple box standing in a doorway.
		Art.round_rect(self, frame_r.grow(5.0), 24.0, OUTLINE)
		Art.round_rect(
			self, Rect2(frame.x * 0.24, frame.y * 0.24, frame.x * 0.52, frame.y * 0.76), 12.0,
			Color(0.09, 0.06, 0.15)
		)
		Art.draw_env(self, "gate", Vector2(frame.x * 0.5, frame.y), frame.y + 8.0)
		# The arch art carries a dark doorway, so the light has to be laid over it
		# rather than behind it.
		if open_amount > 0.02:
			var inner := Rect2(
				frame.x * 0.27, frame.y - 22.0 - (frame.y * 0.62) * open_amount, frame.x * 0.46, frame.y * 0.66
			)
			Art.round_rect(self, inner, 14.0, Color(light.r, light.g, light.b, 0.20 + open_amount * 0.55))
			draw_circle(
				Vector2(frame.x * 0.5, frame.y * 0.62),
				30.0 + sin(_t * 3.0) * 5.0,
				Color(light.r, light.g, light.b, 0.14 * open_amount)
			)
		var slab_h: float = frame.y * 0.62 * (1.0 - open_amount)
		if slab_h > 2.0:
			var slab := Rect2(Vector2(frame.x * 0.27, frame.y * 0.30), Vector2(frame.x * 0.46, slab_h))
			Art.round_rect(self, slab, 10.0, body)
			Art.draw_cap(self, cap, slab.position.x, slab.position.y + slab.size.y, slab.size.x, 15.0)
			for i: int in range(3):
				var yy: float = frame.y * 0.34 + float(i) * 30.0
				if yy < slab.position.y + slab.size.y - 6.0:
					draw_line(
						Vector2(slab.position.x + 5.0, yy), Vector2(slab.end.x - 5.0, yy),
						Art.shade(body, -0.22).lerp(Color(0, 0, 0, 1), 0.35), 4.0
					)
		if want_open:
			for i: int in range(5):
				var a: float = _t * 1.4 + float(i) * 1.3
				Art.draw_env(
					self, "coin",
					Vector2(frame.x * 0.5 + cos(a) * frame.x * 0.26, frame.y * 0.55 + sin(a * 1.7) * 24.0),
					13.0, false, 0.45 + 0.35 * sin(a * 2.0)
				)


class Checkpoint extends Area2D:
	var raised := false
	var col := Color("59a7f0")
	var host: Node2D
	var _t := 0.0

	func _init(at: Vector2, c: Color) -> void:
		position = at
		col = c
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(52.0, 60.0)
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = Vector2(26.0, 30.0)
		add_child(cs)
		body_entered.connect(_on_in)

	func _on_in(body: Node) -> void:
		if body is Player and not raised:
			raised = true
			Sfx.play("plate")
			if host != null:
				host.register_checkpoint(self)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var h := 74.0 if raised else 66.0
		if raised:
			draw_circle(Vector2(26.0, -h * 0.2), 30.0 + sin(_t * 3.0) * 3.0, Color(col.r, col.g, col.b, 0.16))
		Art.draw_env(self, "flag", Vector2(26.0, 4.0), h, false, 1.0 if raised else 0.55)


class BoostPad extends Area2D:
	var power := 1080.0
	var board := Vector2(58.0, 18.0)
	var press := 0.0
	var col := Color("63d9a6")

	func _init(at: Vector2, p: float, c: Color) -> void:
		position = at
		power = p
		col = c
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(board.x, board.y + 22.0)
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = Vector2(board.x * 0.5, board.y * 0.5)
		add_child(cs)
		body_entered.connect(_on_in)

	func _on_in(body: Node) -> void:
		if body is Player:
			(body as Player).launch(power)
			press = 1.0
			Sfx.play("boing")

	func _process(delta: float) -> void:
		press = maxf(0.0, press - delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		var squash: float = press * 9.0
		var h: float = board.y + 26.0 - squash
		Art.round_rect(self, Rect2(Vector2(-2.0, board.y - 2.0), Vector2(board.x + 4.0, 10.0)), 5.0, OUTLINE)
		Art.draw_env(self, "spring", Vector2(board.x * 0.5, board.y + 8.0), h)
		if press > 0.1:
			for i: int in range(3):
				var t: float = clampf(press - float(i) * 0.22, 0.0, 1.0)
				if t > 0.02:
					draw_line(
						Vector2(board.x * 0.5 - 14.0 + float(i) * 14.0, -10.0 - (1.0 - t) * 26.0),
						Vector2(board.x * 0.5 - 8.0 + float(i) * 14.0, -24.0 - (1.0 - t) * 26.0),
						Color(1, 1, 1, t * 0.6), 3.0, true
					)


class Coin extends Area2D:
	var taken := false
	var host: Node2D
	var _t := 0.0
	var r := 13.0
	var seed_i := 0.0

	func _init(at: Vector2) -> void:
		position = at
		seed_i = at.x * 0.017 + at.y * 0.031
		collision_layer = 0
		collision_mask = 2

	func _ready() -> void:
		var circ := CircleShape2D.new()
		circ.radius = r
		var cs := CollisionShape2D.new()
		cs.shape = circ
		add_child(cs)
		body_entered.connect(_on_in)

	func _on_in(body: Node) -> void:
		if body is Player and not taken:
			taken = true
			Game.coins += 1
			if host != null:
				host.note_coin()
			Sfx.play("coin")
			queue_free()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var lift: float = sin(_t * 2.0 + seed_i) * 3.0
		var wob: float = 0.72 + 0.28 * absf(cos(_t * 1.9 + seed_i))
		draw_circle(Vector2(0.0, lift), r * 2.1, Color(1, 0.86, 0.5, 0.13))
		Art.draw_env(self, "coin", Vector2(0.0, lift + r * 0.9), r * 2.0, false, 1.0)
		draw_set_transform(Vector2(0.0, lift), 0.0, Vector2(wob, 1.0))
		draw_rect(Rect2(-2.0, -r * 0.7, 4.0, r * 0.5), Color(1, 1, 1, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Pulley extends Node2D:
	var wheel := 30.0
	var _t := 0.0
	var spin := 0.0
	var engaged := false
	var col := Color("c69a6d")

	func _init(at: Vector2, d: Dictionary) -> void:
		position = at
		col = d.get("col", Color("c69a6d"))

	func _process(delta: float) -> void:
		_t += delta
		spin += delta * (1.8 if engaged else 0.5)
		queue_redraw()

	func _draw() -> void:
		draw_line(Vector2(0.0, -wheel * 0.5), Vector2(0.0, -wheel - 30.0), OUTLINE, 8.0)
		draw_line(Vector2(0.0, -wheel * 0.5), Vector2(0.0, -wheel - 30.0), Color("8f86a6"), 4.0)
		draw_circle(Vector2.ZERO, wheel + 5.0, OUTLINE)
		Art.draw_env_spin(self, "pulley", Vector2.ZERO, wheel * 2.2, spin, 1.0)
		draw_circle(Vector2(0.0, 0.0), 5.0, Color(col.r, col.g, col.b, 0.9))
		if engaged:
			draw_circle(Vector2.ZERO, wheel + 9.0 + sin(_t * 5.0) * 2.0, Color(1, 1, 1, 0.12))


class Prompt extends Node2D:
	var text := ""
	var kind := "jump"
	var _t := 0.0

	func _init(at: Vector2, s: String, k: String) -> void:
		position = at
		text = s
		kind = k
		z_index = 3

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var bob: float = sin(_t * 2.0) * 3.0
		var w: float = UI.text_width(text, 19) + 30.0
		var r := Rect2(-w * 0.5, -46.0 + bob, w, 34.0)
		Art.round_rect(self, r.grow(2.0), 15.0, Color(0.10, 0.07, 0.16, 0.55))
		Art.round_rect(self, r, 13.0, Color(0.94, 0.92, 0.98, 0.92))
		UI.label(self, text, 0.0, -23.0 + bob, 19, Color("3a2b52"))
		var tip := PackedVector2Array([Vector2(-7.0, -12.0 + bob), Vector2(7.0, -12.0 + bob), Vector2(0.0, -2.0 + bob)])
		draw_colored_polygon(tip, Color(0.94, 0.92, 0.98, 0.92))
		if kind == "both":
			draw_circle(Vector2(-w * 0.5 + 14.0, -29.0 + bob), 4.0, Art.ACCENT_COLORS[0])
			draw_circle(Vector2(w * 0.5 - 14.0, -29.0 + bob), 4.0, Art.ACCENT_COLORS[1])


# Foliage that hangs in front of the play field. It drifts a notch faster than the
# world and only ever occupies the top fifth of the screen, so it frames the shot
# without hiding a bear.
class Canopy extends Node2D:
	var camera: Camera2D
	var world_size := Vector2(1900.0, 760.0)
	var biome: Dictionary = {}

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		# An open sky is what tells a meadow from a forest, so the fringe is a per-biome
		# choice rather than a layer every chapter has to carry.
		var alpha: float = float(biome.get("fringe", 0.0))
		var tex := Art.env("bg_canopy")
		if alpha <= 0.01 or tex == null or camera == null:
			return
		var z: float = maxf(0.05, camera.zoom.x)
		var vp := get_viewport_rect().size
		var vw: float = vp.x / z
		var vh: float = vp.y / z
		var cam := camera.global_position
		var r := Rect2(
			cam.x - vw * 0.5 - 30.0 - (cam.x - world_size.x * 0.5) * 0.12,
			cam.y - vh * 0.5 - 8.0,
			vw + 60.0,
			vh * 0.22
		)
		var tint: Color = biome.get("canopy", Color("3f6b58"))
		draw_texture_rect(tex, r, false, Color(tint.r, tint.g, tint.b, 0.92))


# --------------------------------------------------------------------------------
# A crate is the one object both games hand the rope to: it holds a plate down, it
# shrinks a gap, and a partner can be pulled onto it.
# --------------------------------------------------------------------------------
class Crate extends RigidBody2D:
	var board := Vector2(46.0, 46.0)

	func _init(at: Vector2) -> void:
		position = at
		collision_layer = 4
		collision_mask = 1 | 2 | 4
		mass = 1.5
		linear_damp = 1.1
		angular_damp = 4.0
		can_sleep = true

	func _ready() -> void:
		var rect := RectangleShape2D.new()
		rect.size = board
		var cs := CollisionShape2D.new()
		cs.shape = rect
		add_child(cs)

	func _physics_process(delta: float) -> void:
		if not Game.playing():
			linear_velocity = Vector2.ZERO
			return
		# Project gravity is switched off so the CharacterBody tuning owns the fall,
		# which means the box has to be handed the same acceleration by hand.
		apply_central_force(Vector2(0.0, mass * Player.GRAVITY))
		if global_position.y > 4000.0:
			queue_free()

	func _draw() -> void:
		Art.draw_env_spin(self, "crate", Vector2.ZERO, board.x + 8.0, rotation, 1.0)


func level_data() -> Dictionary:
	return {}


func _ready() -> void:
	data = level_data()
	add_to_group("level")
	biome_id = String(data.get("biome", "meadow"))
	biome = Biomes.get_def(biome_id)
	_build()


func _build() -> void:
	var size: Vector2 = data.bounds
	var backdrop := Backdrop.new()
	backdrop.world_size = size
	backdrop.sky_top = data.sky[0]
	backdrop.sky_bottom = data.sky[1]
	backdrop.biome = biome
	add_child(backdrop)

	var spike := String(biome.get("spike", "spike_stone"))
	for e: Array in data.get("platforms", []):
		add_child(Platform.new(Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), _flags(e), biome))
	for e: Array in data.get("crumbles", []):
		var p := Platform.new(Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), "c" + _flags(e), biome)
		_crumbles.append(p)
		add_child(p)
	for e: Dictionary in data.get("movers", []):
		var md: Dictionary = e.duplicate(true)
		md["cap"] = biome.get("cap", "cap_grass")
		add_child(MovingPlatform.new(md))
	for e: Array in data.get("belts", []):
		add_child(Conveyor.new({
			"at": Vector2(float(e[0]), float(e[1])),
			"box": Vector2(float(e[2]), float(e[3])),
			"dir": float(e[4]),
			"speed": float(e[5]),
		}))
	for e: Array in data.get("hazards", []):
		add_child(Hazard.new(Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), spike))
	for e: Dictionary in data.get("saws", []):
		add_child(MovingHazard.new(e, spike))
	for e: Dictionary in data.get("sweepers", []):
		add_child(Sweeper.new(e))
	for e: Dictionary in data.get("fans", []):
		add_child(Fan.new(e))
	for e: Array in data.get("pads", []):
		add_child(BoostPad.new(Vector2(float(e[0]), float(e[1])), float(e[2]), Color("63d9a6")))

	plates = []
	for e: Array in data.get("plates", []):
		var plate := Plate.new(Vector2(float(e[0]), float(e[1])), Color("ffd166"))
		plates.append(plate)
		add_child(plate)
	for e: Array in data.get("latches", []):
		var latch := Plate.new(Vector2(float(e[0]), float(e[1])), Color("63d9a6"), true)
		plates.append(latch)
		add_child(latch)
	# Gates have to be wired after every plate exists, so a barrier can hold the
	# indices of the switches that lift it.
	for e: Array in data.get("barriers", []):
		var wired: Array = []
		for k: int in range(4, e.size()):
			wired.append(_source(int(e[k])))
		add_child(Barrier.new(
			Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), wired, String(biome.get("cap", "cap_grass"))
		))

	coins_total = 0
	for e: Array in data.get("coins", []):
		var coin := Coin.new(Vector2(float(e[0]), float(e[1])))
		coin.host = self
		coins_total += 1
		add_child(coin)

	for e: Array in data.get("crates", []):
		add_child(Crate.new(Vector2(float(e[0]), float(e[1]))))

	door = GoalDoor.new(Vector2(data.goal.x, data.goal.y), String(biome.get("cap", "cap_grass")))
	add_child(door)

	for e: Array in data.get("checkpoints", []):
		var cp := Checkpoint.new(Vector2(float(e[0]), float(e[1])), Color("59a7f0"))
		cp.host = self
		add_child(cp)

	spawn_points = []
	for s: Vector2 in data.spawns:
		spawn_points.append(s)

	players = []
	for i: int in range(2):
		var p := Player.new(i)
		p.position = spawn_points[i]
		add_child(p)
		players.append(p)
		p.died.connect(_on_player_died)

	for e: Array in data.get("pulleys", []):
		var wheel := Pulley.new(
			Vector2(float(e[0]), float(e[1])),
			{"sticky": e.size() > 2 and String(e[2]) == "s", "col": Biomes.PULLEY_COL.get(biome_id, Color("c69a6d"))}
		)
		pulleys.append(wheel)
		add_child(wheel)

	for e: Array in data.get("prompts", []):
		add_child(Prompt.new(Vector2(float(e[0]), float(e[1])), String(e[2]), String(e[3])))

	tether = Tether.new()
	tether.name = "Tether"
	tether.length = float(data.get("rope", 300.0))
	tether.posts = pulleys
	add_child(tether)
	tether.bind(players[0], players[1])
	players[0].tether = tether
	players[1].tether = tether

	camera = Camera2D.new()
	camera.position = spawn_points[0]
	add_child(camera)
	camera.make_current()
	backdrop.camera = camera

	_canopy = Canopy.new()
	_canopy.camera = camera
	_canopy.world_size = size
	_canopy.biome = biome
	add_child(_canopy)

	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 90
	_confetti.lifetime = 1.6
	_confetti.explosiveness = 1.0
	_confetti.direction = Vector2(0.0, -1.0)
	_confetti.spread = 62.0
	_confetti.gravity = Vector2(0.0, 620.0)
	_confetti.initial_velocity_min = 180.0
	_confetti.initial_velocity_max = 460.0
	_confetti.scale_amount_min = 3.0
	_confetti.scale_amount_max = 7.0
	_confetti.color = Color("ffd166")
	_confetti.position = Vector2(data.goal.x + 74.0, data.goal.y + 50.0)
	add_child(_confetti)


func _flags(e: Array) -> String:
	return String(e[4]) if e.size() > 4 else ""


func _source(i: int) -> Node:
	return plates[i] if i >= 0 and i < plates.size() else null


func _process(delta: float) -> void:
	if not Game.playing():
		return
	_update_camera(delta)
	_update_goal()
	_update_state(delta)


func note_coin() -> void:
	coins_taken += 1


func kick(amount: float) -> void:
	if not bool(Game.settings.get("shake", true)):
		return
	_shake = maxf(_shake, amount)


func _update_state(delta: float) -> void:
	var size: Vector2 = data.bounds
	for p: Player in players:
		if not is_instance_valid(p):
			continue
		if p.alive and p.global_position.y > size.y + 260.0:
			p.die()

	for c: Platform in _crumbles:
		if is_instance_valid(c):
			c.step(delta)

	for w: Node2D in pulleys:
		if w is Pulley:
			(w as Pulley).engaged = tether != null and tether.is_engaged(w)

	if _respawn_wait > 0.0:
		_respawn_wait -= delta
		if _respawn_wait <= 0.0:
			for i: int in range(players.size()):
				players[i].respawn(spawn_points[i])
			if tether != null:
				tether.active = true
	_shake = maxf(0.0, _shake - delta * 42.0)

	if _celebrate > 0.0:
		_celebrate -= delta
		if _celebrate <= 0.0:
			Game.complete_level(stars())


func _update_goal() -> void:
	if door == null:
		return
	var open_now := String(data.get("unlock", "plates")) == "free" or _plates_satisfied()
	if not finished and not _unlocked and open_now:
		_unlocked = true
		door.want_open = true
		Sfx.play("door")
	if finished or not _unlocked:
		return
	var standing := 0
	for p: Player in players:
		if p.alive and door.inside.has(p):
			standing += 1
	if standing >= players.size():
		finished = true
		_celebrate = 1.0
		_confetti.restart()
		_confetti.emitting = true
		Sfx.play("win")
		for p: Player in players:
			p.frozen = true
			p.launch(430.0)


func _plates_satisfied() -> bool:
	if plates.is_empty():
		return true
	var free: Array[int] = []
	for i: int in range(plates.size()):
		if plates[i].weights.is_empty() and not plates[i].latched:
			free.append(i)
	var taken := {}
	return _match(free, 0, taken)


func _match(order: Array[int], index: int, used: Dictionary) -> bool:
	if index >= order.size():
		return true
	for p: Player in plates[order[index]].occupants:
		var id := p.get_instance_id()
		if used.has(id):
			continue
		used[id] = true
		if _match(order, index + 1, used):
			return true
		used.erase(id)
	return false


func register_checkpoint(cp: Area2D) -> void:
	for i: int in range(players.size()):
		spawn_points[i] = cp.global_position + Vector2(float(i) * 46.0 - 23.0, -34.0)


func _on_player_died(_who: Player) -> void:
	if finished:
		return
	Game.deaths += 1
	Game.note("deaths")
	_shake = 15.0
	_respawn_wait = 0.7
	# The rope stops pulling: a corpse dragged along by a live partner is both
	# unreadable and enough to yank the survivor off the ledge.
	if tether != null:
		tether.active = false
	for p: Player in players:
		p.frozen = true


func _update_camera(delta: float) -> void:
	# QA hook: frame the whole chapter at once so a route can be read in one still.
	if preview:
		var pvp := get_viewport_rect().size
		var fit: float = minf(pvp.x / maxf(1.0, data.bounds.x), pvp.y / maxf(1.0, data.bounds.y))
		camera.zoom = Vector2(fit, fit)
		camera.global_position = data.bounds * 0.5
		return
	var box := Rect2(players[0].global_position, Vector2.ZERO)
	for p: Player in players:
		if is_instance_valid(p):
			box = box.expand(p.global_position)
	box = box.grow(170.0)
	var vp := get_viewport_rect().size
	var want: float = clampf(
		minf(vp.x / maxf(box.size.x, 1.0), vp.y / maxf(box.size.y, 1.0)), 0.46, 1.1
	)
	var center := box.get_center()
	var half := vp * 0.5 / want
	center.x = _clamp_axis(center.x, half.x, data.bounds.x)
	center.y = _clamp_axis(center.y - 30.0, half.y, data.bounds.y)
	var k: float = 1.0 - exp(-9.0 * delta)
	camera.zoom = camera.zoom.lerp(Vector2(want, want), k)
	var target := center
	if _shake > 0.1:
		target += Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	camera.global_position = camera.global_position.lerp(target, k)


func _clamp_axis(value: float, half: float, span: float) -> float:
	if half * 2.0 >= span:
		return span * 0.5
	return clampf(value, half, span - half)


func hud_info() -> Dictionary:
	return {
		"name": String(data.get("name", "")),
		"hint": String(data.get("hint", "")),
		"biome": biome_id,
		"world": int(data.get("world", 1)),
		"plates_total": plates.size(),
		"plates_ok": _unlocked,
		"goal": data.get("goal", Vector2.ZERO),
		"coins_taken": coins_taken,
		"coins_total": coins_total,
		"par": float(data.get("par", 60.0)),
		"stars": stars(),
		"finished": finished,
	}


func stars() -> int:
	var s := 1
	if coins_total > 0 and coins_taken >= coins_total:
		s += 1
	if float(data.get("par", 60.0)) > 0.0 and Game.level_time() <= float(data.get("par", 60.0)):
		s += 1
	return s
