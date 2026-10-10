extends Node

# Headless level validator. Run:
#   godot --headless --path . res://tools/level_check.tscn
# It is a scene rather than a --script so the autoloads exist; no window is
# opened and the save file is never touched. Physics limits come back out of
# player.gd / tether.gd and the door + plate boxes out of level_base.gd's own
# classes, so retuning the game shows up here instead of quietly invalidating
# this file.

const LEVEL_SCRIPTS := [
	"res://scripts/levels/level_01.gd",
	"res://scripts/levels/level_02.gd",
	"res://scripts/levels/level_03.gd",
	"res://scripts/levels/level_04.gd",
	"res://scripts/levels/level_05.gd",
	"res://scripts/levels/level_06.gd",
	"res://scripts/levels/level_07.gd",
	"res://scripts/levels/level_08.gd",
	"res://scripts/levels/level_09.gd",
	"res://scripts/levels/level_10.gd",
	"res://scripts/levels/level_11.gd",
	"res://scripts/levels/level_12.gd",
]
const CHECKPOINT_BOX := Vector2(52.0, 60.0)
const PLAYER_BOX := Vector2(26.0, 36.0)
const PAD_W := 58.0
const CRATE := Vector2(46.0, 46.0)

var _fails := 0
var _warns := 0
var _tag := ""
var _bounds := Vector2.ZERO
var _solids: Array[Rect2] = []
var _posts: Array[Vector2] = []
var _fans: Array[Rect2] = []
var _speed := 0.0
var _gravity := 0.0
var _jump := {}
var _sync := {}
var _boost := {}
var _door_size := Vector2.ZERO
var _plate_size := Vector2.ZERO


func _ready() -> void:
	print("=== 一二布布 关卡自检 ===")
	var pc: Dictionary = (load("res://scripts/player.gd") as GDScript).get_script_constant_map()
	var tc: Dictionary = (load("res://scripts/tether.gd") as GDScript).get_script_constant_map()
	_speed = float(pc.SPEED)
	_gravity = float(pc.GRAVITY)
	_jump = _arcs(float(pc.JUMP_VELOCITY), _speed, _gravity)
	_sync = _arcs(float(pc.JUMP_VELOCITY) + float(tc.SYNC_BOOST), _speed, _gravity)
	_boost = _arcs(float(pc.STOMP_BOUNCE), _speed, _gravity)

	var lb: Dictionary = (load("res://scripts/level_base.gd") as GDScript).get_script_constant_map()
	var door: Object = (lb.GoalDoor as GDScript).new(Vector2.ZERO, "cap_grass")
	_door_size = door.frame
	door.free()
	var plate: Object = (lb.Plate as GDScript).new(Vector2.ZERO, Color.WHITE)
	_plate_size = plate.board
	plate.free()
	print("    单跳 %.0f 高 / %.0f 远 · 同心跳 %.0f 高 / %.0f 远 · 踩头 %.0f 高 / %.0f 远 · 门 %s · 板 %s" % [
		_jump.rise, _jump.reach, _sync.rise, _sync.reach, _boost.rise, _boost.reach,
		_door_size, _plate_size
	])
	print("")

	for i: int in range(LEVEL_SCRIPTS.size()):
		_tag = "第 %d 关" % (i + 1)
		var script: GDScript = load(LEVEL_SCRIPTS[i])
		var instance: Object = script.new()
		var data: Dictionary = instance.level_data()
		instance.free()
		print("--- %s · %s" % [_tag, String(data.get("name", ""))])
		_check(data)
		print("")

	if _fails == 0 and _warns == 0:
		print("全部通过：0 失败 · 0 提醒")
	else:
		print("合计 %d 失败 · %d 提醒" % [_fails, _warns])
	get_tree().quit(1 if _fails > 0 else 0)


func _arcs(v: float, speed: float, gravity: float) -> Dictionary:
	return {"v": v, "rise": v * v / (2.0 * gravity), "reach": speed * (2.0 * v / gravity)}


