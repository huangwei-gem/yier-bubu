extends Node

# Automated play-through. Runs the real main scene, feeds it synthesised key
# events (no window focus needed), and writes a screenshot per checkpoint into
#   %APPDATA%/Godot/app_userdata/一二布布/qa/
# Run:  godot --path . res://tools/play_probe.tscn

const FADE := 40
const SETTLE := 25

# One still per mechanic, keyed on the data field that introduces it.
const _ELEMENT_SHOTS := [
	{"key": "crumble", "data": "crumbles", "fn": "_crumble_shot"},
	{"key": "saw", "data": "saws", "fn": "_saw_shot"},
	{"key": "crate", "data": "crates", "fn": "_crate_shot"},
	{"key": "pulley", "data": "pulleys", "fn": "_pulley_shot"},
	{"key": "fan", "data": "fans", "fn": "_fan_shot"},
]

var _shots := 0
var _seen := {}


# Clearing chapter N must open exactly chapter N+1 — not two, and not none.
func _check_unlock_progression() -> void:
	Game.unlocked = 1
	Game.level_index = 0
	Game.run_results.clear()
	Game.complete_level()
	var ok := Game.unlocked == 2 and Game.level_index == 1
	print("PROBE unlock after ch1 = %d (expect 2) %s" % [Game.unlocked, "OK" if ok else "FAIL"])
	Game.unlocked = 1
	Game.level_index = 0
	Game.run_results.clear()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("qa"))
	_stash_save()
	_check_unlock_progression()
	get_tree().root.size = Vector2i(1280, 720)
	# Unlocked before Main exists: the title menu builds its rows in _ready().
	Game.unlocked = Game.level_count()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	await _frames(30)

	await _shot("01_title")

	# PROBE_ONLY=8 re-runs a single chapter's clear sequence, which turns a
	# eight-minute crawl into a ten-second one while a level is being fixed.
	var only := int(OS.get_environment("PROBE_ONLY"))
	if only > 0:
		Game.start_run(only - 1)
		await _await_level(only - 1)
		await _shot("only_%d_start" % only)
		await _element_shots(get_tree().get_first_node_in_group("level") as LevelBase)
		await _finish_current_level(only - 1)
		await _shot("only_%d_after" % only)
		print("PROBE SHOTS=%d" % _shots)
		_restore_save()
		get_tree().quit()
		return

	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_SPACE)
	await _frames(FADE + SETTLE)
	await _shot("02_level_select")
	for i: int in range(Game.level_count() - 1):
		await _tap(KEY_LEFT)

	await _tap(KEY_SPACE)
	await _await_level(0)
	await _shot("03_level1_start")

	await _hold(KEY_D, 60)
	await _tap(KEY_W)
	await _frames(20)
	await _shot("04_level1_walk")

	await _hold(KEY_A, 40)

	await _pause_shot()

	for i: int in range(Game.level_count()):
		await _await_level(i)
		var level := get_tree().get_first_node_in_group("level") as LevelBase
		if level == null:
			print("PROBE MISSING level %d" % (i + 1))
			continue
		if i == 0:
			await _both_jump()
			await _death_shot(level)
		await _element_shots(level)
		await _frames(30)
		await _shot("1%d_scene" % (i + 1))
		# One frame of the whole chapter, so the route reads as a plan rather than as
		# whatever happens to be behind the spawn point.
		level.preview = true
		await _frames(4)
		await _shot("2%d_over" % (i + 1))
		level.preview = false
		await _finish_current_level(i)

	await _await_screen(4, "victory")
	await _shot("20_victory")
	await _art_closeup()

	print("PROBE SHOTS=%d" % _shots)
	_restore_save()
	get_tree().quit()


# Each mechanic gets exactly one still, taken in whichever chapter first
# introduces it — keying on the data rather than a chapter number means a
# reshuffled order cannot silently retire a screenshot.
func _element_shots(level: LevelBase) -> void:
	for e: Dictionary in _ELEMENT_SHOTS:
		if _seen.has(e.key) or (level.data.get(e.data, []) as Array).is_empty():
			continue
		_seen[e.key] = true
		await call(String(e.fn), level)


