class_name M3Model
extends RefCounted

# The whole match-3 ruleset lives here as plain data so it can be driven from a
# headless validator with no window, no sprites and no input. The view never
# decides anything: it replays the Action list this object returns.

const EMPTY := -1
const SP_NONE := 0
const SP_ROW := 1
const SP_COL := 2
const SP_BOMB := 3
const SP_RAINBOW := 4

const ST_PLAY := 0
const ST_WIN := 1
const ST_LOSE := 2

const A_SWAP := 0
const A_INVALID := 1
const A_POP := 2
const A_FALL := 3
const A_SHUFFLE := 4

const BASE_SCORE := 60
const SPECIAL_SCORE := 240
const RAINBOW_SCORE := 600
const CHAIN_STEP := 0.5

var w := 8
var h := 8
var set_ids: PackedStringArray = []
var moves_left := 0
var moves_used := 0
var score := 0
var chain := 0
var chain_best := 0
var ice_broken := 0
var state := ST_PLAY
var def: Dictionary = {}
var taken: Dictionary = {}

var _kind: Array[int] = []
var _spec: Array[int] = []
var _ice: Array[int] = []
var rng := RandomNumberGenerator.new()


# Test seam: the validator needs to place a specific board to check the shape rules
# (four-in-a-row, L, five-in-a-row) and the deadlock path, which no amount of
# random play would pin down.
func set_board(kinds: Array[int], specs: Array[int] = [], ice: Array[int] = [], level: Dictionary = {}) -> void:
	if not level.is_empty():
		def = level
		w = int(level.w)
		h = int(level.h)
		set_ids = PackedStringArray(level.set)
		moves_left = int(level.get("moves", 30))
		# A hand-placed board has to start from a clean slate, otherwise the state
		# left by the previous test decides whether this swap is even attempted.
		state = ST_PLAY
		score = 0
		chain = 0
		chain_best = 0
		ice_broken = 0
		taken = {}
		for id: String in set_ids:
			taken[id] = 0
	assert(kinds.size() == w * h)
	_kind = kinds.duplicate()
	_spec.resize(w * h)
	_ice.resize(w * h)
	_spec.fill(SP_NONE)
	_ice.fill(0)
	for i: int in range(mini(specs.size(), _spec.size())):
		_spec[i] = specs[i]
	for i: int in range(mini(ice.size(), _ice.size())):
		_ice[i] = ice[i]


func scan() -> Array[Dictionary]:
	return _scan_groups()


func legal_swaps() -> Array[Dictionary]:
	return _legal_swaps()


func place_specials() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(_kind.size()):
		if _spec[i] != SP_NONE:
			out.append({"i": i, "spec": _spec[i]})
	return out


func gravity() -> Dictionary:
	return _gravity_action()


func force_resolve() -> Array[Dictionary]:
	return _settle([])


func check_end() -> Array[Dictionary]:
	return _check_end()


func rank_move(m: Dictionary) -> int:
	return _rank_move(m)


func plan(seeds: Array[int]) -> Dictionary:
	return _plan(seeds)


func emit_pop(p: Dictionary) -> Dictionary:
	return _emit_pop(p)


func at_kind(v: Vector2i) -> int:
	return _kind[at(v)]


func setup_seed(seed: int) -> void:
	rng.seed = seed


func setup(level: Dictionary, seed: int = 0) -> void:
	def = level
	w = int(level.w)
	h = int(level.h)
	set_ids = PackedStringArray(level.set)
	moves_left = int(level.moves)
	moves_used = 0
	score = 0
	chain = 0
	chain_best = 0
	ice_broken = 0
	state = ST_PLAY
	taken = {}
	for id: String in set_ids:
		taken[id] = 0
	_kind.resize(w * h)
	_spec.resize(w * h)
	_ice.resize(w * h)
	_kind.fill(EMPTY)
	_spec.fill(SP_NONE)
	_ice.fill(0)
	rng.seed = seed if seed != 0 else 20260101
	for row: Array in level.get("ice", []):
		var i := at(Vector2i(int(row[0]), int(row[1])))
		if i >= 0:
			_ice[i] = maxi(1, int(row[2]) if row.size() > 2 else 1)
	_fill()
	# A board that opens with a ready-made match plays itself for free, and a board
	# with no legal move is a wall, so neither may leave setup.
	var guard := 0
	while guard < 60 and (not _scan_groups().is_empty() or _legal_swaps().is_empty()):
		_permute()
		guard += 1


