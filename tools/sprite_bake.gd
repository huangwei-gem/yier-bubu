# Bakes the AI-generated pose sheets into transparent game frames. Each sheet is
# one row of poses on a flat studio field: the tool splits the row on empty
# columns, keys each cell, drops the watermark, un-premultiplies the silhouette
# edge, then rescales every pose by its own eye spacing so the head is the same
# size in all of them and the feet share one baseline.
#
# Run: godot --headless --path . res://tools/sprite_bake.tscn
extends Node

const SHEETS := [
	{
		"src": "res://assets/src/yier_sheet.png",
		"name": "yier",
		# Sampled off the user's reference photo. Text-to-image cannot be steered
		# onto an exact hex, so the palette is re-applied here instead of asked for.
		"body": "ffffff",
		"ink": "46241c",
		"blush": "fec4b9",
	},
	{
		"src": "res://assets/src/bubu_sheet.png",
		"name": "bubu",
		"body": "e0a48a",
		"ink": "48251f",
		"blush": "f7c389",
	},
]
const LABELS := ["idle", "run_a", "run_b", "jump", "fall"]
# The idle pose is normalised to this height first; every other pose is then
# matched to it by inter-eye distance rather than by bounding box, because a
# tucked jump is genuinely shorter and must not be blown up to compensate.
const REF_H := 240.0
const CELL_W := 256
const CELL_H := 272
const PAD := 6
const MIN_SEG_W := 80
const ICON_OUT := "res://assets/icon.png"
const ICON_SIZE := 512
const SUPERSAMPLE := 2
const EDGE := 4

# The generated art always sits on a rose/magenta field, so "more red and more
# blue than green" identifies background at any brightness the gradient hits.
# Neither character has a pixel matching it: 一二's pink cheeks and 布布's
# apricot cheeks are both far bluer-than-red.
const BG_R_OVER_G := 40.0
const BG_B_OVER_G := 18.0
const BG_MIN_R := 130.0


func _ready() -> void:
	var idle: Array[Image] = []
	for job: Dictionary in SHEETS:
		var pal := {
			"body": String(job.body), "ink": String(job.ink), "blush": String(job.blush)
		}
		var got := _bake_sheet(String(job.src), String(job.name), pal)
		if got == null:
			push_error("bake failed for " + String(job.src))
			continue
		idle.append(got)
	if idle.size() == SHEETS.size():
		_make_icon(idle)
	get_tree().quit()


