class_name M3UI
extends RefCounted

# Three screens for the puzzle mode: a front door, a chapter grid, and the board
# itself. They are drawn the same way the adventure game draws its menus — one
# Control painting itself in _draw() — so the two modes cannot look like two games.


static func _bg(ci: CanvasItem, biome_id: String, t: float, world: String) -> void:
	var biome: Dictionary = Biomes.get_def(biome_id)
	var area := Rect2(Vector2.ZERO, ci.get_viewport_rect().size)
	var sky: Array = biome.get("sky", [Color("5b3f8f"), Color("ffd6c0")])
	UI.sky(ci, area, Color(sky[0]), Color(sky[1]))
	var step := 0
	for pair: Array in [["bg_far", "far", 0.40], ["bg_mid", "mid", 0.34], ["bg_near", "near", 0.28]]:
		var tex := Art.env(String(pair[0]))
		if tex == null:
			continue
		var col: Color = Color(biome.get(pair[1], Color.WHITE))
		var drift: float = sin(t * 0.16 + float(step)) * 10.0
		col.a = 0.5 + float(step) * 0.2
		var hh: float = area.size.y * float(pair[2])
		ci.draw_texture_rect(
			tex,
			Rect2(drift - 20.0, area.size.y - hh + float(step) * 14.0, area.size.x + 40.0, hh),
			false, col
		)
		step += 1
	if not world.is_empty():
		UI.label(ci, world, area.size.x * 0.5, 40.0, 20, Color(1, 1, 1, 0.62))


static func _tile_icon(ci: CanvasItem, id: String, at: Vector2, size: float) -> void:
	if M3Levels.is_face(id):
		var tex := Art.frame_tex(M3Levels.face_index(id), Art.F_IDLE)
		if tex == null:
			return
		var s := size / Art.STAND_H
		var w: float = Art.CELL_W * s
		var hh: float = Art.CELL_H * s
		ci.draw_set_transform(at, 0.0, Vector2(1.0 if M3Levels.face_index(id) == 0 else -1.0, 1.0))
		ci.draw_texture_rect(tex, Rect2(-Vector2(w, hh) * 0.5 + Vector2(0, hh * 0.08), Vector2(w, hh)), false)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var tex2 := M3Levels.art_tex(id)
	if tex2 == null:
		return
	var ratio := float(tex2.get_width()) / maxf(1.0, float(tex2.get_height()))
	var hh2 := size
	var ww2 := size * ratio
	if ww2 > size:
		ww2 = size
		hh2 = size / maxf(0.05, ratio)
	ci.draw_texture_rect(tex2, Rect2(at - Vector2(ww2, hh2) * 0.5, Vector2(ww2, hh2)), false)