func at(v: Vector2i) -> int:
	if v.x < 0 or v.y < 0 or v.x >= w or v.y >= h:
		return -1
	return v.y * w + v.x


func cell_xy(i: int) -> Vector2i:
	return Vector2i(i % w, int(i / w))


func kind_of(i: int) -> int:
	return _kind[i] if i >= 0 and i < _kind.size() else EMPTY


func spec_of(i: int) -> int:
	return _spec[i] if i >= 0 and i < _spec.size() else SP_NONE


func ice_of(i: int) -> int:
	return _ice[i] if i >= 0 and i < _ice.size() else 0


func is_iced(i: int) -> bool:
	return ice_of(i) > 0


func tile_id(kind_index: int) -> String:
	return set_ids[kind_index] if kind_index >= 0 and kind_index < set_ids.size() else ""


func id_of(i: int) -> String:
	return tile_id(kind_of(i))


# --------------------------------------------------------------------------------
# Player moves
# --------------------------------------------------------------------------------

func playable(v: Vector2i) -> bool:
	var i := at(v)
	return i >= 0 and _kind[i] >= 0 and _ice[i] == 0


func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func try_swap(a: Vector2i, b: Vector2i) -> Array[Dictionary]:
	if state != ST_PLAY:
		return []
	var ia := at(a)
	var ib := at(b)
	if ia < 0 or ib < 0 or not adjacent(a, b):
		return [_invalid(a, b)]
	if _ice[ia] > 0 or _ice[ib] > 0 or _kind[ia] < 0 or _kind[ib] < 0:
		return [_invalid(a, b)]

	# A rainbow needs no line-up: it eats whatever colour it is fed, so the swap is
	# legal even though nothing matches.
	var ra: bool = _spec[ia] == SP_RAINBOW
	var rb: bool = _spec[ib] == SP_RAINBOW
	if not ra and not rb:
		_swap_cells(ia, ib)
		var groups: Array[Dictionary] = _scan_groups()
		_swap_cells(ia, ib)
		if groups.is_empty():
			return [_invalid(a, b)]

	var out: Array[Dictionary] = [{"type": A_SWAP, "a": a, "b": b}]
	_swap_cells(ia, ib)
	moves_left = maxi(0, moves_left - 1)
	moves_used += 1
	if ra or rb:
		out.append_array(_eat_rainbow(ia if rb else ib, ia if ra else ib))
	return _settle(out)


func _invalid(a: Vector2i, b: Vector2i) -> Dictionary:
	return {"type": A_INVALID, "a": a, "b": b}


func _eat_rainbow(rainbow_cell: int, partner: int) -> Array[Dictionary]:
	# What else goes with the rainbow depends on what it was fed. Two rainbows
	# together is the whole board — the one thing that has to feel like an event.
	var seeds: Array[int] = [rainbow_cell]
	if _spec[partner] == SP_RAINBOW:
		for i: int in range(_kind.size()):
			if _kind[i] >= 0 and _ice[i] == 0:
				seeds.append(i)
	else:
		var want := _kind[partner]
		for i: int in range(_kind.size()):
			if _kind[i] == want and _ice[i] == 0:
				seeds.append(i)
	var plan := _plan(seeds)
	return [_emit_pop(plan)]


# --------------------------------------------------------------------------------
# Cascade
# --------------------------------------------------------------------------------

func _settle(out: Array[Dictionary]) -> Array[Dictionary]:
	chain = 0
	var guard := 0
	while guard < 60:
		guard += 1
		var groups: Array[Dictionary] = _scan_groups()
		if groups.is_empty():
			break
		chain += 1
		chain_best = maxi(chain_best, chain)
		var seeds: Array[int] = []
		var spawns := {}
		for g: Dictionary in groups:
			for i: int in g.cells:
				seeds.append(i)
			if not g.spawn.is_empty():
				var cell: int = int(g.spawn.cell)
				if not spawns.has(cell):
					spawns[cell] = g.spawn
		var plan := _plan(seeds)
		var action := _emit_pop(plan)
		action.chain = chain
		out.append(action)
		for cell: int in spawns:
			# A special is born out of the match that made it, so it keeps that
			# colour and gains its power on top rather than arriving as a new piece.
			_kind[cell] = int(spawns[cell].kind)
			_spec[cell] = int(spawns[cell].spec)
		out.append(_gravity_action())
	var holes := 0
	for i: int in range(_kind.size()):
		if _ice[i] == 0 and _kind[i] == EMPTY:
			holes += 1
	if holes > 0:
		# A colour wiped by a rainbow leaves a board full of gaps and no match to
		# follow it, so the falling has to be promised here rather than by the cascade.
		out.append(_gravity_action())
	out.append_array(_check_end())
	return out


