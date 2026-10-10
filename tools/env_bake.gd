extends Node

# Environment art baker. Turns the flat-magenta sheets in assets/src into
# transparent PNGs in assets/env, and writes one contact sheet into user://qa/ so
# a bad key line is visible without launching the game.
#
# It borrows the character pipeline's edge un-premultiply by instantiating
# sprite_bake.gd directly, so the two can never drift apart. Two things differ.
# These sheets are grids, so cells come out of connected components rather than
# column runs. And the field test is strict: the loose magenta rule that suits a
# white bear reads a plum rock or a hot-pink spike as background and eats it.
#
# Run:  godot --headless --path . res://tools/env_bake.tscn

const OUT_DIR := "res://assets/env/"
const MIN_CELL_ART := 900
const SPECK := 260
const BAND_TARGET := 1400
const ISLAND_TOL := 42.0

const SHEETS := [
	{
		"src": "env_terrain.png", "max": 300.0,
		"labels": ["blk_meadow", "blk_canyon", "blk_forest", "blk_cave", "blk_ice", "blk_slate"],
	},
	{
		"src": "env_props_plants.png", "max": 190.0,
		"labels": [
			"bush", "sapling", "fern", "tuft", "mushroom", "flower",
			"rockpile", "log", "crystal", "lamp_post", "signpost", "pine",
		],
	},
	{
		"src": "env_props_mecha.png", "max": 190.0,
		"labels": [
			"crate", "barrel", "chain", "wheel_wood", "bamboo", "blossom",
			"vine", "icicle", "clock", "lantern", "chimney", "candy_shroom",
		],
	},
	{
		"src": "env_hazards.png", "max": 210.0,
		"labels": ["spike_stone", "spike_ice", "spike_candy", "saw", "firebowl", "gear"],
		"round": ["saw", "gear"],
	},
	{
		"src": "env_bits.png", "max": 300.0,
		"labels": ["coin", "gate", "flag", "pulley", "spring", "plate"],
	},
	{
		"src": "env_caps_a.png", "max": 340.0, "mirror": true, "cap_report": true, "cap_crop": true,
		"labels": ["cap_grass", "cap_sand", "cap_moss"],
	},
	{
		"src": "env_caps_b.png", "max": 340.0, "mirror": true, "cap_report": true, "cap_crop": true,
		"labels": ["cap_honey", "cap_snow", "cap_slate"],
	},
	{"src": "env_bg_far.png", "band": "stand", "labels": ["bg_far"]},
	{"src": "env_bg_mid.png", "band": "stand", "labels": ["bg_mid"]},
	{"src": "env_bg_near.png", "band": "stand", "labels": ["bg_near"]},
	{"src": "env_bg_canopy.png", "band": "hang", "labels": ["bg_canopy"]},
]

var _bk: Object
var _out: Array[Dictionary] = []
var _fails := 0
var _report_only := false
var _only := ""
var _px: PackedByteArray
var _ids := PackedInt32Array()
var _w := 0
var _h := 0


func _ready() -> void:
	_report_only = OS.get_environment("ENVBAKE_REPORT") == "1"
	_only = OS.get_environment("ENVBAKE_ONLY")
	_bk = (load("res://tools/sprite_bake.gd") as GDScript).new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("qa"))
	var t0 := Time.get_ticks_msec()
	for job: Dictionary in SHEETS:
		if not _only.is_empty() and not String(job.src).begins_with(_only):
			continue
		_bake(job)
	_contact_sheet()
	print("[env] %d pieces, %d failures, %dms" % [_out.size(), _fails, Time.get_ticks_msec() - t0])
	_bk.free()
	get_tree().quit(1 if _fails > 0 else 0)


# --------------------------------------------------------------------------------
# field test
# --------------------------------------------------------------------------------

# The generator is asked for flat #FF00FF every time and delivers it almost never:
# the fields that came back are rose #BE3963, pink #D948A9, cream #F5C4B1 and one
# true magenta. So the field is measured off the border rather than assumed, and
# only border-connected pixels within reach of it count as background.
var _field := Vector3.ZERO
var _fd := Vector2.ZERO
var _mode := 0
var _tol := 55.0
# Which edge of the sheet is guaranteed to be field. A props sheet is all field at
# the rim; a standing silhouette carries its own art along the bottom edge, and a
# hanging fringe along the top, so sampling the whole rim there measures the art.
var _edge := 0


