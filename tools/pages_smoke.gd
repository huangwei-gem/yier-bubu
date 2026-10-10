extends Node

# 三块页面的无头自检。跑法：
#   godot --headless --path . res://tools/pages_smoke.tscn
# 页面是真挂进真树里跑的：合成按键和鼠标事件走 Input.parse_input_event，所以测的是
# _input 这条真的路，而不是绕开它调内部函数。存档先抄一份、跑完还回去——这一趟会
# 真的写 Game.set_setting，也会真的绑键、真的解锁成就。

const SAVE := "user://yier_bubu.cfg"
const BACKUP := "user://yier_bubu.smoke.bak"

var _fails := 0
var _checks := 0
var _layer: CanvasLayer
# 每一趟跑完都留个名。页面类编译不过时 new() 会直接报错、整趟半途而废，光看
# _fails 会把“什么都没测”读成“全绿”。
var _done: Array[String] = []


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_backup()
	_layer = CanvasLayer.new()
	_layer.name = "SmokeUI"
	add_child(_layer)

	await _settings()
	await _achieves()
	await _howto()
	await _audio()
	_check(_done.size() == 4, "有一趟自检没跑完：%s" % ", ".join(_done))

	_restore()
	if _fails == 0:
		print("[pages] OK · %d 项检查" % _checks)
	else:
		print("[pages] FAIL %d" % _fails)
	# Quitting straight out of _ready() can fault during teardown and turn a green
	# report into a segfault exit code, which reads as a failure.
	await get_tree().process_frame
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		return
	_fails += 1
	print("[pages] FAIL " + what)


func _ok(r: Rect2) -> bool:
	return is_finite(r.position.x) and is_finite(r.position.y) \
		and is_finite(r.size.x) and is_finite(r.size.y)


func _frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().process_frame


