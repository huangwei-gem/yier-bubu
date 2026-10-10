# Measures a character silhouette the same way for the reference photos and for
# the generated sheets, so "does it match" is a number and not an opinion.
#
# Run: godot --headless --path . res://tools/ref_measure.tscn
extends Node

const TARGETS := [
	{"img": "res://assets/src/ref_stand.jpg", "x0": 20, "x1": 670, "white": true, "tag": "REF  一二"},
	{"img": "res://assets/src/ref_stand.jpg", "x0": 740, "x1": 1400, "white": true, "tag": "REF  布布"},
	{"img": "res://assets/sprites/yier/idle.png", "x0": 0, "x1": -1, "tag": "CUR  一二"},
	{"img": "res://assets/sprites/bubu/idle.png", "x0": 0, "x1": -1, "tag": "CUR  布布"},
]

var _bake


func _ready() -> void:
	_bake = load("res://tools/sprite_bake.gd").new()
	for t: Dictionary in TARGETS:
		_measure(t)
	get_tree().quit()


func _load(path: String) -> Image:
	var buf := FileAccess.get_file_as_bytes(path)
	var png := Image.new()
	if png.load_png_from_buffer(buf) == OK:
		return png
	var jpg := Image.new()
	if jpg.load_jpg_from_buffer(buf) == OK:
		return jpg
	return null


func _measure(t: Dictionary) -> void:
	var src := _load(String(t.img))
	if src == null:
		print("%-9s MISSING %s" % [String(t.tag), String(t.img)])
		return
	var x0: int = int(t.x0)
	var x1: int = int(t.x1) if int(t.x1) > 0 else src.get_width()
	var cell := src.get_region(Rect2i(x0, 0, x1 - x0, src.get_height()))
	var keyed: Image = _bake._key_cell(cell, {}, bool(t.get("white", false)))
	var w: int = keyed.get_width()
	var h: int = keyed.get_height()
	# One byte pass: get_pixel over a megapixel twice per row takes minutes.
	var px: PackedByteArray = keyed.get_data()
	var spans := PackedInt32Array()
	spans.resize(h)
	var widest := 0
	for y: int in range(h):
		var first := -1
		var last := -1
		var row := y * w
		for x: int in range(w):
			if px[(row + x) * 4 + 3] > 127:
				if first < 0:
					first = x
				last = x
		spans[y] = 0 if first < 0 else last - first + 1
		widest = maxi(widest, spans[y])

	var head_bottom := 0
	for y: int in range(h):
		if spans[y] >= widest * 0.85:
			head_bottom = y
	var head_h := head_bottom + 1

	var pair: Dictionary = _bake._eye_pair(_bake._find_eyes(keyed), float(w) * 0.5, float(h))
	var line := "%-9s h=%-4d headW=%-4d headH=%-4d  head/total=%.3f  headW/H=%.3f  headW/total=%.3f" % [
		String(t.tag), h, widest, head_h,
		float(head_h) / float(h),
		float(widest) / float(head_h),
		float(widest) / float(h),
	]
	if pair.is_empty():
		print(line + "  no eyes")
		return
	var a: Dictionary = (pair.list as Array)[0]
	var b: Dictionary = (pair.list as Array)[1]
	var d: float = (float(a.box.size.x) + float(b.box.size.x)) * 0.5
	var ey: float = (float(a.centre.y) + float(b.centre.y)) * 0.5
	print(
		line
		+ "  eye=%.1f (%.3f of headW)  span=%.1f (%.3f)  eyeY=%.3f of head"
		% [d, d / float(widest), float(pair.span), float(pair.span) / float(widest), ey / float(head_h)]
	)