# A crumbling step has to be seen in both of its states, or "it vanished" and "it
# was never there" look identical in a still.
func _crumble_shot(level: LevelBase) -> void:
	var rows: Array = level.data.get("crumbles", [])
	if rows.is_empty():
		return
	var e: Array = rows[0]
	_stand_pair(level, Vector2(float(e[0]) + float(e[2]) * 0.5, float(e[1]) - 19.0))
	await _frames(34)
	await _shot("06a_crumble_breaking")
	await _frames(90)
	await _shot("06b_crumble_gone")


func _saw_shot(level: LevelBase) -> void:
	var rows: Array = level.data.get("saws", [])
	if rows.is_empty():
		return
	var d: Dictionary = rows[0]
	# Just off the near end of the track, standing on the same floor the blade
	# rolls along: close enough to read the hazard, far enough to stay alive.
	var a: Vector2 = d.a
	var surface: float = a.y + float(d.get("size", 52.0)) * 0.5
	_stand_pair(level, Vector2(a.x - 78.0, surface - 19.0), 26.0)
	await _frames(20)
	await _shot("06c_saw")


func _crate_shot(level: LevelBase) -> void:
	var rows: Array = level.data.get("crates", [])
	if rows.is_empty():
		return
	var e: Array = rows[0]
	# Level on the crate's own height and let gravity find the floor, then walk
	# right into it — the same route a player would take.
	_stand_pair(level, Vector2(float(e[0]) - 74.0, float(e[1])), 22.0)
	await _frames(20)
	await _hold(KEY_D, 90)
	await _shot("06d_crate_pushed")


func _fan_shot(level: LevelBase) -> void:
	var rows: Array = level.data.get("fans", [])
	if rows.is_empty():
		return
	var d: Dictionary = rows[0]
	var at: Vector2 = d.at
	var box: Vector2 = d.get("box", Vector2(150.0, 300.0))
	_stand_pair(level, Vector2(at.x + box.x * 0.5, at.y + box.y - 40.0))
	await _press(KEY_W, true)
	await _press(KEY_UP, true)
	await _frames(45)
	await _shot("06e_fan_lift")
	await _press(KEY_W, false)
	await _press(KEY_UP, false)


# Put both bears upright, side by side, with their feet on the surface implied by
# `at`. Positions are set through respawn() so the pair start at rest and briefly
# immune, which keeps a staging teleport from reading as a death in the still.
func _stand_pair(level: LevelBase, at: Vector2, gap := 20.0) -> void:
	for i: int in range(level.players.size()):
		level.players[i].respawn(at + Vector2(float(i) * gap - gap * 0.5, 0.0))