class Home extends Control:
	var _menu := UI.MenuNav.new()
	var _b0: UI.Buddy
	var _b1: UI.Buddy
	var _t := 0.0
	var _help := false

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.size = 26
		_menu.row = 48.0
		_menu.add("开 始 消 消 乐")
		_menu.add("继 续 下 去", Game.m3_unlocked > 1)
		_menu.add("选 择 局 数", Game.m3_unlocked > 1)
		_menu.add("玩 法")
		_menu.add("回 闯 关 模 式")
		_b0 = UI.Buddy.new()
		_b0.scale = Vector2(1.5, 1.5)
		add_child(_b0)
		_b1 = UI.Buddy.new()
		_b1.index = 1
		_b1.flip = -1.0
		_b1.scale = Vector2(1.5, 1.5)
		add_child(_b1)

	func _input(event: InputEvent) -> void:
		if _help:
			if event is InputEventKey and event.pressed and not event.echo:
				var k := _key(event)
				if k == KEY_ESCAPE or k == KEY_SPACE or k == KEY_ENTER or k == KEY_H:
					_help = false
					Sfx.play("select")
			elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				_help = false
			return
		var picked: int = _menu.feed(self, event)
		if picked < 0:
			return
		match picked:
			0:
				_launch(clampi(Game.m3_unlocked - 1, 0, M3Levels.count() - 1))
			1:
				_launch(clampi(Game.m3_unlocked - 1, 0, M3Levels.count() - 1))
			2:
				_pick()
			3:
				_help = true
				Sfx.play("select")
			4:
				Game.go_platform()

	func _key(event: InputEvent) -> int:
		var ev := event as InputEventKey
		return ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode

	func _launch(index: int) -> void:
		Game.open_m3(index)

	func _pick() -> void:
		Game.open_m3_pick()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		M3UI._bg(self, "dusk", _t, "")
		var cx: float = vp.x * 0.5
		UI.label(self, "一二布布 · 消消乐", cx, vp.y * 0.16 + 40.0, 54, Color("fff6ea"))
		UI.label(self, "一 根 绳 的 另 一 种 玩 法", cx, vp.y * 0.16 + 74.0, 20, Color("ffd9e6"))
		var by: float = vp.y * 0.34
		var beat: float = absf(sin(_t * 2.0)) * 12.0
		_b0.position = Vector2(cx - 132.0, by - beat)
		_b1.position = Vector2(cx + 132.0, by - absf(sin(_t * 2.0 + 0.8)) * 12.0)
		for k: int in range(4):
			var id: String = String(["coin", "crystal", "mushroom", "flower"][k])
			var at := Vector2(cx - 168.0 + float(k) * 112.0, by + 58.0 + sin(_t * 1.8 + float(k)) * 5.0)
			M3UI._tile_icon(self, id, at, 44.0)
		_menu.cx = cx
		_menu.top = vp.y * 0.50
		_menu.draw(self, _t)
		UI.label(
			self, "已解锁 %d / %d 局 · 同心 %d / %d 星" % [
				Game.m3_unlocked, M3Levels.count(), Game.m3_total_stars(), M3Levels.count() * 3
			],
			cx, vp.y * 0.50 - 26.0, 18, Color("ffe9a8")
		)
		UI.label(self, "↑ ↓ 选择 · 空格 确认 · 也可以直接用鼠标点", cx, vp.y - 66.0, 18, Color(1, 1, 1, 0.5))
		UI.label(self, "换相邻的两个，三个同色就连成线 · 四个出爆破条 · 五个出彩虹球", cx, vp.y - 40.0, 19, Color(1, 1, 1, 0.72))
		if _help:
			_help_panel(vp)

	func _help_panel(vp: Vector2) -> void:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.04, 0.12, 0.78))
		var r := Rect2(vp.x * 0.5 - 430.0, vp.y * 0.16, 860.0, vp.y * 0.7)
		Art.round_rect(self, r, 20.0, Color(0.12, 0.08, 0.22, 0.94))
		Art.round_rect_outline(self, r.grow(2.0), 22.0, Color(1, 1, 1, 0.25), 2.2)
		var cx: float = vp.x * 0.5
		UI.label(self, "玩 法", cx, r.position.y + 44.0, 32, Color("fff6ea"))
		var rows: Array[Array] = [
			["coin", "三个同色连成一线就消掉，上面的补下来，连锁越深分越高。"],
			["crystal", "四个连成一排：留下爆破条，炸开它所在的整行或整列。"],
			["mushroom", "拐个 L 形：留下炸弹，炸掉周围 3×3。"],
			["flower", "五个连成一排：留下彩虹球，跟任意一块换位就清掉那一整色。"],
			["icicle", "冰块不能换也不能消，只能在它旁边消一次，敲薄一层。"],
			["bamboo", "步数用完前凑齐左边的目标物就过关；分数过两条线才给二三星。"],
		]
		for k: int in range(rows.size()):
			var at := Vector2(r.position.x + 52.0, r.position.y + 96.0 + float(k) * 62.0)
			M3UI._tile_icon(self, String(rows[k][0]), at, 40.0)
			UI.label_left(self, String(rows[k][1]), at.x + 34.0, at.y + 7.0, 20, Color("fff6ea"))
		UI.label(self, "H 提示一步 · R 重开本局 · ESC 返回", cx, r.end.y - 28.0, 19, Color(1, 1, 1, 0.6))
		UI.label(self, "空格 / 点一下 关闭", cx, r.end.y - 54.0, 18, UI.tint(_t))

