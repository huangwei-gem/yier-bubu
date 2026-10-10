extends Node

var stage: Node2D
var ui: CanvasLayer
var fade: ColorRect
var current: LevelBase
var hud: Control
var overlay: Control
var modal: Control

var _fade_a := 1.0
var _fade_dir := 0
var _mid := Callable()


func _ready() -> void:
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)

	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)

	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0.06, 0.04, 0.12, 1.0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(fade)

	Game.level_started.connect(_on_level_started)
	Game.screen_changed.connect(_on_screen_changed)
	Game.m3_changed.connect(_on_m3_changed)
	Input.joy_connection_changed.connect(_on_pad_changed)
	_show_title()


func _on_m3_changed() -> void:
	if Game.mode == Game.Mode.MATCH3:
		_show_m3()


func _show_m3() -> void:
	_transition(
		func() -> void:
			_clear_branch()
			var screen: Control
			match Game.m3_screen:
				Game.M3Screen.HOME:
					screen = M3UI.Home.new()
					screen.name = "M3Home"
				Game.M3Screen.PICK:
					screen = M3UI.Pick.new()
					screen.name = "M3Pick"
				_:
					var play := M3UI.Play.new()
					play.index = Game.m3_index
					play.name = "M3Play"
					screen = play
			ui.add_child(screen)
	)


func _process(delta: float) -> void:
	if _fade_dir == 0:
		return
	_fade_a += float(_fade_dir) * delta / 0.26
	if _fade_a >= 1.0:
		_fade_a = 1.0
		_fade_dir = -1
		var callback := _mid
		_mid = Callable()
		if callback.is_valid():
			callback.call()
	elif _fade_a <= 0.0:
		_fade_a = 0.0
		_fade_dir = 0
	fade.color.a = _fade_a


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ev := event as InputEventKey
	if not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	if k == KEY_F11 or (k == KEY_ENTER and ev.alt_pressed):
		# Two people leaning over one keyboard want the whole screen, and the project
		# carries no input map, so the toggle has to live here.
		toggle_fullscreen()
		return
	if Game.page_open():
		# While a page is up its own _input owns the keys: ESC means "leave the page",
		# and R/P must not reach the level frozen underneath.
		if k == KEY_ESCAPE:
			Game.close_page()
		return
	match k:
		KEY_R:
			if Game.screen_state == Game.Screen.PLAYING:
				Game.restart_level()
		KEY_ESCAPE:
			match Game.screen_state:
				Game.Screen.PLAYING:
					Game.set_screen(Game.Screen.PAUSED)
				Game.Screen.PAUSED:
					Game.set_screen(Game.Screen.PLAYING)
				Game.Screen.LEVELS:
					Game.go_to_title()
		KEY_P:
			if Game.screen_state == Game.Screen.PLAYING or Game.screen_state == Game.Screen.PAUSED:
				Game.set_paused(Game.screen_state == Game.Screen.PLAYING)
		KEY_M:
			Sfx.toggle_mute()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Counters only hit the disk when an achievement lands, so the window's own
		# close is the last chance to write the run's progress.
		Game.save_now()


func _transition(to: Callable) -> void:
	if _fade_a >= 1.0:
		to.call()
		_fade_dir = -1
		return
	_mid = to
	_fade_dir = 1


func _on_pad_changed(_device: int, _connected: bool) -> void:
	Pads.refresh()


func toggle_fullscreen() -> void:
	var root := get_tree().root
	root.mode = Window.MODE_FULLSCREEN if root.mode != Window.MODE_FULLSCREEN else Window.MODE_WINDOWED


func _clear_branch() -> void:
	for child: Node in stage.get_children():
		stage.remove_child(child)
		child.queue_free()
	for child: Node in ui.get_children():
		if child == fade:
			continue
		ui.remove_child(child)
		child.queue_free()
	current = null
	hud = null
	overlay = null
	modal = null


func _hide_modal() -> void:
	if modal == null:
		return
	ui.remove_child(modal)
	modal.queue_free()
	modal = null


func _show_title() -> void:
	Game.set_screen(Game.Screen.TITLE)
	_transition(
		func() -> void:
			_clear_branch()
			overlay = UI.Title.new()
			overlay.name = "Title"
			ui.add_child(overlay)
	)


func _show_levels() -> void:
	_transition(
		func() -> void:
			_clear_branch()
			overlay = UI.LevelSelect.new()
			overlay.name = "LevelSelect"
			ui.add_child(overlay)
	)


func _show_victory() -> void:
	_transition(
		func() -> void:
			_clear_branch()
			overlay = UI.Victory.new()
			overlay.name = "Victory"
			ui.add_child(overlay)
	)


func _show_pause() -> void:
	modal = UI.Pause.new()
	modal.name = "Pause"
	modal.level = current
	ui.add_child(modal)


func _show_page(to: int) -> void:
	var page: Control
	match to:
		Game.Screen.SETTINGS:
			page = Pages.Settings.new()
			page.name = "Settings"
		Game.Screen.ACHIEVES:
			page = Pages.Achievements.new()
			page.name = "Achieves"
		Game.Screen.HOWTO:
			page = Pages.HowTo.new()
			page.name = "HowTo"
		_:
			return
	modal = page
	ui.add_child(page)


func _on_screen_changed(to: int) -> void:
	match to:
		Game.Screen.VICTORY:
			_show_victory()
		Game.Screen.TITLE:
			_show_title()
		Game.Screen.LEVELS:
			_show_levels()
		Game.Screen.PAUSED:
			_show_pause()
		Game.Screen.MATCH3:
			_show_m3()
		Game.Screen.SETTINGS, Game.Screen.ACHIEVES, Game.Screen.HOWTO:
			# A page is mounted over the level rather than instead of it: the stage and
			# the HUD stay exactly where they were and simply stop being stepped.
			_hide_modal()
			_show_page(to)
		Game.Screen.PLAYING:
			_hide_modal()


func _on_level_started(index: int) -> void:
	var path: String = Game.LEVELS[clampi(index, 0, Game.LEVELS.size() - 1)]
	_transition(
		func() -> void:
			_clear_branch()
			Game.set_screen(Game.Screen.PLAYING)
			current = (load(path) as PackedScene).instantiate()
			stage.add_child(current)
			var layer := UI.Hud.new()
			layer.name = "Hud"
			layer.level = current
			hud = layer
			ui.add_child(layer)
	)
