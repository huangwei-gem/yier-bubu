class_name Pages extends RefCounted

# 设置 / 成就 / 教学三块页面。和 ui.gd 里的每一屏同构：一个全屏 Control，东西全部在
# _draw() 里画，键盘和鼠标命中同一套矩形——这个项目没有 .tres 也没有主题，界面能用的
# 只有 CanvasItem 的绘制调用和 Art 里烤好的那批图。


# 三块页共用的画板。它们不共享一个 _ready 链，共享的是这些静态助手：页面之间唯一的
# 重复就是三行 _ready，而多套一层 Control 会把三块页绑成一起改。
class Ink extends RefCounted:
	const DESIGN := Vector2(1280.0, 720.0)

	# 只给读不出来的键写名字。OS.get_keycode_string 交回来的是 "Left"、"Escape" 这样
	# 的英文单词，而那块键盘上印的是箭头；字母它本来就答得对，不必占这张表。
	const KEY_NAMES := {
		KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓",
		KEY_SPACE: "空格", KEY_ENTER: "回车", KEY_KP_ENTER: "小键盘回车",
		KEY_ESCAPE: "ESC", KEY_TAB: "Tab", KEY_BACKSPACE: "退格",
		KEY_DELETE: "删除", KEY_INSERT: "插入", KEY_HOME: "Home", KEY_END: "End",
		KEY_PAGEUP: "PgUp", KEY_PAGEDOWN: "PgDn", KEY_PAUSE: "暂停", KEY_MENU: "菜单",
		KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_META: "Win",
		KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SEMICOLON: ";",
		KEY_APOSTROPHE: "'", KEY_MINUS: "-", KEY_EQUAL: "=",
		KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_BACKSLASH: "\\",
		KEY_QUOTELEFT: "`",
		KEY_KP_MULTIPLY: "小键盘 *", KEY_KP_DIVIDE: "小键盘 /",
		KEY_KP_SUBTRACT: "小键盘 -", KEY_KP_ADD: "小键盘 +", KEY_KP_PERIOD: "小键盘 .",
	}

	static func key_name(k: int) -> String:
		if KEY_NAMES.has(k):
			return String(KEY_NAMES[k])
		var s := OS.get_keycode_string(k)
		return s if not s.is_empty() else "—"

	# 无头模式和布局完成之前窗口尺寸是 0：面板宽度跟着除零，每块矩形都变成 NaN，
	# 与其画出一屏垃圾不如按设计尺寸走。
	static func area(host: Control) -> Rect2:
		var s := Vector2.ZERO
		if host.get_viewport() != null:
			s = host.get_viewport_rect().size
		if s.x < 480.0 or s.y < 320.0:
			s = DESIGN
		return Rect2(Vector2.ZERO, s)

	# 只认真正按下的一次：echo 会让滑块在按住方向键时一路狂跳到头。
	static func fresh(event: InputEvent) -> int:
		if not (event is InputEventKey) or not (event as InputEventKey).pressed:
			return -1
		var ev := event as InputEventKey
		if ev.echo:
			return -1
		return ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode

	static func is_mouse(event: InputEvent) -> bool:
		if event is InputEventMouseMotion:
			return true
		return event is InputEventMouseButton and (event as InputEventMouseButton).pressed

	static func mouse_at(event: InputEvent) -> Vector2:
		return (event as InputEventMouse).position

	# 和标题页同一批深度带：设置页读的应该是这个世界，不是一块紫色渐变。
	static func backdrop(host: Control, t: float, head: String, sub: String) -> Rect2:
		var a := area(host)
		UI.sky(host, a, Color("241a46"), Color("e9a7c4"))
		for i: int in range(6):
			var r: float = 130.0 + float(i) * 78.0
			host.draw_arc(
				Vector2(a.size.x * 0.5, a.size.y * 1.1), r + sin(t + float(i)) * 5.0,
				PI, TAU, 40, Color(1, 1, 1, 0.045), 24.0
			)
		var biome: Dictionary = Biomes.get_def("dusk")
		var drift: float = sin(t * 0.18) * 10.0
		var step := 0
		for pair: Array in [["bg_far", "far", 0.26], ["bg_mid", "mid", 0.2], ["bg_near", "near", 0.16]]:
			var tex := Art.env(String(pair[0]))
			if tex == null:
				continue
			var hh: float = a.size.y * float(pair[2])
			var col: Color = Color(biome.get(pair[1], Color.WHITE))
			col.a = 0.3 + float(step) * 0.12
			host.draw_texture_rect(
				tex,
				Rect2(
					drift * float(step + 1) * 0.4,
					a.size.y - hh + float(step) * 14.0, a.size.x + 40.0, hh
				),
				false, col
			)
			step += 1
		var cx: float = a.size.x * 0.5
		UI.label(host, head, cx, 62.0, 40, Color("fff6ea"))
		UI.label(host, sub, cx, 88.0, 16, Color("ffd9e6"))
		return a

	static func panel(host: Control, r: Rect2, alpha: float = 0.62) -> void:
		Art.round_rect(host, r.grow(3.0), 20.0, Color(0.06, 0.04, 0.12, 0.35))
		Art.round_rect(host, r, 17.0, Color(0.16, 0.11, 0.26, alpha))

	static func head(host: Control, r: Rect2, text: String) -> void:
		UI.label_left(host, text, r.position.x + 22.0, r.position.y + 30.0, 21, Color("fff6ea"))
		host.draw_line(
			Vector2(r.position.x + 20.0, r.position.y + 40.0),
			Vector2(r.end.x - 20.0, r.position.y + 40.0), Color(1, 1, 1, 0.14), 1.5, true
		)

	# 轨道：底槽 + 已填的一段 + 一个圆头。音量滑块和成就进度条共用它。
	static func track(host: Control, r: Rect2, ratio: float, col: Color, knob := true) -> void:
		var h: float = r.size.y
		Art.round_rect(host, r, h * 0.5, Color(0.07, 0.05, 0.14, 0.75))
		var filled := Rect2(r.position, Vector2(maxf(h, r.size.x * clampf(ratio, 0.0, 1.0)), h))
		Art.round_rect(host, filled, h * 0.5, col)
		if not knob:
			return
		var at := Vector2(filled.end.x - h * 0.5, r.get_center().y)
		host.draw_circle(at, h * 0.72, Color(0.09, 0.06, 0.16, 0.55))
		host.draw_circle(at, h * 0.48, Color("fff6ea"))

	static func toggle(host: Control, r: Rect2, on: bool, t: float) -> void:
		var col: Color = UI.tint(t) if on else Color(0.28, 0.24, 0.36, 0.9)
		Art.round_rect(host, r.grow(2.0), r.size.y * 0.5 + 2.0, Color(0.07, 0.05, 0.14, 0.8))
		Art.round_rect(host, r, r.size.y * 0.5, col)
		var kx: float = r.position.x + r.size.y * 0.5 + (r.size.x - r.size.y) * (0.0 if on else 1.0)
		host.draw_circle(Vector2(kx, r.get_center().y), r.size.y * 0.36, Color("fff6ea"))
		UI.label_right(
			host, "开" if on else "关", r.position.x - 12.0, r.get_center().y + 6.0, 15,
			Color(1, 1, 1, 0.55)
		)

	static func stepper(host: Control, r: Rect2, glyph: String) -> void:
		Art.round_rect(host, r, 9.0, Color(0.07, 0.05, 0.14, 0.7))
		Art.round_rect_outline(host, r, 9.0, Color(1.0, 0.69, 0.75, 0.5), 1.6)
		UI.label(host, glyph, r.get_center().x, r.get_center().y + r.size.y * 0.28, 18, Color("ffb0c0"))

	static func hint(host: Control, a: Rect2, text: String) -> void:
		UI.label(host, text, a.size.x * 0.5, a.size.y - 22.0, 15, Color(1, 1, 1, 0.42))

	# MenuNav 的热点矩形是它自己在 draw 里算的；想在鼠标没压上去之前不把光标画出来，
	# 就得按同样的算法在这里抄一份。
	static func nav_rect(nav: UI.MenuNav) -> Rect2:
		var w: float = UI.text_width(String(nav.items[0].label), nav.size)
		return Rect2(nav.cx - w * 0.5 - 28.0, nav.top - 8.0, w + 56.0, float(nav.size) + 24.0)