func _bg(i: int) -> bool:
	var r: float = float(_px[i * 4])
	var g: float = float(_px[i * 4 + 1])
	var b: float = float(_px[i * 4 + 2])
	if _mode == 0:
		# A vignette or a soft gradient moves the field's brightness without moving
		# its hue, so channel differences against green separate field from art where
		# an absolute colour distance either strands half the field or eats a cream
		# prop.
		return absf((r - g) - _fd.x) < _tol and absf((b - g) - _fd.y) < _tol
	var dr: float = r - _field.x
	var dg: float = g - _field.y
	var db: float = b - _field.z
	return dr * dr + dg * dg + db * db < _tol * _tol


func _detect_field() -> void:
	var counts := {}
	var sums := {}
	var dcounts := {}
	var dsums := {}
	# Only the sampled edge is guaranteed to be field, so the rim rows and the stretch
	# of the side columns both stay on that side of the sheet.
	var rows: Array = [0, _h - 1]
	var y0 := 0
	var y1 := _h - 1
	if _edge == 1:
		rows = [0]
		y1 = maxi(2, int(_h * 0.3))
	elif _edge == 2:
		rows = [_h - 1]
		y0 = mini(_h - 3, int(_h * 0.7))
	for x: int in range(0, _w, 3):
		for y: int in rows:
			_bucket(y * _w + x, counts, sums, dcounts, dsums)
	for y: int in range(y0, y1, 3):
		for x: int in [0, _w - 1]:
			_bucket(y * _w + x, counts, sums, dcounts, dsums)
	var best := ""
	var best_n := 0
	for key: String in counts:
		if int(counts[key]) > best_n:
			best_n = int(counts[key])
			best = key
	if not best.is_empty():
		var s: Vector3 = sums[best]
		_field = Vector3(s.x / float(best_n), s.y / float(best_n), s.z / float(best_n))
	var dbest := ""
	var dbest_n := 0
	for key: String in dcounts:
		if int(dcounts[key]) > dbest_n:
			dbest_n = int(dcounts[key])
			dbest = key
	if not dbest.is_empty():
		var d: Vector2 = dsums[dbest]
		_fd = Vector2(d.x / float(dbest_n), d.y / float(dbest_n))
	print("[env] field = %s  dr-g=%.0f db-g=%.0f (%d of %d border samples)" % [
		Color(_field.x / 255.0, _field.y / 255.0, _field.z / 255.0, 1.0).to_html(),
		_fd.x, _fd.y, best_n, walking_samples()
	])


func walking_samples() -> int:
	return int(ceil(_w / 3.0)) * 2 + int(ceil(_h / 3.0)) * 2


func _bucket(
	i: int, counts: Dictionary, sums: Dictionary, dcounts: Dictionary, dsums: Dictionary
) -> void:
	var r := int(_px[i * 4])
	var g := int(_px[i * 4 + 1])
	var b := int(_px[i * 4 + 2])
	var key := "%d_%d_%d" % [r >> 4, g >> 4, b >> 4]
	counts[key] = int(counts.get(key, 0)) + 1
	var s: Vector3 = sums.get(key, Vector3.ZERO)
	sums[key] = s + Vector3(float(r), float(g), float(b))
	var dkey := "%d_%d" % [(r - g) >> 4, (b - g) >> 4]
	dcounts[dkey] = int(dcounts.get(dkey, 0)) + 1
	var ds: Vector2 = dsums.get(dkey, Vector2.ZERO)
	dsums[dkey] = ds + Vector2(float(r - g), float(b - g))


# A too-tight tolerance strands part of the field inside a component and links the
# props together; a too-loose one eats the art. Widen it until the sheet falls apart
# into exactly the number of pieces the job expects.
func _attempt(job: Dictionary) -> Dictionary:
	var gone := _flood()
	# A gradient or vignette on the field leaves a hairline skin of almost-field
	# colour that links every prop on the sheet into one component. Eroding the art
	# by two pixels kills the skin and a generator signature, and costs a solid prop
	# nothing but a rim that the bounding box grows back.
	var art := PackedByteArray()
	art.resize(_w * _h)
	for i: int in range(_w * _h):
		art[i] = 0 if gone[i] == 1 else 1
	var core: PackedByteArray = _bk._erode(art, _w, _h, 2)
	var parts := _parts(core)
	var biggest := 0
	for p: Dictionary in parts:
		biggest = maxi(biggest, int(p.size))
	var chosen: Array[Dictionary] = []
	for p: Dictionary in parts:
		var box: Rect2i = p.box
		var aspect: float = float(box.size.x) / float(maxi(1, box.size.y))
		if int(p.size) < maxi(SPECK, int(biggest * 0.05)):
			continue
		if job.has("band"):
			# A parallax band is one long low silhouette, so the shape tests that
			# exist to throw away signatures do not apply to it.
			chosen.append(p)
			continue
		# The generator signs its sheets: a wide thin scrawl in a bottom corner that
		# is small next to the props and shaped like nothing that lives in a level.
		# Crust bands are exempt: being six times wider than tall is the whole point.
		if box.size.x < 40 or box.size.y < 40 or aspect < 0.28:
			continue
		if not job.has("cap_crop") and aspect > 3.2:
			continue
		# A vignette survives erosion as a sheet-spanning frame that links every prop.
		if float(box.size.x * box.size.y) > float(_w * _h) * 0.55:
			continue
		chosen.append(p)
	return {
		"gone": gone, "core": core, "parts": chosen, "raw": parts, "mode": _mode, "tol": _tol
	}


