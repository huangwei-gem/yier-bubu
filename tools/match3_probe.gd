extends Node

# Windowed QA harness for the puzzle mode: it mounts the real main scene, walks the
# menus the way a player would, makes scripted swaps through the board's own input
# path, and leaves screenshots behind to be looked at. Unlike the static validator
# this one exists to catch what only shows up on screen — a tile drawn off-centre, a
# HUD that runs off the panel, a cascade that finishes before the eye does.

const OUT := "user://qa/"
const MOVES_PER_LEVEL := 7

var saved := 0
var fails := 0
var only_input := false


func _ready() -> void:
	# "godot ... res://tools/match3_probe.tscn -- input-only" skips the slow walk through
	# all 15 boards, so a single interaction case can be re-run in seconds.
	for a: String in OS.get_cmdline_user_args():
		if a == "input-only":
			only_input = true
	DirAccess.make_dir_recursive_absolute(OUT)
	_stash_save()
	await get_tree().process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _settle(0.9)
	if only_input:
		Game.go_match3()
		await _settle(0.9)
		await _input_path_case()
		await _finish()
		return
	_shot("m3_00_title")
	_check_title()
	await _page_shots()

	Game.go_match3()
	await _settle(0.9)
	_shot("m3_01_home")
	if _find("M3Home") == null:
		_fail("消消乐首页没有挂上")

	Game.open_m3_pick()
	await _settle(0.8)
	_shot("m3_02_pick")
	if _find("M3Pick") == null:
		_fail("选局页没有挂上")

	for i: int in range(M3Levels.count()):
		Game.open_m3(i)
		await _settle(0.8)
		var play: Control = _find("M3Play") as Control
		if play == null:
			_fail("第 %d 局没有挂上棋盘" % [i + 1])
			continue
		var board: M3Board = play.board
		if board.cell < 40.0:
			fail_too_small(i, board.cell)
		var before: int = int(board.model.score)
		var made := 0
		for k: int in range(MOVES_PER_LEVEL):
			var pair := board.model.find_move()
			if pair.is_empty():
				break
			board.move(board.model.at(pair.a), board.model.at(pair.b))
			await _settle(0.12)
			if k == 2:
				_shot("m3_%02d_mid" % [i + 1])
			await _settle(0.45)
			made += 1
		await _settle(0.5)
		if int(board.model.score) <= before:
			_fail("第 %d 局走了 %d 步，分数没有动" % [i + 1, made])
		_shot("m3_%02d_play" % [i + 1])
		var colors := _board_colors(board)
		if colors < 12:
			_fail("第 %d 局 棋盘区域只采到 %d 种颜色，棋子根本没画出来" % [i + 1, colors])
		var m := board.model
		print("PROBE 第%2d局 步=%d 分=%d 剩=%d 连锁=%d 冰=%d 状态=%d" % [
			i + 1, made, int(m.score), m.moves_left, m.chain_best, m.ice_broken, m.state
		])
		if m.state == M3Model.ST_PLAY and m.legal_swaps().is_empty():
			_fail("第 %d 局 卡在无步可走但没有触发重排" % [i + 1])

	await _overlay_cases()
	await _input_path_case()
	await _finish()


func _input_path_case() -> void:
	# Everything above drives the board through its own API, which would still pass if
	# the mouse never reached a cell at all, so one step is pushed through real
	# synthesised press / drag / release events instead.
	Game.open_m3(1)
	await _settle(1.0)
	var play := _find("M3Play") as Control
	if play == null:
		_fail("输入用例拿不到棋盘")
		return
	var board: M3Board = play.board
	for attempt: int in range(3):
		var pair := board.model.find_move()
		if pair.is_empty():
			_fail("输入用例找不到可走的一步")
			return
		var before: int = board.model.moves_used
		var va: Vector2i = pair.a
		var vb: Vector2i = pair.b
		var a: Vector2 = board.origin + (Vector2(va) + Vector2(0.5, 0.5)) * board.cell
		var b: Vector2 = board.origin + (Vector2(vb) + Vector2(0.5, 0.5)) * board.cell
		_pointer(a, true)
		await _settle(0.05)
		_pointer(a.lerp(b, 0.75), false)
		await _settle(0.05)
		_pointer(b, false)
		_release(b)
		await _settle(1.6)
		print("PROBE 输入用例#%d (%d,%d)->(%d,%d) 已用步数 %d->%d" % [
			attempt + 1, va.x, va.y, vb.x, vb.y, before, board.model.moves_used
		])
		if board.model.moves_used > before:
			print("PROBE 输入路径 OK · 鼠标拖动走出一步")
			_shot("m3_92_after_drag")
			var colors := _board_colors(board)
			print("PROBE 拖动后棋盘颜色数=%d" % colors)
			if colors < 12:
				_fail("拖动后棋盘只采到 %d 种颜色，棋子没画出来" % colors)
			return
	_fail("三次鼠标拖动都没有走出一步")