class Settings extends Control:
	const DESC := {
		"volume": "所有声音的总大小，背景音乐也走它",
		"muted": "一键全哑，键盘上的 M 就是这个开关",
		"fullscreen": "铺满整块屏幕，F11 或 Alt+回车 一样能切",
		"shake": "摔倒和重落地时屏幕跟着一抖",
		"bump": "从队友头顶落下时按跳，踩着他上楼",
		"music": "每个地貌自己弹一段配乐，坐在音效底下",
	}
	const FOOT := ["恢复默认键位", "清空存档", "返 回"]

	# 四组栏位：设置项 → 一二的键 → 布布的键 → 底部操作。↑↓ 一路走过去，←→ 只在
	# 左栏调数值——UI.MenuNav 把 ←→ 也当成导航，这一页给不了，所以键盘由页面自己
	# 路由，MenuNav 仍旧负责三组列表的高亮、悬停和点击。
	var _group := 0
	var _row := 0
	# 每组列表自己的光标：整页只亮一个框，四个框同时闪就是 bug 的样子。
	var _cursor := [0, 0, 0, 0]
	var _foot := UI.MenuNav.new()
	var _p0 := UI.MenuNav.new()
	var _p1 := UI.MenuNav.new()

	var _cap_p := -1
	var _cap_a := ""
	var _arm := -1
	var _arm_t := 0.0
	var _note := ""
	var _note_t := 0.0
	var _t := 0.0

	var _hot_row: Array[Rect2] = []
	var _hot_dec: Array[Rect2] = []
	var _hot_inc: Array[Rect2] = []
	var _bands: Array[Rect2] = []
	var _b0: UI.Buddy
	var _b1: UI.Buddy

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_foot.size = 20
		_foot.row = 44.0
		for text: String in FOOT:
			_foot.add(text)
		for p: int in range(2):
			var nav: UI.MenuNav = _p0 if p == 0 else _p1
			nav.size = 18
			nav.row = 38.0
			for a: String in Game.KEY_ACTIONS:
				nav.add(String(Game.KEY_LABELS[a]))
		_b0 = _buddy(0, 1.0)
		_b1 = _buddy(1, -1.0)
		_sync()
		# 存档里那份键位是唯一真相，页面只是它的一张脸：任何一边改了都得重拼标签。
		Game.settings_changed.connect(_sync)

	func _buddy(index: int, flip: float) -> UI.Buddy:
		var b := UI.Buddy.new()
		b.index = index
		b.flip = flip
		b.scale = Vector2(0.5, 0.5)
		add_child(b)
		return b

	func _nav(g: int) -> UI.MenuNav:
		if g == 1:
			return _p0
		if g == 2:
			return _p1
		return _foot

	# MenuNav 只会给 index 那一行画框，所以不在当前栏位时先把行号挪到 -1、画完再还
	# 回去。不用 enabled=false 那一招：它会把热点矩形一起清空，鼠标就点不到没在焦点
	# 的那几栏了。
	func _draw_nav(g: int) -> void:
		var nav: UI.MenuNav = _nav(g)
		var last := nav.items.size() - 1
		if _group == g:
			_cursor[g] = clampi(nav.index, 0, last)
		nav.index = _cursor[g] if _group == g else -1
		nav.draw(self, _t)
		nav.index = _cursor[g]

	func _sync() -> void:
		for p: int in range(2):
			var nav: UI.MenuNav = _p0 if p == 0 else _p1
			for i: int in range(Game.KEY_ACTIONS.size()):
				var a := String(Game.KEY_ACTIONS[i])
				var shown := Ink.key_name(Game.key_of(p, a))
				if _cap_p == p and _cap_a == a:
					shown = "按下键位…"
				nav.items[i].label = "%s · %s" % [String(Game.KEY_LABELS[a]), shown]
		for i: int in range(_foot.items.size()):
			_foot.items[i].label = ("再按一次确认：" + FOOT[i]) if _arm == i and i < 2 else FOOT[i]

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _arm >= 0:
			_arm_t -= delta
			# 人去读别栏的时候把销毁项一直挂着不算设计，让它自己过期。
			if _arm_t <= 0.0:
				_arm = -1
				_sync()
		_note_t = maxf(0.0, _note_t - delta)

	func _input(event: InputEvent) -> void:
		if _cap_p >= 0:
			_capture(event)
			return
		var k: int = Ink.fresh(event)
		if k >= 0:
			_keys(k)
			return
		if not Ink.is_mouse(event):
			return
		# 滚轮不算点击：MenuNav 只看热点，滚过头就会把那一行当成按下去。
		var b := event as InputEventMouseButton
		var wheel: bool = b != null and (
			b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
		if not wheel:
			for g: int in range(1, 4):
				var nav: UI.MenuNav = _nav(g)
				var picked := nav.feed(self, event)
				if picked >= 0:
					_group = g
					_act(g, picked)
					return
		if event is InputEventMouseButton:
			if b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_step(1)
			elif b.button_index == MOUSE_BUTTON_WHEEL_UP:
				_step(-1)
			else:
				_point(b.position)
		_hover(Ink.mouse_at(event))

	func _keys(k: int) -> void:
		match k:
			KEY_ESCAPE:
				if _arm >= 0:
					_arm = -1
					_sync()
					Sfx.play("taut")
				else:
					Sfx.play("start")
					Game.close_page()
			KEY_UP, KEY_W:
				_step(-1)
			KEY_DOWN, KEY_S:
				_step(1)
			KEY_LEFT, KEY_A:
				if _group == 0:
					_adjust(-1)
				else:
					_step(-1)
			KEY_RIGHT, KEY_D:
				if _group == 0:
					_adjust(1)
				else:
					_step(1)
			KEY_TAB:
				_enter_group(_group + 1 if _group < 3 else 0)
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_act(_group, _row if _group == 0 else _nav(_group).index)

	# 一列走到底就滑进下一列，最后一列再绕回第一列：四组东西共用一套 ↑↓，
	# 手不用离开这两个键就能把整页配完。
	func _step(d: int) -> void:
		if _group == 0:
			var n := Game.SETTINGS.size()
			if d < 0 and _row == 0:
				_enter_group(3, true)
				return
			if d > 0 and _row == n - 1:
				_enter_group(1)
				return
			var next := posmod(_row + d, n)
			if next != _row:
				_row = next
				Sfx.play("select")
			return
		var nav: UI.MenuNav = _nav(_group)
		var last := nav.items.size() - 1
		if d < 0 and nav.index == 0:
			_enter_group(_group - 1 if _group > 1 else 0, true)
			return
		if d > 0 and nav.index == last:
			_enter_group(_group + 1 if _group < 3 else 0)
			return
		var i := clampi(nav.index + d, 0, last)
		if i != nav.index:
			nav.index = i
			Sfx.play("select")

	func _enter_group(g: int, to_last := false) -> void:
		_group = clampi(g, 0, 3)
		if _group == 0:
			_row = Game.SETTINGS.size() - 1 if to_last else 0
		else:
			var nav: UI.MenuNav = _nav(_group)
			nav.index = nav.items.size() - 1 if to_last else 0
		Sfx.play("select")

	# 滑块按 d 走一格；开关不看 d，落到这一行就是翻一次。
	func _adjust(d: int) -> void:
		var spec: Dictionary = Game.SETTINGS[_row]
		var key := String(spec.key)
		if String(spec.kind) == "range":
			var now: float = float(Game.settings.get(key, 0.0))
			var want: float = snappedf(
				clampf(now + float(spec.step) * float(d), float(spec.min), float(spec.max)),
				float(spec.step)
			)
			if is_equal_approx(want, now):
				Sfx.play("taut")
				return
			Game.set_setting(key, want)
		else:
			Game.set_setting(key, not bool(Game.settings.get(key, false)))
		Sfx.play("press")

	func _act(g: int, i: int) -> void:
		# 就地按一下：滑块走一格、开关翻一次，绝不碰“返回”那两项——第一组栏位的
		# 行号从 0 数到 5，和底部菜单的行号撞车，靠 g 分清楚。
		if g == 0:
			_row = clampi(i, 0, Game.SETTINGS.size() - 1)
			_adjust(1)
			return
		if g == 1 or g == 2:
			_cap_p = g - 1
			_cap_a = String(Game.KEY_ACTIONS[clampi(i, 0, Game.KEY_ACTIONS.size() - 1)])
			_sync()
			Sfx.play("press")
			return
		if i >= 2:
			Sfx.play("start")
			Game.close_page()
			return
		if _arm != i:
			# 销毁性的两项第一次按下只是武装，标签同时改成“再按一次确认”。
			_arm = i
			_arm_t = 4.0
			_sync()
			Sfx.play("taut")
			return
		_arm = -1
		if i == 0:
			Game.reset_keys()
			_note = "键位已经回到默认"
			_note_t = 2.6
			_sync()
			Sfx.play("start")
			return
		# 清空存档之后没有“刚才那页”可回了，直接回标题。
		Game.reset_save()
		Sfx.play("start")
		Game.go_to_title()

	func _capture(event: InputEvent) -> void:
		# 绑定途中只吃键盘：这时长任何鼠标都不该把刚按下的键丢掉。
		var k: int = Ink.fresh(event)
		if k < 0:
			return
		var p := _cap_p
		var a := _cap_a
		_cap_p = -1
		_cap_a = ""
		var old := Game.key_of(p, a)
		if k == KEY_ESCAPE or k == old:
			_sync()
			Sfx.play("taut")
			return
		# 撞车就把被抢的那一行挪到老键位上。两个人共用一块键盘时，这是唯一不会把
		# 某个动作彻底变没的处理：旧键位刚空出来，正好给占新键位的人去站。
		for q: int in range(2):
			for b: String in Game.KEY_ACTIONS:
				if q == p and b == a:
					continue
				if Game.key_of(q, b) != k:
					continue
				Game.set_key(q, b, old)
				_note = "%s 的%s 被占了，改到 %s" % [
					Art.NAMES[q], String(Game.KEY_LABELS[b]), Ink.key_name(old)
				]
				_note_t = 3.4
		Game.set_key(p, a, k)
		_sync()
		Sfx.play("start")

	func _point(m: Vector2) -> void:
		for i: int in range(_hot_row.size()):
			# −/＋ 在整行的矩形里，先判它们，否则一次点减号只会被当成“选中这一行”。
			if _hot_dec[i].has_point(m):
				_group = 0
				_row = i
				_adjust(-1)
				return
			if _hot_inc[i].has_point(m):
				_group = 0
				_row = i
				_adjust(1)
				return
			if _hot_row[i].has_point(m):
				_group = 0
				if _row != i:
					_row = i
					Sfx.play("select")
				_adjust(1)
				return

	# 悬停只改光标不改值：一路划过整列就一路改设置是灾难。
	func _hover(m: Vector2) -> void:
		for i: int in range(_hot_row.size()):
			if _hot_row[i].has_point(m):
				if _row != i or _group != 0:
					_group = 0
					_row = i
					Sfx.play("select")
				return
		for g: int in range(_bands.size()):
			if _bands[g].has_point(m) and _group != g + 1:
				_group = g + 1
				return

	func _draw() -> void:
		var a := Ink.backdrop(self, _t, "设 置", "声音、画面和两个人的键位")
		var vp := a.size
		var top := 108.0
		var left := Rect2(40.0, top, floorf(vp.x * 0.47), vp.y - top - 62.0)
		var right := Rect2(
			left.end.x + 22.0, top, maxf(340.0, vp.x - left.end.x - 62.0), vp.y - top - 62.0
		)
		Ink.panel(self, left)
		Ink.panel(self, right)
		_hot_row.clear()
		_hot_dec.clear()
		_hot_inc.clear()
		_bands.clear()
		_rows(left)
		_keys_panel(right)
		_foot.cx = right.get_center().x
		_foot.top = right.end.y - 30.0 - float(_foot.items.size()) * _foot.row
		_draw_nav(3)
		_bands.append(Rect2(right.position.x, _foot.top - 8.0, right.size.x, float(_foot.items.size()) * _foot.row))
		if _note_t > 0.0:
			UI.label(
				self, _note, right.get_center().x, _foot.top - 18.0, 15,
				Color("ffe9a8", 0.6 + 0.4 * minf(1.0, _note_t))
			)
		Ink.hint(self, a, "↑↓ 走栏 · ←→ 调数值 · 空格 确认 · Tab 换栏 · 点一下也能用 · ESC 返回")
		if _cap_p >= 0:
			_veil()

	func _rows(panel_r: Rect2) -> void:
		var n: int = Game.SETTINGS.size()
		var rh: float = minf(84.0, (panel_r.size.y - 58.0) / float(n))
		Ink.head(self, panel_r, "声 音 与 画 面")
		var muted: bool = bool(Game.settings.get("muted", false))
		for i: int in range(n):
			var spec: Dictionary = Game.SETTINGS[i]
			var key := String(spec.key)
			var is_range: bool = String(spec.kind) == "range"
			var on: bool = bool(Game.settings.get(key, false))
			var r := Rect2(
				panel_r.position.x + 14.0, panel_r.position.y + 52.0 + float(i) * rh,
				panel_r.size.x - 28.0, rh - 6.0
			)
			_hot_row.append(r)
			_hot_dec.append(Rect2(0.0, 0.0, -1.0, -1.0))
			_hot_inc.append(Rect2(0.0, 0.0, -1.0, -1.0))
			var lit: bool = i == _row and _group == 0
			# 静音时音量滑块是死的，把它压暗：一条看着能动的死滑块最骗人。
			var dead: bool = key == "volume" and muted
			if lit:
				Art.round_rect(self, r, 13.0, Color(0.16, 0.10, 0.26, 0.6))
				Art.round_rect_outline(self, r.grow(1.5), 14.0, UI.tint(_t), 2.2)
			UI.label_left(
				self, String(spec.label), r.position.x + 18.0, r.position.y + 26.0, 21,
				Color("fff6ea") if not dead else Color(1, 1, 1, 0.42)
			)
			UI.label_left(
				self, String(DESC.get(key, "")), r.position.x + 18.0, r.position.y + 46.0, 14,
				Color("ffb0b8") if dead else Color(1, 1, 1, 0.48)
			)
			var wy: float = r.position.y + 36.0
			var wend: float = r.end.x - 22.0
			var wx: float = r.position.x + r.size.x * 0.5
			var col: Color = Color(1, 1, 1, 0.28) if dead else UI.tint(_t)
			if is_range:
				var ratio: float = float(Game.settings.get(key, 0.0))
				var sb := 30.0
				var dec := Rect2(wx, wy - sb * 0.5, sb, sb)
				var inc := Rect2(wend - sb, wy - sb * 0.5, sb, sb)
				var tr := Rect2(dec.end.x + 12.0, wy - 5.0, maxf(40.0, inc.position.x - dec.end.x - 24.0), 10.0)
				Ink.stepper(self, dec, "−")
				Ink.stepper(self, inc, "+")
				_hot_dec[i] = dec
				_hot_inc[i] = inc
				Ink.track(self, tr, ratio, col)
				UI.label(
					self, "%d%%" % int(roundf(ratio * 100.0)), tr.get_center().x, wy - 12.0, 15,
					Color("ffe9a8")
				)
			else:
				Ink.toggle(self, Rect2(wend - 58.0, wy - 14.0, 58.0, 28.0), on, _t)
			if not on and key == "bump":
				# 踩头是某些章节唯一的解，关掉它必须留下一句警告，而不是悄悄关灯。
				UI.label_left(
					self, "警告：有些台阶只能靠踩头过去，关掉后那一关可能没有解",
					r.position.x + 18.0, r.position.y + 64.0, 13, Color("ffb0b8")
				)

	func _keys_panel(right: Rect2) -> void:
		Ink.head(self, right, "键 位 重 映 射")
		var y0: float = right.position.y + 58.0
		var half: float = (right.size.x - 54.0) * 0.5
		var nav: UI.MenuNav = _p0
		for p: int in range(2):
			nav = _p0 if p == 0 else _p1
			var bx: float = right.position.x + 18.0 + float(p) * (half + 18.0)
			var buddy: UI.Buddy = _b0 if p == 0 else _b1
			buddy.position = Vector2(bx + 22.0, y0 + 26.0)
			UI.label_left(self, Art.NAMES[p], bx + 44.0, y0 + 16.0, 18, Art.ACCENT_COLORS[p])
			nav.cx = bx + half * 0.5
			nav.top = y0 + 32.0
			_draw_nav(p + 1)
			_bands.append(Rect2(bx, nav.top - 8.0, half, nav.row * float(nav.items.size())))
		var ny: float = y0 + 32.0 + nav.row * float(nav.items.size()) + 24.0
		var note := "点一行、再按一个键就绑上了。撞车时把队友挪到老键位，ESC 取消。"
		for line: String in UI.wrap(note, 14, right.size.x - 44.0):
			UI.label(self, line, right.get_center().x, ny, 14, Color(1, 1, 1, 0.42))
			ny += 18.0

	func _veil() -> void:
		var a := Ink.area(self)
		draw_rect(Rect2(Vector2.ZERO, a.size), Color(0.05, 0.03, 0.10, 0.5))
		var cx: float = a.size.x * 0.5
		var cy: float = a.size.y * 0.5
		var box := Rect2(cx - 250.0, cy - 62.0, 500.0, 124.0)
		Art.round_rect(self, box, 20.0, Color(0.12, 0.08, 0.22, 0.92))
		Art.round_rect_outline(self, box, 20.0, UI.tint(_t), 2.4)
		UI.label(self, "按下要绑定的键", cx, cy - 8.0, 30, Color("fff6ea"))
		UI.label(
			self, "%s · %s" % [Art.NAMES[_cap_p], String(Game.KEY_LABELS.get(_cap_a, ""))],
			cx, cy + 24.0, 18, Color("ffd9e6")
		)
		UI.label(self, "ESC 取消", cx, cy + 48.0, 15, Color(1, 1, 1, 0.6 + 0.4 * sin(_t * 5.0)))


# 成就墙。两列在 1280×720 排得满，不用滚；滚动只是给更矮的窗口兜底。
class Achievements extends Control:
	const CH := 50.0
	const GAP := 10.0

	var _cols := 2
	var _sel := 0
	var _scroll := 0.0
	var _max_scroll := 0.0
	var _cells: Array[Rect2] = []
	var _panel := Rect2()
	var _t := 0.0
	var _fresh := ""
	var _fresh_t := 0.0
	var _back := UI.MenuNav.new()
	# “返 回”只在鼠标真的压在它上面时才亮框：这页的键盘光标在格子上，两个框同时亮
	# 就读不出键盘现在归谁。
	var _back_on := false
	var _back_hot := Rect2()

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.size = 20
		_back.row = 34.0
		_back.add("返 回")
		Game.achievement_unlocked.connect(_on_unlocked)

	func _exit_tree() -> void:
		if Game.achievement_unlocked.is_connected(_on_unlocked):
			Game.achievement_unlocked.disconnect(_on_unlocked)

	# 当场解锁的那条亮一下，并把光标挪过去：正在翻这页的人应该立刻看到新拿的那颗。
	func _on_unlocked(ach: Dictionary) -> void:
		_fresh = String(ach.id)
		_fresh_t = 3.2
		for i: int in range(Game.ACHIEVEMENTS.size()):
			if String(Game.ACHIEVEMENTS[i].id) == _fresh:
				_sel = i
				_keep()

	func _process(delta: float) -> void:
		_t += delta
		_fresh_t = maxf(0.0, _fresh_t - delta)
		queue_redraw()

	func _input(event: InputEvent) -> void:
		var k: int = Ink.fresh(event)
		if k >= 0:
			match k:
				KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					Sfx.play("start")
					Game.close_page()
				KEY_UP, KEY_W:
					_move(-_cols)
				KEY_DOWN, KEY_S:
					_move(_cols)
				KEY_LEFT, KEY_A:
					_move(-1)
				KEY_RIGHT, KEY_D:
					_move(1)
				KEY_PAGEUP:
					_scroll_to(_scroll - _panel.size.y * 0.7)
				KEY_PAGEDOWN:
					_scroll_to(_scroll + _panel.size.y * 0.7)
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var b := event as InputEventMouseButton
			if b.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_to(_scroll - 90.0)
				return
			if b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_to(_scroll + 90.0)
				return
		if not Ink.is_mouse(event):
			return
		var m := Ink.mouse_at(event)
		_back_on = _back_hot.has_point(m)
		# 点击时 MenuNav 自己会响“start”，这里别再叠一遍。
		if _back.feed(self, event) >= 0:
			Game.close_page()
			return
		for i: int in range(_cells.size()):
			if _cells[i].has_point(m) and i != _sel:
				_sel = i
				Sfx.play("select")
				break

	func _move(d: int) -> void:
		var n := Game.ACHIEVEMENTS.size()
		if n == 0:
			return
		var next := clampi(_sel + d, 0, n - 1)
		if next != _sel:
			_sel = next
			_keep()
			Sfx.play("select")

	func _cell_of(i: int) -> Rect2:
		var cw: float = (_panel.size.x - GAP * float(_cols + 1.0)) / float(_cols)
		return Rect2(
			_panel.position.x + GAP + float(i % _cols) * (cw + GAP),
			_panel.position.y + GAP + floorf(float(i) / float(_cols)) * (CH + GAP) - _scroll,
			cw, CH
		)

	# 光标永远留在窗口里：一个看不见的高亮比没有高亮更糟。
	func _keep() -> void:
		var c := _cell_of(_sel)
		if c.position.y < _panel.position.y + 6.0:
			_scroll_to(_scroll + (c.position.y - _panel.position.y) - 6.0)
		elif c.end.y > _panel.end.y - 6.0:
			_scroll_to(_scroll + (c.end.y - _panel.end.y) + 6.0)

	func _scroll_to(v: float) -> void:
		_scroll = clampf(v, 0.0, _max_scroll)

	func _draw() -> void:
		var a := Ink.backdrop(self, _t, "成 就", "两个人一起留下来的记录")
		var total := Game.ACHIEVEMENTS.size()
		UI.label(
			self, "已收 %d / %d" % [Game.ach_count(), total],
			a.size.x * 0.5 + UI.text_width("成 就", 40) * 0.5 + 96.0, 60.0, 18, Color("ffe9a8")
		)
		UI.label(
			self, "闯关 %d / %d 星" % [Game.total_stars(), Game.level_count() * 3],
			a.size.x - 132.0, 44.0, 17, Color(1, 1, 1, 0.55)
		)
		_panel = Rect2(40.0, 108.0, a.size.x - 80.0, a.size.y - 108.0 - 96.0)
		Ink.panel(self, _panel, 0.5)
		var rows := int(ceilf(float(total) / float(_cols)))
		_max_scroll = maxf(0.0, GAP + float(rows) * (CH + GAP) - _panel.size.y)
		_cells.clear()
		for i: int in range(total):
			_cells.append(_cell_of(i))
		for i: int in range(total):
			_card(i)
		_fade()
		_back.cx = a.size.x * 0.5
		_back.top = _panel.end.y + 16.0
		_back_hot = Ink.nav_rect(_back)
		_back.index = 0 if _back_on else -1
		_back.draw(self, _t)
		Ink.hint(self, a, "↑↓←→ 翻 · 滚轮 看下面 · ESC 返回")
		if _fresh_t > 0.0:
			_toast(a)

	func _card(i: int) -> void:
		var r := _cells[i]
		# 滚动之后整行都可能落到面板外；这里没有裁剪可借用，就少画一行，
		# 剩下的交给 _fade() 那条渐变。
		if r.end.y < _panel.position.y + 4.0 or r.position.y > _panel.end.y - 2.0:
			return
		var ach: Dictionary = Game.ACHIEVEMENTS[i]
		var got := Game.ach_done(String(ach.id))
		var mid: float = r.position.y + r.size.y * 0.5
		Art.round_rect(self, r.grow(3.0), 15.0, Color(0.06, 0.04, 0.12, 0.4))
		Art.round_rect(
			self, r, 13.0,
			Color(0.34, 0.24, 0.12, 0.7) if got else Color(0.14, 0.10, 0.20, 0.6)
		)
		if i == _sel:
			Art.round_rect_outline(self, r.grow(4.5), 17.0, UI.tint(_t), 2.4)
		var at := Vector2(r.position.x + 26.0, mid)
		if got:
			UI.star(self, at, 12.0, Color("ffd166"))
			draw_circle(at + Vector2(-2.6, -3.4), 3.0, Color("fff6d0"))
		else:
			UI.star(self, at, 11.0, Color(1, 1, 1, 0.14))
		UI.label_left(
			self, String(ach.name), r.position.x + 48.0, r.position.y + 21.0, 18,
			Color("fff6ea") if got else Color(1, 1, 1, 0.44)
		)
		UI.label_left(
			self, String(ach.desc), r.position.x + 48.0, r.position.y + 39.0, 13,
			Color("ffd9e6") if got else Color(1, 1, 1, 0.3)
		)
		if String(ach.id) == _fresh:
			Art.round_rect_outline(
				self, r.grow(2.0), 15.0, Color(1.0, 0.82, 0.4, clampf(_fresh_t / 3.2, 0.0, 1.0)), 2.0
			)
		if got:
			UI.label_right(self, "已达成", r.end.x - 16.0, r.position.y + 21.0, 14, Color("ffe9a8"))
			return
		var prog: Dictionary = Game.ach_progress(ach)
		var now := int(prog.now)
		var goal := maxi(int(prog.goal), 1)
		UI.label_right(
			self, "%d / %d" % [now, goal], r.end.x - 16.0, r.position.y + 21.0, 15,
			Color(1, 1, 1, 0.5)
		)
		Ink.track(
			self, Rect2(r.end.x - 138.0, mid + 4.0, 118.0, 7.0),
			clampf(float(now) / float(goal), 0.0, 1.0), Color("b98fd0"), false
		)

	# 被滚动切掉的那半行用一条同色渐变盖住，比让一行字横穿面板边界干净。
	func _fade() -> void:
		if _max_scroll <= 0.5:
			return
		var w: float = _panel.size.x - 6.0
		if _scroll > 0.5:
			draw_texture_rect(
				Art.vgrad(Color(0.16, 0.11, 0.26, 0.96), Color(0.16, 0.11, 0.26, 0.0)),
				Rect2(_panel.position.x + 3.0, _panel.position.y + 3.0, w, 34.0), false
			)
		if _scroll < _max_scroll - 0.5:
			draw_texture_rect(
				Art.vgrad(Color(0.16, 0.11, 0.26, 0.0), Color(0.16, 0.11, 0.26, 0.96)),
				Rect2(_panel.position.x + 3.0, _panel.end.y - 42.0, w, 39.0), false
			)

	func _toast(a: Rect2) -> void:
		var k: float = clampf(_fresh_t / 3.2, 0.0, 1.0)
		var w := UI.text_width(_fresh, 19) + 210.0
		var r := Rect2(a.size.x * 0.5 - w * 0.5, 14.0, w, 40.0)
		Art.round_rect(self, r, 14.0, Color(0.20, 0.13, 0.06, 0.9 * k))
		Art.round_rect_outline(
			self, r.grow(1.5), 15.0, Color(1.0, 0.82, 0.4, k * (0.65 + 0.35 * sin(_t * 6.0))), 2.2
		)
		UI.star(self, Vector2(r.position.x + 26.0, r.get_center().y), 11.0, Color("ffd166"))
		UI.label_left(
			self, "解锁成就 · %s" % _fresh, r.position.x + 46.0, r.get_center().y + 7.0, 19,
			Color("ffe9a8")
		)


# 教学页。数字全部从 Player / Tether 自己抄，页面不可能把游戏说成另一个样子。
class HowTo extends Control:
	const CH := 114.0
	const GAP := 10.0
	const SECTIONS := [
		{"t": "移动与跳", "ch": 0, "art": "move", "biome": "meadow"},
		{"t": "同心跳", "ch": 0, "art": "sync", "biome": "meadow"},
		{"t": "踩头弹跳", "ch": 1, "art": "stomp", "biome": "forest"},
		{"t": "绳与滑轮", "ch": 7, "art": "pulley", "biome": "cave"},
		{"t": "抓绳上爬 · 荡绳", "ch": 3, "art": "swing", "biome": "forest"},
		{"t": "木箱压按钮", "ch": 6, "art": "plate", "biome": "cave"},
		{"t": "冰上刹车", "ch": 8, "art": "ice", "biome": "snow"},
		{"t": "三星规则", "ch": 11, "art": "stars", "biome": "dusk"},
	]
	# player.gd 把冰面的 grip 写成了 0.16 这个字面量，刹车距离条要用它。改那边必须
	# 改这里——它是这页唯一没能从常量里读出来的数。
	const ICE_GRIP := 0.16

	# 插图里的熊要摆姿势，所以是自己的一批 Node2D：Art 的助手设的是绝对画布变换，
	# 外层缩放包不住一次直接调用；和 ui.gd 的 UI.Buddy 比只多了一个 frame。
	class Pose extends Node2D:
		var index := 0
		var flip := 1.0
		var frame := Art.F_IDLE
		var _t := 0.0

		func _process(delta: float) -> void:
			_t += delta
			queue_redraw()

		func _draw() -> void:
			Art.draw_buddy(self, index, Vector2.ZERO, flip, frame, 0.0, _t)

	var _poses: Array = []
	var _cols := 2
	var _sel := 0
	var _scroll := 0.0
	var _max_scroll := 0.0
	var _cells: Array[Rect2] = []
	var _panel := Rect2()
	var _t := 0.0
	var _back := UI.MenuNav.new()
	var _back_on := false
	var _back_hot := Rect2()

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.size = 20
		_back.row = 34.0
		_back.add("返 回")
		# 每格两张熊脸各占一个节点：共用一个的话，后画的格子会把先画的拖走。
		for i: int in range(SECTIONS.size() * 2):
			var p := Pose.new()
			p.scale = Vector2(0.5, 0.5)
			add_child(p)
			_poses.append(p)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _input(event: InputEvent) -> void:
		var k: int = Ink.fresh(event)
		if k >= 0:
			match k:
				KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					Sfx.play("start")
					Game.close_page()
				KEY_UP, KEY_W:
					_move(-_cols)
				KEY_DOWN, KEY_S:
					_move(_cols)
				KEY_LEFT, KEY_A:
					_move(-1)
				KEY_RIGHT, KEY_D:
					_move(1)
				KEY_PAGEUP:
					_scroll_to(_scroll - _panel.size.y * 0.7)
				KEY_PAGEDOWN:
					_scroll_to(_scroll + _panel.size.y * 0.7)
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var b := event as InputEventMouseButton
			if b.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_to(_scroll - 120.0)
				return
			if b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_to(_scroll + 120.0)
				return
		if not Ink.is_mouse(event):
			return
		var m := Ink.mouse_at(event)
		_back_on = _back_hot.has_point(m)
		if _back.feed(self, event) >= 0:
			Game.close_page()
			return
		for i: int in range(_cells.size()):
			if _cells[i].has_point(m) and i != _sel:
				_sel = i
				Sfx.play("select")
				break

	func _move(d: int) -> void:
		var next := clampi(_sel + d, 0, SECTIONS.size() - 1)
		if next != _sel:
			_sel = next
			_keep()
			Sfx.play("select")

	func _cell_of(i: int) -> Rect2:
		var cw: float = (_panel.size.x - GAP * float(_cols + 1.0)) / float(_cols)
		return Rect2(
			_panel.position.x + GAP + float(i % _cols) * (cw + GAP),
			_panel.position.y + GAP + floorf(float(i) / float(_cols)) * (CH + GAP) - _scroll,
			cw, CH
		)

	func _keep() -> void:
		var c := _cell_of(_sel)
		if c.position.y < _panel.position.y + 6.0:
			_scroll_to(_scroll + (c.position.y - _panel.position.y) - 6.0)
		elif c.end.y > _panel.end.y - 6.0:
			_scroll_to(_scroll + (c.end.y - _panel.end.y) + 6.0)

	func _scroll_to(v: float) -> void:
		_scroll = clampf(v, 0.0, _max_scroll)

	func _draw() -> void:
		var a := Ink.backdrop(self, _t, "怎 么 玩", "一根绳拴在一起的两个人，八件要会的事")
		_panel = Rect2(40.0, 106.0, a.size.x - 80.0, a.size.y - 106.0 - 104.0)
		Ink.panel(self, _panel, 0.42)
		var rows := int(ceilf(float(SECTIONS.size()) / float(_cols)))
		_max_scroll = maxf(0.0, GAP + float(rows) * (CH + GAP) - _panel.size.y)
		_cells.clear()
		for i: int in range(SECTIONS.size()):
			_cells.append(_cell_of(i))
		for i: int in range(SECTIONS.size()):
			_card(i)
		_back.cx = a.size.x * 0.5
		_back.top = _panel.end.y + 6.0
		_back_hot = Ink.nav_rect(_back)
		_back.index = 0 if _back_on else -1
		_back.draw(self, _t)
		UI.label(
			self, "F11 / Alt+回车 全屏 · ESC 暂停 · R 重开本关 · M 静音 · P 暂停",
			a.size.x * 0.5, a.size.y - 46.0, 16, Color(1, 1, 1, 0.62)
		)
		Ink.hint(self, a, "↑↓←→ 选一张 · 滚轮翻页 · ESC 返回")

	func _card(i: int) -> void:
		var r := _cells[i]
		if r.end.y < _panel.position.y + 4.0 or r.position.y > _panel.end.y - 2.0:
			return
		var sec: Dictionary = SECTIONS[i]
		Art.round_rect(self, r.grow(3.0), 16.0, Color(0.06, 0.04, 0.12, 0.35))
		Art.round_rect(self, r, 14.0, Color(0.16, 0.11, 0.26, 0.66))
		if i == _sel:
			Art.round_rect_outline(self, r.grow(4.0), 18.0, UI.tint(_t), 2.4)
		var box := Rect2(r.position.x + 14.0, r.position.y + 50.0, 150.0, 48.0)
		var tx: float = box.end.x + 20.0
		UI.label_left(self, String(sec.t), tx, r.position.y + 24.0, 19, Color("fff6ea"))
		var parts: PackedStringArray = Game.level_name(int(sec.ch)).split(" · ")
		UI.label_right(
			self, parts[parts.size() - 1], r.end.x - 16.0, r.position.y + 23.0, 13,
			Color(1, 1, 1, 0.42)
		)
		var lines := UI.wrap(_body(i), 14, r.end.x - tx - 18.0)
		for l: int in range(mini(lines.size(), 4)):
			UI.label_left(
				self, lines[l], tx, r.position.y + 46.0 + float(l) * 17.0, 14, Color(1, 1, 1, 0.72)
			)
		_art(String(sec.art), box, String(sec.biome), i)

	func _body(i: int) -> String:
		match i:
			0:
				return "一二用 WASD、布布用方向键，一秒走 %d 像素。走出台沿还有 %.2f 秒能补一跳，落地前沿 %.2f 秒按下跳会先记着，一碰地就替你跳出去。" % [int(Player.SPEED), Player.COYOTE, Player.BUFFER]
			1:
				return "两人在 %.2f 秒之内先后按下跳，绳子把两股力气并成一次：这一跳多给 %.0f 升力，刚好够上一格单人跳不到的台阶。" % [Tether.SYNC_WINDOW, Tether.SYNC_BOOST]
			2:
				return "一位站稳，另一位从他头顶落下，接触的那一帧按跳就能弹到 %.0f 的速度，比自己的跳高出一截。设置里关掉踩头弹跳就没有这一步。" % Player.STOMP_BOUNCE
			3:
				return "绳子搭上滑轮，一头走就有一头升：想被吊上去，脚下那位得一直往后退。轮子只认绳绷紧的那一会儿，两人都得朝同一个方向使劲。"
			4:
				return "悬空又绷紧时按住跳就沿绳往队友那边爬，一秒 %.0f 像素。高处那位站稳就是轴，下面那位是一只钟摆，松手前最快能带出 %.0f 每秒。" % [Player.CLIMB_SPEED, Player.SWING_MAX_X]
			5:
				return "黄色按钮要一直有人压着，绿色带点的踩一下就自己卡住。木箱能替人站班，所以先过去的人把箱子推上黄板，或者自己顶着门等后面那位。"
			6:
				return "冰面几乎不给摩擦：同样 %d 的速度，平地 %d 像素站住，冰上要 %d 像素。想停就松开方向键让它自己慢下来，别一路按着往前冲。" % [int(Player.SPEED), _skid(1.0), _skid(ICE_GRIP)]
			7:
				return "第一颗星：每块按钮都被压住、门开了，两人一起站进门里；第二颗：这一关的金币一枚不剩；第三颗：在 par 秒之内到门。HUD 一直在替你数着后两颗。"
		return ""

	func _skid(grip: float) -> int:
		return int(roundf(Player.SPEED * Player.SPEED / (2.0 * Player.FRICTION * grip)))

	func _art(kind: String, box: Rect2, biome_id: String, i: int) -> void:
		var biome: Dictionary = Biomes.get_def(biome_id)
		var cap := String(biome.get("cap", "cap_grass"))
		_floor(box, cap, biome)
		match kind:
			"move":
				_how_move(box, i)
			"sync":
				_how_sync(box, i)
			"stomp":
				_how_stomp(box, i)
			"pulley":
				_how_pulley(box, i)
			"swing":
				_how_swing(box, i, cap)
			"plate":
				_how_plate(box, i)
			"ice":
				_how_ice(box, i)
			"stars":
				_how_stars(box, i)

	# --- 八张小插图，全部在 _draw 里现算：一张会动的图比一行字讲得快。 ---

	func _how_move(box: Rect2, i: int) -> void:
		var g := box.end.y
		_pose(i, 0, Vector2(box.position.x + 34.0, g), 1.0, Art.F_RUN_A)
		_pose(i, 1, Vector2(box.position.x + 112.0, g - absf(sin(_t * 1.7)) * 16.0), -1.0, Art.F_JUMP)
		_rope(Vector2(box.position.x + 44.0, g - 22.0), Vector2(box.position.x + 102.0, g - 24.0))
		UI.label(self, "W A S D", box.position.x + 34.0, g + 11.0, 12, Color(1, 1, 1, 0.48))
		UI.label(self, "↑ ← →", box.position.x + 112.0, g + 11.0, 12, Color(1, 1, 1, 0.48))

	func _how_sync(box: Rect2, i: int) -> void:
		var g := box.end.y
		# 两条弧的真高是 v²/2g，一起跳那条多出 SYNC_BOOST 的一截正好看得见。
		var h1: float = Player.JUMP_VELOCITY * Player.JUMP_VELOCITY / (2.0 * Player.GRAVITY)
		var v2: float = Player.JUMP_VELOCITY + Tether.SYNC_BOOST
		var h2: float = v2 * v2 / (2.0 * Player.GRAVITY)
		var sc: float = 30.0 / h2
		_arc(Vector2(box.position.x + 14.0, g), 56.0, h1 * sc, Color(1, 1, 1, 0.26))
		_arc(Vector2(box.position.x + 78.0, g), 62.0, h2 * sc, Color("ffd166"))
		_pose(i, 0, Vector2(box.position.x + 18.0, g), 1.0, Art.F_IDLE)
		_pose(i, 1, Vector2(box.position.x + 134.0, g - h2 * sc + 2.0), 1.0, Art.F_JUMP)
		UI.label(self, "+%.0f" % Tether.SYNC_BOOST, box.position.x + 110.0, box.position.y + 6.0, 13, Color("ffd166"))

	func _how_stomp(box: Rect2, i: int) -> void:
		var g := box.end.y
		var head_y: float = g - 22.0
		var high_y: float = box.position.y + 4.0
		_pose(i, 0, Vector2(box.position.x + 52.0, g), 1.0, Art.F_IDLE)
		# 落下、顶住、弹起：一条循环把三个动作讲完，比一张静止的叠立图老实。
		var q: float = fposmod(_t * 0.5, 1.0)
		var dy: float
		if q < 0.5:
			var a := q / 0.5
			dy = lerpf(high_y, head_y, a * a)
		else:
			var b := (q - 0.5) / 0.5
			dy = lerpf(head_y, high_y - 8.0, sqrt(b))
		_pose(i, 1, Vector2(box.position.x + 52.0, dy), 1.0, Art.F_FALL if q < 0.5 else Art.F_JUMP)
		_arrow(Vector2(box.position.x + 106.0, box.position.y + 6.0), Vector2(box.position.x + 106.0, head_y), Color(1, 1, 1, 0.35))
		_arrow(Vector2(box.position.x + 126.0, head_y), Vector2(box.position.x + 126.0, box.position.y + 4.0), Color("ffd166"))

	func _how_pulley(box: Rect2, i: int) -> void:
		var wheel := Vector2(box.get_center().x, box.position.y + 10.0)
		Art.draw_env_spin(self, "pulley", wheel, 30.0, _t * 1.6)
		var k: float = 0.5 + 0.4 * sin(_t * 1.05)
		var ly: float = lerpf(box.position.y + 34.0, box.end.y - 2.0, k)
		var ry: float = lerpf(box.end.y - 2.0, box.position.y + 34.0, k)
		draw_line(wheel + Vector2(-14.0, 3.0), Vector2(wheel.x - 14.0, ly), Color(0.20, 0.14, 0.28, 0.95), 3.0, true)
		draw_line(wheel + Vector2(14.0, 3.0), Vector2(wheel.x + 14.0, ry), Color(0.20, 0.14, 0.28, 0.95), 3.0, true)
		_pose(i, 0, Vector2(wheel.x - 14.0, ly), 1.0, Art.F_IDLE)
		_pose(i, 1, Vector2(wheel.x + 14.0, ry), -1.0, Art.F_IDLE)

	# 一位站在高处当轴，另一位挂在绳上：把绳画成从轴那侧的台沿垂下去的，钟摆就在
	# 台子外面晃，两者不会叠在一起。
	func _how_swing(box: Rect2, i: int, cap: String) -> void:
		var ledge := Rect2(box.position.x + 2.0, box.position.y + 18.0, 46.0, 11.0)
		Art.round_rect(self, ledge, 5.0, Art.cap_body(cap))
		Art.draw_cap(self, cap, ledge.position.x, ledge.position.y + 4.0, ledge.size.x, 8.0)
		var anchor := Vector2(ledge.end.x - 4.0, box.position.y + 2.0)
		_pose(i, 0, Vector2(ledge.position.x + 16.0, ledge.position.y), 1.0, Art.F_IDLE)
		# 半径就是绳长，所以那条黄色引导弧和熊走的轨迹是同一个圆。
		var radius := 44.0
		var ang: float = 0.3 + 0.55 * absf(sin(_t * 1.3))
		var bob := anchor + Vector2(sin(ang) * radius, cos(ang) * radius)
		_rope(anchor, bob)
		_pose(i, 1, bob, 1.0, Art.F_FALL)
		draw_arc(anchor, radius, PI * 0.5 - 0.85, PI * 0.5 - 0.3, 20, Color("ffd166"), 1.6, true)

	func _how_plate(box: Rect2, i: int) -> void:
		var g := box.end.y
		_plate(Vector2(box.position.x + 32.0, g), Color("ffd166"))
		Art.draw_env(self, "crate", Vector2(box.position.x + 32.0, g), 34.0)
		_plate(Vector2(box.end.x - 44.0, g), Color("63d9a6"))
		Art.draw_env(self, "gate", Vector2(box.end.x - 6.0, g), 44.0, false, 0.85)
		_pose(i, 0, Vector2(box.position.x + 98.0, g), 1.0, Art.F_RUN_A)

	func _how_ice(box: Rect2, i: int) -> void:
		var far := float(_skid(ICE_GRIP))
		var near := float(_skid(1.0))
		var sc: float = (box.size.x - 42.0) / maxf(far, 1.0)
		var y0: float = box.position.y + 8.0
		_bar(Vector2(box.position.x + 16.0, y0), near * sc, Color("9fe0c0"))
		_bar(Vector2(box.position.x + 16.0, y0 + 18.0), far * sc, Color("ffd166"))
		_pose(i, 1, Vector2(box.position.x + 16.0 + far * sc, box.end.y), 1.0, Art.F_FALL)
		UI.label_left(self, "平地 %d" % int(near), box.position.x + 20.0 + near * sc, y0 + 7.0, 12, Color(1, 1, 1, 0.5))
		UI.label_left(self, "冰 %d" % int(far), box.position.x + 20.0 + far * sc, y0 + 25.0, 12, Color("ffe9a8"))

	func _how_stars(box: Rect2, i: int) -> void:
		var g := box.end.y
		Art.draw_env(self, "gate", Vector2(box.position.x + 26.0, g), 50.0, false, 0.95)
		_pose(i, 0, Vector2(box.position.x + 20.0, g), 1.0, Art.F_IDLE)
		_pose(i, 1, Vector2(box.position.x + 46.0, g), -1.0, Art.F_IDLE)
		Art.draw_env(self, "coin", Vector2(box.end.x - 28.0, g - 28.0 - sin(_t * 2.4) * 4.0), 18.0)
		_plate(Vector2(box.end.x - 62.0, g), Color("ffd166"))
		# 三颗星按顺序亮起来再清空：这个循环本身就是三星规则。
		UI.pips(self, Vector2(box.get_center().x + 6.0, box.position.y + 8.0), int(fposmod(_t * 0.9, 4.2)), 8.0, 22.0)

	func _floor(box: Rect2, cap: String, biome: Dictionary) -> void:
		var col: Color = Color(biome.get("near", Color.WHITE))
		col.a = 0.42
		draw_rect(Rect2(box.position.x, box.end.y, box.size.x, 4.0), col)
		Art.draw_cap(self, cap, box.position.x, box.end.y, box.size.x, 12.0)

	func _plate(at: Vector2, col: Color) -> void:
		Art.draw_env(self, "plate", at, 26.0)
		Art.round_rect(self, Rect2(at.x - 15.0, at.y - 8.0, 30.0, 5.0), 2.5, col)

	func _bar(from: Vector2, w: float, col: Color) -> void:
		Art.round_rect(self, Rect2(from.x, from.y, maxf(4.0, w), 7.0), 3.5, Color(col.r, col.g, col.b, 0.8))

	func _arc(from: Vector2, w: float, h: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i: int in range(13):
			var t: float = float(i) / 12.0
			pts.append(from + Vector2(t * w, -4.0 * h * t * (1.0 - t)))
		for i: int in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], col, 2.2, true)

	func _arrow(from: Vector2, to: Vector2, col: Color) -> void:
		draw_line(from, to, col, 2.4, true)
		var d: Vector2 = (to - from).normalized()
		var n := Vector2(-d.y, d.x)
		draw_line(to, to - d * 7.0 + n * 4.0, col, 2.4, true)
		draw_line(to, to - d * 7.0 - n * 4.0, col, 2.4, true)

	func _rope(a: Vector2, b: Vector2) -> void:
		var sag: float = Tether.SAG_RATIO * a.distance_to(b) * 0.45
		var steps := 18
		var pts := PackedVector2Array()
		for i: int in range(steps + 1):
			var t: float = float(i) / float(steps)
			pts.append(a.lerp(b, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t)))
		for i: int in range(pts.size() - 1):
			var u: float = float(i) / float(maxi(steps - 1, 1))
			draw_line(pts[i], pts[i + 1], Art.ACCENT_COLORS[0].lerp(Art.ACCENT_COLORS[1], u), 2.4, true)

	func _pose(which: int, slot: int, at: Vector2, flip: float, frame: int) -> void:
		var k := clampi(which * 2 + slot, 0, _poses.size() - 1)
		var p: Pose = _poses[k]
		p.position = at
		p.flip = flip
		# 一号熊和二号熊轮流坐每个格子，教学页上出现的脸和它们讲的永远是同一对。
		p.index = (which * 2 + slot) % 2
		p.frame = frame
