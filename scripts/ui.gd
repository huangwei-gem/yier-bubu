class_name UI
extends RefCounted

static var _font: Font


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"PingFang SC", "Hiragino Sans GB", "Heiti SC", "Arial Unicode MS",
			"Microsoft YaHei", "Noto Sans CJK SC",
		])
		_font = f
	return _font


static func label(
	ci: CanvasItem, text: String, center_x: float, y: float, size: int, col: Color
) -> void:
	var f := font()
	var s: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size)
	ci.draw_string(f, Vector2(center_x - s.x * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


static func text_width(text: String, size: int) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size).x


static func label_right(
	ci: CanvasItem, text: String, right_x: float, y: float, size: int, col: Color
) -> void:
	label(ci, text, right_x - text_width(text, size) * 0.5, y, size, col)


static func label_left(
	ci: CanvasItem, text: String, left_x: float, y: float, size: int, col: Color
) -> void:
	label(ci, text, left_x + text_width(text, size) * 0.5, y, size, col)


# Hints are written by hand per level and some of them are longer than 1280 px
# at 22 pt, so they get broken on character boundaries rather than clipped.
static func wrap(text: String, size: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for i: int in range(text.length()):
		var trial := cur + text[i]
		if not cur.is_empty() and text_width(trial, size) > max_w:
			out.append(cur)
			cur = text[i]
		else:
			cur = trial
	if not cur.is_empty():
		out.append(cur)
	return out


static var _sky_cache: Dictionary = {}


static func sky(ci: CanvasItem, area: Rect2, top: Color, bottom: Color) -> void:
	var key := top.to_html() + bottom.to_html()
	var tex: GradientTexture2D = _sky_cache.get(key)
	if tex == null:
		var grad := Gradient.new()
		grad.set_color(0, top)
		grad.set_color(1, bottom)
		tex = GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 2
		tex.height = 256
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0.0, 0.0)
		tex.fill_to = Vector2(0.0, 1.0)
		_sky_cache[key] = tex
	ci.draw_texture_rect(tex, area, false)


static func tint(t: float) -> Color:
	return Art.ACCENT_COLORS[0].lerp(Art.ACCENT_COLORS[1], 0.5 + 0.5 * sin(t * 2.6))


static func star(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in range(10):
		var ang: float = -PI * 0.5 + float(i) * PI * 0.1
		var k: float = r if i % 2 == 0 else r * 0.46
		pts.append(at + Vector2(cos(ang), sin(ang)) * k)
	ci.draw_polygon(pts, PackedColorArray([col]))


# Three pips in the order they are earned: clear the door, take every coin, beat
# par. An unearned pip is still drawn, because a gap reads as a missing icon.
static func pips(ci: CanvasItem, at: Vector2, earned: int, r: float, gap: float) -> void:
	for i: int in range(3):
		var x: float = at.x + (float(i) - 1.0) * gap
		if i >= earned:
			star(ci, Vector2(x, at.y), r, Color(1, 1, 1, 0.13))
			continue
		star(ci, Vector2(x, at.y), r + 1.2, Color(0.35, 0.22, 0.06, 0.55))
		star(ci, Vector2(x, at.y), r, Color("ffd166"))
		# A specular dot rather than a second star: a half-size star turns the pip
		# into a crescent once it is drawn at 8 px on a card.
		ci.draw_circle(Vector2(x - r * 0.2, at.y - r * 0.28), r * 0.26, Color("fff6d0"))


# Shared keyboard + mouse list navigation so 标题/暂停 cannot drift apart on
# which keys they accept.
class MenuNav extends RefCounted:
	var items: Array[Dictionary] = []
	var index := 0
	var cx := 0.0
	var top := 0.0
	var row := 46.0
	var size := 26

	var _hot: Array[Rect2] = []
	var _confirmed := -1

	func add(text: String, enabled := true) -> void:
		items.append({"label": text, "enabled": enabled})
		focus_first()

	func focus_first() -> void:
		for i: int in range(items.size()):
			if bool(items[i].enabled):
				index = i
				return
		index = 0

	func confirm() -> int:
		if items.is_empty() or not bool(items[index].enabled):
			return -1
		return index

	func _step(d: int) -> void:
		var n := items.size()
		if n == 0:
			return
		var i := index
		for k: int in range(n):
			i = posmod(i + d, n)
			if bool(items[i].enabled):
				if i != index:
					index = i
					Sfx.play("select")
				return

	# Returns the confirmed row, or -1 when the event was only navigation.
	func feed(ci: Control, event: InputEvent) -> int:
		if event is InputEventKey and event.pressed and not event.echo:
			var ev := event as InputEventKey
			var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			match k:
				KEY_UP, KEY_W, KEY_LEFT, KEY_A:
					_step(-1)
				KEY_DOWN, KEY_S, KEY_RIGHT, KEY_D:
					_step(1)
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					var picked := confirm()
					if picked >= 0:
						Sfx.play("start")
					return picked
		elif event is InputEventMouseMotion:
			_point(ci, false)
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			return _point(ci, true)
		return -1

	func _point(ci: Control, click: bool) -> int:
		var m: Vector2 = ci.get_global_mouse_position()
		for i: int in range(_hot.size()):
			if not _hot[i].has_point(m) or not bool(items[i].enabled):
				continue
			if i != index:
				index = i
				Sfx.play("select")
			if click:
				Sfx.play("start")
				return i
			return -1
		return -1

	func draw(ci: CanvasItem, t: float) -> void:
		_hot.clear()
		_hot.resize(items.size())
		for i: int in range(items.size()):
			var at := Vector2(cx, top + row * float(i))
			var enabled: bool = bool(items[i].enabled)
			var text: String = String(items[i].label)
			var w: float = UI.text_width(text, size)
			var r := Rect2(at.x - w * 0.5 - 28.0, at.y - 8.0, w + 56.0, float(size) + 24.0)
			_hot[i] = r if enabled else Rect2(0.0, 0.0, -1.0, -1.0)
			var on: bool = i == index and enabled
			if on:
				Art.round_rect(ci, r, 13.0, Color(0.16, 0.10, 0.26, 0.6))
				Art.round_rect_outline(ci, r.grow(1.5), 14.0, UI.tint(t), 2.2)
			UI.label(
				ci, text, at.x, at.y + float(size) + 4.0, size,
				Color("fff6ea") if enabled else Color(1, 1, 1, 0.22)
			)
			if on:
				UI.label(ci, "▸", r.position.x - 14.0, at.y + float(size) + 4.0, size, UI.tint(t))


# A buddy drawn by its own Node2D so menu screens can scale it up — Art's
# helpers set an absolute canvas transform, so an outer scale cannot be
# wrapped around a direct draw_buddy() call.
class Buddy extends Node2D:
	var index := 0
	var flip := 1.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		Art.draw_buddy(self, index, Vector2.ZERO, flip, Art.F_IDLE, 0.0, _t)


class Title extends Control:
	var _menu := MenuNav.new()
	var _b0: Buddy
	var _b1: Buddy
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.size = 23
		_menu.row = 42.0
		_menu.add("开 始 冒 险")
		_menu.add("继 续 闯 关", Game.unlocked > 1)
		_menu.add("选 择 关 卡", Game.unlocked > 1)
		_menu.add("消 消 乐")
		_menu.add("设 置")
		_menu.add("成 就")
		_menu.add("玩 法 教 学")
		_menu.add("退 出 游 戏")
		_b0 = _buddy(0, 1.0)
		_b1 = _buddy(1, -1.0)

	func _buddy(index: int, flip: float) -> Buddy:
		var b := Buddy.new()
		b.index = index
		b.flip = flip
		b.scale = Vector2(1.45, 1.45)
		add_child(b)
		return b

	func _input(event: InputEvent) -> void:
		var picked: int = _menu.feed(self, event)
		if picked < 0:
			return
		match picked:
			0:
				Game.start_run(0)
			1:
				Game.start_run(Game.unlocked - 1)
			2:
				Game.go_to_levels()
			3:
				Game.go_match3()
			4:
				Game.set_screen(Game.Screen.SETTINGS)
			5:
				Game.set_screen(Game.Screen.ACHIEVES)
			6:
				Game.set_screen(Game.Screen.HOWTO)
			7:
				get_tree().quit()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, get_viewport_rect().size)
		UI.sky(self, area, Color("2a2050"), Color("ff9ec4"))
		for i: int in range(7):
			var r: float = 90.0 + float(i) * 60.0
			draw_arc(
				Vector2(area.size.x * 0.5, area.size.y * 1.05),
				r + sin(_t + float(i)) * 6.0,
				PI, TAU, 40, Color(1, 1, 1, 0.05), 26.0
			)
		_ridges(area)

		var cx: float = area.size.x * 0.5
		var top: float = area.size.y * 0.09
		UI.label(self, "一二布布", cx, top + 52.0, 64, Color("fff6ea"))
		UI.label(self, "一 根 绳 拴 在 一 起 的 双 人 闯 关", cx, top + 86.0, 19, Color("ffd9e6"))

		var by: float = area.size.y * 0.27
		var beat: float = absf(sin(_t * 2.2)) * 13.0
		var other: float = absf(sin(_t * 2.2 + 0.9)) * 13.0
		var pa := Vector2(cx - 96.0, by - beat)
		var pb := Vector2(cx + 96.0, by - other)
		_b0.position = pa
		_b1.position = pb
		_draw_rope(pa, pb)

		_menu.cx = cx
		_menu.top = area.size.y * 0.375
		_menu.draw(self, _t)
		if Game.unlocked > 1:
			UI.label(
				self, "已到第 %d 关" % Game.unlocked, cx + UI.text_width("继 续 闯 关", 23) * 0.5 + 78.0,
				_menu.top + _menu.row + 20.0, 15, Color(1, 1, 1, 0.45)
			)
		UI.label(
			self, "同一套画片 · 另一种玩法", cx + UI.text_width("消 消 乐", 23) * 0.5 + 116.0,
			_menu.top + _menu.row * 3.0 + 20.0, 15, Color(1, 1, 1, 0.4)
		)

		UI.label(
			self, "↑ ↓ 选择 · 空格 确认 · 也可以直接用鼠标点 · F11 全屏", cx, area.size.y - 70.0,
			18, Color(1, 1, 1, 0.45)
		)
		UI.label(
			self, "两人一台电脑：一二 WASD · 布布 方向键 · 同时按跳 = 同心跳 · 从队友头顶落下按跳 = 踩头",
			cx, area.size.y - 42.0, 18, Color(1, 1, 1, 0.62)
		)
		if Game.best_time > 0.0:
			UI.label(
				self, "最快通关 " + Game.format_time(Game.best_time),
				area.size.x - 120.0, 40.0, 18, Color(1, 1, 1, 0.6)
			)

	func _draw_rope(pa: Vector2, pb: Vector2) -> void:
		var a0: Vector2 = pa + Vector2(24.0, -8.0)
		var b0: Vector2 = pb + Vector2(-24.0, -8.0)
		var sag: float = 34.0 + 10.0 * sin(_t * 1.6)
		var pts := PackedVector2Array()
		var steps: int = 26
		for i: int in range(steps + 1):
			var t: float = float(i) / float(steps)
			pts.append(a0.lerp(b0, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t)))
		for i: int in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], Color(0.20, 0.14, 0.28, 0.9), 6.0, true)
		for i: int in range(pts.size() - 1):
			var t: float = float(i) / float(steps - 1)
			var c := Art.ACCENT_COLORS[0].lerp(Art.ACCENT_COLORS[1], t)
			draw_line(pts[i], pts[i + 1], c, 3.2, true)
		draw_circle(pts[0], 4.0, Color("ffd166"))
		draw_circle(pts[pts.size() - 1], 4.0, Color("ffd166"))

	# The three baked depth bands, sunk into the bottom of the frame, so the title
	# page is the same world the pair walk through rather than a gradient.
	func _ridges(area: Rect2) -> void:
		var biome: Dictionary = Biomes.get_def("dusk")
		var drift: float = sin(_t * 0.18) * 12.0
		var step := 0
		for pair: Array in [["bg_far", "far", 0.34], ["bg_mid", "mid", 0.30], ["bg_near", "near", 0.26]]:
			var tex := Art.env(String(pair[0]))
			if tex == null:
				continue
			var hh: float = area.size.y * float(pair[2])
			var col: Color = Color(biome.get(pair[1], Color.WHITE))
			col.a = 0.55 + float(step) * 0.18
			draw_texture_rect(
				tex,
				Rect2(
					drift * float(step + 1) * 0.4,
					area.size.y - hh + float(step) * 16.0,
					area.size.x + 40.0, hh
				),
				false, col
			)
			step += 1