func _check(d: Dictionary) -> void:
	var missing := false
	for key: String in ["name", "hint", "bounds", "sky", "biome", "spawns", "goal"]:
		if not d.has(key):
			_hard(false, "缺少字段 %s" % key)
			missing = true
	if missing:
		return
	_bounds = d["bounds"]
	_solids = []
	_posts = []
	_fans = []
	for e: Array in d.get("pulleys", []):
		_posts.append(Vector2(float(e[0]), float(e[1])))
	for e: Dictionary in d.get("fans", []):
		_fans.append(Rect2(e.at.x, e.at.y, float(e.box.x), float(e.box.y)))
	for key: String in ["platforms", "crumbles"]:
		for e: Array in d.get(key, []):
			var r := Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3]))
			_hard(r.size.x > 0.0 and r.size.y > 0.0, "%s %s 尺寸为 0" % [key, r.position])
			# Ground slabs deliberately hang below the world edge; only the walking
			# surface and the horizontal extent have to stay inside the level.
			_in_bounds(Vector2(r.position.x, r.position.y), "%s %s" % [key, r.position])
			_hard(r.end.x <= _bounds.x, "%s %s 右端伸出了 bounds" % [key, r.position])
			_solids.append(r)
	for e: Array in d.get("belts", []):
		var r := Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3]))
		_in_bounds(Vector2(r.position.x, r.position.y), "传送带 %s" % r.position)
		_hard(r.end.x <= _bounds.x, "传送带 %s 右端伸出了 bounds" % r.position)
		_solids.append(r)

	var rope: float = float(d.get("rope", 300.0))
	_hard(rope > 120.0, "绳长 %.0f 太短，两人会被绳锁死" % rope)
	_hard((d["sky"] as Array).size() == 2, "sky 需要上下两个颜色")
	_hard((d["spawns"] as Array).size() == 2, "spawns 必须是两个出生点")

	var surfaces := _surfaces(d)
	var goal: Vector2 = d["goal"]
	var door := Rect2(goal.x, goal.y, _door_size.x, _door_size.y)
	_in_bounds(door.end, "大门右下角")
	var door_surface := _surface_top(door.get_center().x, door.end.y)
	_hard(door_surface >= 0.0, "大门底边没有踩在任何平台上")
	_hard(_surface_top(door.position.x + 18.0, door.end.y) >= 0.0
		and _surface_top(door.end.x - 18.0, door.end.y) >= 0.0,
		"大门两侧超出了所在平台，两个人挤不进门")

	_check_spawns(d, rope)
	_check_plates(d, rope)
	_check_props(d)
	_check_movers(d)
	_check_new(d)
	_check_coins(d, surfaces)
	_connectivity(d, surfaces, door_surface, goal, rope)


func _check_spawns(d: Dictionary, rope: float) -> void:
	var spawns: Array = d["spawns"]
	var gap: float = (spawns[0] as Vector2).distance_to(spawns[1] as Vector2)
	_hard(gap < rope, "出生点相距 %.0f，开局绳子就是直的（绳长 %.0f）" % [gap, rope])
	for i: int in range(spawns.size()):
		var at: Vector2 = spawns[i]
		_in_bounds(at, "出生点 %d" % i)
		var drop: float = _ground_below(at)
		_hard(drop >= 0.0 and drop < 70.0, "出生点 %d 脚下 %.0f px 内没有地面" % [i, drop])


func _check_plates(d: Dictionary, rope: float) -> void:
	var plates: Array = d.get("plates", [])
	# Two plates is the door's own rule (both bears, one each). A chapter that opens
	# its door some other way is free to use plates purely as puzzle switches.
	var for_door: bool = String(d.get("unlock", "plates")) != "free"
	if for_door:
		_hard(plates.size() == 2, "大门要两人各踩一块板，本关只有 %d 块" % plates.size())
	for i: int in range(plates.size()):
		var p := Vector2(float(plates[i][0]), float(plates[i][1]))
		_in_bounds(p, "压力板 %d" % (i + 1))
		var center := p.x + _plate_size.x * 0.5
		# A plate's origin sits above the slab it rests on, so the ground has to be
		# somewhere under the drawn box rather than exactly at its bottom edge.
		_hard(_rests_on(center, p.y, p.y + _plate_size.y + 12.0), "压力板 %d 悬空" % (i + 1))
		_hard(_rests_on(p.x + 4.0, p.y, p.y + _plate_size.y + 12.0)
			and _rests_on(p.x + _plate_size.x - 4.0, p.y, p.y + _plate_size.y + 12.0),
			"压力板 %d 有一半探在平台外" % (i + 1))
		if not for_door:
			continue
		for j: int in range(i + 1, plates.size()):
			var q := Vector2(float(plates[j][0]), float(plates[j][1]))
			var span: float = Vector2(center, p.y).distance_to(
				Vector2(q.x + _plate_size.x * 0.5, q.y))
			_hard(span <= rope - 30.0,
				"压力板 %d/%d 相距 %.0f，绳长只有 %.0f，两人踩不住" % [i + 1, j + 1, span, rope])
			# A crate is 46 wide and a plate 86, so two plates closer than a crate
			# plus its own width would let one box hold both switches at once.
			_hard(span >= 134.0, "压力板 %d/%d 只隔 %.0f，一只木箱就能同时压住两块" % [
				i + 1, j + 1, span
			])
	for i: int in range(d.get("latches", []).size()):
		var e: Array = d.latches[i]
		var at := Vector2(float(e[0]), float(e[1]))
		_in_bounds(at, "自锁按钮 %d" % (i + 1))
		_hard(_rests_on(at.x + _plate_size.x * 0.5, at.y, at.y + _plate_size.y + 12.0),
			"自锁按钮 %d 悬空" % (i + 1))