func _bake_sheet(src: String, name: String, pal: Dictionary) -> Image:
	var t0 := Time.get_ticks_msec()
	var sheet := Image.new()
	# Read as bytes rather than Image.load_from_file: these sources are tool-only
	# inputs that never ship, and the raw-file loader warns about exactly that.
	if sheet.load_png_from_buffer(FileAccess.get_file_as_bytes(src)) != OK:
		push_error("cannot load " + src)
		return null
	sheet.convert(Image.FORMAT_RGBA8)
	var w := sheet.get_width()
	var h := sheet.get_height()
	var segs := _segments(sheet.get_data(), w, h)
	if segs.size() != LABELS.size():
		push_error("%s split into %d cells, expected %d" % [name, segs.size(), LABELS.size()])
		return null

	var keyed: Array[Image] = []
	var spans: Array[float] = []
	var pairs: Array[Dictionary] = []
	for seg: Vector2i in segs:
		var cell := _key_cell(sheet.get_region(Rect2i(seg.x, 0, seg.y, h)), pal)
		var pair := _eye_pair(_find_eyes(cell), cell.get_width() * 0.5, cell.get_height())
		if pair.is_empty():
			push_error("%s: no eye pair found in one cell" % name)
			return null
		keyed.append(cell)
		pairs.append(pair)
		spans.append(float(pair.span))

	var scale0: float = REF_H / float(keyed[0].get_height())
	var eye_canon: float = spans[0] * scale0
	var scaled: Array[Image] = []
	for i: int in range(keyed.size()):
		var s: float = eye_canon / spans[i]
		scaled.append(
			_resample(keyed[i], int(round(float(keyed[i].get_width()) * s)), int(round(float(keyed[i].get_height()) * s)))
		)
		print("   %-6s %dx%d  eye=%.1f  scale=%.3f" % [LABELS[i], scaled[i].get_width(), scaled[i].get_height(), spans[i], s])

	var blink := keyed[0].duplicate()
	_paint_closed_eyes(blink, pairs[0].list)
	scaled.append(_resample(blink, scaled[0].get_width(), scaled[0].get_height()))

	var cw := 0
	var ch := 0
	for f: Image in scaled:
		cw = maxi(cw, f.get_width())
		ch = maxi(ch, f.get_height())
	if cw > CELL_W - PAD * 2 or ch > CELL_H - PAD * 2:
		push_error("%s frames %dx%d overflow the %dx%d cell" % [name, cw, ch, CELL_W, CELL_H])
		return null
	var baseline := float(CELL_H - PAD)
	var out_dir := "res://assets/sprites/%s" % name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for i: int in range(scaled.size()):
		var label: String = LABELS[i] if i < LABELS.size() else "blink"
		var canvas := Image.create(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
		_blit_bottom(canvas, scaled[i], baseline)
		var path := "%s/%s.png" % [out_dir, label]
		if canvas.save_png(path) != OK:
			push_error("save failed " + path)
	_key_out(name, cw, ch, t0)
	return _resample(scaled[0], int(float(scaled[0].get_width()) * 0.9), int(REF_H * 0.9))


func _key_out(name: String, cw: int, ch: int, t0: int) -> void:
	print("[bake] %s widest=%d tallest=%d cell=%dx%d  %dms" % [name, cw, ch, CELL_W, CELL_H, Time.get_ticks_msec() - t0])


# A column with no character pixel in it at all separates two poses.
func _segments(px: PackedByteArray, w: int, h: int) -> Array[Vector2i]:
	var segs: Array[Vector2i] = []
	var x := 0
	while x < w:
		var open := true
		for y: int in range(0, h, 2):
			if not _is_bg(px, y * w + x):
				open = false
				break
		x += 1
		if open:
			continue
		var x0 := x - 1
		while x < w:
			var still := true
			for y: int in range(0, h, 2):
				if not _is_bg(px, y * w + x):
					still = false
					break
			if still:
				break
			x += 1
		if x - x0 >= MIN_SEG_W:
			segs.append(Vector2i(x0, x - x0))
	return segs


func _key_cell(cell: Image, pal: Dictionary = {}, white: bool = false) -> Image:
	cell.convert(Image.FORMAT_RGBA8)
	var w := cell.get_width()
	var h := cell.get_height()
	var px := cell.get_data()
	var gone := _flood_background(px, w, h, white)
	var kept := _largest_shape(gone, w, h)
	if not pal.is_empty():
		_snap_palette(px, kept, gone, w, h, pal)
	_soften_edge(px, kept, gone, w, h)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.set_data(w, h, false, Image.FORMAT_RGBA8, px)
	return out.get_region(out.get_used_rect())


# Re-applies the measured reference palette. The generator cannot be steered
# onto an exact hex — 布布 came out rose once and beige once — so the three
# dominant fills are bucketed and rewritten instead. Pixels near the silhouette
# edge are skipped so the anti-aliased blend survives to be un-premultiplied.
func _snap_palette(
	px: PackedByteArray, kept: PackedByteArray, gone: PackedByteArray, w: int, h: int, pal: Dictionary
) -> void:
	var band := _dilate(gone, w, h, EDGE + 2)
	var counts := {}
	var sums := {}
	for i: int in range(w * h):
		if int(kept[i]) == 0 or int(band[i]) == 1:
			continue
		var o := i * 4
		var key: int = ((px[o] >> 4) << 8) | ((px[o + 1] >> 4) << 4) | (px[o + 2] >> 4)
		counts[key] = int(counts.get(key, 0)) + 1
		var s: Array = sums.get(key, [0, 0, 0])
		s[0] += int(px[o])
		s[1] += int(px[o + 1])
		s[2] += int(px[o + 2])
		sums[key] = s
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b) -> bool: return int(counts[a]) > int(counts[b]))
	var reps: Array[Dictionary] = []
	for k: int in keys.slice(0, mini(6, keys.size())):
		var c := int(counts[k])
		var s: Array = sums[k]
		reps.append({
			"c": Color(float(s[0]) / float(c) / 255.0, float(s[1]) / float(c) / 255.0, float(s[2]) / float(c) / 255.0),
			"n": c
		})
	if reps.size() < 2:
		return
	var body_i := 0
	var ink_i := 0
	for i: int in range(reps.size()):
		if int(reps[i].n) > int(reps[body_i].n):
			body_i = i
		if _lum(reps[i].c) < _lum(reps[ink_i].c):
			ink_i = i
	var blush_i := -1
	for i: int in range(reps.size()):
		if i == body_i or i == ink_i:
			continue
		if blush_i < 0 or _spread(reps[i].c) > _spread(reps[blush_i].c):
			blush_i = i
	var rep_label := {}
	rep_label[body_i] = 1
	rep_label[ink_i] = 2
	if blush_i >= 0:
		rep_label[blush_i] = 3
	var total_kept := 0
	var lbl := PackedByteArray()
	lbl.resize(w * h)
	for i: int in range(w * h):
		if int(kept[i]) == 0 or int(band[i]) == 1:
			continue
		total_kept += 1
		var o := i * 4
		var cur := Vector3(float(px[o]), float(px[o + 1]), float(px[o + 2]))
		var best_i := -1
		var best_d := 1e20
		for r: int in range(reps.size()):
			var rc: Color = reps[r].c
			var d: float = cur.distance_squared_to(Vector3(rc.r * 255.0, rc.g * 255.0, rc.b * 255.0))
			if d < best_d:
				best_d = d
				best_i = r
		lbl[i] = int(rep_label.get(best_i, 0))
	_prune_blush(lbl, w, h, total_kept)
	for i: int in range(w * h):
		if lbl[i] == 0:
			continue
		var out: Color = [Color(), Color(String(pal.body)), Color(String(pal.ink)), Color(String(pal.blush))][lbl[i]]
		var o := i * 4
		px[o] = int(round(out.r * 255.0))
		px[o + 1] = int(round(out.g * 255.0))
		px[o + 2] = int(round(out.b * 255.0))