class LevelSelect extends Control:
	var _cards: Array[Rect2] = []
	var _sel := 0
	var _cols := 1
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sel = clampi(Game.unlocked - 1, 0, Game.level_count() - 1)

	# Three rows of four, one row per act: the acts are the pacing unit the chapters
	# were written in, and a flat grid of twelve hides that.
	func _layout(vp: Vector2) -> void:
		_cards.clear()
		_cols = 4
		var gx := 18.0
		var gy := 54.0
		var cw: float = (vp.x - 80.0 - gx * float(_cols - 1)) / float(_cols)
		var ch := 134.0
		var y0: float = vp.y * 0.18
		for i: int in range(Game.level_count()):
			_cards.append(
				Rect2(
					40.0 + float(i % _cols) * (cw + gx),
					y0 + float(int(i / float(_cols))) * (ch + gy),
					cw, ch
				)
			)

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			var ev := event as InputEventKey
			var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			match k:
				KEY_LEFT, KEY_A:
					_move(-1)
				KEY_RIGHT, KEY_D:
					_move(1)
				KEY_UP, KEY_W:
					_move(-_cols)
				KEY_DOWN, KEY_S:
					_move(_cols)
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_pick(_sel)
		elif event is InputEventMouseMotion:
			_hover(event as InputEventMouse, false)
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			if _hover(event as InputEventMouse, true):
				_pick(_sel)

	func _move(d: int) -> void:
		var n := _cards.size()
		if n == 0:
			return
		var next := clampi(_sel + d, 0, n - 1)
		if next != _sel:
			_sel = next
			Sfx.play("select")

	func _hover(ev: InputEventMouse, click: bool) -> bool:
		var m: Vector2 = get_global_mouse_position()
		for i: int in range(_cards.size()):
			if not _cards[i].has_point(m) or not Game.is_unlocked(i):
				continue
			if i != _sel:
				_sel = i
				Sfx.play("select")
			return click
		return false

	func _pick(i: int) -> void:
		if not Game.is_unlocked(i):
			Sfx.play("taut")
			return
		Sfx.play("start")
		Game.start_run(i)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		UI.sky(self, Rect2(Vector2.ZERO, vp), Color("241a46"), Color("e9a7c4"))
		var cx: float = vp.x * 0.5
		UI.label(self, "选 择 关 卡", cx, vp.y * 0.095, 38, Color("fff6ea"))
		var total: int = Game.level_count() * 3
		UI.label(
			self, "同心 %d / %d 星" % [Game.total_stars(), total],
			cx + UI.text_width("选 择 关 卡", 38) * 0.5 + 74.0, vp.y * 0.095 - 2.0, 17,
			Color("ffe9a8")
		)
		_layout(vp)
		for w: int in range(Game.WORLDS.size()):
			var first: int = int(Game.WORLDS[w].from)
			if first >= _cards.size():
				continue
			UI.label_left(
				self, String(Game.WORLDS[w].name), 40.0, _cards[first].position.y - 13.0, 19,
				Color(1, 1, 1, 0.62)
			)
		for i: int in range(_cards.size()):
			_card(_cards[i], i, i == _sel)
		UI.label(self, "← → 选择 · 空格 出发 · ESC 返回标题", cx, vp.y - 30.0, 18, Color(1, 1, 1, 0.5))

	# A card leads with the ground it is played on: the crust strip the chapter's
	# platforms actually wear, over that biome's own sky and treeline.
	func _card(r: Rect2, i: int, on: bool) -> void:
		var open: bool = Game.is_unlocked(i)
		var biome: Dictionary = Biomes.get_def(Game.level_biome(i))
		var sky: Array = biome.get("sky", [Color("5b3f8f"), Color("ffd6c0")])
		Art.round_rect(self, r, 16.0, LevelBase.OUTLINE)
		Art.round_rect(
			self, r.grow(-3.0), 13.0,
			Color(0.16, 0.11, 0.26, 0.80) if open else Color(0.14, 0.10, 0.20, 0.55)
		)
		var band := Rect2(r.position.x + 4.0, r.position.y + 4.0, r.size.x - 8.0, 48.0)
		UI.sky(self, band, Color(sky[0]), Color(sky[1]))
		var veil: float = 1.0 if open else 0.4
		for pair: Array in [["bg_far", "far", 8.0, 2.0], ["bg_near", "near", 16.0, 8.0]]:
			var tex := Art.env(String(pair[0]))
			if tex == null:
				continue
			var col: Color = Color(biome.get(pair[1], Color.WHITE))
			col.a = veil
			draw_texture_rect(
				tex,
				Rect2(band.position.x, band.position.y + float(pair[2]), band.size.x, band.size.y - float(pair[2]) + float(pair[3])),
				false, col
			)
		if open:
			Art.draw_cap(self, String(biome.get("cap", "cap_grass")), band.position.x,
				band.position.y + band.size.y, band.size.x, 15.0)
		if on:
			Art.round_rect_outline(self, r.grow(1.0), 19.0,
				UI.tint(_t) if open else Color(1, 1, 1, 0.22), 2.6 if open else 2.0)

		var parts: PackedStringArray = Game.level_name(i).split(" · ")
		var title: String = parts[parts.size() - 1]
		var text_col: Color = Color("fff6ea") if open else Color(1, 1, 1, 0.30)
		var mid: float = r.get_center().x
		var badge := Vector2(r.position.x + 26.0, r.position.y + 74.0)
		draw_circle(badge, 14.0, Color(1, 1, 1, 0.14 if open else 0.06))
		UI.label(self, str(i + 1), badge.x, badge.y + 6.0, 18,
			Color("ffe9a8") if open else Color(1, 1, 1, 0.28))
		UI.label_right(self, title, r.position.x + r.size.x - 16.0, badge.y + 6.0, 19, text_col)

		var foot: float = r.position.y + r.size.y - 20.0
		if not open:
			_lock(Vector2(mid, r.position.y + 100.0))
			UI.label(self, "通关上一关解锁", mid, foot, 13, Color(1, 1, 1, 0.25))
			return
		UI.pips(self, Vector2(r.position.x + 28.0, foot - 5.0), Game.stars_of(i), 8.5, 21.0)
		var rec: Dictionary = Game.level_best.get(i, {})
		if rec.is_empty():
			UI.label_right(self, "未通过", r.position.x + r.size.x - 16.0, foot, 15, Color(1, 1, 1, 0.35))
			return
		UI.label_right(
			self, "%s · %d 金币" % [Game.format_time(float(rec.time)), int(rec.coins)],
			r.position.x + r.size.x - 16.0, foot, 15, Color("cfe4ff")
		)

	func _lock(at: Vector2) -> void:
		Art.round_rect(self, Rect2(at + Vector2(-13.0, -2.0), Vector2(26.0, 20.0)), 5.0, Color(1, 1, 1, 0.22))
		draw_arc(at + Vector2(0.0, -2.0), 8.0, PI, TAU, 10, Color(1, 1, 1, 0.22), 3.0, true)