func _check_props(d: Dictionary) -> void:
	for e: Array in d.get("hazards", []):
		var r := Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3]))
		_in_bounds(r.end, "尖刺右下角")
		_hard(_surface_top(r.get_center().x, r.end.y) >= 0.0, "尖刺 %s 没有铺在地面上" % r.position)
	for e: Array in d.get("pads", []):
		var pad := Vector2(float(e[0]), float(e[1]))
		var power: float = float(e[2])
		_in_bounds(pad, "推进板")
		_hard(_rests_on(pad.x + 29.0, pad.y, pad.y + 30.0), "推进板 %s 悬空" % pad)
		_hard(power * power / (2.0 * _gravity) > float(_jump.rise),
			"推进板 %.0f 弹射高度不超过普通跳，摆了个寂寞" % power)
	for e: Array in d.get("checkpoints", []):
		var cp := Vector2(float(e[0]), float(e[1]))
		_in_bounds(cp, "旗帜")
		_hard(_rests_on(cp.x + CHECKPOINT_BOX.x * 0.5, cp.y, cp.y + CHECKPOINT_BOX.y),
			"旗帜 %s 悬空" % cp)
		for i: int in range(2):
			var land := cp + Vector2(float(i) * 46.0 - 23.0, -30.0)
			var drop: float = _ground_below(land)
			_hard(drop >= 0.0 and drop < 90.0, "旗帜 %s 的重生点 %d 落不回平台（%.0f）" % [cp, i, drop])
	for e: Array in d.get("pulleys", []):
		_in_bounds(Vector2(float(e[0]), float(e[1])), "滑轮")


func _check_movers(d: Dictionary) -> void:
	var movers: Array = d.get("movers", [])
	for m: int in range(movers.size()):
		var mv: Dictionary = movers[m]
		var a: Vector2 = mv.a
		var b: Vector2 = mv.b
		var board: Vector2 = mv.board
		var speed: float = float(mv.get("speed", 95.0))
		_in_bounds(a, "移动平台 %d 起点" % (m + 1))
		_in_bounds(b + board, "移动平台 %d 终点右下角" % (m + 1))
		_hard(a.distance_to(b) > board.x * 0.6 or absf(a.y - b.y) > board.y * 2.0,
			"移动平台 %d 行程比板子还短，等于没动" % (m + 1))
		_hard(speed >= 40.0 and speed <= 200.0, "移动平台 %d 速度 %.0f，站着会不舒服" % [m + 1, speed])
		var swept := Rect2(a, board).merge(Rect2(b, board))
		for s: Rect2 in _solids:
			_hard(not swept.intersects(s.grow(-3.0)),
				"移动平台 %d 的行程与静态平台 %s 重叠" % [m + 1, s.position])
		var boardable := false
		for s: Rect2 in _solids:
			var dy: float = minf(a.y, b.y) - s.position.y
			var rise: float = maxf(0.0, -dy)
			var gap: float = maxf(0.0, _gap_x(
				Vector2(s.position.x, s.end.x), Vector2(swept.position.x, swept.end.x)) - PLAYER_BOX.x)
			for arc: Dictionary in [_jump, _sync, _boost]:
				if rise <= float(arc.rise) and gap <= _arc_reach(float(arc.v), dy):
					boardable = true
		_hard(boardable, "移动平台 %d 没有任何静态平台跳得上去" % (m + 1))


