class_name Player
extends CharacterBody2D

const SPEED := 272.0
const GROUND_ACCEL := 3000.0
const AIR_ACCEL := 2000.0
const FRICTION := 3200.0
const JUMP_VELOCITY := 660.0
const GRAVITY := 1750.0
const MAX_FALL := 1320.0
const COYOTE := 0.10
const BUFFER := 0.13
const JUMP_CUT := 260.0
const STOMP_BOUNCE := 1000.0
const HEAD_Y := -22.0
const CLIMB_SPEED := 190.0
const CLIMB_STOP := 42.0
const SWING_MAX_X := 660.0

signal died(who: Player)

var player_index := 0
var frozen := false
var alive := true
var invuln := 0.0
var press_timer := 0.0
var ground_dist := 0.0
var facing := 1.0
var blinking := false
var rope_taut := false
var clinging := false
var tether: Tether
var jump_request := -10.0
var sync_ready := true
var coyote_left := 0.0
var cling_lock := 0.0
var _squash := Vector2.ONE
var _buffer := 0.0
var _own_jump := false
var _jump_held := false
var _was_floor := false
var _run_phase := 0.0
var _blink_wait := 2.0
var _blink_on := 0.0
var _visual: CharVisual
var _dust: CPUParticles2D


class CharVisual extends Node2D:
	var host: Player
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		scale = host.squash_scale()
		queue_redraw()

	func _draw() -> void:
		Art.draw_buddy(
			self,
			host.player_index,
			Vector2.ZERO,
			host.facing,
			host.visual_frame(),
			host.press_timer,
			_t
		)


func _init(index: int) -> void:
	player_index = clampi(index, 0, 1)
	name = Art.NAMES[player_index]
	collision_layer = 2
	# Layer 4 is crates: the pair have to push them, and a crate has to hold them up.
	collision_mask = 1 | 4


func _ready() -> void:
	add_to_group("players")
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26.0, 36.0)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	shape.position = Vector2(0.0, 1.0)
	add_child(shape)

	_visual = CharVisual.new()
	_visual.host = self
	add_child(_visual)

	_dust = CPUParticles2D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 10
	_dust.lifetime = 0.42
	_dust.explosiveness = 1.0
	_dust.direction = Vector2(0.0, -0.45)
	_dust.spread = 68.0
	_dust.gravity = Vector2(0.0, 440.0)
	_dust.initial_velocity_min = 55.0
	_dust.initial_velocity_max = 145.0
	_dust.scale_amount_min = 2.0
	_dust.scale_amount_max = 5.0
	_dust.color = Color(1, 1, 1, 0.72)
	_dust.position = Vector2(0.0, 17.0)
	add_child(_dust)


func squash_scale() -> Vector2:
	return _squash


# The baked poses carry the walking and the air time, so this is just a state
# pick. Clinging reads as arms-up, which is exactly the climb pose.
func visual_frame() -> int:
	if not alive:
		return Art.F_FALL
	if clinging or not is_on_floor():
		return Art.F_JUMP if (clinging or velocity.y < 0.0) else Art.F_FALL
	if absf(velocity.x) > 24.0:
		return Art.F_RUN_A if int(_run_phase * 0.40) % 2 == 0 else Art.F_RUN_B
	return Art.F_BLINK if blinking else Art.F_IDLE