# Widen until the sheet stops falling apart into the right number of pieces, then
# use the loosest setting that still worked. The first tolerance that happens to
# give the right count is often one that left half the field unkeyed, which shows up
# later as a pink blob welded to the side of a crystal.
func _solve_field(job: Dictionary, want: int) -> Dictionary:
	var last_good: Dictionary = {}
	var closest: Dictionary = {}
	var closest_gap := 1 << 30
	var misses := 0
	for probe: Array in [[0, 26.0], [0, 40.0], [0, 62.0], [1, 55.0], [1, 85.0], [1, 125.0]]:
		_mode = int(probe[0])
		_tol = float(probe[1])
		var attempt := _attempt(job)
		var gap: int = absi(int(attempt.parts.size()) - want)
		print("[env] mode=%d tol=%.0f pieces=%d want=%d" % [_mode, _tol, attempt.parts.size(), want])
		if gap == 0:
			last_good = attempt
			misses = 0
			continue
		misses += 1
		if gap < closest_gap:
			closest_gap = gap
			closest = attempt
		if not last_good.is_empty() and misses >= 2:
			break
	# Each probe relabels the sheet and leaves its label map behind, so the winner's
	# ids are no longer in _ids by the time this returns. Re-running the winning
	# parameters is the only way to hand back a mask that matches its own boxes.
	var win: Dictionary = last_good if not last_good.is_empty() else closest
	_mode = int(win.mode)
	_tol = float(win.tol)
	return _attempt(job)


func _flood() -> PackedByteArray:
	var gone := PackedByteArray()
	gone.resize(_w * _h)
	var q := PackedInt32Array()
	for x: int in range(_w):
		_seed(q, gone, x)
		_seed(q, gone, (_h - 1) * _w + x)
	for y: int in range(1, _h - 1):
		_seed(q, gone, y * _w)
		_seed(q, gone, y * _w + _w - 1)
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % _w
		var y := i / _w
		if x > 0 and gone[i - 1] == 0 and _bg(i - 1):
			gone[i - 1] = 1
			q.append(i - 1)
		if x < _w - 1 and gone[i + 1] == 0 and _bg(i + 1):
			gone[i + 1] = 1
			q.append(i + 1)
		if y > 0 and gone[i - _w] == 0 and _bg(i - _w):
			gone[i - _w] = 1
			q.append(i - _w)
		if y < _h - 1 and gone[i + _w] == 0 and _bg(i + _w):
			gone[i + _w] = 1
			q.append(i + _w)
	return gone


func _seed(q: PackedInt32Array, gone: PackedByteArray, i: int) -> void:
	if gone[i] == 1 or not _bg(i):
		return
	gone[i] = 1
	q.append(i)


# A ring, a blade and a cog are all drawn with the field showing straight through
# their hub, and a flood from the sheet rim never gets in there — the hub is painted
# adjacent to the metal, so it labels as part of the same piece. Field colour the rim
# cannot reach is still field, so walk the reachable field a second time and punch
# whatever it missed.
func _punch_islands(kept: PackedByteArray) -> void:
	var seen := PackedByteArray()
	seen.resize(_w * _h)
	var q := PackedInt32Array()
	for x: int in range(_w):
		_seen_seed(seen, q, x)
		_seen_seed(seen, q, (_h - 1) * _w + x)
	for y: int in range(1, _h - 1):
		_seen_seed(seen, q, y * _w)
		_seen_seed(seen, q, y * _w + _w - 1)
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % _w
		var y := i / _w
		if x > 0 and seen[i - 1] == 0 and _near_field(i - 1):
			seen[i - 1] = 1
			q.append(i - 1)
		if x < _w - 1 and seen[i + 1] == 0 and _near_field(i + 1):
			seen[i + 1] = 1
			q.append(i + 1)
		if y > 0 and seen[i - _w] == 0 and _near_field(i - _w):
			seen[i - _w] = 1
			q.append(i - _w)
		if y < _h - 1 and seen[i + _w] == 0 and _near_field(i + _w):
			seen[i + _w] = 1
			q.append(i + _w)
	for i: int in range(_w * _h):
		if kept[i] == 1 and seen[i] == 0 and _near_field(i):
			kept[i] = 0


