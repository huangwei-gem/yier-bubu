class_name M3Levels
extends RefCounted

# Tiles are the baked art the platformer already owns: the two bears for the faces
# and the environment props for the rest, so the puzzle game cannot drift into a
# different palette from the adventure game.
const LABELS := {
	"yier": "一二", "bubu": "布布", "coin": "金币", "mushroom": "蘑菇",
	"crystal": "水晶", "flower": "小花", "pine": "松树", "icicle": "冰凌",
	"blossom": "樱花", "bamboo": "竹",
}
const ART := {
	"yier": {"face": 0},
	"bubu": {"face": 1},
	"coin": {"env": "coin"},
	"mushroom": {"env": "mushroom"},
	"crystal": {"env": "crystal"},
	"flower": {"env": "flower"},
	"pine": {"env": "pine"},
	"icicle": {"env": "icicle"},
	"blossom": {"env": "blossom"},
	"bamboo": {"env": "bamboo"},
}
const BIOME := {
	"meadow": "草原", "canyon": "峡谷", "forest": "松林",
	"cave": "洞窟", "snow": "霜雪", "dusk": "暮色",
}

# star_scores are the [二星, 三星] cuts; one star only means the objectives were met.
# They are measured off simulated playthroughs (tools/match3_check.gd) rather than
# guessed, because a cut nobody can reach is worse than no cut at all.
const LEVELS: Array[Dictionary] = [
	{
		"name": "第 1 局 · 手牵手", "hint": "换一下相邻的两个，三个同色就连成线。",
		"biome": "meadow", "w": 7, "h": 7, "set": ["yier", "bubu", "coin", "mushroom"],
		"moves": 20, "objectives": [{"id": "yier", "need": 14}, {"id": "bubu", "need": 14}],
		"star_scores": [4700, 10800],
	},
	{
		"name": "第 2 局 · 五种颜色", "hint": "颜色多一种，线就难连一条。",
		"biome": "meadow", "w": 8, "h": 8, "set": ["yier", "bubu", "coin", "mushroom", "crystal"],
		"moves": 22, "objectives": [{"id": "coin", "need": 20}, {"id": "crystal", "need": 20}],
		"star_scores": [7900, 9400],
	},
	{
		"name": "第 3 局 · 四条以上", "hint": "四个连成一条会留下爆破条，五个连成一条留下彩虹球。",
		"biome": "forest", "w": 8, "h": 8, "set": ["yier", "bubu", "coin", "mushroom", "pine"],
		"moves": 26, "objectives": [{"id": "pine", "need": 20}, {"id": "coin", "need": 16}],
		"star_scores": [7200, 12900],
	},
	{
		"name": "第 4 局 · 上冰", "hint": "冰块不能换也不能消，只能在它旁边消一次，把它敲薄一层。",
		"biome": "snow", "w": 8, "h": 8, "set": ["yier", "bubu", "coin", "icicle"],
		"moves": 24, "objectives": [{"id": "ice", "need": 10}, {"id": "yier", "need": 16}],
		"ice": [[2, 2], [2, 3], [3, 2], [5, 4], [5, 5], [4, 5], [6, 1], [1, 6], [6, 6], [3, 4]],
		"star_scores": [8300, 11600],
	},
	{
		"name": "第 5 局 · 洞窟的窗", "hint": "冰会挡住这一列，上面的东西落不下来。",
		"biome": "cave", "w": 8, "h": 8, "set": ["crystal", "coin", "mushroom", "bubu"],
		"moves": 26, "objectives": [{"id": "ice", "need": 16}, {"id": "crystal", "need": 22}],
		"ice": [[2, 1], [2, 2], [2, 3], [5, 1], [5, 2], [5, 3], [2, 4], [2, 5], [5, 4], [5, 5], [3, 6], [4, 6], [0, 3], [7, 3], [1, 1], [6, 6]],
		"star_scores": [11400, 16000],
	},
	{
		"name": "第 6 局 · 花与松", "hint": "大棋盘更难看清，多绕两次就能连成长线。",
		"biome": "forest", "w": 9, "h": 9, "set": ["flower", "pine", "yier", "bubu", "mushroom"],
		"moves": 28, "objectives": [{"id": "flower", "need": 22}, {"id": "pine", "need": 22}],
		"star_scores": [9900, 16400],
	},
	{
		"name": "第 7 局 · 冰墙", "hint": "一道冰墙把棋盘分成两半，先把墙打通。",
		"biome": "snow", "w": 9, "h": 9, "set": ["icicle", "coin", "crystal", "yier"],
		"moves": 28, "objectives": [{"id": "ice", "need": 22}, {"id": "icicle", "need": 24}],
		"ice": [[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8], [1, 2], [1, 6], [7, 2], [7, 6], [2, 4], [6, 4], [0, 0], [8, 8], [3, 1], [5, 1], [3, 7], [5, 7], [1, 4], [7, 4]],
		"star_scores": [24800, 28400],
	},
	{
		"name": "第 8 局 · 大丰收", "hint": "三种收成同时催，优先消最快凑齐的那一种。",
		"biome": "meadow", "w": 9, "h": 9, "set": ["coin", "mushroom", "flower", "bubu", "yier"],
		"moves": 30, "objectives": [{"id": "coin", "need": 30}, {"id": "mushroom", "need": 30}, {"id": "flower", "need": 26}],
		"star_scores": [13500, 20400],
	},
	{
		"name": "第 9 局 · 暮色五色", "hint": "颜色一多，随手三连就靠不住了，先看全盘再换。",
		"biome": "dusk", "w": 9, "h": 9, "set": ["blossom", "bamboo", "coin", "crystal", "yier"],
		"moves": 34, "objectives": [{"id": "blossom", "need": 24}, {"id": "bamboo", "need": 24}],
		"star_scores": [13100, 16800],
	},
	{
		"name": "第 10 局 · 双层冰", "hint": "厚冰要敲两下，别把步数浪费在同一块上。",
		"biome": "snow", "w": 9, "h": 9, "set": ["icicle", "crystal", "coin", "yier", "bubu"],
		"moves": 34, "objectives": [{"id": "ice", "need": 24}, {"id": "crystal", "need": 24}],
		"ice": [[2, 2, 2], [3, 2, 2], [2, 3, 2], [3, 3, 2], [6, 2, 2], [5, 2, 2], [6, 3, 2], [5, 3, 2], [4, 4, 1], [4, 5, 1], [2, 6, 2], [3, 6, 2], [6, 6, 2], [5, 6, 2], [0, 4, 1], [8, 4, 1], [4, 0, 1], [4, 8, 1], [1, 1, 1], [7, 7, 1], [1, 7, 1], [7, 1, 1], [4, 2, 1], [4, 6, 1], [2, 4, 1], [6, 4, 1], [0, 0, 1], [8, 8, 1], [0, 8, 1], [8, 0, 1]],
		"star_scores": [11500, 12500],
	},
	{
		"name": "第 11 局 · 彩虹练习", "hint": "凑五个连成一条，彩虹球换一个就清掉一整色。",
		"biome": "cave", "w": 9, "h": 9, "set": ["crystal", "mushroom", "coin", "bubu", "yier"],
		"moves": 30, "objectives": [{"id": "crystal", "need": 40}, {"id": "coin", "need": 34}],
		"star_scores": [15700, 22000],
	},
	{
		"name": "第 12 局 · 峡谷集市", "hint": "三种收成加一层冰，先清冰才数得着后面的。",
		"biome": "canyon", "w": 9, "h": 9, "set": ["coin", "flower", "pine", "mushroom", "yier"],
		"moves": 34, "objectives": [{"id": "coin", "need": 34}, {"id": "flower", "need": 30}, {"id": "ice", "need": 14}],
		"ice": [[2, 2], [6, 2], [2, 6], [6, 6], [4, 2], [4, 6], [2, 4], [6, 4], [0, 4], [8, 4], [4, 0], [4, 8], [1, 1], [7, 7], [3, 5], [5, 3]],
		"star_scores": [14200, 20800],
	},
	{
		"name": "第 13 局 · 霜雪关", "hint": "冰比颜色多，这一关考的是敲冰的顺序。",
		"biome": "snow", "w": 9, "h": 9, "set": ["icicle", "crystal", "yier", "bubu", "coin"],
		"moves": 34, "objectives": [{"id": "ice", "need": 30}, {"id": "icicle", "need": 30}],
		"ice": [[2, 2, 2], [6, 2, 2], [2, 6, 2], [6, 6, 2], [4, 4, 2], [4, 1], [4, 7], [1, 4], [7, 4], [3, 3], [5, 3], [3, 5], [5, 5], [0, 0], [8, 8], [0, 8], [8, 0], [2, 4], [6, 4], [4, 2], [4, 6], [1, 1], [7, 7], [1, 7], [7, 1], [0, 4], [8, 4], [4, 0], [4, 8], [3, 1], [5, 7]],
		"star_scores": [13600, 17600],
	},
	{
		"name": "第 14 局 · 花与竹", "hint": "五加一层冰，留几步给最后一次连锁。",
		"biome": "dusk", "w": 9, "h": 9, "set": ["blossom", "bamboo", "yier", "bubu", "coin"],
		"moves": 38, "objectives": [{"id": "blossom", "need": 26}, {"id": "bamboo", "need": 26}, {"id": "ice", "need": 16}],
		"ice": [[3, 2], [5, 2], [3, 6], [5, 6], [4, 3], [4, 5], [2, 4], [6, 4], [0, 2], [8, 6], [1, 0], [7, 8], [0, 6], [8, 2], [2, 2], [6, 6], [4, 1], [4, 7]],
		"star_scores": [13900, 18000],
	},
	{
		"name": "第 15 局 · 一起回家", "hint": "两只熊各要一份，冰也要拆完，三样同时齐才算毕业。",
		"biome": "dusk", "w": 9, "h": 9, "set": ["yier", "bubu", "coin", "crystal", "flower", "icicle"],
		"moves": 42, "objectives": [{"id": "yier", "need": 28}, {"id": "bubu", "need": 28}, {"id": "ice", "need": 18}],
		"ice": [[2, 2, 2], [6, 2, 2], [2, 6, 2], [6, 6, 2], [4, 4, 2], [4, 2, 1], [4, 6, 1], [2, 4, 1], [6, 4, 1], [0, 0, 1], [8, 8, 1], [0, 8, 1], [8, 0, 1], [1, 3, 1], [7, 3, 1], [1, 5, 1], [7, 5, 1], [3, 1, 1], [5, 1, 1], [3, 7, 1], [5, 7, 1], [0, 4, 1], [8, 4, 1], [4, 0, 1], [4, 8, 1]],
		"star_scores": [11500, 13900],
	},
]


static func count() -> int:
	return LEVELS.size()


# Three acts of five, so the grid can say what a chapter is for instead of showing
# fifteen undifferentiated numbers.
const WORLDS := [
	{"name": "上半 · 手与眼", "from": 0, "to": 4},
	{"name": "中段 · 冰与墙", "from": 5, "to": 9},
	{"name": "收尾 · 归途", "from": 10, "to": 14},
]


static func world_of(index: int) -> int:
	for w: int in range(WORLDS.size()):
		if index >= int(WORLDS[w].from) and index <= int(WORLDS[w].to):
			return w
	return WORLDS.size() - 1


static func world_name(index: int) -> String:
	return String(WORLDS[world_of(index)].name)


static func get_def(index: int) -> Dictionary:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


static func art_tex(id: String) -> Texture2D:
	var d: Dictionary = ART.get(id, {})
	if d.is_empty():
		return null
	if d.has("face"):
		return Art.frame_tex(int(d.face), Art.F_IDLE)
	return Art.env(String(d.env))


static func is_face(id: String) -> bool:
	return ART.get(id, {}).has("face")


static func face_index(id: String) -> int:
	return int(ART[id].face)