func _emit_pop(plan: Dictionary) -> Dictionary:
	var gain := 0
	var cells: Array[int] = []
	var kinds: Array[int] = []
	var specs: Array[int] = []
	for i: int in plan.pops:
		if _kind[i] < 0:
			continue
		# The look of the pop is decided here, while the tiles still exist: by the time
		# the view replays this Action the board has already moved on without them.
		cells.append(i)
		kinds.append(_kind[i])
		specs.append(_spec[i])
		gain += BASE_SCORE
		if _spec[i] == SP_RAINBOW:
			gain += RAINBOW_SCORE
		elif _spec[i] != SP_NONE:
			gain += SPECIAL_SCORE
		_taken_add(_kind[i])
	# Every chain level after the first pays more, which is the only reason to set up
	# a cascade instead of taking the match in front of you.
	var mult: float = 1.0 + CHAIN_STEP * float(maxi(0, chain - 1))
	var total := int(float(gain) * mult)
	score += total
	for i: int in cells:
		_kind[i] = EMPTY
		_spec[i] = SP_NONE
	for i: int in plan.ice:
		_ice[i] = maxi(0, _ice[i] - 1)
		if _ice[i] == 0:
			ice_broken += 1
	return {
		"type": A_POP, "cells": cells, "kinds": kinds, "specs": specs,
		"ice": plan.ice, "chain": 1, "gain": total
	}


func _taken_add(kind_index: int) -> void:
	if kind_index < 0 or kind_index >= set_ids.size():
		return
	var id := set_ids[kind_index]
	taken[id] = int(taken.get(id, 0)) + 1


# A dead board is re-dealt rather than left there, and the shuffle is returned as an
# Action so the view can show it instead of the tiles silently teleporting.
func _check_end() -> Array[Dictionary]:
	if objectives_done():
		state = ST_WIN
		return []
	if moves_left <= 0:
		state = ST_LOSE
		return []
	if _legal_swaps().is_empty():
		# One re-deal is not enough to promise a playable board, so keep dealing
		# until there is a move; the permute side already guarantees no free match.
		var guard := 0
		while _legal_swaps().is_empty() and guard < 24:
			_permute()
			guard += 1
		return [{"type": A_SHUFFLE}]
	return []


func objectives_done() -> bool:
	for o: Dictionary in def.get("objectives", []):
		if got_of(o) < int(o.need):
			return false
	return objectives_present()


func objectives_present() -> bool:
	return not def.get("objectives", []).is_empty()


func got_of(o: Dictionary) -> int:
	var id := String(o.id)
	return ice_broken if id == "ice" else int(taken.get(id, 0))


func stars() -> int:
	return _cut_stars() if state == ST_WIN else 0


# The HUD shows the star level this run would earn if it ended now, so the bar can
# move before the objectives are in.
func projected_stars() -> int:
	return _cut_stars()


func _cut_stars() -> int:
	var s := 1
	var cut: Array = def.get("star_scores", [])
	if cut.size() > 1 and score >= int(cut[0]):
		s = 2
	if cut.size() > 2 and score >= int(cut[1]):
		s = 3
	return s


func objective_line(o: Dictionary) -> Dictionary:
	var id := String(o.id)
	if id == "ice":
		return {"label": "冰块", "now": ice_broken, "need": int(o.need), "tile": -1}
	return {
		"label": String(M3Levels.LABELS.get(id, id)),
		"now": int(taken.get(id, 0)),
		"need": int(o.need),
		"tile": set_ids.find(id),
	}


# --------------------------------------------------------------------------------
# Match detection
# --------------------------------------------------------------------------------

