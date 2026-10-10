class_name Biomes
extends RefCounted

# One entry per visual world. A biome is a colour script, not a texture pack: the
# terrain body colour is sampled from its own cap strip at runtime (Art.cap_body),
# so these tables only carry the things that cannot be derived — sky, the depth
# tints for each parallax band, which props live here, and what falls out of the
# air.
#
# Band tints follow the readability rule: background mass sits 1.5 value steps
# away from playable geometry and is desaturated, so nothing competes with the
# band the two bears occupy.

const DEFS := {
	"meadow": {
		"title": "晨光草原",
		"sky": [Color("5b3f8f"), Color("ffd6c0")],
		"sun": Color("fff4d2"),
		"far": Color("c0aede"), "mid": Color("8fb9a6"), "near": Color("5d8f76"),
		"canopy": Color("3f6b58"),
		"fringe": 0.0,
		"fog": Color("ffcdb8"), "vig": Color("2a1b3c"),
		"cap": "cap_grass",
		"props": ["bush", "tuft", "flower", "mushroom", "sapling"],
		"hang": "vine",
		"spike": "spike_candy",
		"ambient": "petal", "ambient_col": [Color("ffd0e0"), Color("fff0d0")],
	},
	"canyon": {
		"title": "落日峡谷",
		"sky": [Color("6b3a63"), Color("ffb478")],
		"sun": Color("ffe6b0"),
		"far": Color("d9a4b4"), "mid": Color("b9808f"), "near": Color("8f5a70"),
		"canopy": Color("5f3a52"),
		"fringe": 0.0,
		"fog": Color("ffbf8f"), "vig": Color("3a1c34"),
		"cap": "cap_sand",
		"props": ["rockpile", "tuft", "log", "signpost", "candy_shroom"],
		"hang": "vine",
		"spike": "spike_stone",
		"ambient": "dust", "ambient_col": [Color("ffd9a8"), Color("fff0cf")],
	},
	"forest": {
		"title": "雾色松林",
		"sky": [Color("2f4f6b"), Color("cfeadd")],
		"sun": Color("f2ffe0"),
		"far": Color("9dc2c9"), "mid": Color("6fa294"), "near": Color("3f6f5f"),
		"canopy": Color("27463c"),
		"fringe": 0.95,
		"fog": Color("cfeee2"), "vig": Color("152e30"),
		"cap": "cap_moss",
		"props": ["fern", "pine", "mushroom", "bush", "log"],
		"hang": "vine",
		"spike": "spike_stone",
		"ambient": "leaf", "ambient_col": [Color("9fd9a0"), Color("e8d48a")],
	},
	"cave": {
		"title": "蜜糖洞窟",
		"sky": [Color("241a3d"), Color("7a4f6b")],
		"sun": Color("ffcf8a"),
		"far": Color("7f6a9e"), "mid": Color("5f4a78"), "near": Color("413055"),
		"canopy": Color("2a1c3a"),
		"fringe": 0.8,
		"fog": Color("a8788f"), "vig": Color("150f24"),
		"cap": "cap_honey",
		"props": ["crystal", "mushroom", "candy_shroom", "rockpile", "lamp_post"],
		"hang": "vine",
		"spike": "spike_candy",
		"ambient": "mote", "ambient_col": [Color("ffd98a"), Color("ffb0d0")],
	},
	"snow": {
		"title": "霜雪岭",
		"sky": [Color("1e3a63"), Color("d8ecff")],
		"sun": Color("eaf6ff"),
		"far": Color("bcd8ef"), "mid": Color("8fb4d6"), "near": Color("5f88b0"),
		"canopy": Color("3a5f82"),
		"fringe": 0.0,
		"fog": Color("e4f2ff"), "vig": Color("12243f"),
		"cap": "cap_snow",
		"props": ["pine", "sapling", "rockpile", "tuft", "signpost"],
		"hang": "icicle",
		"spike": "crystal",
		"ambient": "snow", "ambient_col": [Color("ffffff"), Color("cfe6ff")],
	},
	"dusk": {
		"title": "归家暮色",
		"sky": [Color("2a2050"), Color("ffb9cf")],
		"sun": Color("ffe2b0"),
		"far": Color("ab8fc4"), "mid": Color("7a5f9e"), "near": Color("54407a"),
		"canopy": Color("382a55"),
		"fringe": 0.85,
		"fog": Color("ffc6d8"), "vig": Color("1a1234"),
		"cap": "cap_slate",
		"props": ["blossom", "bamboo", "lamp_post", "bush", "signpost"],
		"hang": "vine",
		"spike": "spike_stone",
		"ambient": "firefly", "ambient_col": [Color("ffe9a8"), Color("ffd0e8")],
	},
}

# Which wheel the chapter's machinery is drawn with, so a factory chapter does not
# show a wooden pulley.
const PULLEY_COL := {
	"meadow": Color("c69a6d"), "canyon": Color("b98a63"), "forest": Color("9ec4a8"),
	"cave": Color("e0b06a"), "snow": Color("cfe4f5"), "dusk": Color("d9b47c"),
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS.meadow)