func _seen_seed(seen: PackedByteArray, q: PackedInt32Array, i: int) -> void:
	if seen[i] == 1 or not _near_field(i):
		return
	seen[i] = 1
	q.append(i)


# Absolute distance to the measured field, far tighter than the keying tolerance: an
# island of sky trapped inside a prop is the untouched field colour, while a cream
# coin highlight on a cream field is tens of units away and has to survive.
func _near_field(i: int) -> bool:
	var dr: float = float(_px[i * 4]) - _field.x
	var dg: float = float(_px[i * 4 + 1]) - _field.y
	var db: float = float(_px[i * 4 + 2]) - _field.z
	return dr * dr + dg * dg + db * db < ISLAND_TOL * ISLAND_TOL


# Labels every isolated piece of art with its bounding box and area, in one pass,
# and keeps the label map in _ids for the mask step to read back. Takes the eroded
# core mask, so `box` grows back by the erosion radius.
func _parts(core: PackedByteArray) -> Array[Dictionary]:
	_ids.resize(_w * _h)
	_ids.fill(0)
	var out: Array[Dictionary] = []
	var id := 0
	var q := PackedInt32Array()
	for i: int in range(_w * _h):
		if core[i] == 0 or _ids[i] != 0:
			continue
		id += 1
		q.resize(0)
		q.append(i)
		_ids[i] = id
		var head := 0
		var size := 0
		var x0 := _w
		var y0 := _h
		var x1 := 0
		var y1 := 0
		while head < q.size():
			var c: int = q[head]
			head += 1
			size += 1
			var x := c % _w
			var y := c / _w
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x + 1)
			y1 = maxi(y1, y + 1)
			if x > 0 and core[c - 1] == 1 and _ids[c - 1] == 0:
				_ids[c - 1] = id
				q.append(c - 1)
			if x < _w - 1 and core[c + 1] == 1 and _ids[c + 1] == 0:
				_ids[c + 1] = id
				q.append(c + 1)
			if y > 0 and core[c - _w] == 1 and _ids[c - _w] == 0:
				_ids[c - _w] = id
				q.append(c - _w)
			if y < _h - 1 and core[c + _w] == 1 and _ids[c + _w] == 0:
				_ids[c + _w] = id
				q.append(c + _w)
		out.append({
			"id": id,
			"size": size,
			"box": Rect2i(
				maxi(0, x0 - 2), maxi(0, y0 - 2),
				mini(_w, x1 + 2) - maxi(0, x0 - 2), mini(_h, y1 + 2) - maxi(0, y0 - 2)
			),
		})
	return out


# Reading order: cluster into rows by centre height, then sort each row left to
# right. Without this a prop that sits a little higher than its neighbour would
# steal its label.
func _rows(parts: Array[Dictionary]) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for p: Dictionary in parts:
		list.append(p)
	list.sort_custom(_by_cy)
	var rows: Array[Dictionary] = []
	var group: Array[Dictionary] = []
	var anchor := 0.0
	for p: Dictionary in list:
		var box: Rect2i = p.box
		var cy: float = float(box.position.y) + float(box.size.y) * 0.5
		if not group.is_empty():
			var gb: Rect2i = group[0].box
			if absf(cy - anchor) > float(gb.size.y) * 0.55:
				_flush(group, rows)
				group = []
		if group.is_empty():
			anchor = cy
		group.append(p)
	_flush(group, rows)
	return rows


func _by_cy(a: Dictionary, b: Dictionary) -> bool:
	var ra: Rect2i = a.box
	var rb: Rect2i = b.box
	return ra.position.y + ra.size.y * 0.5 < rb.position.y + rb.size.y * 0.5


func _flush(group: Array[Dictionary], into: Array[Dictionary]) -> void:
	if group.is_empty():
		return
	group.sort_custom(_by_cx)
	for p: Dictionary in group:
		into.append(p)