# The blush bucket is chosen by colour spread, so a soft shaded band along the
# jaw gets scooped up too and turns into a wide pink stripe. Real cheeks are two
# small round blobs, so anything else wearing the blush colour goes back to body.
func _prune_blush(lbl: PackedByteArray, w: int, h: int, total_kept: int) -> void:
	if total_kept <= 0:
		return
	var seen := PackedByteArray()
	seen.resize(w * h)
	var q := PackedInt32Array()
	for i: int in range(w * h):
		if int(lbl[i]) != 3 or int(seen[i]) != 0:
			continue
		q.resize(0)
		q.append(i)
		seen[i] = 1
		var size := 0
		var minx := w
		var maxx := 0
		var miny := h
		var maxy := 0
		var head := 0
		while head < q.size():
			var c: int = q[head]
			head += 1
			size += 1
			var x := c % w
			var y := c / w
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			miny = mini(miny, y)
			maxy = maxi(maxy, y)
			if x > 0 and int(lbl[c - 1]) == 3 and int(seen[c - 1]) == 0:
				seen[c - 1] = 1
				q.append(c - 1)
			if x < w - 1 and int(lbl[c + 1]) == 3 and int(seen[c + 1]) == 0:
				seen[c + 1] = 1
				q.append(c + 1)
			if y > 0 and int(lbl[c - w]) == 3 and int(seen[c - w]) == 0:
				seen[c - w] = 1
				q.append(c - w)
			if y < h - 1 and int(lbl[c + w]) == 3 and int(seen[c + w]) == 0:
				seen[c + w] = 1
				q.append(c + w)
		var bw := float(maxx - minx + 1)
		var bh := float(maxy - miny + 1)
		var fill := float(size) / (bw * bh)
		var ok: bool = (
			float(size) >= float(total_kept) * 0.0004
			and float(size) <= float(total_kept) * 0.02
			and fill >= 0.5
			and bw / bh >= 0.55
			and bw / bh <= 1.8
		)
		if ok:
			continue
		for k: int in range(q.size()):
			lbl[q[k]] = 1


