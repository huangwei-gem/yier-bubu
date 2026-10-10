class_name MovingPlatform
extends AnimatableBody2D

var from := Vector2.ZERO
var to := Vector2.ZERO
var board := Vector2(150.0, 26.0)
var speed := 95.0
var offset := 0.0
var step_delta := Vector2.ZERO
var col := Color("8d7cc4")
var cap := "cap_grass"

var _axis := Vector2.RIGHT
var _span := 0.0
var _dist := 0.0
var _dir := 1.0


func _init(data: Dictionary) -> void:
	from = data.a
	to = data.b
	board = data.board
	speed = float(data.get("speed", 95.0))
	offset = float(data.get("offset", 0.0))
	cap = String(data.get("cap", cap))
	collision_layer = 1
	collision_mask = 0


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

	var shape := RectangleShape2D.new()
	shape.size = board
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = board * 0.5
	add_child(cs)


func _physics_process(delta: float) -> void:
	if not Game.playing():
		return
	var prev := global_position
	_dist += _dir * speed * delta
	if _dist >= _span:
		_dist = _span
		_dir = -1.0
	elif _dist <= 0.0:
		_dist = 0.0
		_dir = 1.0
	global_position = from + _axis * _dist
	step_delta = global_position - prev
	queue_redraw()


func _draw() -> void:
	var outline := Color(0.24, 0.17, 0.31)
	var body := Art.cap_body(cap)
	Art.round_rect(self, Rect2(-3.0, -3.0, board.x + 6.0, board.y + 6.0), 13.0, outline)
	Art.round_rect(self, Rect2(Vector2.ZERO, board), 10.0, body)
	draw_texture_rect(
		Art.vgrad(Color(1.06, 1.05, 1.03), Color(0.55, 0.5, 0.62)),
		Rect2(Vector2.ZERO, board), false, body
	)
	Art.draw_cap(self, cap, 0.0, 0.0, board.x, clampf(board.y * 0.5, 20.0, 30.0))
	# The travel direction is the one thing a player has to read off a lift, so it is
	# painted on the slab rather than left to inference.
	for i: int in range(3):
		var t: float = (float(i) + 0.5) / 3.0
		var p := Vector2(board.x * t, board.y * 0.72)
		draw_circle(p, 2.6, Color(1, 1, 1, 0.42))