# Every baked pose has to be seen at a size where a bad key line or a mismatched
# head would show, so this lays all six frames of both buddies out in one shot.
func _art_closeup() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("6b4f7a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var n := Art.FRAME_NAMES.size()
	for index: int in range(2):
		for f: int in range(n):
			var node := ArtProbe.new()
			node.index = index
			node.frame_id = f
			node.press_at = 0.2 if f == Art.F_IDLE and index == 1 else 0.0
			node.scale = Vector2(1.35, 1.35)
			node.position = Vector2(118.0 + float(f) * 190.0, 250.0 if index == 0 else 560.0)
			layer.add_child(node)
	print("PROBE frames left-to-right: ", ", ".join(Art.FRAME_NAMES))
	await _frames(6)
	await _shot("21_art_closeup")
	layer.queue_free()
	await _frames(2)


class ArtProbe extends Node2D:
	var index := 0
	var frame_id := 0
	var press_at := 0.0

	func _draw() -> void:
		Art.draw_buddy(self, index, Vector2.ZERO, 1.0, frame_id, press_at, 0.0)


func _await_screen(state: int, what: String) -> void:
	for i: int in range(600):
		if Game.screen_state == state:
			return
		await get_tree().physics_frame
	print("PROBE TIMEOUT waiting for %s" % what)


func _await_level(index: int) -> void:
	await _await_screen(2, "playing")
	for i: int in range(600):
		var level := get_tree().get_first_node_in_group("level") as LevelBase
		if level != null and Game.level_index == index and level.players.size() == 2 \
				and level.players[0].global_position.y > 0.0:
			return
		await get_tree().physics_frame
	print("PROBE TIMEOUT level %d never loaded" % (index + 1))


func _finish_current_level(index: int) -> void:
	var level := get_tree().get_first_node_in_group("level") as LevelBase
	if level == null:
		print("PROBE MISSING level %d" % index)
		return
	var frame: Vector2 = level.door.frame
	var stand := Vector2(level.data.goal.x + frame.x * 0.5, level.data.goal.y + frame.y)
	# First hold every switch the door asks for, then walk both bears into the
	# doorway. A chapter whose door opens some other way has nothing to hold, and
	# a latch stands in for whichever switch a player cannot reach.
	for i: int in range(level.plates.size()):
		var plate: LevelBase.Plate = level.plates[i]
		if i < level.players.size():
			# A plate is drawn straddling the slab it sits on, whose top face is 24 px
			# under the plate's own origin, so this puts each bear's feet on it.
			level.players[i].respawn(Vector2(plate.position.x + plate.board.x * 0.5, plate.position.y + 5.0))
		else:
			plate.latched = true
	await _frames(80)
	for i: int in range(level.players.size()):
		level.players[i].respawn(stand + Vector2(float(i) * 34.0 - 17.0, -24.0))
	await _frames(46)
	await _shot("3%d_score" % (index + 1))
	await _frames(140)
	# A freed scene means the chapter ended and the next one (or the victory page)
	# took over; only a live level still on this index is a real stall.
	if not is_instance_valid(level) or Game.level_index != index:
		return
	print("PROBE STUCK level %d unlocked=%s door_open=%s inside=%d/%d plates=%s" % [
		index + 1, level._unlocked, level.door.want_open, level.door.inside.size(),
		level.players.size(), _plate_state(level),
	])


func _plate_state(level: LevelBase) -> String:
	var out: Array[String] = []
	for p: LevelBase.Plate in level.plates:
		out.append("%d:%s/%s" % [int(p.position.x), "P%d" % p.occupants.size(), "W%d" % p.weights.size()])
	return " ".join(out)


func _pause_shot() -> void:
	await _tap(KEY_ESCAPE)
	await _frames(10)
	await _shot("05_pause")
	await _tap(KEY_ESCAPE)
	await _frames(10)


# Both jump keys down on the same physics frame — SYNC_WINDOW compares wall-clock
# timestamps, so anything less simultaneous is a normal double jump instead.
func _both_jump() -> void:
	await _press(KEY_W, true)
	await _press(KEY_UP, true)
	await _frames(3)
	await _shot("06_sync_jump")
	await _press(KEY_W, false)
	await _press(KEY_UP, false)
	await _frames(40)


func _death_shot(level: LevelBase) -> void:
	level.players[0].die()
	await _frames(14)
	await _shot("06_death")
	await _frames(80)


func _pulley_shot(level: LevelBase) -> void:
	var w: Vector2 = (level.pulleys[0] as Node2D).global_position
	# Straddle the wheel so the rope bends over it, then overshoot its length so
	# the solve is visibly working through the pulley instead of in a straight line.
	level.players[0].respawn(w + Vector2(-410.0, 570.0))
	level.players[1].respawn(w + Vector2(490.0, 140.0))
	await _frames(30)
	await _shot("07_pulley")


func _tap(key: int) -> void:
	await _press(key, true)
	await _frames(3)
	await _press(key, false)
	await _frames(3)


func _hold(key: int, frames: int) -> void:
	await _press(key, true)
	await _frames(frames)
	await _press(key, false)
	await _frames(4)


func _press(key: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = down
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "user://qa/%s.png" % name
	var err := img.save_png(path)
	if err != OK:
		print("PROBE SAVE FAILED %s (%d)" % [path, err])
		return
	_shots += 1
	var level := get_tree().get_first_node_in_group("level") as LevelBase
	var state := "screen=%d" % Game.screen_state
	if level != null:
		state += " players=%s/%s rope_taut=%s" % [
			level.players[0].global_position, level.players[1].global_position, level.tether.taut
		]
	print("PROBE %s %s" % [name, state])

const SAVE := "user://yier_bubu.cfg"
const SAVE_BAK := "user://yier_bubu.probe.bak"


func _stash_save() -> void:
	# The probes drive the real Game autoload, so without this they would leave
	# bot-made records in the player's own save file.
	if FileAccess.file_exists(SAVE):
		_recopy(SAVE, SAVE_BAK)


func _restore_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	if FileAccess.file_exists(SAVE_BAK):
		_recopy(SAVE_BAK, SAVE)
		DirAccess.remove_absolute(SAVE_BAK)


func _recopy(from: String, to: String) -> void:
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(FileAccess.get_file_as_bytes(from))
	f.close()