func _physics_process(delta: float) -> void:
	if not Game.playing():
		return
	if not alive:
		_dead_step(delta)
		return
	var keys := {"left": key("left"), "right": key("right"), "jump": key("jump")}
	var on_floor := is_on_floor()
	var dir := 0.0
	if not frozen:
		if Input.is_physical_key_pressed(keys.left):
			dir -= 1.0
		if Input.is_physical_key_pressed(keys.right):
			dir += 1.0
		dir = clampf(dir + Pads.axis(player_index, JOY_AXIS_LEFT_X), -1.0, 1.0)
		if Pads.button(player_index, JOY_BUTTON_DPAD_LEFT):
			dir = -1.0
		if Pads.button(player_index, JOY_BUTTON_DPAD_RIGHT):
			dir = 1.0

	var below := _probe_below()
	var surf: Node = below.body
	# Ice is the one surface that refuses to grip: the same legs slide on it, so the
	# level's own braking distance becomes the puzzle.
	var slippery: bool = surf != null and surf.get("slippery") == true
	var grip: float = 0.16 if slippery else 1.0

	var accel := (GROUND_ACCEL if on_floor else AIR_ACCEL) * (grip if on_floor else 1.0)
	if dir != 0.0:
		facing = signf(dir)
		# Never scrub speed the rope (or a bounce) already gave us, or swinging
		# would cancel itself out on the very frame you let go.
		if absf(velocity.x) > SPEED and velocity.x * dir > 0.0:
			velocity.x = clampf(velocity.x, -SWING_MAX_X, SWING_MAX_X)
		else:
			velocity.x = move_toward(velocity.x, dir * SPEED, accel * delta)
	else:
		velocity.x = move_toward(
			velocity.x, 0.0, FRICTION * (grip if on_floor else 0.35) * delta
		)

	var held := (
		Input.is_physical_key_pressed(keys.jump) or Pads.button(player_index, JOY_BUTTON_A)
	) and not frozen
	if held and not _jump_held:
		_buffer = BUFFER
		jump_request = Time.get_ticks_msec() / 1000.0
	_jump_held = held
	_buffer = maxf(0.0, _buffer - delta)

	if on_floor:
		coyote_left = COYOTE
		_own_jump = false
		sync_ready = true
	else:
		coyote_left = maxf(0.0, coyote_left - delta)

	clinging = false
	var anchor := global_position
	if rope_taut and tether != null:
		anchor = tether.anchor_for(self)
	var hanging_below := global_position.y > anchor.y + 12.0
	var near_anchor := anchor.distance_to(global_position) < CLIMB_STOP
	var on_rope: bool = (
		not on_floor and rope_taut and tether != null and hanging_below and not near_anchor
	)

	cling_lock = maxf(0.0, cling_lock - delta)
	if _buffer > 0.0 and coyote_left > 0.0:
		_do_jump(false)
	elif _buffer > 0.0 and on_rope:
		_do_jump(true)
	elif held and on_rope and cling_lock <= 0.0 and velocity.y > -140.0:
		clinging = true
		_buffer = 0.0
		_own_jump = false
		velocity = (anchor - global_position).normalized() * CLIMB_SPEED
	elif not held and _own_jump and velocity.y < -JUMP_CUT:
		velocity.y = -JUMP_CUT
		_own_jump = false

	if not clinging and not on_floor:
		velocity.y = minf(MAX_FALL, velocity.y + GRAVITY * delta)

	# Anything that reports a step_delta carries the bear standing on it: that is how
	# a lift moves you and how a belt drags you along without touching your inputs.
	if on_floor and surf != null and "step_delta" in surf:
		global_position += surf.step_delta

	var pre_fall: float = velocity.y
	move_and_slide()
	_check_stomp()

	if on_floor and not _was_floor and pre_fall > 260.0:
		_squash = Vector2(1.28, 0.72)
		_dust.restart()
		_dust.emitting = true
		Sfx.play("land")
	_was_floor = on_floor

	var moving := clampf(absf(velocity.x) / SPEED, 0.0, 1.0)
	if moving > 0.06 and on_floor:
		_run_phase += delta * (4.0 + moving * 6.6)
	else:
		_run_phase = move_toward(_run_phase, 0.0, delta * 6.0)

	_squash = _squash.lerp(Vector2.ONE, minf(1.0, delta * 11.0))
	ground_dist = float(below.dist)
	press_timer = maxf(0.0, press_timer - delta)
	invuln = maxf(0.0, invuln - delta)
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_wait = randf_range(2.2, 5.4)
		_blink_on = 0.12
	_blink_on = maxf(0.0, _blink_on - delta)
	blinking = _blink_on > 0.0
	modulate.a = 0.45 if (invuln > 0.0 and int(invuln * 14.0) % 2 == 0) else 1.0