class Pick extends Control:
	var _cards: Array[Rect2] = []
	var _sel := 0
	var _cols := 1
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sel = clampi(Game.m3_unlocked - 1, 0, M3Levels.count() - 1)

	func _layout(vp: Vector2) -> void:
		_cards.clear()
		_cols = 5
		var gx := 16.0
		var gy := 18.0
		var cw: float = (vp.x - 120.0 - gx * float(_cols - 1)) / float(_cols)
		var ch := 108.0
		var y0: float = vp.y * 0.22
		for i: int in range(M3Levels.count()):
			_cards.append(
				Rect2(
					60.0 + float(i % _cols) * (cw + gx),
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
				KEY_ESCAPE:
					Game.m3_home()
			return
		if event is InputEventMouseMotion:
			_hover(false)
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			if _hover(true):
				_pick(_sel)

	func _move(d: int) -> void:
		var next := clampi(_sel + d, 0, _cards.size() - 1)
		if next != _sel:
			_sel = next
			Sfx.play("select")

	func _hover(click: bool) -> bool:
		var m: Vector2 = get_global_mouse_position()
		for i: int in range(_cards.size()):
			if not _cards[i].has_point(m) or not Game.m3_is_unlocked(i):
				continue
			if i != _sel:
				_sel = i
				Sfx.play("select")
			return click
		return false

	func _pick(i: int) -> void:
		if not Game.m3_is_unlocked(i):
			Sfx.play("taut")
			return
		Sfx.play("start")
		Game.open_m3(i)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		M3UI._bg(self, "meadow", _t, "")
		var cx: float = vp.x * 0.5
		UI.label(self, "选 择 局 数", cx, vp.y * 0.115, 36, Color("fff6ea"))
		UI.label(
			self, "同心 %d / %d 星" % [Game.m3_total_stars(), M3Levels.count() * 3],
			cx + UI.text_width("选 择 局 数", 36) * 0.5 + 66.0, vp.y * 0.115 - 2.0, 17, Color("ffe9a8")
		)
		_layout(vp)
		for i: int in range(_cards.size()):
			_card(_cards[i], i, i == _sel)
		UI.label(self, "← → 选择 · 空格 开局 · ESC 返回", cx, vp.y - 32.0, 18, Color(1, 1, 1, 0.5))

	func _card(r: Rect2, i: int, on: bool) -> void:
		var open_it: bool = Game.m3_is_unlocked(i)
		var d: Dictionary = M3Levels.get_def(i)
		var biome: Dictionary = Biomes.get_def(String(d.get("biome", "meadow")))
		var sky: Array = biome.get("sky", [Color("5b3f8f"), Color("ffd6c0")])
		Art.round_rect(self, r, 14.0, LevelBase.OUTLINE)
		Art.round_rect(
			self, r.grow(-3.0), 12.0,
			Color(0.16, 0.11, 0.26, 0.82) if open_it else Color(0.14, 0.10, 0.20, 0.55)
		)
		var band := Rect2(r.position.x + 4.0, r.position.y + 4.0, r.size.x - 8.0, 34.0)
		UI.sky(self, band, Color(sky[0]), Color(sky[1]))
		if on:
			Art.round_rect_outline(self, r.grow(1.0), 16.0, UI.tint(_t) if open_it else Color(1, 1, 1, 0.2), 2.4)
		var badge := Vector2(r.position.x + 24.0, r.position.y + 30.0)
		draw_circle(badge, 13.0, Color(1, 1, 1, 0.14 if open_it else 0.06))
		UI.label(self, str(i + 1), badge.x, badge.y + 5.0, 17, Color("ffe9a8") if open_it else Color(1, 1, 1, 0.28))
		var parts: PackedStringArray = String(d.name).split(" · ")
		var title: String = parts[parts.size() - 1]
		UI.label_left(
			self, title, r.position.x + 44.0, r.position.y + 66.0, 18,
			Color("fff6ea") if open_it else Color(1, 1, 1, 0.3)
		)
		if not open_it:
			UI.label(self, "锁", r.get_center().x, r.position.y + 96.0, 15, Color(1, 1, 1, 0.25))
			return
		UI.pips(self, Vector2(r.position.x + 26.0, r.position.y + 92.0), Game.m3_stars_of(i), 7.5, 18.0)
		var best: int = Game.m3_score_of(i)
		if best > 0:
			UI.label_right(self, str(best), r.end.x - 14.0, r.position.y + 96.0, 14, Color("cfe4ff"))
		else:
			UI.label_right(self, "%d 步" % int(d.moves), r.end.x - 14.0, r.position.y + 96.0, 14, Color(1, 1, 1, 0.35))


class Overlay extends Control:
	# The board is a child of Play, so anything Play paints in its own _draw() lands
	# under the tiles. The end-of-level panel has to sit on top of them, which is what
	# this node is for: it is added after the board and forwards its drawing to Play.
	var on_draw: Callable

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if on_draw.is_valid():
			on_draw.call(self)


class Play extends Control:
	var index := 0
	var board: M3Board
	var _overlay: Overlay
	var _t := 0.0
	var _awarded := false
	var _result := -1
	var _result_t := 0.0
	var _buttons: Array[Rect2] = []
	var _result_buttons: Array[Rect2] = []
	var _flash := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var def: Dictionary = M3Levels.get_def(index)
		board = M3Board.new()
		board.name = "Board"
		add_child(board)
		_overlay = Overlay.new()
		_overlay.name = "ResultOverlay"
		_overlay.on_draw = _draw_overlay
		add_child(_overlay)
		board.setup(def, int(Time.get_ticks_msec()) ^ (index * 7919))
		board.on_settled = _on_settled
		Sfx.set_music(String(def.get("biome", "meadow")))

	func _on_settled() -> void:
		var m := board.model
		if m.state == M3Model.ST_PLAY:
			return
		if _awarded:
			return
		_awarded = true
		_result = 0 if m.state == M3Model.ST_WIN else 1
		_result_t = 0.0
		if _result == 0:
			var stars: int = m.stars()
			Game.m3_complete(index, stars, int(m.score))
			Sfx.play("win")
			_flash = 1.0
		else:
			Sfx.play("die")

	func _input(event: InputEvent) -> void:
		if not (event is InputEventKey) or not event.pressed or event.echo:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				_click((event as InputEventMouseButton).position)
			return
		var ev := event as InputEventKey
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		if _result >= 0:
			match k:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					if _result == 0:
						_next()
					else:
						_replay()
				KEY_R:
					_replay()
				KEY_ESCAPE:
					Game.open_m3_pick()
			return
		match k:
			KEY_H:
				board.ask_hint()
			KEY_R:
				_replay()
			KEY_ESCAPE:
				Game.m3_home()

	func _click(m: Vector2) -> void:
		var list: Array[Rect2] = _result_buttons if _result >= 0 else _buttons
		for i: int in range(list.size()):
			if not list[i].has_point(m):
				continue
			if _result >= 0:
				match i:
					0:
						if _result == 0:
							_next()
						else:
							_replay()
					1:
						_replay()
					2:
						Game.open_m3_pick()
			else:
				match i:
					0:
						board.ask_hint()
					1:
						_replay()
					2:
						Game.m3_home()
			Sfx.play("start")
			return

	func _replay() -> void:
		_awarded = false
		_result = -1
		board.restart()

	func _next() -> void:
		var nxt := index + 1
		if nxt >= M3Levels.count():
			Game.open_m3_pick()
		else:
			Game.open_m3(nxt)

	func _process(delta: float) -> void:
		_t += delta
		_result_t += delta
		_flash = maxf(0.0, _flash - delta * 1.6)
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var m := board.model
		var def: Dictionary = board.level
		M3UI._bg(self, String(def.get("biome", "meadow")), _t, "")
		_header(vp, m, def)
		_objectives(vp, m, def)
		if _result < 0:
			_buttons = _button_row(self, vp, [["提 示", "H"], ["重 开", "R"], ["换 局", "ESC"]])
		else:
			_buttons.clear()
		var hint: String = String(def.get("hint", ""))
		if not hint.is_empty() and _t < 12.0 and _result < 0:
			var alpha: float = clampf(12.0 - _t, 0.0, 1.0)
			var lines := UI.wrap(hint, 15, 300.0)
			var hy: float = 170.0 + float((def.objectives as Array).size()) * 64.0
			for i: int in range(lines.size()):
				UI.label_left(
					self, lines[i], 28.0, hy + float(i) * 22.0, 15, Color(1, 1, 1, 0.72 * alpha)
				)

	func _draw_overlay(ci: CanvasItem) -> void:
		var vp := get_viewport_rect().size
		if _flash > 0.0:
			ci.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, _flash * 0.22))
		if _result >= 0:
			_result_panel(ci, vp, board.model, board.level)

	func _header(vp: Vector2, m: M3Model, def: Dictionary) -> void:
		var r := Rect2(24.0, 18.0, 300.0, 66.0)
		Art.round_rect(self, r, 16.0, Color(0.12, 0.08, 0.22, 0.62))
		UI.label(self, String(def.name), r.get_center().x, 42.0, 20, Color("fff6ea"))
		UI.label(
			self, "%s · 第 %d / %d 局 · %d 色" % [
				M3Levels.world_name(index), index + 1, M3Levels.count(), (def.set as Array).size()
			],
			r.get_center().x, 66.0, 14, Color(1, 1, 1, 0.55)
		)
		var rr := Rect2(vp.x - 324.0, 18.0, 300.0, 66.0)
		Art.round_rect(self, rr, 16.0, Color(0.12, 0.08, 0.22, 0.62))
		UI.label(self, "分数 " + str(int(m.score)), rr.get_center().x, 42.0, 22, Color("ffe9a8"))
		_stars_bar(rr, m, def)
		# The move count is the one number that decides whether this run can still be
		# won, so it gets the biggest type on the screen.
		var low: bool = m.moves_left <= 5
		var left := Vector2(vp.x * 0.5 + 70.0, 52.0)
		UI.label(self, "剩 余 步 数", left.x, left.y - 16.0, 15, Color(1, 1, 1, 0.5))
		UI.label(self, str(m.moves_left), left.x, left.y + 26.0, 44, Color("ffd0d8") if low else Color("fff6ea"))

	func _stars_bar(rr: Rect2, m: M3Model, def: Dictionary) -> void:
		var cut: Array = def.get("star_scores", [])
		var top := float(cut[cut.size() - 1]) if cut.size() > 0 else 1000.0
		var f: float = clampf(float(m.score) / maxf(1.0, top), 0.0, 1.0)
		var bar := Rect2(rr.position.x + 22.0, rr.end.y - 15.0, rr.size.x - 44.0, 7.0)
		Art.round_rect(self, bar, 4.0, Color(1, 1, 1, 0.12))
		Art.round_rect(self, Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), 4.0, Color("ffd166"))
		for i: int in range(2):
			if cut.size() <= i:
				continue
			var mark: float = float(cut[i]) / maxf(1.0, top)
			draw_line(
				Vector2(bar.position.x + bar.size.x * mark, bar.position.y - 4.0),
				Vector2(bar.position.x + bar.size.x * mark, bar.end.y + 4.0),
				Color(1, 1, 1, 0.4), 1.6
			)
		UI.pips(self, Vector2(rr.get_center().x, rr.position.y + 58.0), m.projected_stars(), 6.2, 17.0)

	func _objectives(vp: Vector2, m: M3Model, def: Dictionary) -> void:
		var list: Array = def.get("objectives", [])
		var panel := Rect2(24.0, 100.0, 300.0, float(list.size()) * 64.0 + 40.0)
		Art.round_rect(self, panel, 16.0, Color(0.12, 0.08, 0.22, 0.55))
		UI.label_left(self, "目 标", panel.position.x + 20.0, panel.position.y + 28.0, 18, Color(1, 1, 1, 0.6))
		for i: int in range(list.size()):
			var o: Dictionary = m.objective_line(list[i])
			var odef: Dictionary = list[i]
			var is_ice: bool = String(odef.id) == "ice"
			var at := Vector2(panel.position.x + 34.0, panel.position.y + 66.0 + float(i) * 64.0)
			var done_it: bool = int(o.now) >= int(o.need)
			if is_ice:
				var r := Rect2(at - Vector2(18.0, 18.0), Vector2(36.0, 36.0))
				Art.round_rect(self, r, 8.0, Color(0.6, 0.82, 1.0, 0.5))
				Art.round_rect_outline(self, r, 8.0, Color(1, 1, 1, 0.6), 2.0)
			else:
				M3UI._tile_icon(self, String(odef.id), at, 40.0)
			UI.label_left(self, String(o.label), at.x + 30.0, at.y + 2.0, 18, Color("fff6ea"))
			var w_bar := 150.0
			var bar := Rect2(at.x + 30.0, at.y + 12.0, w_bar, 7.0)
			Art.round_rect(self, bar, 3.5, Color(1, 1, 1, 0.13))
			var f: float = clampf(float(o.now) / maxf(1.0, float(o.need)), 0.0, 1.0)
			Art.round_rect(
				self, Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), 3.5,
				Color("63d9a6") if done_it else Color("ffd166")
			)
			UI.label_right(
				self, "%d / %d" % [mini(int(o.now), int(o.need)), int(o.need)],
				bar.end.x + 22.0, at.y + 2.0, 16, Color("63d9a6") if done_it else Color(1, 1, 1, 0.7)
			)
		var rr := Rect2(vp.x - 324.0, 100.0, 300.0, 92.0)
		Art.round_rect(self, rr, 16.0, Color(0.12, 0.08, 0.22, 0.45))
		var cuts: Array = def.get("star_scores", [])
		var two := int(cuts[0]) if cuts.size() > 0 else 0
		var three := int(cuts[1]) if cuts.size() > 1 else 0
		UI.label_left(self, "二星 %d 分" % two, rr.position.x + 20.0, rr.position.y + 34.0, 16, Color("ffd166"))
		UI.label_left(self, "三星 %d 分" % three, rr.position.x + 20.0, rr.position.y + 60.0, 16, Color("ffe9a8"))
		UI.label_left(
			self, "最高 %d" % Game.m3_score_of(index), rr.position.x + 176.0, rr.position.y + 60.0,
			15, Color(1, 1, 1, 0.5)
		)

	func _button_row(ci: CanvasItem, vp: Vector2, specs: Array) -> Array[Rect2]:
		var out: Array[Rect2] = []
		var cx: float = vp.x * 0.5 + 70.0
		var y: float = vp.y - 60.0
		var w := 116.0
		var gap := 14.0
		var total: float = float(specs.size()) * w + float(specs.size() - 1) * gap
		for i: int in range(specs.size()):
			var r := Rect2(cx - total * 0.5 + float(i) * (w + gap), y - 18.0, w, 36.0)
			out.append(r)
			var arr: Array = specs[i]
			var hot: bool = r.has_point(get_global_mouse_position())
			Art.round_rect(ci, r, 12.0, Color(0.16, 0.10, 0.26, 0.72) if not hot else Color(0.26, 0.17, 0.4, 0.85))
			Art.round_rect_outline(ci, r, 12.0, Color(1, 1, 1, 0.2 if not hot else 0.5), 1.8)
			UI.label(ci, String(arr[0]), r.get_center().x, r.get_center().y + 6.0, 18, Color("fff6ea"))
			UI.label(ci, String(arr[1]), r.end.x - 18.0, r.position.y + 16.0, 12, Color(1, 1, 1, 0.4))
		return out

	func _result_panel(ci: CanvasItem, vp: Vector2, m: M3Model, def: Dictionary) -> void:
		ci.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.04, 0.12, 0.66))
		var k: float = clampf(_result_t / 0.28, 0.0, 1.0)
		var r := Rect2(vp.x * 0.5 - 260.0, vp.y * 0.5 - 132.0 + (1.0 - k) * 26.0, 520.0, 264.0)
		Art.round_rect(ci, r, 22.0, Color(0.11, 0.08, 0.2, 0.95))
		Art.round_rect_outline(ci, r.grow(2.0), 24.0, Color(1, 1, 1, 0.3), 2.4)
		var cx: float = vp.x * 0.5
		if _result == 0:
			UI.label(ci, "过 关 啦", cx, r.position.y + 48.0, 34, Color("fff6ea"))
			var shown := 0
			for i: int in range(m.stars()):
				if float(i) * 0.16 > _result_t - 0.2:
					break
				shown += 1
			UI.pips(ci, Vector2(cx, r.position.y + 92.0), shown, 15.0, 42.0)
			UI.label(
				ci, "%d 分 · 用了 %d 步" % [int(m.score), int(def.moves) - m.moves_left],
				cx, r.position.y + 138.0, 18, Color("ffd9e6")
			)
			UI.label(
				ci, "最高连锁 x%d · 碎冰 %d 块" % [m.chain_best, m.ice_broken],
				cx, r.position.y + 166.0, 17, Color(1, 1, 1, 0.6)
			)
			_result_buttons = _button_row(ci, vp, [["下 一 局", ""], ["再 玩 一 遍", "R"], ["选 局", ""]])
		else:
			UI.label(ci, "步 数 用 完 了", cx, r.position.y + 52.0, 32, Color("ffd0d8"))
			for o: Dictionary in (def.objectives as Array):
				var line: Dictionary = m.objective_line(o)
				var left: int = maxi(0, int(line.need) - int(line.now))
				if left <= 0:
					continue
				var at := Vector2(cx - 150.0, r.position.y + 100.0)
				M3UI._tile_icon(ci, String(o.id) if String(o.id) != "ice" else "icicle", at, 30.0)
				UI.label_left(
					ci, "%s 还差 %d" % [String(line.label), left], at.x + 26.0, at.y + 6.0,
					18, Color("fff6ea")
				)
				break
			UI.label(ci, "差一点，换个顺序再试一次", cx, r.position.y + 152.0, 17, Color(1, 1, 1, 0.6))
			_result_buttons = _button_row(ci, vp, [["重 新 开", ""], ["换 一 局", ""], ["选 局", ""]])
		if _result >= 0:
			UI.label(ci, "空格 继续", cx, r.end.y - 26.0, 16, Color(1, 1, 1, 0.45))