func _by_cx(a: Dictionary, b: Dictionary) -> bool:
	var ra: Rect2i = a.box
	var rb: Rect2i = b.box
	return ra.position.x < rb.position.x


# --------------------------------------------------------------------------------
# baking
# --------------------------------------------------------------------------------
# The generator stamps "Qoder AI 生成" into the bottom-right corner of every sheet.
# On a props sheet that scrawl is rejected by the shape tests; on a parallax band it
# lands in the middle of the art, so the corner is repainted with a mirrored copy of
# the strip to its left. Foliage hides the seam, rock hides the seam.
func _patch_watermark() -> void:
	var w: int = maxi(96, int(_w * 0.13))
	var h: int = maxi(24, int(_h * 0.09))
	var x0: int = _w - w
	if x0 <= 0:
		return
	for y: int in range(_h - h, _h):
		for x: int in range(w):
			var src: int = y * _w + (x0 - 1 - x)
			var dst: int = y * _w + x0 + x
			for c: int in range(4):
				_px[dst * 4 + c] = _px[src * 4 + c]


func _bake(job: Dictionary) -> void:
	var src := "res://assets/src/" + String(job.src)
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(src)) != OK:
		_fail("cannot load %s" % src)
		return
	img.convert(Image.FORMAT_RGBA8)
	_w = img.get_width()
	_h = img.get_height()
	_px = img.get_data()
	_tol = 55.0
	_field = Vector3.ZERO
	_edge = 1 if String(job.get("band", "")) == "stand" else (2 if String(job.get("band", "")) == "hang" else 0)
	print("[env] %s %dx%d" % [job.src, _w, _h])
	if _edge != 0:
		_patch_watermark()
	_detect_field()
	if _report_only:
		return

	var labels: Array = job.labels
	var attempt := _solve_field(job, labels.size())
	if attempt.parts.size() != labels.size():
		var raw: Array[Dictionary] = attempt.raw
		raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.size) > int(b.size))
		for i: int in range(mini(8, raw.size())):
			var rb: Rect2i = raw[i].box
			print("[env]   raw %d size=%d box=%dx%d@%d,%d" % [
				i, int(raw[i].size), rb.size.x, rb.size.y, rb.position.x, rb.position.y
			])
	var gone: PackedByteArray = attempt.gone
	var parts: Array[Dictionary] = attempt.parts

	# Every kept piece gets its edge un-premultiplied in one whole-sheet pass, so
	# the blend math sees the same neighbourhood it was written for.
	var keep_ids := {}
	for p: Dictionary in parts:
		keep_ids[int(p.id)] = true
	var kept := PackedByteArray()
	kept.resize(_w * _h)
	for i: int in range(_w * _h):
		kept[i] = 1 if keep_ids.has(_ids[i]) else 0
	_punch_islands(kept)
	_bk._soften_edge(_px, kept, gone, _w, _h)
	for i: int in range(_w * _h):
		if kept[i] == 0:
			_px[i * 4 + 3] = 0
	if _edge != 0:
		# A band that kept its sky instead of its silhouette still reports exactly one
		# piece, so the only thing that tells the two apart is which edge has art: the
		# one opposite the edge the field was measured from.
		var top_art := 0
		var bot_art := 0
		for x: int in range(_w):
			top_art += int(kept[x])
			bot_art += int(kept[(_h - 1) * _w + x])
		var near := bot_art if _edge == 1 else top_art
		var far := top_art if _edge == 1 else bot_art
		if far * 10 > _w or near * 10 < _w:
			_fail("%s keyed the sky, not the silhouette (top %d%%, bottom %d%% art)" % [
				job.src, top_art * 100 / _w, bot_art * 100 / _w
			])
			return
	var sheet := Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	sheet.set_data(_w, _h, false, Image.FORMAT_RGBA8, _px)

	var cells: Array[Dictionary] = []
	var chosen: Array[Dictionary] = parts
	if job.has("band"):
		var union := Rect2i(0, 0, 0, 0)
		var first := true
		for p: Dictionary in chosen:
			var b: Rect2i = p.box
			union = b if first else union.merge(b)
			first = false
		cells = [{"box": union, "size": 1}]
	else:
		for p: Dictionary in _rows(chosen):
			if int(p.size) >= MIN_CELL_ART:
				cells.append(p)
	if cells.size() != labels.size():
		_fail("%s found %d pieces, expected %d (%s)" % [
			job.src, cells.size(), labels.size(), _dump(cells)
		])
		return

	for i: int in range(cells.size()):
		var box: Rect2i = cells[i].box
		if box.size.x < 8 or box.size.y < 8:
			_fail("%s cell %d (%s) is empty" % [job.src, i, labels[i]])
			continue
		var keyed := sheet.get_region(box)
		if job.has("cap_crop"):
			# A crust strip's lower half is flat fill, so only the fringe is worth
			# carrying: this leaves a low wide tile that reads as a crust, not a slab.
			var keep_h: int = mini(keyed.get_height(), maxi(
				int(float(keyed.get_height()) * 0.2), int(float(keyed.get_width()) / 6.0)
			))
			keyed = keyed.get_region(Rect2i(0, 0, keyed.get_width(), keep_h))
		var label := String(labels[i])
		keyed = _fit(keyed, float(BAND_TARGET) if job.has("band") else float(job.get("max", 220.0)))
		if (job.get("round", []) as Array).has(label):
			keyed = _centre_square(keyed)
		if job.has("cap_report"):
			_report_base(keyed, label)
		# A piece can be found, counted, cropped and still be nothing: a box that
		# landed on sky. Coverage is the only test that says so.
		var filled := _coverage(keyed)
		if filled < 0.12:
			_fail("%s %s is %d%% opaque, expected a prop" % [job.src, label, int(filled * 100.0)])
			continue
		_write(keyed, label)
		if job.has("mirror"):
			var mir := keyed.duplicate()
			mir.flip_x()
			_write(mir, label + "_m")
		_out.append({"label": label, "img": keyed, "band": job.has("band")})