# Runs are merged into groups before anything pops, because an L or a T is two runs
# sharing exactly one cell: left separate, that cell pays out twice and the bomb
# never appears.
func _scan_groups() -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for y: int in range(h):
		var x := 0
		while x < w:
			var i := at(Vector2i(x, y))
			if _kind[i] < 0 or _ice[i] > 0:
				x += 1
				continue
			var run: Array[int] = [i]
			var xx := x + 1
			while xx < w:
				var j := at(Vector2i(xx, y))
				if _ice[j] > 0 or _kind[j] != _kind[i]:
					break
				run.append(j)
				xx += 1
			if run.size() >= 3:
				runs.append({"cells": run, "axis": 0, "len": run.size(), "kind": _kind[i]})
			x = xx
	for x: int in range(w):
		var y := 0
		while y < h:
			var i := at(Vector2i(x, y))
			if _kind[i] < 0 or _ice[i] > 0:
				y += 1
				continue
			var run: Array[int] = [i]
			var yy := y + 1
			while yy < h:
				var j := at(Vector2i(x, yy))
				if _ice[j] > 0 or _kind[j] != _kind[i]:
					break
				run.append(j)
				yy += 1
			if run.size() >= 3:
				runs.append({"cells": run, "axis": 1, "len": run.size(), "kind": _kind[i]})
			y = yy
	if runs.is_empty():
		return []

	var used := {}
	var groups: Array[Dictionary] = []
	for r: int in range(runs.size()):
		if used.has(r):
			continue
		var bucket: Array[Dictionary] = [runs[r]]
		used[r] = true
		var grew := true
		while grew:
			grew = false
			for k: int in range(runs.size()):
				if used.has(k):
					continue
				for b: Dictionary in bucket:
					if int(b.axis) != int(runs[k].axis) and _shares(b.cells, runs[k].cells):
						bucket.append(runs[k])
						used[k] = true
						grew = true
						break
				if grew:
					break
		groups.append(_make_group(bucket))
	return groups


func _shares(a: Array[int], b: Array[int]) -> bool:
	for i: int in a:
		if b.has(i):
			return true
	return false


func _make_group(bucket: Array[Dictionary]) -> Dictionary:
	var cells: Array[int] = []
	var cross: Array[int] = []
	for r: Dictionary in bucket:
		for i: int in r.cells:
			if cells.has(i):
				if not cross.has(i):
					cross.append(i)
			else:
				cells.append(i)
	var longest: Dictionary = bucket[0]
	for r: Dictionary in bucket:
		if int(r.len) > int(longest.len):
			longest = r
	var kind := int(longest.kind)
	var spawn := {}
	if not cross.is_empty():
		# The shared corner is where the bomb sits, because that is the cell the
		# player's eye already reads as the centre of the figure.
		spawn = {"cell": cross[0], "kind": kind, "spec": SP_BOMB}
	elif int(longest.len) >= 5:
		spawn = {"cell": int(longest.cells[int(longest.len) / 2]), "kind": kind, "spec": SP_RAINBOW}
	elif int(longest.len) == 4:
		# A four keeps its own direction and sweeps along it: a horizontal match
		# clears the row it lies in.
		spawn = {
			"cell": int(longest.cells[1]), "kind": kind,
			"spec": SP_ROW if int(longest.axis) == 0 else SP_COL
		}
	return {"cells": cells, "spawn": spawn, "len": int(longest.len), "kind": kind}


# --------------------------------------------------------------------------------
# Special activation
# --------------------------------------------------------------------------------

# Popping is closed under "what a popped special then destroys", so a row blast that
# hits a bomb detonates it in the same frame rather than leaving it for next turn.
func _plan(seeds: Array[int]) -> Dictionary:
	var pops := {}
	var stack: Array[int] = seeds.duplicate()
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if i < 0 or i >= _kind.size() or pops.has(i):
			continue
		if _ice[i] > 0 or _kind[i] < 0:
			continue
		pops[i] = true
		var x: int = i % w
		var y: int = i / w
		match _spec[i]:
			SP_ROW:
				for xx: int in range(w):
					stack.append(y * w + xx)
			SP_COL:
				for yy: int in range(h):
					stack.append(yy * w + x)
			SP_BOMB:
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						stack.append(at(Vector2i(x + dx, y + dy)))
			SP_RAINBOW:
				var want := _dominant_kind()
				for k: int in range(_kind.size()):
					if _kind[k] == want:
						stack.append(k)
	var ice := {}
	for i: int in pops:
		var x: int = i % w
		var y: int = i / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var j := at(Vector2i(x + d.x, y + d.y))
			if j >= 0 and _ice[j] > 0:
				ice[j] = true
	var pop_list: Array[int] = []
	for i: int in pops.keys():
		pop_list.append(i)
	var ice_list: Array[int] = []
	for i: int in ice.keys():
		ice_list.append(i)
	pop_list.sort()
	ice_list.sort()
	return {"pops": pop_list, "ice": ice_list}