func _lum(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


func _spread(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


func _blit_bottom(canvas: Image, f: Image, baseline: float) -> void:
	var ox := int(round(float(canvas.get_width() - f.get_width()) * 0.5))
	var oy := int(round(baseline - float(f.get_height())))
	for y: int in range(f.get_height()):
		for x: int in range(f.get_width()):
			var c := f.get_pixel(x, y)
			if c.a > 0.001:
				canvas.set_pixel(ox + x, oy + y, c)


# The eyes are the only blob pair that is equal in size, level, and symmetric
# about the face — an open mouth in the jump pose breaks all three. 布布's dark
# inner-ear crescents are also symmetric and level, so the pair is required to
# sit below the crown band where ears can never reach.
func _eye_pair(blobs: Array[Dictionary], cx: float, img_h: float = 0.0) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 1e20
	for i: int in range(blobs.size()):
		for j: int in range(i + 1, blobs.size()):
			var a: Dictionary = blobs[i]
			var b: Dictionary = blobs[j]
			if img_h > 0.0 and (
				float(a.centre.y) < img_h * 0.22 or float(b.centre.y) < img_h * 0.22
			):
				continue
			var span: float = absf(float(b.centre.x) - float(a.centre.x))
			if span < 20.0:
				continue
			var mid: float = (float(a.centre.x) + float(b.centre.x)) * 0.5
			var ratio: float = maxf(float(a.area), float(b.area)) / maxf(1.0, minf(float(a.area), float(b.area)))
			var score: float = (
				absf(float(a.centre.y) - float(b.centre.y)) * 3.0
				+ absf(mid - cx) * 1.5
				+ absf(ratio - 1.0) * 40.0
			)
			if score >= best_score:
				continue
			best_score = score
			var pair: Array[Dictionary] = [a, b]
			best = {"span": span, "list": pair}
	return best


# 1 = this pixel is studio background, reachable from the picture edge.
# The generated sheets sit on magenta; the reference photos sit on white, so the
# measuring tool asks for the other test.
func _flood_background(px: PackedByteArray, w: int, h: int, white: bool = false) -> PackedByteArray:
	var gone := PackedByteArray()
	gone.resize(w * h)
	var q := PackedInt32Array()
	for x: int in range(w):
		_seed(q, gone, px, x, white)
		_seed(q, gone, px, (h - 1) * w + x, white)
	for y: int in range(1, h - 1):
		_seed(q, gone, px, y * w, white)
		_seed(q, gone, px, y * w + w - 1, white)
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % w
		var y := i / w
		if x > 0 and gone[i - 1] == 0 and _is_bg(px, i - 1, white):
			gone[i - 1] = 1
			q.append(i - 1)
		if x < w - 1 and gone[i + 1] == 0 and _is_bg(px, i + 1, white):
			gone[i + 1] = 1
			q.append(i + 1)
		if y > 0 and gone[i - w] == 0 and _is_bg(px, i - w, white):
			gone[i - w] = 1
			q.append(i - w)
		if y < h - 1 and gone[i + w] == 0 and _is_bg(px, i + w, white):
			gone[i + w] = 1
			q.append(i + w)
	return gone


func _seed(q: PackedInt32Array, gone: PackedByteArray, px: PackedByteArray, i: int, white: bool = false) -> void:
	if gone[i] == 1 or not _is_bg(px, i, white):
		return
	gone[i] = 1
	q.append(i)


func _is_bg(px: PackedByteArray, i: int, white: bool = false) -> bool:
	var r: float = float(px[i * 4])
	var g: float = float(px[i * 4 + 1])
	var b: float = float(px[i * 4 + 2])
	if white:
		return r > 235.0 and g > 235.0 and b > 235.0
	return r > g + BG_R_OVER_G and b > g + BG_B_OVER_G and r > BG_MIN_R


# Only the biggest blob survives: the generator's watermark sits in a corner of
# the same field and would otherwise come along.
func _largest_shape(gone: PackedByteArray, w: int, h: int) -> PackedByteArray:
	# Labels go in an int array: a PackedByteArray would wrap at 256 and hand a
	# later component the same mark as an earlier one.
	var seen := PackedInt32Array()
	seen.resize(w * h)
	var best_size := 0
	var best_label := 0
	var label := 0
	var q := PackedInt32Array()
	for i: int in range(w * h):
		if gone[i] == 1 or seen[i] != 0:
			continue
		label += 1
		var size := 0
		q.resize(0)
		q.append(i)
		seen[i] = label
		var head := 0
		while head < q.size():
			var c: int = q[head]
			head += 1
			size += 1
			var x := c % w
			var y := c / w
			if x > 0 and gone[c - 1] == 0 and seen[c - 1] == 0:
				seen[c - 1] = label
				q.append(c - 1)
			if x < w - 1 and gone[c + 1] == 0 and seen[c + 1] == 0:
				seen[c + 1] = label
				q.append(c + 1)
			if y > 0 and gone[c - w] == 0 and seen[c - w] == 0:
				seen[c - w] = label
				q.append(c - w)
			if y < h - 1 and gone[c + w] == 0 and seen[c + w] == 0:
				seen[c + w] = label
				q.append(c + w)
		if size > best_size:
			best_size = size
			best_label = label
	var kept := PackedByteArray()
	kept.resize(w * h)
	for i: int in range(w * h):
		kept[i] = 1 if seen[i] == best_label else 0
	print("[bake] silhouette kept %d px of %d" % [best_size, w * h])
	return kept


# Anti-aliased pixels along the silhouette are a blend of outline and studio
# pink. Solving p = bg*(1-a) + fg*a for a gives a real coverage value instead of
# a hard 1px edge, and the recovered fg stops the outline from going purple.
func _soften_edge(
	px: PackedByteArray, kept: PackedByteArray, gone: PackedByteArray, w: int, h: int
) -> void:
	var fg_map := _nearest_source(_erode(kept, w, h, EDGE), w, h)
	var band := _dilate(gone, w, h, EDGE)
	for i: int in range(w * h):
		if int(kept[i]) != 1 or int(band[i]) == 0:
			continue
		var j: int = fg_map[i]
		if j < 0:
			continue
		var bg := _bg_near(px, gone, w, h, i)
		var o := i * 4
		var dr: float = float(px[j * 4]) - bg.x
		var dg: float = float(px[j * 4 + 1]) - bg.y
		var db: float = float(px[j * 4 + 2]) - bg.z
		var den: float = dr * dr + dg * dg + db * db
		if den < 900.0:
			continue
		var num: float = (float(px[o]) - bg.x) * dr + (float(px[o + 1]) - bg.y) * dg + (float(px[o + 2]) - bg.z) * db
		var a: float = clampf(num / den, 0.0, 1.0)
		if a < 0.04:
			px[o + 3] = 0
			continue
		px[o] = int(clampf((float(px[o]) - bg.x * (1.0 - a)) / a, 0.0, 255.0))
		px[o + 1] = int(clampf((float(px[o + 1]) - bg.y * (1.0 - a)) / a, 0.0, 255.0))
		px[o + 2] = int(clampf((float(px[o + 2]) - bg.z * (1.0 - a)) / a, 0.0, 255.0))
		px[o + 3] = int(a * 255.0)
	for i: int in range(w * h):
		if int(kept[i]) == 0:
			px[i * 4 + 3] = 0


func _bg_near(px: PackedByteArray, gone: PackedByteArray, w: int, h: int, i: int) -> Vector3:
	var x := i % w
	var y := i / w
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var n := 0
	for dy: int in range(-EDGE, EDGE + 1):
		var v: int = y + dy
		if v < 0 or v >= h:
			continue
		var row := v * w
		for dx: int in range(-EDGE, EDGE + 1):
			var u: int = x + dx
			if u < 0 or u >= w:
				continue
			if int(gone[row + u]) == 0:
				continue
			sr += float(px[(row + u) * 4])
			sg += float(px[(row + u) * 4 + 1])
			sb += float(px[(row + u) * 4 + 2])
			n += 1
	if n == 0:
		return Vector3(236.0, 88.0, 148.0)
	return Vector3(sr / float(n), sg / float(n), sb / float(n))


# Separable "every pixel in the window is set" / "any pixel in the window is
# set" filters, via prefix sums — a nested radius loop over a megapixel takes
# minutes in GDScript.
func _erode(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _window(_window(mask, w, h, r, true, false), w, h, r, false, false)


func _dilate(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _window(_window(mask, w, h, r, true, true), w, h, r, false, true)


func _window(
	src: PackedByteArray, w: int, h: int, r: int, horiz: bool, any: bool
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	var major := h if horiz else w
	var minor := w if horiz else h
	var pre := PackedInt32Array()
	pre.resize(minor + 1)
	for m: int in range(major):
		pre[0] = 0
		if horiz:
			var row := m * w
			for n: int in range(minor):
				var v: int = int(src[row + n])
				pre[n + 1] = pre[n] + ((1 - v) if not any else v)
			for n: int in range(minor):
				var s: int = pre[mini(minor, n + r + 1)] - pre[maxi(0, n - r)]
				out[row + n] = (1 if s == 0 else 0) if not any else (1 if s > 0 else 0)
		else:
			for n: int in range(minor):
				var v2: int = int(src[n * w + m])
				pre[n + 1] = pre[n] + ((1 - v2) if not any else v2)
			for n: int in range(minor):
				var s2: int = pre[mini(minor, n + r + 1)] - pre[maxi(0, n - r)]
				out[n * w + m] = (1 if s2 == 0 else 0) if not any else (1 if s2 > 0 else 0)
	return out


# Multi-source BFS: every pixel learns which solid pixel owns it, so an edge
# pixel can borrow the colour of the outline it is fading into.
func _nearest_source(solid: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(w * h)
	map.fill(-1)
	var q := PackedInt32Array()
	for i: int in range(w * h):
		if int(solid[i]) == 1:
			map[i] = i
			q.append(i)
	var head := 0
	while head < q.size():
		var c: int = q[head]
		head += 1
		var x := c % w
		var y := c / w
		if x > 0 and map[c - 1] == -1:
			map[c - 1] = map[c]
			q.append(c - 1)
		if x < w - 1 and map[c + 1] == -1:
			map[c + 1] = map[c]
			q.append(c + 1)
		if y > 0 and map[c - w] == -1:
			map[c - w] = map[c]
			q.append(c - w)
		if y < h - 1 and map[c + w] == -1:
			map[c + w] = map[c]
			q.append(c + w)
	return map


# Small isolated dark blobs are the eyes; the outline is one huge blob hugging
# the silhouette and the ω mouth is too thin, so neither shows up here.
func _find_eyes(img: Image) -> Array[Dictionary]:
	var w := img.get_width()
	var h := img.get_height()
	var dark := PackedByteArray()
	dark.resize(w * h)
	for y: int in range(h):
		for x: int in range(w):
			var c := img.get_pixel(x, y)
			if c.a > 0.6 and (c.r + c.g + c.b) / 3.0 < 0.34:
				dark[y * w + x] = 1
	var seen := PackedByteArray()
	seen.resize(w * h)
	var found: Array[Dictionary] = []
	var q := PackedInt32Array()
	for i: int in range(w * h):
		if int(dark[i]) == 0 or int(seen[i]) != 0:
			continue
		q.resize(0)
		q.append(i)
		seen[i] = 1
		var size := 0
		var sx := 0.0
		var sy := 0.0
		var minx := w
		var maxx := 0
		var miny := h
		var maxy := 0
		var head := 0
		while head < q.size():
			var c: int = q[head]
			head += 1
			size += 1
			var x := c % w
			var y := c / w
			sx += float(x)
			sy += float(y)
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			miny = mini(miny, y)
			maxy = maxi(maxy, y)
			if x > 0 and dark[c - 1] == 1 and seen[c - 1] == 0:
				seen[c - 1] = 1
				q.append(c - 1)
			if x < w - 1 and dark[c + 1] == 1 and seen[c + 1] == 0:
				seen[c + 1] = 1
				q.append(c + 1)
			if y > 0 and dark[c - w] == 1 and seen[c - w] == 0:
				seen[c - w] = 1
				q.append(c - w)
			if y < h - 1 and dark[c + w] == 1 and seen[c + w] == 0:
				seen[c + w] = 1
				q.append(c + w)
		var bw := float(maxx - minx + 1)
		var bh := float(maxy - miny + 1)
		if size < 80 or size > 6000 or bw / bh < 0.5 or bw / bh > 2.2:
			continue
		found.append(
			{
				"area": size,
				"centre": Vector2(sx / float(size), sy / float(size)),
				"box": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1),
				"norm": Vector2(sx / float(size) / float(w), sy / float(size) / float(h)),
				"ink": img.get_pixel(int(sx / float(size)), int(sy / float(size))),
			}
		)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a.area) > int(b.area)
	)
	return found


# A second pose with the eyes shut, baked at source resolution. Painting the
# blink live at 42 px leaves a visible smudge, so the pair just swap textures.
func _paint_closed_eyes(img: Image, eyes: Array[Dictionary]) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var hole := PackedByteArray()
	hole.resize(w * h)
	for e: Dictionary in eyes:
		var bb: Rect2i = e.box
		for y: int in range(maxi(0, bb.position.y - 6), mini(h, bb.end.y + 6)):
			for x: int in range(maxi(0, bb.position.x - 6), mini(w, bb.end.x + 6)):
				hole[y * w + x] = 1
	_inpaint(img, hole, w, h)
	for e: Dictionary in eyes:
		_closed_bar(img, Vector2(e.centre), float(e.box.size.x), float(e.box.size.y), Color(e.ink))


# Fills the erased eye discs by growing the surrounding face inwards, so the
# soft shading the generated art puts on the head carries through instead of a
# flat patch standing out.
func _inpaint(img: Image, hole: PackedByteArray, w: int, h: int) -> void:
	var todo := PackedInt32Array()
	for i: int in range(w * h):
		if int(hole[i]) == 1:
			todo.append(i)
	var filled := PackedByteArray()
	filled.resize(w * h)
	filled.fill(1)
	for i: int in range(w * h):
		if int(hole[i]) == 1:
			filled[i] = 0
	var left := todo.size()
	var rounds := 0
	while left > 0 and rounds < 80:
		rounds += 1
		var next := PackedInt32Array()
		for i: int in range(left):
			var c: int = todo[i]
			if int(filled[c]) == 1:
				continue
			var x := c % w
			var y := c / w
			var sr := 0.0
			var sg := 0.0
			var sb := 0.0
			var n := 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var u: int = x + d.x
				var v: int = y + d.y
				if u < 0 or v < 0 or u >= w or v >= h:
					continue
				var j := v * w + u
				if int(filled[j]) == 0:
					continue
				var col := img.get_pixel(u, v)
				sr += col.r
				sg += col.g
				sb += col.b
				n += 1
			if n == 0:
				next.append(c)
				continue
			img.set_pixel(x, y, Color(sr / float(n), sg / float(n), sb / float(n), 1.0))
			filled[c] = 1
		todo = next
		left = todo.size()


func _closed_bar(img: Image, at: Vector2, ew: float, eh: float, ink: Color) -> void:
	var half: float = ew * 0.60
	var thick: float = maxf(7.0, eh * 0.30)
	var w := img.get_width()
	var h := img.get_height()
	for y: int in range(maxi(0, int(at.y - thick)), mini(h, int(at.y + thick) + 2)):
		for x: int in range(maxi(0, int(at.x - half) - 2), mini(w, int(at.x + half) + 3)):
			var dx: float = maxf(0.0, absf(float(x) + 0.5 - at.x) - half)
			var dy: float = absf(float(y) + 0.5 - at.y)
			var a: float = clampf(thick * 0.5 - Vector2(dx, dy).length() + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var d := img.get_pixel(x, y)
			var m := d.lerp(ink, a)
			m.a = d.a
			img.set_pixel(x, y, m)


func _make_icon(idle: Array[Image]) -> void:
	var s := ICON_SIZE * SUPERSAMPLE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var sky_a := Color("2a2050")
	var sky_b := Color("ff9ec4")
	for y: int in range(s):
		img.fill_rect(Rect2i(0, y, s, 1), sky_a.lerp(sky_b, float(y) / float(s - 1)))
	var rad := int(float(s) * 0.10)
	var rr := float(rad)
	# Rounded-rect SDF, evaluated only inside the four corner squares.
	for cx: int in [rad, s - 1 - rad]:
		for cy: int in [rad, s - 1 - rad]:
			var x0: int = 0 if cx < s / 2 else s - rad
			var x1: int = rad if cx < s / 2 else s
			var y0: int = 0 if cy < s / 2 else s - rad
			var y1: int = rad if cy < s / 2 else s
			for y: int in range(y0, y1):
				for x: int in range(x0, x1):
					var p := Vector2(float(x) + 0.5, float(y) + 0.5)
					var q := Vector2(clampf(p.x, rr, float(s) - rr), clampf(p.y, rr, float(s) - rr))
					if (p - q).length() > rr:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
	# The tether goes down behind the pair, so both of them visibly belong to it.
	_rope(
		img,
		Vector2(float(s) * 0.17, float(s) * 0.42),
		Vector2(float(s) * 0.83, float(s) * 0.42)
	)
	for k: int in range(idle.size()):
		var src: Image = idle[k]
		var th: int = int(float(s) * 0.37)
		var sp := _resample(src, int(float(th) * float(src.get_width()) / float(src.get_height())), th)
		var foot := float(s) * 0.74
		var mid := float(s) * (0.285 if k == 0 else 0.715)
		_composite(img, sp, Vector2(mid - float(sp.get_width()) * 0.5, foot - float(sp.get_height())))
	img = _resample(img, ICON_SIZE, ICON_SIZE)
	var err := img.save_png(ICON_OUT)
	print("[bake] icon -> %s %dx%d err=%d" % [ICON_OUT, ICON_SIZE, ICON_SIZE, err])


# Area-average resample in premultiplied space. Godot 4.7 has no premultiplied
# resize mode and plain bilinear on a 3x downscale shatters the outline.
func _resample(src: Image, tw: int, th: int) -> Image:
	tw = maxi(1, tw)
	th = maxi(1, th)
	var w := src.get_width()
	var h := src.get_height()
	var px := src.get_data()
	var out := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var ob := out.get_data()
	var fx := float(w) / float(tw)
	var fy := float(h) / float(th)
	for oy: int in range(th):
		var y0 := int(floor(float(oy) * fy))
		var y1: int = mini(h, maxi(y0 + 1, int(ceil(float(oy + 1) * fy))))
		for ox: int in range(tw):
			var x0 := int(floor(float(ox) * fx))
			var x1: int = mini(w, maxi(x0 + 1, int(ceil(float(ox + 1) * fx))))
			var sr := 0.0
			var sg := 0.0
			var sb := 0.0
			var sa := 0.0
			var n := 0
			for yy: int in range(y0, y1):
				var row := yy * w
				for xx: int in range(x0, x1):
					var i := (row + xx) * 4
					var a := float(px[i + 3]) / 255.0
					sr += float(px[i]) * a
					sg += float(px[i + 1]) * a
					sb += float(px[i + 2]) * a
					sa += a
					n += 1
			var o := (oy * tw + ox) * 4
			if n == 0 or sa <= 0.0001:
				ob[o] = 0
				ob[o + 1] = 0
				ob[o + 2] = 0
				ob[o + 3] = 0
				continue
			var inv := 1.0 / float(n)
			var alpha: float = sa * inv
			ob[o] = int(clampf(sr * inv / alpha, 0.0, 255.0))
			ob[o + 1] = int(clampf(sg * inv / alpha, 0.0, 255.0))
			ob[o + 2] = int(clampf(sb * inv / alpha, 0.0, 255.0))
			ob[o + 3] = int(clampf(alpha * 255.0, 0.0, 255.0))
	out.set_data(tw, th, false, Image.FORMAT_RGBA8, ob)
	return out


func _rope(img: Image, a: Vector2, b: Vector2) -> void:
	var steps := 48
	var pts := PackedVector2Array()
	for i: int in range(steps + 1):
		var t := float(i) / float(steps)
		pts.append(a.lerp(b, t) + Vector2(0.0, 26.0 * SUPERSAMPLE * 4.0 * t * (1.0 - t)))
	for i: int in range(pts.size() - 1):
		var c := Color("f58f95").lerp(Color("e8a05c"), float(i) / float(pts.size() - 1))
		_line(img, pts[i], pts[i + 1], c.darkened(0.5), 13.0 * SUPERSAMPLE)
		_line(img, pts[i], pts[i + 1], c, 7.0 * SUPERSAMPLE)


func _line(img: Image, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var n: int = maxi(1, int(a.distance_to(b) / 3.0))
	for i: int in range(n + 1):
		_blob(img, a.lerp(b, float(i) / float(n)), width * 0.5, col)


func _blob(img: Image, at: Vector2, r: float, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y: int in range(maxi(0, int(at.y - r)), mini(h, int(at.y + r) + 2)):
		for x: int in range(maxi(0, int(at.x - r)), mini(w, int(at.x + r) + 2)):
			var d: float = Vector2(float(x) + 0.5 - at.x, float(y) + 0.5 - at.y).length()
			var a: float = clampf(r - d + 0.5, 0.0, 1.0) * col.a
			if a > 0.0:
				_over(img, x, y, Color(col.r, col.g, col.b, a))


func _composite(img: Image, spr: Image, at: Vector2) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y: int in range(maxi(0, int(at.y)), mini(h, int(at.y) + spr.get_height())):
		for x: int in range(maxi(0, int(at.x)), mini(w, int(at.x) + spr.get_width())):
			var c := spr.get_pixel(x - int(at.x), y - int(at.y))
			if c.a > 0.001:
				_over(img, x, y, c)


func _over(img: Image, x: int, y: int, src: Color) -> void:
	var d := img.get_pixel(x, y)
	var a: float = src.a + d.a * (1.0 - src.a)
	if a <= 0.0:
		return
	img.set_pixel(
		x, y,
		Color(
			(src.r * src.a + d.r * d.a * (1.0 - src.a)) / a,
			(src.g * src.a + d.g * d.a * (1.0 - src.a)) / a,
			(src.b * src.a + d.b * d.a * (1.0 - src.a)) / a,
			a
		)
	)