func _check_new(d: Dictionary) -> void:
	# Crumbling steps are in _solids like any other floor, so they must be compared
	# against the static slabs only — otherwise every one of them overlaps itself.
	var statics: Array[Rect2] = []
	for e: Array in d.get("platforms", []):
		statics.append(Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])))
	for e: Array in d.get("crumbles", []):
		var r := Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3]))
		_in_bounds(Vector2(r.position.x, r.position.y), "碎台 %s" % r.position)
		_hard(r.end.x <= _bounds.x, "碎台 %s 右端伸出了 bounds" % r.position)
		for s: Rect2 in statics:
			_hard(not r.intersects(s.grow(-2.0)), "碎台 %s 与实体 %s 重叠" % [r.position, s.position])
	for e: Array in d.get("belts", []):
		var speed: float = float(e[5])
		_hard(speed >= 60.0 and speed <= 200.0, "传送带速度 %.0f，站着会被拖得很惨" % speed)
		_hard(absf(float(e[4])) == 1.0, "传送带方向必须是 1 或 -1")
	for e: Dictionary in d.get("saws", []):
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var size: float = float(e.get("size", 46.0))
		var speed: float = float(e.get("speed", 92.0))
		_in_bounds(a, "锯片起点")
		_in_bounds(b, "锯片终点")
		_hard(speed >= 40.0 and speed <= 190.0, "锯片速度 %.0f 不在能读出来(range)的范围内" % speed)
		# A blade that spends any part of its run inside the slab it rides on is
		# invisible half the time, which is the one thing a hazard may never be.
		var swept := Rect2(a, Vector2(0, 0)).merge(Rect2(b, Vector2(0, 0))).grow(size * 0.38)
		for s: Rect2 in _solids:
			_soft(not swept.intersects(s.grow(2.0)), "锯片 %s-%s 的轨道穿进了实体 %s" % [a, b, s.position])
	for e: Dictionary in d.get("sweepers", []):
		var at: Vector2 = e.at
		var arm: float = float(e.get("arm", 180.0))
		var period: float = float(e.get("period", 3.4))
		_in_bounds(at, "吊摆支点")
		_hard(arm >= 110.0 and arm <= 340.0, "吊摆臂长 %.0f 不合理" % arm)
		_hard(period >= 2.2 and period <= 7.0, "吊摆周期 %.1f 秒，要么读不出来要么等得烦" % period)
		_hard(at.y + arm + 24.0 <= _bounds.y, "吊摆 %s 会甩到世界外" % at)
	for e: Dictionary in d.get("fans", []):
		var at: Vector2 = e.at
		var box: Vector2 = e.box
		var lift: float = float(e.get("lift", 2400.0))
		_in_bounds(at, "风柱")
		_in_bounds(at + box, "风柱右下角")
		_hard(lift > _gravity, "风柱升力 %.0f 小于重力 %.0f，那是装饰不是电梯" % [lift, _gravity])
		# A column with no floor under it is a wall of air nobody finds.
		var over_floor := false
		for s: Rect2 in _solids:
			if s.position.y >= at.y and s.position.y <= at.y + box.y + 30.0 \
					and _gap_x(Vector2(at.x, at.x + box.x), Vector2(s.position.x, s.end.x)) == 0.0:
				over_floor = true
		_hard(over_floor, "风柱 %s 底下没有落脚的平台" % at)
	for e: Array in d.get("barriers", []):
		var r := Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3]))
		_in_bounds(Vector2(r.position.x, r.position.y), "闸门")
		_hard(_surface_top(r.get_center().x, r.end.y) >= 0.0, "闸门 %s 没有立在任何平台上" % r.position)
		_hard(e.size() > 4, "闸门 %s 没有接任何按钮" % r.position)
		var n: int = d.get("plates", []).size() + d.get("latches", []).size()
		for k: int in range(4, e.size()):
			_hard(int(e[k]) >= 0 and int(e[k]) < n, "闸门 %s 接到不存在的开关 %d" % [r.position, int(e[k])])
	for e: Array in d.get("crates", []):
		var at := Vector2(float(e[0]), float(e[1]))
		_in_bounds(at, "木箱")
		var drop: float = _ground_below(at)
		_hard(drop >= 0.0 and drop < 60.0, "木箱 %s 脚下 %.0f px 内没有地面" % [at, drop])
	for e: Array in d.get("prompts", []):
		_in_bounds(Vector2(float(e[0]), float(e[1])), "提示牌")
		_hard(String(e[2]).length() <= 12, "提示牌文字太长：%s" % String(e[2]))


