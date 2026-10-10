extends Node

# Headless gate for the puzzle mode. Two halves: the rules are checked by placing
# boards by hand (a four-in-a-row must become a row blast, ice must never pop as if
# it were a tile), and the shipped levels are checked by playing them with a seeded
# greedy bot, so the star cuts and the move budget are measured rather than assumed.

const SIMS_PER_LEVEL := 6
const MIN_WIN_RATE_EARLY := 0.5
const MIN_WIN_RATE_LATE := 0.33
const EARLY_UNTO := 8
const MAX_STEPS := 150

var fails := 0
var warns := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	print("=== 消消乐校验 · match3_check ===")
	_shape_rules()
	_special_rules()
	_ice_rules()
	_gravity_rules()
	_deadlock_rule()
	_level_defs()
	# M3CHECK_NOSIM=1 checks only the rules and the level data; M3CHECK_LEVELS=n
	# shortens the play-through to the first n chapters. Both exist because a full
	# simulated sweep of every chapter is the slow half of this tool.
	if OS.get_environment("M3CHECK_NOSIM") == "1":
		print("\n--- 模拟通关已跳过 (M3CHECK_NOSIM=1)")
	else:
		_play_through()
	print("")
	if fails == 0 and warns == 0:
		print("全部通过：0 失败 · 0 提醒")
	else:
		print("结果：%d 失败 · %d 提醒" % [fails, warns])
	# Quitting from inside _ready tears the tree down while this frame's freshly
	# loaded resources are still on the stack, which showed up as a segfault after an
	# otherwise clean report.
	await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)


func fail(msg: String) -> void:
	fails += 1
	print("  [FAIL] " + msg)


func warn(msg: String) -> void:
	warns += 1
	print("  [WARN] " + msg)


func probe(kinds_count: int, side: int = 8, moves: int = 30) -> Dictionary:
	var src: Array = M3Levels.get_def(0).set
	var ids: Array[String] = []
	for i: int in range(kinds_count):
		ids.append(String(src[i % src.size()]))
	return {
		"w": side, "h": side, "set": ids, "moves": moves,
		"objectives": [{"id": ids[0], "need": 9999}],
		"star_scores": [1000, 2000],
	}


# A filler that never repeats horizontally or vertically, so a painted test shape is
# the only match on the board and the assertions mean what they say.
func blank(n: int, side: int) -> Array[int]:
	var out: Array[int] = []
	for y: int in range(side):
		for x: int in range(side):
			out.append((x + 3 * y) % n)
	return out


func build(model: M3Model, kinds: Array[int], level: Dictionary, specs: Array[int] = [], ice: Array[int] = []) -> void:
	model.set_board(kinds, specs, ice, level)


func count_kind(model: M3Model, side: int, want: int) -> int:
	var n := 0
	for y: int in range(side):
		for x: int in range(side):
			if model.at_kind(Vector2i(x, y)) == want:
				n += 1
	return n


