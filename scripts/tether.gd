class_name Tether
extends Node2D

const SAG_RATIO := 0.30
const SYNC_WINDOW := 0.15
const SYNC_BOOST := 250.0
const CORRECTION_CAP := 15.0

var length := 300.0
var posts: Array[Node2D] = []
var a: Player
var b: Player

var taut := false
var active := true
var glow := 0.0
var pulse := 0.0
var engaged: Array[Node2D] = []
var _was_taut := false
var _taut_cd := 0.0

var _path: Array[Vector2] = []


func _ready() -> void:
	z_index = 5


func bind(player_a: Player, player_b: Player) -> void:
	a = player_a
	b = player_b


func is_engaged(post: Node2D) -> bool:
	return engaged.has(post)


func _physics_process(delta: float) -> void:
	if a == null or b == null or not Game.playing():
		return
	if active:
		_try_sync_jump()
	_solve()
	a.rope_taut = taut
	b.rope_taut = taut
	glow = move_toward(glow, 1.0 if taut else 0.0, delta * 7.0)
	pulse = maxf(0.0, pulse - delta * 2.2)
	_taut_cd = maxf(0.0, _taut_cd - delta)
	if taut and not _was_taut and _taut_cd <= 0.0:
		_taut_cd = 0.3
		Sfx.play("taut")
	_was_taut = taut
	queue_redraw()


func _solve() -> void:
	var pa := a.global_position
	var pb := b.global_position
	var middle: Array[Vector2] = []
	engaged.clear()
	for post: Node2D in posts:
		if _wrapped(pa, pb, post.global_position):
			middle.append(post.global_position)
			engaged.append(post)

	var path: Array[Vector2] = [pa]
	for m: Vector2 in middle:
		path.append(m)
	path.append(pb)
	var total := 0.0
	for i: int in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])

	taut = active and total > length - 1.0
	if not taut:
		_path = path
		return

	var excess: float = total - length
	# Standing on the ground is the anchor: friction lets you lean on the rope, so
	# only the airborne half of the pair yields. Two free-falling players split it.
	var wa: float = 0.0 if a.is_on_floor() else 1.0
	var wb: float = 0.0 if b.is_on_floor() else 1.0
	if wa == 0.0 and wb == 0.0:
		wa = 1.0
		wb = 1.0
	var share_a: float = wa / (wa + wb)
	var share_b: float = wb / (wa + wb)

	var dir_a: Vector2 = (path[1] - pa).normalized()
	var dir_b: Vector2 = (path[path.size() - 2] - pb).normalized()

	a.global_position += dir_a * minf(excess * share_a, CORRECTION_CAP)
	b.global_position += dir_b * minf(excess * share_b, CORRECTION_CAP)
	_kill_separating(a, -dir_a)
	_kill_separating(b, -dir_b)

	_path = [a.global_position]
	for m: Vector2 in middle:
		_path.append(m)
	_path.append(b.global_position)


func _kill_separating(who: Player, outward: Vector2) -> void:
	if not who.alive:
		return
	var away: float = who.velocity.dot(outward)
	if away > 0.0:
		who.velocity -= outward * away


# The rope is threaded through the wheel, so it has to bend there. That reads as
# "engaged" only while the two players sit on opposite sides and the wheel is
# above the straight chord between them; otherwise the rope runs straight past it.
func _wrapped(pa: Vector2, pb: Vector2, center: Vector2) -> bool:
	if (pa.x - center.x) * (pb.x - center.x) > 0.0:
		return false
	var dx := pb.x - pa.x
	if absf(dx) < 1.0:
		return false
	var t := (center.x - pa.x) / dx
	if t <= 0.0 or t >= 1.0:
		return false
	return center.y < lerpf(pa.y, pb.y, t) - 8.0


func anchor_for(who: Player) -> Vector2:
	if _path.size() < 2:
		return who.global_position
	return _path[1] if who == a else _path[_path.size() - 2]


func _try_sync_jump() -> void:
	if not a.alive or not b.alive:
		return
	if not a.sync_ready or not b.sync_ready:
		return
	if absf(a.jump_request - b.jump_request) > SYNC_WINDOW:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - a.jump_request > 0.4 or now - b.jump_request > 0.4:
		return
	# Both must be rising from their own jump, so the boost reads as one shared leap.
	if a.velocity.y > -Player.JUMP_CUT or b.velocity.y > -Player.JUMP_CUT:
		return
	for who: Player in [a, b]:
		who.sync_boost(SYNC_BOOST)
		who.sync_ready = false
	Game.note("sync")
	pulse = 1.0
	Sfx.play("sync")


func _draw() -> void:
	if _path.size() < 2:
		return
	var pts := PackedVector2Array()
	for i: int in range(_path.size() - 1):
		var p0: Vector2 = _path[i]
		var p1: Vector2 = _path[i + 1]
		var seg: float = p0.distance_to(p1)
		var slack: float = clampf(1.0 - seg / length, 0.0, 1.0)
		var guided: bool = i > 0 or i + 1 < _path.size() - 1
		var sag: float = slack * SAG_RATIO * seg * (0.26 if guided else 1.0)
		var steps: int = clampi(int(seg / 20.0), 6, 26)
		for s: int in range(steps + 1):
			var t: float = float(s) / float(steps)
			pts.append(p0.lerp(p1, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t) * 0.5))

	var last: int = maxi(1, pts.size() - 2)
	if glow > 0.02:
		for i: int in range(pts.size() - 1):
			var t: float = float(i) / float(last)
			var c := Art.ACCENT_COLORS[0].lerp(Art.ACCENT_COLORS[1], t)
			draw_line(pts[i], pts[i + 1], Color(c.r, c.g, c.b, 0.20 * glow), 9.0, true)
	for i: int in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], Color(0.20, 0.14, 0.28, 0.95), 6.0, true)
	for i: int in range(pts.size() - 1):
		var t: float = float(i) / float(last)
		var c := Art.ACCENT_COLORS[0].lerp(Art.ACCENT_COLORS[1], t)
		if pulse > 0.0:
			c = c.lerp(Color(1, 1, 1, 1), pulse * 0.7)
		draw_line(pts[i], pts[i + 1], c, 3.4, true)
	# A rope that is taking weight has to look like it is: the slack goes out of the
	# curve and a bright fibre appears along the core.
	if glow > 0.05:
		for i: int in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], Color(1, 1, 1, 0.42 * glow), 1.3, true)

	for i: int in range(_path.size()):
		var at: Vector2 = _path[i]
		var col: Color = Color("ffd166")
		if i == 0:
			col = Art.ACCENT_COLORS[0]
		elif i == _path.size() - 1:
			col = Art.ACCENT_COLORS[1]
		draw_circle(at, 5.0, Color(0.20, 0.14, 0.28, 0.95))
		draw_circle(at, 2.8, col)