class Pause extends Control:
	var _menu := MenuNav.new()
	var _t := 0.0
	var level: Node2D

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.size = 24
		_menu.row = 44.0
		_menu.add("继 续")
		_menu.add("重 开 本 关")
		_menu.add("设 置")
		_menu.add("玩 法 教 学")
		_menu.add("回 到 标 题")

	func _input(event: InputEvent) -> void:
		var picked: int = _menu.feed(self, event)
		if picked < 0:
			return
		match picked:
			1:
				Game.set_screen(Game.Screen.PLAYING)
				Game.restart_level()
			2:
				Game.set_screen(Game.Screen.SETTINGS)
			3:
				Game.set_screen(Game.Screen.HOWTO)
			4:
				# Straight to TITLE: dropping back to PLAYING first would blank the menu
				# out over the level and the fade would read as a glitch.
				Game.go_to_title()
			_:
				Game.set_screen(Game.Screen.PLAYING)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.04, 0.12, 0.72))
		var cx: float = vp.x * 0.5
		UI.label(self, "暂 停", cx, vp.y * 0.24, 50, Color("fff6ea"))
		if level != null and is_instance_valid(level):
			UI.label(self, String(level.hud_info().name), cx, vp.y * 0.24 + 32.0, 17, Color(1, 1, 1, 0.5))
		_menu.cx = cx
		_menu.top = vp.y * 0.38
		_menu.draw(self, _t)
		UI.label(self, "ESC 继续 · R 重开本关 · M 音效 · F11 全屏", cx, vp.y - 44.0, 17, Color(1, 1, 1, 0.45))