func pop_sizes(acts: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for a: Dictionary in acts:
		if int(a.type) == M3Model.A_POP:
			out.append((a.cells as Array).size())
	return out


func _shape_rules() -> void:
	print("\n--- 形状判定")
	var n := 4
	var side := 8
	var lvl := probe(n, side)
	var m := M3Model.new()

	var k := blank(n, side)
	for x: int in range(1, 5):
		k[3 * side + x] = 0
	build(m, k, lvl)
	var g: Array[Dictionary] = m.scan()
	if g.size() != 1:
		fail("四连横排应当只有一组，实际 %d 组" % g.size())
	elif int(g[0].len) != 4:
		fail("四连横排长度判成 %d" % int(g[0].len))
	elif int(g[0].spawn.get("spec", -1)) != M3Model.SP_ROW:
		fail("四连横排没有产出横向爆破条：%s" % str(g[0].spawn))
	elif int(g[0].spawn.get("cell", -1)) != 3 * side + 2:
		fail("横向爆破条没有落在排内的第二格")

	k = blank(n, side)
	for y: int in range(2, 6):
		k[y * side + 4] = 0
	build(m, k, lvl)
	g = m.scan()
	if g.size() != 1 or int(g[0].spawn.get("spec", -1)) != M3Model.SP_COL:
		fail("四连竖排没有产出竖向爆破条：%s" % str(g))
	elif int(g[0].len) != 4:
		fail("四连竖排长度判成 %d" % int(g[0].len))

	k = blank(n, side)
	for x: int in range(2, 5):
		k[2 * side + x] = 0
	for y: int in range(2, 5):
		k[y * side + 4] = 0
	build(m, k, lvl)
	g = m.scan()
	if g.size() != 1:
		fail("L 形应当合并成一组，实际 %d 组" % g.size())
	elif int(g[0].spawn.get("spec", -1)) != M3Model.SP_BOMB:
		fail("L 形没有产出炸弹：%s" % str(g[0].spawn))
	elif int(g[0].spawn.get("cell", -1)) != 2 * side + 4:
		fail("炸弹没有落在两条的交点上")

	k = blank(n, side)
	for x: int in range(1, 6):
		k[5 * side + x] = 0
	build(m, k, lvl)
	g = m.scan()
	if g.size() != 1 or int(g[0].spawn.get("spec", -1)) != M3Model.SP_RAINBOW:
		fail("五连没有产出彩虹球：%s" % str(g))
	print("  形状：4 横 → 横爆 · 4 竖 → 竖爆 · L → 炸弹 · 5 连 → 彩虹球")


func _special_rules() -> void:
	print("\n--- 特殊块引爆")
	var n := 4
	var side := 8
	var lvl := probe(n, side)
	var m := M3Model.new()

	# A row blast is set off by a three-wide match, so anything wider than three proves
	# the sweep actually ran.
	var k := blank(n, side)
	for x: int in range(2, 5):
		k[3 * side + x] = 0
	var sp: Array[int] = []
	sp.resize(side * side)
	sp[3 * side + 3] = M3Model.SP_ROW
	build(m, k, lvl, sp)
	var sizes := pop_sizes(m.force_resolve())
	var widest := 0
	for s: int in sizes:
		widest = maxi(widest, s)
	if widest < side:
		fail("横向爆破只清了 %d 格，不足一行的 %d 格" % [widest, side])

	k = blank(n, side)
	for x: int in range(2, 5):
		k[4 * side + x] = 0
	sp = []
	sp.resize(side * side)
	sp[4 * side + 3] = M3Model.SP_BOMB
	build(m, k, lvl, sp)
	var biggest := 0
	for s: int in pop_sizes(m.force_resolve()):
		biggest = maxi(biggest, s)
	if biggest < 8:
		fail("炸弹只清了 %d 格，不足 3x3 的规模" % biggest)

	# A rainbow fed a colour must wipe that colour. Refills may bring a few back, so
	# the check is "most of it is gone", not "none of it is left".
	k = blank(n, side)
	sp = []
	sp.resize(side * side)
	sp[4 * side + 4] = M3Model.SP_RAINBOW
	var want := k[4 * side + 5]
	build(m, k, lvl, sp)
	var before := count_kind(m, side, want)
	if m.try_swap(Vector2i(4, 4), Vector2i(5, 4)).is_empty():
		fail("彩虹球换色被拒，动作表为空")
	var after := count_kind(m, side, want)
	if before <= 0 or after * 2 > before:
		fail("彩虹球只吃掉 %d/%d 个该色" % [before - after, before])
	print("  引爆：横爆 %d 格 · 炸弹 %d 格 · 彩虹球 %d→%d" % [widest, biggest, before, after])


func _ice_rules() -> void:
	print("\n--- 冰块")
	var n := 4
	var side := 8
	var lvl := probe(n, side)
	var m := M3Model.new()
	var k := blank(n, side)
	for x: int in range(2, 5):
		k[4 * side + x] = 0
	var ice: Array[int] = []
	ice.resize(side * side)
	ice[3 * side + 3] = 2
	ice[5 * side + 3] = 1
	build(m, k, lvl, [], ice)
	# One wave only: a full resolve can chain, and a chain is allowed to pop a cell
	# whose ice broke in an earlier wave. The invariant to test is per-wave.
	var groups: Array[Dictionary] = m.scan()
	if groups.is_empty():
		fail("冰块测试棋盘没找到三连")
	else:
		var seeds: Array[int] = []
		for i: int in groups[0].cells:
			seeds.append(i)
		var plan := m.plan(seeds)
		for i: int in plan.pops:
			if i == 3 * side + 3 or i == 5 * side + 3:
				fail("冰块被当成普通块消掉了")
		if not plan.ice.has(3 * side + 3) or not plan.ice.has(5 * side + 3):
			fail("相邻的冰块没有被列入本次敲击：%s" % str(plan.ice))
		m.emit_pop(plan)
		if m.ice_of(3 * side + 3) != 1:
			fail("双层冰被一次相邻消除后应剩一层，实际 %d" % m.ice_of(3 * side + 3))
		if m.ice_of(5 * side + 3) != 0:
			fail("单层冰应已被敲碎，实际 %d" % m.ice_of(5 * side + 3))
		if m.ice_broken != 1:
			fail("碎冰计数应为 1，实际 %d" % m.ice_broken)
	m.force_resolve()
	if not m.playable(Vector2i(3, 5)):
		fail("敲碎的格子应当变回可用的空格")
	print("  冰：不会被直接消掉 · 相邻一次减一层 · 碎冰计入目标")


func _gravity_rules() -> void:
	print("\n--- 掉落与补块")
	var n := 4
	var side := 8
	var lvl := probe(n, side)
	var m := M3Model.new()
	var k := blank(n, side)
	for x: int in range(2, 5):
		k[6 * side + x] = 0
	var ice: Array[int] = []
	ice.resize(side * side)
	ice[4 * side + 3] = 1
	build(m, k, lvl, [], ice)
	var acts := m.force_resolve()
	var fell := 0
	var holes := 0
	for a: Dictionary in acts:
		if int(a.type) == M3Model.A_FALL:
			fell += (a.moves as Array).size()
	for y: int in range(side):
		for x: int in range(side):
			var i := m.at(Vector2i(x, y))
			if m.ice_of(i) == 0 and m.at_kind(Vector2i(x, y)) < 0:
				holes += 1
	if fell == 0:
		fail("消掉三格后没有任何掉落动作")
	if holes > 0:
		fail("掉落之后仍有 %d 个空格没有补上" % holes)
	if m.at_kind(Vector2i(3, 3)) < 0:
		fail("冰格正上方的格子被清空了，说明有块穿过了冰")
	print("  掉落：%d 次位移 · 补块后剩 %d 个空格 · 冰仍挡住该列" % [fell, holes])


func _deadlock_rule() -> void:
	print("\n--- 死局重排")
	# kind = (x + 2y) mod 4 has no equal neighbours in either direction, and every
	# single swap only ever puts a tile next to two that differ from it, so this board
	# is provably dead: exactly what the reshuffle exists for.
	var side := 4
	var lvl := probe(4, side, 5)
	var k: Array[int] = []
	for y: int in range(side):
		for x: int in range(side):
			k.append((x + 2 * y) % 4)
	var m := M3Model.new()
	m.set_board(k, [], [], lvl)
	if not m.scan().is_empty():
		fail("对角色板本不该有现成三连，检测却报了")
	if not m.legal_swaps().is_empty():
		fail("对角色板被判定为可走，死局检测失效（找到 %d 步）" % m.legal_swaps().size())
	var extra: Array[Dictionary] = m.check_end()
	if extra.is_empty() or int(extra[0].type) != M3Model.A_SHUFFLE:
		fail("死局没有产出重排动作：%s" % str(extra))
	if m.legal_swaps().is_empty():
		fail("重排后仍然无解")
	if not m.scan().is_empty():
		fail("重排后的棋盘自带现成三连")
	print("  死局：无解棋盘自动重排，重排后可走且不自带三连")


func _level_defs() -> void:
	print("\n--- 关卡定义")
	for i: int in range(M3Levels.count()):
		var d: Dictionary = M3Levels.get_def(i)
		var tag := "第 %d 局" % (i + 1)
		for key: String in ["name", "hint", "biome", "w", "h", "set", "moves", "objectives", "star_scores"]:
			if not d.has(key):
				fail(tag + " 缺少字段 " + key)
		var w := int(d.w)
		var h := int(d.h)
		if w < 5 or w > 10 or h < 5 or h > 10:
			fail(tag + " 棋盘尺寸越界 %dx%d" % [w, h])
		var ids: Array = d.set
		if ids.size() < 4:
			fail(tag + " 颜色少于 4 种，随便一换就三连")
		if ids.size() > 6:
			warn(tag + " 颜色 %d 种，偏难" % ids.size())
		var seen := {}
		for id: String in ids:
			if not M3Levels.ART.has(id):
				fail(tag + " 用了没有美术的块 " + id)
			elif M3Levels.art_tex(id) == null:
				fail(tag + " 的贴图取不到：" + id)
			if seen.has(id):
				fail(tag + " 颜色重复：" + id)
			seen[id] = true
		if int(d.moves) < 8:
			fail(tag + " 步数只有 %d，太紧" % int(d.moves))
		var cut: Array = d.star_scores
		if cut.size() != 2 or int(cut[0]) >= int(cut[1]):
			fail(tag + " 二三星门槛没有递增：%s" % str(cut))
		var need_total := 0
		var wants_ice := 0
		for o: Dictionary in d.objectives:
			var oid := String(o.id)
			if oid != "ice" and not seen.has(oid):
				fail(tag + " 目标物 %s 不在这一局的色板里" % oid)
			if int(o.get("need", 0)) <= 0:
				fail(tag + " 目标 %s 数量非法" % oid)
			if oid == "ice":
				wants_ice = int(o.need)
			need_total += int(o.need)
		var layers := 0
		var ice_seen := {}
		for row: Array in d.get("ice", []):
			var x := int(row[0])
			var y := int(row[1])
			if x < 0 or y < 0 or x >= w or y >= h:
				fail(tag + " 冰格出界 (%d,%d)" % [x, y])
				continue
			if ice_seen.has(Vector2i(x, y)):
				fail(tag + " 冰格重复 (%d,%d)" % [x, y])
			ice_seen[Vector2i(x, y)] = true
			layers += int(row[2]) if row.size() > 2 else 1
		if wants_ice > 0 and layers < wants_ice:
			fail(tag + " 要敲 %d 块冰，但盘上只有 %d 层" % [wants_ice, layers])
		if wants_ice == 0 and layers > 0:
			warn(tag + " 摆了 %d 层冰却没有冰块目标" % layers)
		if layers > 0 and ice_seen.size() >= w * h:
			fail(tag + " 整盘都是冰，没有可消的块")
		if need_total > int(d.moves) * 9:
			warn(tag + " 目标合计 %d 高于步数 %d 的常速产出" % [need_total, int(d.moves)])
		var m := M3Model.new()
		m.setup(d, 20260101 + i * 7)
		if not m.scan().is_empty():
			fail(tag + " 开局棋盘自带现成三连")
		if m.legal_swaps().is_empty():
			fail(tag + " 开局一步都走不了")
		var live := 0
		for y2: int in range(h):
			for x2: int in range(w):
				if m.playable(Vector2i(x2, y2)):
					live += 1
		if live < w * h * 0.5:
			fail(tag + " 可玩格只剩 %d/%d" % [live, w * h])
	print("  定义：%d 局字段齐全、贴图可取、开局可走" % M3Levels.count())


func _play_through() -> void:
	print("\n--- 模拟通关（机器人 · 每局 %d 种种子）" % SIMS_PER_LEVEL)
	var limit := M3Levels.count()
	var env_n := OS.get_environment("M3CHECK_LEVELS")
	if env_n.is_valid_int() and int(env_n) > 0:
		limit = mini(limit, int(env_n))
	for i: int in range(limit):
		var d: Dictionary = M3Levels.get_def(i)
		var win_scores: Array[int] = []
		var wins := 0
		var best_chain := 0
		var saw_special := false
		var stalled := 0
		_rng.seed = 77 + i
		for s: int in range(SIMS_PER_LEVEL):
			var m := M3Model.new()
			m.setup(d, 1000 + i * 97 + s * 13)
			var steps := 0
			while m.state == M3Model.ST_PLAY and steps < MAX_STEPS:
				steps += 1
				var list := m.legal_swaps()
				if list.is_empty():
					stalled += 1
					break
				var pick: Dictionary = list[0]
				var best_rank := -1
				for cand: Dictionary in list:
					var r: int = m.rank_move(cand) + _rng.randi() % 3
					if r > best_rank:
						best_rank = r
						pick = cand
				m.try_swap(pick.a, pick.b)
				# A settled board with a hole in it reads as a broken game to the player,
				# and the view replays animations from the model, so the model is where
				# this has to be proven — not in a screenshot.
				var holes := 0
				for c: int in range(m.w * m.h):
					# A cell still wearing frost has no tile under it by design; only an
					# open cell may not be empty once the board has settled.
					if m.kind_of(c) < 0 and m.ice_of(c) == 0:
						holes += 1
				if holes > 0:
					fail("第 %d 局 第 %d 步后棋盘留下 %d 个空格没有补" % [i + 1, steps, holes])
					break
				if not m.place_specials().is_empty():
					saw_special = true
				best_chain = maxi(best_chain, m.chain_best)
			if steps >= MAX_STEPS:
				fail("第 %d 局 模拟未收敛（%d 步仍在继续）" % [i + 1, steps])
			if m.state == M3Model.ST_WIN:
				wins += 1
				win_scores.append(int(m.score))
		win_scores.sort()
		var cut: Array = d.star_scores
		var rate := float(wins) / float(SIMS_PER_LEVEL)
		var min_rate := MIN_WIN_RATE_EARLY if i < EARLY_UNTO else MIN_WIN_RATE_LATE
		# Star cuts are measured off the runs that actually finished the level: a cut
		# set against losing scores would reward exactly the play that lost.
		var wmedian := 0
		var wp90 := 0
		var wmax := 0
		if not win_scores.is_empty():
			wmedian = win_scores[int(win_scores.size() / 2)]
			wp90 = win_scores[mini(win_scores.size() - 1, int(float(win_scores.size()) * 0.9))]
			wmax = win_scores[win_scores.size() - 1]
		var want := floorf(float(wmedian) / 100.0) * 100.0
		var want3 := floorf(float(wp90) / 100.0) * 100.0
		print("  第 %2d 局 %s 胜率 %3d%%  获胜局分数 中位 %6d p90 %6d 最高 %6d  连锁 %d  建议 [%d, %d]%s" % [
			i + 1, String(d.name), int(rate * 100), wmedian, wp90, wmax, best_chain,
			int(want), int(want3), "" if saw_special else "  [没有特殊块]"
		])
		if stalled > 0:
			fail("第 %d 局 有 %d 次卡在无步可走" % [i + 1, stalled])
		if rate < min_rate:
			fail("第 %d 局 机器人胜率只有 %d%%，低于 %d%%，门槛或步数不合理" % [i + 1, int(rate * 100), int(min_rate * 100)])
		if not saw_special:
			warn("第 %d 局 一整轮都没生成过特殊块" % [i + 1])
		if wins == 0:
			continue
		if int(cut[0]) > wmax or int(cut[1]) > wmax:
			fail("第 %d 局 门槛 %s 高于获胜局最高分 %d，拿不到" % [i + 1, str(cut), wmax])
		elif int(cut[0]) >= int(want3) or int(cut[1]) <= int(want):
			warn("第 %d 局 门槛 %s 与实测 %s 不匹配" % [i + 1, str(cut), str([int(want), int(want3)])])
		elif int(cut[0]) < int(want) / 2:
			warn("第 %d 局 二星门槛 %d 远低于获胜中位 %d" % [i + 1, int(cut[0]), wmedian])