func _coverage(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var hit := 0
	var n := 0
	for y: int in range(0, h, 2):
		for x: int in range(0, w, 2):
			n += 1
			if img.get_pixel(x, y).a > 0.06:
				hit += 1
	return float(hit) / float(maxi(1, n))


func _fit(img: Image, max_dim: float) -> Image:
	var w := float(img.get_width())
	var h := float(img.get_height())
	var k: float = minf(1.0, max_dim / maxf(w, h))
	if k >= 1.0:
		return img
	return _bk._resample(img, maxi(8, int(w * k)), maxi(8, int(h * k)))


# A saw blade or a cog has to spin about its own middle, so pad it to a square
# first: wherever the draw call lands, the sprite centre is the axle.
func _centre_square(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var side := maxi(w, h)
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((side - w) / 2, (side - h) / 2))
	return out


# The cap strips are drawn over a procedurally shaded slab, so the body colour has
# to be the colour the strip actually ended up as.
func _report_base(img: Image, label: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var sum := Vector3.ZERO
	var n := 0
	for y: int in range(maxi(0, h - 12), h):
		for x: int in range(0, w, 3):
			var c := img.get_pixel(x, y)
			if c.a < 0.6:
				continue
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return
	print("[cap] %s base = %s size=%dx%d" % [label, Color(sum.x / n, sum.y / n, sum.z / n).to_html(true), w, h])


func _write(img: Image, label: String) -> void:
	if img.save_png(OUT_DIR + label + ".png") != OK:
		_fail("cannot write " + label)


# Everything on one board so a leftover magenta halo or a clipped prop is obvious
# in a single look.
func _contact_sheet() -> void:
	var cw := 300
	var ch := 230
	var cols := 6
	var rows := ceili(_out.size() / float(cols))
	var sheet := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.24, 0.20, 0.30, 1.0))
	for i: int in range(_out.size()):
		var e: Dictionary = _out[i]
		var img: Image = e.img
		var box := Vector2(cw - 14.0, ch - 14.0)
		var k: float = minf(1.0, minf(box.x / img.get_width(), box.y / img.get_height()))
		if k < 1.0:
			img = _bk._resample(img, maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)))
		var at := Vector2(
			float(i % cols) * cw + (cw - img.get_width()) * 0.5,
			float(i / cols) * ch + ch - img.get_height() - 7.0
		)
		_bk._composite(sheet, img, at)
	var path := OS.get_user_data_dir().path_join("qa/env_contact.png")
	if sheet.save_png(path) != OK:
		_fail("cannot write " + path)
	print("[env] contact sheet -> " + path)


func _dump(cells: Array[Dictionary]) -> String:
	var t: Array[String] = []
	for c: Dictionary in cells:
		var b: Rect2i = c.box
		t.append("%dx%d@%d,%d" % [b.size.x, b.size.y, b.position.x, b.position.y])
	return ", ".join(t)


func _fail(message: String) -> void:
	_fails += 1
	push_error(message)
	print("[FAIL] ", message)