class Hud extends Control:
	var level: Node2D
	var _t := 0.0
	var _win := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		var done: bool = level != null and is_instance_valid(level) and bool(level.finished)
		_win = clampf(_win + (delta * 3.4 if done else -delta * 7.0), 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		if level == null or not is_instance_valid(level):
			return
		var info: Dictionary = level.hud_info()
		var vp := get_viewport_rect().size
		var w: float = vp.x
		var h: float = vp.y
		Art.round_rect(self, Rect2(18.0, 16.0, 340.0, 62.0), 16.0, Color(0.12, 0.08, 0.22, 0.62))
		UI.label(self, String(info.name), 190.0, 50.0, 24, Color("fff6ea"))
		UI.label(
			self,
			"%s · 第 %d / %d 关" % [Game.world_name(Game.level_index), Game.level_index + 1, Game.level_count()],
			190.0, 70.0, 15, Color(1, 1, 1, 0.55)
		)
		# The two stars still up for grabs, live: the door star only lands at the end,
		# so the HUD carries the parts the pair can still lose.
		var live := 0
		if int(info.coins_total) > 0 and int(info.coins_taken) >= int(info.coins_total):
			live += 1
		if Game.level_time() <= float(info.par):
			live += 1
		UI.pips(self, Vector2(330.0, 34.0), live, 6.4, 15.0)

		Art.round_rect(self, Rect2(w - 348.0, 16.0, 330.0, 62.0), 16.0, Color(0.12, 0.08, 0.22, 0.62))
		UI.label(self, "时间 " + Game.format_time(Game.run_time), w - 258.0, 42.0, 18, Color("fff6ea"))
		UI.label(self, "失误 " + str(Game.deaths), w - 158.0, 42.0, 18, Color("ffd0d8"))
		UI.label(self, "金币 " + str(Game.coins), w - 58.0, 42.0, 18, Color("ffe9a8"))
		var taken: int = int(info.coins_taken)
		var total_coins: int = int(info.coins_total)
		UI.label(
			self,
			"本关 %d / %d" % [taken, total_coins],
			w - 186.0, 68.0, 15,
			Color("ffe9a8") if total_coins > 0 and taken >= total_coins else Color(1, 1, 1, 0.5)
		)

		var total: int = int(info.plates_total)
		var ok: bool = bool(info.plates_ok)
		var sy: float = 62.0
		var n := maxi(total, 1)
		var panel_w := float(n) * 32.0 + 28.0
		Art.round_rect(
			self,
			Rect2(w * 0.5 - panel_w * 0.5, sy - 21.0, panel_w, 42.0),
			20.0,
			Color("6b4f2a") if ok else Color(0.12, 0.08, 0.22, 0.62)
		)
		for i: int in range(n):
			var at := Vector2(w * 0.5 - float(n - 1) * 16.0 + float(i) * 32.0, sy)
			var lit: bool = ok or (i < level.plates.size() and level.plates[i].pressed())
			draw_circle(at, 11.0, Color("ffd166") if lit else Color(1, 1, 1, 0.18))
			draw_circle(at, 6.0, Color("fff6d0") if lit else Color(1, 1, 1, 0.1))

		var hint: String = String(info.hint)
		if not hint.is_empty() and _t < 9.0:
			var alpha: float = clampf(9.0 - _t, 0.0, 1.0)
			var f := UI.font()
			var lines := UI.wrap(hint, 22, w - 150.0)
			var line_h := 30.0
			var widest := 0.0
			for line: String in lines:
				widest = maxf(widest, UI.text_width(line, 22))
			var box_h := float(lines.size()) * line_h + 14.0
			var box := Rect2(w * 0.5 - widest * 0.5 - 22.0, h - 46.0 - box_h, widest + 44.0, box_h)
			Art.round_rect(self, box, 14.0, Color(0.12, 0.08, 0.22, 0.5 * alpha))
			for i: int in range(lines.size()):
				var lw: float = UI.text_width(lines[i], 22)
				draw_string(
					f,
					Vector2(box.position.x + 22.0 + (widest - lw) * 0.5, box.position.y + 26.0 + float(i) * line_h),
					lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(1, 1, 1, alpha)
				)

		# The pause menu carries its own key line; two of them stacked read as a bug.
		if Game.screen_state != Game.Screen.PAUSED:
			UI.label(self, "R 重来 · ESC 暂停 · M 音效 · F11 全屏", w * 0.5, h - 24.0, 15, Color(1, 1, 1, 0.35))

		if _win > 0.002:
			_scorecard(info, Vector2(w, h))

	# The chapter's own scorecard, up for the second the celebration lasts, so the
	# stars land in front of the pair before the next chapter does.
	func _scorecard(info: Dictionary, vp: Vector2) -> void:
		var a: float = _win
		var r := Rect2(vp.x * 0.5 - 200.0, vp.y * 0.5 - 128.0 + (1.0 - a) * 24.0, 400.0, 138.0)
		Art.round_rect(self, r, 20.0, Color(0.10, 0.07, 0.19, 0.84 * a))
		Art.round_rect_outline(self, r.grow(2.0), 22.0, Color(1, 1, 1, 0.28 * a), 2.4)
		var cx: float = vp.x * 0.5
		var top: float = r.position.y
		UI.label(self, "过 关 啦", cx, top + 40.0, 30, Color("fff6ea"))
		UI.pips(self, Vector2(cx, top + 76.0), int(info.stars), 13.0, 36.0)
		UI.label(
			self,
			"用时 %s · 金币 %d / %d · 目标 %d 秒" % [
				Game.format_time(Game.level_time()), int(info.coins_taken),
				int(info.coins_total), int(float(info.par))
			],
			cx, top + 118.0, 17, Color("ffd9e6")
		)


class Victory extends Control:
	var _t := 0.0
	var _b0: Buddy
	var _b1: Buddy

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_b0 = Buddy.new()
		_b0.scale = Vector2(1.5, 1.5)
		add_child(_b0)
		_b1 = Buddy.new()
		_b1.index = 1
		_b1.flip = -1.0
		_b1.scale = Vector2(1.5, 1.5)
		add_child(_b1)

	func _input(event: InputEvent) -> void:
		if not (event is InputEventKey) or not event.pressed or event.echo:
			return
		var ev := event as InputEventKey
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		match k:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				Sfx.play("start")
				Game.start_run(0)
			KEY_ESCAPE:
				Game.go_to_title()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, get_viewport_rect().size)
		UI.sky(self, area, Color("241a46"), Color("ffb9cf"))
		var cx: float = area.size.x * 0.5
		for i: int in range(40):
			var seed_a: float = float(i) * 0.61
			var px: float = fposmod(float(i) * 137.0 + _t * 40.0, area.size.x)
			var py: float = fposmod(float(i) * 211.0 + _t * (60.0 + float(i % 5) * 22.0), area.size.y)
			draw_rect(
				Rect2(px, py, 7.0, 12.0),
				Color.from_hsv(fposmod(seed_a * 0.34 + 0.86, 1.0), 0.45, 1.0, 0.72)
			)

		UI.label(self, "一起到家啦", cx, area.size.y * 0.13 + 44.0, 54, Color("fff6ea"))
		_b0.position = Vector2(cx - 72.0, area.size.y * 0.27)
		_b1.position = Vector2(cx + 72.0, area.size.y * 0.27)

		var rows: int = Game.run_results.size()
		var panel_h := float(rows) * 26.0 + 34.0
		var top: float = area.size.y * 0.34
		Art.round_rect(self, Rect2(cx - 250.0, top, 500.0, panel_h), 16.0, Color(0.12, 0.08, 0.22, 0.55))
		for i: int in range(rows):
			var r: Dictionary = Game.run_results[i]
			var y: float = top + 28.0 + float(i) * 26.0
			var done: bool = bool(r.banked)
			UI.label(self, "第 %d 关" % (i + 1), cx - 172.0, y, 18, Color(1, 1, 1, 0.6))
			UI.label(
				self,
				Game.format_time(float(r.time)) if done else "未通过",
				cx + 10.0, y, 18, Color("cfe4ff") if done else Color(1, 1, 1, 0.3)
			)
			UI.label(
				self, "%d 金币" % int(r.coins), cx + 152.0, y, 18,
				Color("ffe9a8") if done else Color(1, 1, 1, 0.3)
			)
			UI.pips(self, Vector2(cx + 216.0, y - 6.0), int(r.get("stars", 0)) if done else 0, 6.0, 14.0)

		var ly: float = top + panel_h + 32.0
		UI.label(
			self, "总用时 " + Game.format_time(Game.run_time), cx, ly, 26, Color("cfe4ff")
		)
		UI.label(
			self, "同心 %d / %d 星 · 失误 %d 次 · 金币 %d 枚" % [
				Game.total_stars(), Game.level_count() * 3, Game.deaths, Game.coins
			], cx, ly + 32.0, 20, Color("ffd9e6")
		)

		var pulse: float = 0.55 + 0.45 * sin(_t * 4.0)
		UI.label(self, "空格 再来一次 · ESC 回标题", cx, area.size.y - 40.0, 24, Color(1, 1, 1, pulse))