func _probe_below() -> Dictionary:
	var from := to_global(Vector2(0.0, 19.0))
	var q := PhysicsRayQueryParameters2D.create(
		from, from + Vector2(0.0, 110.0), 1 | 4, [get_rid()]
	)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"dist": 110.0, "body": null}
	return {"dist": float(hit.position.y) - from.y, "body": hit.collider}


func _check_stomp() -> void:
	if velocity.y < 110.0 or frozen or not bool(Game.settings.get("bump", true)):
		return
	for other: Node in get_tree().get_nodes_in_group("players"):
		if other == self or not (other is Player):
			continue
		var peer := other as Player
		if not peer.alive:
			continue
		var head := peer.head_point()
		if absf(global_position.x - head.x) > 26.0:
			continue
		if global_position.y > head.y + 16.0 or global_position.y < head.y - 46.0:
			continue
		velocity.y = -STOMP_BOUNCE
		_own_jump = false
		_squash = Vector2(0.72, 1.34)
		peer.been_pressed()
		Game.note("stomp")
		# A stomp is the loudest moment the game has; the camera has to admit it.
		get_tree().call_group("level", "kick", 3.5)
		Sfx.play("boing")
		return


func been_pressed() -> void:
	press_timer = 0.34
	_squash = Vector2(1.3, 0.66)
	Sfx.play("press")


func _do_jump(swing: bool) -> void:
	if swing:
		velocity.y = -JUMP_VELOCITY * 1.04
		velocity.x = clampf(velocity.x * 1.14, -SWING_MAX_X, SWING_MAX_X)
	else:
		velocity.y = -JUMP_VELOCITY
	_buffer = 0.0
	coyote_left = 0.0
	cling_lock = 0.3
	_own_jump = true
	_squash = Vector2(0.78, 1.26)
	Sfx.play("swing" if swing else "jump")


func launch(up_speed: float) -> void:
	velocity.y = -up_speed
	coyote_left = 0.0
	_buffer = 0.0
	_own_jump = false
	_squash = Vector2(0.74, 1.3)


func sync_boost(amount: float) -> void:
	velocity.y -= amount
	_own_jump = true
	_squash = Vector2(0.7, 1.36)


func _dead_step(delta: float) -> void:
	# The body still owes the pit a fall: freezing physics on death is what left
	# corpses hanging in mid-air for the whole respawn countdown.
	velocity.y = minf(MAX_FALL, velocity.y + GRAVITY * delta)
	move_and_slide()
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, delta * 4.0))
	_visual.rotation += delta * 2.6
	modulate.a = maxf(0.0, modulate.a - delta * 1.15)
	press_timer = maxf(0.0, press_timer - delta)


func die() -> void:
	if not alive or invuln > 0.0:
		return
	alive = false
	frozen = true
	rope_taut = false
	clinging = false
	velocity = Vector2(0.0, -280.0)
	_squash = Vector2(1.4, 0.6)
	_dust.restart()
	_dust.emitting = true
	Sfx.play("die")
	died.emit(self)


func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	alive = true
	frozen = false
	invuln = 0.9
	_squash = Vector2(0.6, 1.5)
	_jump_held = false
	_buffer = 0.0
	cling_lock = 0.0
	_visual.rotation = 0.0
	modulate.a = 1.0
	show()


func head_point() -> Vector2:
	return to_global(Vector2(0.0, HEAD_Y))


# Bindings live in the save file now, so this is the only place that has to know how
# to turn an action name into a physical key.
func key(action: String) -> int:
	return Game.key_of(player_index, action)


func _draw() -> void:
	var sh: float = clampf(1.0 - ground_dist / 105.0, 0.18, 1.0)
	Art.ellipse(self, Vector2(0.0, 19.5), 15.0 * sh, 4.6 * sh, Color(0.16, 0.10, 0.24, 0.22 * sh))