func _press(key: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = down
	Input.parse_input_event(e)


func _tap(key: int) -> void:
	_press(key, true)
	await _frames(2)
	_press(key, false)
	await _frames(1)


func _mouse(at: Vector2, btn: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.position = at
	e.global_position = at
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(1)


func _hover(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await _frames(2)


# 每一行都往返调一遍：范围行改一格再改回来，开关行翻两次。任何一行了无痕迹都是页面
# 自己坏了，而设置页是唯一一处“点了没反应”会被当成游戏坏了的地方。
func _settings() -> void:
	Game.set_screen(Game.Screen.SETTINGS)
	var page: Pages.Settings = Pages.Settings.new()
	_layer.add_child(page)
	await _frames(20)
	_check(Game.page_open(), "Settings 挂上时算开着页面")
	# 布局硬检查：行矩形必须有限，而且 1280×720 下整列要一屏装得下（滚动只是兜底）。
	_check(page._hot_row.size() == Game.SETTINGS.size(), "左栏的行数和 Game.SETTINGS 不一致")
	for r: Rect2 in page._hot_row:
		_check(_ok(r), "有一行设置项的矩形不是数")
	_check(page._hot_row[Game.SETTINGS.size() - 1].end.y < 720.0 - 40.0, "最后一行掉出屏幕")

	for i: int in range(26):
		await _tap(KEY_DOWN)
	await _tap(KEY_TAB)
	await _tap(KEY_UP)
	await _tap(KEY_LEFT)
	await _tap(KEY_RIGHT)
	await _tap(KEY_SPACE)
	_check(Game.page_open(), "在某一行的空格把整页关掉了")

	for i: int in range(Game.SETTINGS.size()):
		var spec: Dictionary = Game.SETTINGS[i]
		var key := String(spec.key)
		var was: Variant = Game.settings.get(key)
		page._row = i
		page._group = 0
		await _frames(1)
		# ←→ 和 −/＋ 共用 _adjust，空格和点整行共用 _act：四条路都得把这一行真的调一遍。
		page._adjust(1)
		page._adjust(-1)
		_check(absf(float(Game.settings.get(key)) - float(was)) < 0.001, "第 %s 行往返之后变了" % key)
		page._act(0, i)
		if String(spec.kind) != "range":
			_check(bool(Game.settings.get(key)) != bool(was), "开关 %s 没被翻动" % key)
			page._act(0, i)
		else:
			_check(
				absf(float(Game.settings.get(key)) - (float(was) + float(spec.step))) < 0.001,
				"滑块 %s 没走一格" % key
			)
			page._adjust(-1)
		# 音量必须真的落在播放器上，否则这一行只是个装饰。
		if key == "volume":
			_check(
				Sfx._player.volume_db > -79.0 or bool(Game.settings.get("muted", false)),
				"音量没写进播放器"
			)

	await _frames(2)
	var row := page._hot_row[0]
	await _mouse(row.get_center() - Vector2(120.0, 0.0), MOUSE_BUTTON_LEFT)
	var dec: Rect2 = page._hot_dec[0]
	if dec.size.x > 0.0:
		await _mouse(dec.get_center(), MOUSE_BUTTON_LEFT)
		await _mouse(page._hot_inc[0].get_center(), MOUSE_BUTTON_LEFT)
	await _hover(Rect2(row.position + Vector2(20.0, 10.0), Vector2(1.0, 1.0)).get_center())
	_check(page._group == 0, "鼠标划过左栏把焦点放回了设置项")

	# 重映射：进入监听、绑一个新键、撞车时把队友挪走、ESC 取消。
	page._act(1, 0)
	_check(page._cap_p == 0, "点键位行之后进了监听")
	await _tap(KEY_J)
	await _frames(2)
	_check(Game.key_of(0, "left") == KEY_J, "J 没绑给一二的左")
	_check(page._cap_p == -1, "绑完之后没退出监听")

	var p1_jump := Game.key_of(1, "jump")
	var p0_jump := Game.key_of(0, "jump")
	page._act(2, 2)
	await _tap(KEY_W)
	await _frames(2)
	_check(Game.key_of(1, "jump") == p0_jump, "布布的跳没接到新键")
	_check(Game.key_of(0, "jump") == p1_jump, "撞车时一二的跳没挪到老键位")

	page._act(1, 1)
	var before := Game.key_of(0, "right")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(page._cap_p == -1 and Game.key_of(0, "right") == before, "ESC 没能取消监听")

	# 两项销毁操作：第一次按下只是武装，绝不让它在这一趟里跑到第二下。
	page._act(3, 1)
	_check(page._arm == 1, "清空存档没先武装")
	_check(Game.unlocked > 0, "武装时就已经动手了")
	_check(String(page._foot.items[1].label).contains("再按一次"), "武装之后标签没改")
	page._arm = -1
	page._sync()
	page._act(3, 0)
	page._act(3, 0)
	await _frames(2)
	for p: int in range(2):
		for a: String in Game.KEY_ACTIONS:
			_check(Game.key_of(p, a) == int(Game.DEFAULT_KEYS[p][a]), "恢复默认键位没管 %d.%s" % [p, a])

	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(not Game.page_open(), "ESC 没能关设置页")
	_page_done(page)
	_done.append("settings")


func _achieves() -> void:
	Game.set_screen(Game.Screen.ACHIEVES)
	var page: Pages.Achievements = Pages.Achievements.new()
	_layer.add_child(page)
	await _frames(20)
	# 两列八行是这页的设计前提：装不下才滚，装得下还滚就是格子算高了。
	_check(page._cells.size() == Game.ACHIEVEMENTS.size(), "成就格子数和 ACHIEVEMENTS 对不上")
	_check(page._max_scroll <= 0.5, "1280×720 下成就墙还要滚，格子太高了")
	for c: Rect2 in page._cells:
		_check(_ok(c) and c.end.y <= page._panel.end.y + 0.5, "有成就格子画到了面板外")
	var before := Game.ach_count()
	for key: int in [KEY_DOWN, KEY_RIGHT, KEY_UP, KEY_LEFT, KEY_PAGEDOWN, KEY_PAGEUP]:
		await _tap(key)
	await _wheel(3)
	await _wheel(-3)
	_check(page._sel >= 0 and page._sel < Game.ACHIEVEMENTS.size(), "成就光标跑出了列表")

	# 真解锁一次：toast、光标挪过去、格子变亮，这条路径只能靠真的事件测。
	Game.note("sync", 60)
	await _frames(6)
	_check(Game.ach_count() > before, "note() 之后没有成就解锁")
	_check(String(page._fresh) == "rope_learned", "成就页没收到刚解锁的那条")
	_check(page._scroll <= page._max_scroll + 0.01 and page._scroll >= 0.0, "滚动越界了")

	await _hover(Vector2(640.0, 400.0))
	await _tap(KEY_ENTER)
	await _frames(2)
	_check(not Game.page_open(), "成就页回车没能关")
	_page_done(page)
	_done.append("achieves")


func _howto() -> void:
	Game.set_screen(Game.Screen.HOWTO)
	var page: Pages.HowTo = Pages.HowTo.new()
	_layer.add_child(page)
	await _frames(20)
	_check(page._poses.size() == page.SECTIONS.size() * 2, "教学页的熊不够每格两张")
	_check(page._max_scroll <= 0.5, "1280×720 下教学页还要滚，卡片太高了")
	for c: Rect2 in page._cells:
		_check(_ok(c) and c.end.y <= page._panel.end.y + 0.5, "有教学卡片画到了面板外")
		_check(c.size.x > 380.0, "教学卡片窄到放不下正文")
	for i: int in range(page.SECTIONS.size()):
		page._sel = i
		await _frames(2)
	await _wheel(2)
	await _wheel(-2)
	await _tap(KEY_DOWN)
	await _tap(KEY_RIGHT)
	await _hover(page._cells[0].get_center())
	await _mouse(page._cells[1].get_center(), MOUSE_BUTTON_LEFT)
	_check(page._sel == 1, "点一张卡片没把它选上")
	_check(Game.level_name(0).length() > 0, "教学页没能从关卡里取标题")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(not Game.page_open(), "教学页 ESC 没能关")
	_page_done(page)
	_done.append("howto")


func _audio() -> void:
	Sfx.play("jump")
	Sfx.play("select")
	_check(not Sfx._voices.is_empty(), "音效没排进混音")

	Game.level_index = 0
	Game.set_screen(Game.Screen.PLAYING)
	await _frames(30)
	_check(Sfx.music_track() == Game.level_biome(0), "关卡里没自动切到本关地貌")
	_check(Sfx.is_music_playing(), "关卡里配乐没在放")
	_check(Sfx._mus_time > 0.0, "排程器一秒都没走")
	var walked := Sfx._mus_time
	Sfx.set_music(Sfx.music_track())
	_check(is_equal_approx(walked, Sfx._mus_time), "同一首曲子被重头开始了")

	Game.set_screen(Game.Screen.SETTINGS)
	await _frames(6)
	_check(not Sfx.is_music_playing(), "设置页开着时还在放配乐")
	_check(Sfx._mvoices.is_empty(), "关门时没把尾音抹掉")
	Game.close_page()
	await _frames(6)
	_check(Sfx.is_music_playing(), "页面关掉后配乐没接回来")

	Game.set_setting("music", false)
	await _frames(6)
	_check(not Sfx.is_music_playing(), "关掉背景音乐还在放")
	Game.set_setting("music", true)
	await _frames(6)
	_check(Sfx.is_music_playing(), "重新打开背景音乐没接回来")

	Game.set_setting("volume", 0.4)
	_check(is_equal_approx(Sfx._player.volume_db, linear_to_db(0.4)), "音量没写进播放器")
	Game.set_setting("volume", 0.0)
	_check(is_equal_approx(Sfx._player.volume_db, -80.0), "零音量没断掉")
	Game.set_setting("volume", 0.8)

	Sfx.toggle_mute()
	await _frames(4)
	_check(bool(Game.settings.get("muted", false)), "M 键没写进存档")
	_check(not Sfx.is_music_playing(), "静音时还在放配乐")
	_check(is_equal_approx(Sfx._player.volume_db, -80.0), "静音时播放器没断")
	Sfx.toggle_mute()
	await _frames(4)
	_check(not bool(Game.settings.get("muted", true)), "再按一次 M 没能解静音")

	for track: String in ["title", "canyon", "forest", "cave", "snow", "dusk", "m3"]:
		Sfx.set_music(track)
		await _frames(4)
		_check(Sfx.music_track() == track, "%s 这首曲子没切过去" % track)
	Sfx.set_music("根本没有这首")
	_check(Sfx.music_track() == "title", "不认识的曲子没退回主题")
	Sfx.stop_music()
	_check(Sfx.music_track().is_empty(), "stop_music 之后曲子还在")
	_check(not Sfx.is_music_playing(), "stop_music 之后仍在放")

	# 采样器在无头模式下没有消费者，音符只进不出：这条上限必须自己刹住。
	await _frames(40)
	_check(Sfx._mvoices.size() <= 24, "音乐音符堆成了无界队列")

	# 换曲子这件事只在画面真的切换时才发生，所以先退回标题，再从那里进关卡、回标题、
	# 进消消乐：三次切换 covering 自动排曲的三条分支。
	Game.set_screen(Game.Screen.TITLE)
	await _frames(3)
	Game.set_screen(Game.Screen.PLAYING)
	await _frames(4)
	_check(Sfx.music_track() == Game.level_biome(Game.level_index), "回到关卡没换回地貌曲子")
	Game.go_to_title()
	await _frames(6)
	_check(Sfx.music_track() == "title", "回到标题没换回主题曲子")
	Game.go_match3()
	await _frames(6)
	_check(Sfx.music_track() == "m3", "消消乐没切到它自己的曲子")
	Game.go_platform()
	await _frames(6)
	_check(Sfx.music_track() == "title", "离开消消乐没换回主题曲子")
	_done.append("audio")


func _wheel(steps: int) -> void:
	for i: int in range(absi(steps)):
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if steps > 0 else MOUSE_BUTTON_WHEEL_UP
		e.position = Vector2(640.0, 400.0)
		e.global_position = e.position
		e.pressed = true
		Input.parse_input_event(e)
		await _frames(2)


func _page_done(page: Control) -> void:
	_layer.remove_child(page)
	page.free()


func _backup() -> void:
	if FileAccess.file_exists(SAVE):
		_copy(SAVE, BACKUP)


func _restore() -> void:
	# 自检不该留下任何进度上的痕迹：存档原样还回去。
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	if FileAccess.file_exists(BACKUP):
		_copy(BACKUP, SAVE)
		DirAccess.remove_absolute(BACKUP)


func _copy(from: String, to: String) -> void:
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f == null:
		_check(false, "抄存档失败：%s" % to)
		return
	f.store_buffer(FileAccess.get_file_as_bytes(from))
	f.close()