func _release(at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = at
	mb.global_position = at
	Input.parse_input_event(mb)


func _pointer(at: Vector2, pressed_now: bool) -> void:
	if pressed_now:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		mb.position = at
		mb.global_position = at
		Input.parse_input_event(mb)
	else:
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)


func _finish() -> void:
	print("PROBE 截图=%d 失败=%d" % [saved, fails])
	if fails == 0:
		print("PROBE OK -> " + ProjectSettings.globalize_path(OUT))
	_restore_save()
	await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)


func _overlay_cases() -> void:
	# The result panels are only drawn on a real win or lose, which scripted play may
	# never reach, so both are forced here rather than left unseen in the shipped build.
	for pass_n: int in range(2):
		var want_win := pass_n == 0
		Game.m3_home()
		await _settle(0.5)
		Game.open_m3(0)
		var play: Control = null
		for try: int in range(24):
			await _settle(0.15)
			play = _find("M3Play") as Control
			if play != null:
				break
		if play == null:
			_fail("结算面板用例拿不到棋盘（%s）" % ("胜" if want_win else "负"))
			return
		play.board.model.score = 99999 if want_win else 120
		play.board.model.state = M3Model.ST_WIN if want_win else M3Model.ST_LOSE
		play._on_settled()
		await _settle(0.7)
		_shot("m3_9%s" % ["0_win" if want_win else "1_lose"])


func _page_shots() -> void:
	# The three new pages exist only behind a menu entry, and a page that throws on
	# mount would otherwise ship unseen.
	var pages := {
		Game.Screen.SETTINGS: "03_settings",
		Game.Screen.ACHIEVES: "04_achieves",
		Game.Screen.HOWTO: "05_howto",
	}
	for key: int in pages:
		Game.set_screen(key)
		await _settle(0.5)
		if not Game.page_open():
			_fail("页面 %d 没有挂上" % key)
		_shot("m3_" + String(pages[key]))
		Game.close_page()
		await _settle(0.4)
		if Game.screen_state != Game.Screen.TITLE:
			_fail("关掉页面后没有回到 %s，而是 %d" % ["TITLE", Game.screen_state])


func _check_title() -> void:
	var title := _find("Title")
	if title == null:
		_fail("标题页没有挂上")
		return
	# The menu list is the only place the front door is described, so a missing entry
	# here means a feature the player cannot reach at all.
	var n: int = (title as UI.Title)._menu.items.size()
	if n != 8:
		_fail("标题菜单只有 %d 项，应当是 8 项" % n)
	print("PROBE 标题菜单项=%d" % n)


func fail_too_small(i: int, c: float) -> void:
	_fail("第 %d 局 格子只有 %.1f px，棋盘放不下" % [i + 1, c])


func _find(node_name: String) -> Node:
	# The screens live under the UI CanvasLayer, at a depth the main scene can reshuffle
	# at any time, so the probe looks them up by name instead of by hard-coded path.
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name) == node_name:
			return n
		for c: Node in n.get_children():
			stack.append(c)
	return null


func _board_colors(board: M3Board) -> int:
	# A board that is present in the tree but painted behind the background looks
	# exactly like a working board to every other check here, so the pixels themselves
	# are counted: a grid of tiles always holds far more distinct colours than sky.
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return 0
	var seen := {}
	var x0: int = int(board.origin.x)
	var y0: int = int(board.origin.y)
	var x1: int = mini(x0 + int(board.cell * float(board.model.w)), img.get_width())
	var y1: int = mini(y0 + int(board.cell * float(board.model.h)), img.get_height())
	for yy: int in range(maxi(y0, 0), y1, 4):
		for xx: int in range(maxi(x0, 0), x1, 4):
			var c: Color = img.get_pixel(xx, yy)
			seen[Vector3(round(c.r * 6.0), round(c.g * 6.0), round(c.b * 6.0))] = true
	return seen.size()


func _shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.get_width() < 8:
		_fail("截图失败：%s" % tag)
		return
	var err := img.save_png(OUT + tag + ".png")
	if err != OK:
		_fail("写不出 %s.png (%d)" % [tag, err])
		return
	saved += 1


func _settle(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _fail(msg: String) -> void:
	fails += 1
	print("PROBE [FAIL] " + msg)

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