func _dominant_kind() -> int:
	var tally := {}
	var best := -1
	var best_n := 0
	for i: int in range(_kind.size()):
		if _kind[i] < 0 or _ice[i] > 0:
			continue
		var n: int = int(tally.get(_kind[i], 0)) + 1
		tally[_kind[i]] = n
		if n > best_n:
			best_n = n
			best = _kind[i]
	return best


# --------------------------------------------------------------------------------
# Gravity
# --------------------------------------------------------------------------------

# Ice is a wall: it neither falls nor lets anything fall through it, so a column is
# really a stack of short segments divided by iced rows.
func _gravity_action() -> Dictionary:
	var moves: Array[Dictionary] = []
	var spawns: Array[Dictionary] = []
	for x: int in range(w):
		var bottom := h - 1
		for y: int in range(h - 1, -1, -1):
			if _ice[at(Vector2i(x, y))] > 0:
				_drop_column(x, y + 1, bottom, moves, spawns)
				bottom = y - 1
		_drop_column(x, 0, bottom, moves, spawns)
	return {"type": A_FALL, "moves": moves, "spawns": spawns}


func _drop_column(x: int, top: int, bottom: int, moves: Array[Dictionary], spawns: Array[Dictionary]) -> void:
	var write := bottom
	var y := bottom
	while y >= top:
		var i := at(Vector2i(x, y))
		if _kind[i] >= 0:
			if write != y:
				var j := at(Vector2i(x, write))
				_kind[j] = _kind[i]
				_spec[j] = _spec[i]
				_kind[i] = EMPTY
				_spec[i] = SP_NONE
				moves.append({"from": Vector2i(x, y), "to": Vector2i(x, write)})
			write -= 1
		y -= 1
	while write >= top:
		var k := _pick_kind(x, write)
		var cell := at(Vector2i(x, write))
		_kind[cell] = k
		_spec[cell] = SP_NONE
		spawns.append({"at": Vector2i(x, write), "kind": k, "dist": float(write - top + 2)})
		write -= 1


func _pick_kind(x: int, y: int) -> int:
	# A refill that drops straight into a fresh match would keep a lucky cascade going
	# forever, so a new tile is chosen against its settled neighbours, not at random.
	var n := maxi(1, set_ids.size())
	for try: int in range(14):
		var k := rng.randi() % n
		if not _makes_line(x, y, k):
			return k
	return rng.randi() % n


func _makes_line(x: int, y: int, k: int) -> bool:
	if x >= 2 and _kind[at(Vector2i(x - 1, y))] == k and _kind[at(Vector2i(x - 2, y))] == k:
		return true
	if x >= 1 and x < w - 1 and _kind[at(Vector2i(x - 1, y))] == k and _kind[at(Vector2i(x + 1, y))] == k:
		return true
	if y >= 2 and _kind[at(Vector2i(x, y - 1))] == k and _kind[at(Vector2i(x, y - 2))] == k:
		return true
	if y >= 1 and y < h - 1 and _kind[at(Vector2i(x, y - 1))] == k and _kind[at(Vector2i(x, y + 1))] == k:
		return true
	return false


func _swap_cells(a: int, b: int) -> void:
	var k: int = _kind[a]
	_kind[a] = _kind[b]
	_kind[b] = k
	var s: int = _spec[a]
	_spec[a] = _spec[b]
	_spec[b] = s


# --------------------------------------------------------------------------------
# Board generation, hint, deadlock
# --------------------------------------------------------------------------------

func _fill() -> void:
	for y: int in range(h):
		for x: int in range(w):
			if _ice[at(Vector2i(x, y))] > 0:
				continue
			_kind[at(Vector2i(x, y))] = _pick_kind(x, y)