func _check_coins(d: Dictionary, surfaces: Array[Dictionary]) -> void:
	for e: Array in d.get("coins", []):
		var c := Vector2(float(e[0]), float(e[1]))
		_in_bounds(c, "金币")
		for s: Rect2 in _solids:
			_soft(not s.has_point(c), "金币 %s 埋进了实体里" % c)
		var gettable := false
		for surf: Dictionary in surfaces:
			var height: float = float(surf.y) - c.y
			if height > float(_jump.rise):
				continue
			if _gap_x(Vector2(float(surf.x0), float(surf.x1)), Vector2(c.x, c.x)) <= float(_sync.reach):
				gettable = true
		_soft(gettable, "金币 %s 从任何一块地面都够不到" % c)


func _surfaces(d: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Rect2 in _solids:
		out.append({"x0": s.position.x, "x1": s.end.x, "y": s.position.y, "mover": -1, "pad": _has_pad(d, s)})
	var movers: Array = d.get("movers", [])
	for m: int in range(movers.size()):
		var mv: Dictionary = movers[m]
		for end: String in ["a", "b"]:
			var at: Vector2 = mv[end]
			var board: Vector2 = mv.board
			out.append({"x0": at.x, "x1": at.x + board.x, "y": at.y, "mover": m, "pad": false})
	return out


func _has_pad(d: Dictionary, s: Rect2) -> bool:
	for e: Array in d.get("pads", []):
		if s.has_point(Vector2(float(e[0]) + 29.0, float(e[1]) + 20.0)):
			return true
	return false


func _pad_power(d: Dictionary) -> float:
	var best := 0.0
	for e: Array in d.get("pads", []):
		best = maxf(best, float(e[2]))
	return best


func _connectivity(d: Dictionary, surfaces: Array[Dictionary], door_surface: float, goal: Vector2, rope: float) -> void:
	if door_surface < 0.0 or surfaces.is_empty():
		return
	var target := -1
	for i: int in range(surfaces.size()):
		var s: Dictionary = surfaces[i]
		if int(s.mover) < 0 and absf(float(s.y) - door_surface) < 3.0 \
				and goal.x >= float(s.x0) - 4.0 and goal.x <= float(s.x1) + 4.0:
			target = i
	if target < 0:
		_hard(false, "大门所在的地面不在通行图里")
		return

	var spawns: Array = d["spawns"]
	var start := 0
	var best := 1e20
	for i: int in range(surfaces.size()):
		var s: Dictionary = surfaces[i]
		var cost: float = absf(float(s.y) - float(spawns[0].y)) + absf(float(s.x0) - float(spawns[0].x))
		if cost < best:
			best = cost
			start = i

	var pad_arc := _arcs(_pad_power(d), _speed, _gravity)
	var seen: Array[int] = [start]
	var prev: Dictionary = {}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nxt: int in range(surfaces.size()):
			if seen.has(nxt) or not _linked(surfaces[cur], surfaces[nxt], pad_arc, rope):
				continue
			seen.append(nxt)
			prev[nxt] = cur
			queue.append(nxt)
	if not seen.has(target):
		_hard(false, "从出生点出发到不了大门，通行图断开")
		return
	var chain: Array[int] = [target]
	while int(chain.back()) != start:
		chain.append(int(prev[chain.back()]))
	chain.reverse()
	var tags: Array[String] = []
	for c: int in chain:
		tags.append(_surface_tag(surfaces[c]))
	print("    通路 %d 段：%s" % [chain.size() - 1, " → ".join(tags)])


func _surface_tag(s: Dictionary) -> String:
	var mover: int = int(s.mover)
	return "梯%d(y=%.0f)" % [mover + 1, float(s.y)] if mover >= 0 else "台(x%.0f,y%.0f)" % [float(s.x0), float(s.y)]


func _linked(a: Dictionary, b: Dictionary, pad_arc: Dictionary, rope: float) -> bool:
	if int(a.mover) >= 0 and int(a.mover) == int(b.mover):
		return true
	var dy: float = float(b.y) - float(a.y)
	var rise: float = maxf(0.0, -dy)
	var gap := _edge_gap(a, b)
	for arc: Dictionary in [_jump, _sync, _boost]:
		if rise <= float(arc.rise) and gap <= _arc_reach(float(arc.v), dy):
			return true
	if bool(a.pad) and gap <= _arc_reach(float(pad_arc.v), dy):
		return true
	if _pulley_link(a, b, rope):
		return true
	if _fan_link(a, b):
		return true
	# A pendulum on the rope clears gaps no jump reaches, but only downhill and
	# only within one rope length of the anchor.
	return rise <= 0.0 and gap <= rope * 0.9


# An updraft buys height for free as long as you stay inside the column, so any
# surface that overhangs the same column is reachable from any other one in it.
func _fan_link(a: Dictionary, b: Dictionary) -> bool:
	if float(b.y) >= float(a.y):
		return false
	for f: Rect2 in _fans:
		var span := Vector2(f.position.x, f.end.x)
		if _gap_x(Vector2(float(a.x0), float(a.x1)), span) > 0.0:
			continue
		if _gap_x(Vector2(float(b.x0), float(b.x1)), span) > 0.0:
			continue
		if float(a.y) <= f.end.y + 40.0 and f.position.y <= float(b.y):
			return true
	return false


# The body is 26 px wide, so its centre can already be a half-body past the lip
# when it pushes off and only needs a toe on the far slab to land.
func _edge_gap(a: Dictionary, b: Dictionary) -> float:
	return maxf(0.0, _gap_x(
		Vector2(float(a.x0), float(a.x1)), Vector2(float(b.x0), float(b.x1))) - PLAYER_BOX.x)


# Landing further away takes longer when the target sits lower, so reach is a
# function of the height difference rather than a flat-ground constant.
func _arc_reach(v: float, dy: float) -> float:
	var disc: float = v * v + 2.0 * _gravity * dy
	if disc <= 0.0:
		return 0.0
	return _speed * (v + sqrt(disc)) / _gravity


# The rope threaded over a wheel turns one player's walk into the other's lift,
# which is the only way up in the pulley chapters. Both sides have to fit along
# the rope with the wheel as the bend.
func _pulley_link(a: Dictionary, b: Dictionary, rope: float) -> bool:
	for post: Vector2 in _posts:
		var a_left: bool = float(a.x1) <= post.x
		var b_right: bool = float(b.x0) >= post.x
		if not ((a_left and b_right) or (float(b.x1) <= post.x and float(a.x0) >= post.x)):
			continue
		var near_a := Vector2(
			post.x if post.x >= float(a.x0) and post.x <= float(a.x1)
			else (float(a.x0) if post.x < float(a.x0) else float(a.x1)), float(a.y))
		var near_b := Vector2(
			post.x if post.x >= float(b.x0) and post.x <= float(b.x1)
			else (float(b.x0) if post.x < float(b.x0) else float(b.x1)), float(b.y))
		if near_a.distance_to(post) + near_b.distance_to(post) <= rope:
			return true
	return false


func _gap_x(a: Vector2, b: Vector2) -> float:
	# a and b are Vector2(interval_start, interval_end); 0 means they overlap.
	if b.x > a.y:
		return b.x - a.y
	if a.x > b.y:
		return a.x - b.y
	return 0.0


func _surface_top(x: float, y: float) -> float:
	for s: Rect2 in _solids:
		if x >= s.position.x - 3.0 and x <= s.end.x + 3.0 and absf(s.position.y - y) < 5.0:
			return s.position.y
	return -1.0


# True when some platform's top surface crosses the vertical window [y0, y1] at
# x — the shape props are all anchored a little above the slab they stand on.
func _rests_on(x: float, y0: float, y1: float) -> bool:
	for s: Rect2 in _solids:
		if x >= s.position.x - 3.0 and x <= s.end.x + 3.0 and s.position.y >= y0 - 5.0 \
				and s.position.y <= y1 + 5.0:
			return true
	return false


func _ground_below(at: Vector2) -> float:
	var best := 1e20
	for s: Rect2 in _solids:
		if at.x < s.position.x or at.x > s.end.x:
			continue
		if s.position.y >= at.y and s.position.y - at.y < best:
			best = s.position.y - at.y
	return -1.0 if best == 1e20 else best


func _in_bounds(at: Vector2, what: String) -> void:
	_hard(at.x >= 0.0 and at.y >= 0.0 and at.x <= _bounds.x and at.y <= _bounds.y,
		"%s %s 超出了 bounds %s" % [what, at, _bounds])


func _hard(ok: bool, message: String) -> void:
	if ok:
		return
	_fails += 1
	print("  [FAIL] ", message)


func _soft(ok: bool, message: String) -> void:
	if ok:
		return
	_warns += 1
	print("  [WARN] ", message)