# Shuffling keeps the tiles that are already on the board and only re-deals them,
# so a shuffle can never quietly hand the player extra objective pieces or take the
# rare ones away.
func _permute() -> void:
	var live: Array[int] = []
	var slots: Array[int] = []
	for i: int in range(_kind.size()):
		if _ice[i] > 0:
			continue
		if _kind[i] >= 0:
			live.append(_kind[i])
		slots.append(i)
	if slots.is_empty():
		return
	if live.size() != slots.size():
		live.clear()
		for s: int in slots:
			live.append(rng.randi() % maxi(1, set_ids.size()))
	for n: int in range(live.size() - 1, 0, -1):
		var m := rng.randi() % (n + 1)
		var t: int = live[n]
		live[n] = live[m]
		live[m] = t
	for idx: int in range(slots.size()):
		_kind[slots[idx]] = live[idx]
		_spec[slots[idx]] = SP_NONE
	for i: int in range(_kind.size()):
		if _ice[i] > 0:
			_kind[i] = EMPTY
	# A permutation can land a line by accident; breaking those by hand is cheaper
	# than re-rolling the board and keeps the piece mix intact.
	var guard := 0
	while guard < 80:
		var groups: Array[Dictionary] = _scan_groups()
		if groups.is_empty():
			break
		for g: Dictionary in groups:
			var cell: int = int(g.cells[0])
			var n := maxi(1, set_ids.size())
			_kind[cell] = (_kind[cell] + 1) % n
		guard += 1


func find_move() -> Dictionary:
	var list := _legal_swaps()
	if list.is_empty():
		return {}
	var best: Dictionary = list[0]
	var best_rank := -1
	for m: Dictionary in list:
		var rank := _rank_move(m)
		if rank > best_rank:
			best_rank = rank
			best = m
	return best


func _rank_move(m: Dictionary) -> int:
	var ia := at(m.a)
	var ib := at(m.b)
	var rank := 0
	if _spec[ia] != SP_NONE or _spec[ib] != SP_NONE:
		rank += 30
	for o: Dictionary in def.get("objectives", []):
		var id := String(o.id)
		if id == "ice":
			if _near_ice(ia) or _near_ice(ib):
				rank += 12
			continue
		if id == tile_id(_kind[ia]) or id == tile_id(_kind[ib]):
			rank += 8
	return rank


func _near_ice(i: int) -> bool:
	if i < 0:
		return false
	var x: int = i % w
	var y: int = i / w
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var j := at(Vector2i(x + d.x, y + d.y))
		if j >= 0 and _ice[j] > 0:
			return true
	return false


# Every candidate swap is tested by really swapping it and looking for a group, so
# the hint, the deadlock check and the validator can never disagree on what counts
# as a move.
func _legal_swaps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for y: int in range(h):
		for x: int in range(w):
			var i := at(Vector2i(x, y))
			if _kind[i] < 0 or _ice[i] > 0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var v := Vector2i(x + d.x, y + d.y)
				var j := at(v)
				if j < 0 or _kind[j] < 0 or _ice[j] > 0:
					continue
				if _spec[i] == SP_RAINBOW or _spec[j] == SP_RAINBOW:
					out.append({"a": Vector2i(x, y), "b": v})
					continue
				_swap_cells(i, j)
				var hit := _swap_makes_match(i, j)
				_swap_cells(i, j)
				if hit:
					out.append({"a": Vector2i(x, y), "b": v})
	return out


# Only the two lines that pass through the swapped cells can change, so a legality
# test reads those instead of re-scanning the whole board — which matters because the
# hint, the deadlock check and the validator each do this once per cell.
func _swap_makes_match(a: int, b: int) -> bool:
	return _lines_hit(a) or _lines_hit(b)


func _lines_hit(i: int) -> bool:
	return _run_len(i, 0) >= 3 or _run_len(i, 1) >= 3


func _run_len(i: int, axis: int) -> int:
	var k := _kind[i]
	if k < 0 or _ice[i] > 0:
		return 0
	var dx := 1 if axis == 0 else 0
	var dy := 0 if axis == 0 else 1
	var x: int = i % w
	var y: int = int(i / w)
	var n := 1
	var px := x + dx
	var py := y + dy
	while px < w and py < h:
		var j := py * w + px
		if _ice[j] > 0 or _kind[j] != k:
			break
		n += 1
		px += dx
		py += dy
	px = x - dx
	py = y - dy
	while px >= 0 and py >= 0:
		var j2 := py * w + px
		if _ice[j2] > 0 or _kind[j2] != k:
			break
		n += 1
		px -= dx
		py -= dy
	return n
