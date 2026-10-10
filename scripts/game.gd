extends Node

enum Screen { TITLE, LEVELS, PLAYING, PAUSED, VICTORY, SETTINGS, ACHIEVES, HOWTO, MATCH3 }
enum Mode { PLATFORM, MATCH3 }

signal screen_changed(to: int)
signal level_started(index: int)
signal mode_changed(to: int)
signal m3_changed()
signal achievement_unlocked(ach: Dictionary)
signal settings_changed()

enum M3Screen { HOME, PICK, PLAY }

const LEVELS: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_02.tscn",
	"res://scenes/levels/level_03.tscn",
	"res://scenes/levels/level_04.tscn",
	"res://scenes/levels/level_05.tscn",
	"res://scenes/levels/level_06.tscn",
	"res://scenes/levels/level_07.tscn",
	"res://scenes/levels/level_08.tscn",
	"res://scenes/levels/level_09.tscn",
	"res://scenes/levels/level_10.tscn",
	"res://scenes/levels/level_11.tscn",
	"res://scenes/levels/level_12.tscn",
]
const WORLDS := [
	{"name": "第一幕 · 草原与松林", "from": 0, "to": 3},
	{"name": "第二幕 · 峡谷与洞窟", "from": 4, "to": 7},
	{"name": "第三幕 · 霜雪与归途", "from": 8, "to": 11},
]
const SAVE_PATH := "user://yier_bubu.cfg"

# Every tunable the settings page owns lives here, so the page, the save file and
# the code that reads them cannot disagree about what is configurable.
const SETTINGS := [
	{"key": "volume", "label": "音量", "min": 0.0, "max": 1.0, "step": 0.05, "kind": "range"},
	{"key": "muted", "label": "静音", "kind": "toggle"},
	{"key": "fullscreen", "label": "全屏", "kind": "toggle"},
	{"key": "shake", "label": "画面震动", "kind": "toggle"},
	{"key": "bump", "label": "踩头弹跳", "kind": "toggle"},
	{"key": "music", "label": "背景音乐", "kind": "toggle"},
]
const KEY_ACTIONS := ["left", "right", "jump"]
const KEY_LABELS := {"left": "左", "right": "右", "jump": "跳"}
const DEFAULT_KEYS: Array[Dictionary] = [
	{"left": KEY_A, "right": KEY_D, "jump": KEY_W},
	{"left": KEY_LEFT, "right": KEY_RIGHT, "jump": KEY_UP},
]

# A stat is only ever a non-negative integer, which keeps the save file, the
# progress bar and the achievement rule all speaking the same language.
const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_bell", "stat": "levels_cleared", "goal": 1, "name": "第一次到家", "desc": "通关任意一关"},
	{"id": "rope_learned", "stat": "sync", "goal": 25, "name": "绳熟能生巧", "desc": "完成 25 次同心跳"},
	{"id": "big_foot", "stat": "stomp", "goal": 30, "name": "踩得准", "desc": "踩头弹跳 30 次"},
	{"id": "pocket_full", "stat": "coins_banked", "goal": 120, "name": "满口袋", "desc": "累计收下 120 枚金币"},
	{"id": "flawless", "stat": "flawless", "goal": 1, "name": "一次都没掉", "desc": "零失误通关一关"},
	{"id": "quick_pair", "stat": "fast", "goal": 1, "name": "快得离谱", "desc": "用不到目标时间 60% 通关一关"},
	{"id": "half_way", "stat": "max_chapter", "goal": 8, "name": "过半程", "desc": "打到第八章"},
	{"id": "home_at_last", "stat": "max_chapter", "goal": 12, "name": "一起到家", "desc": "打通第十二章"},
	{"id": "all_stars", "stat": "stars_total", "goal": 36, "name": "同心 36 星", "desc": "闯关拿到全部星星"},
	{"id": "clean_run", "stat": "clean_runs", "goal": 1, "name": "一整轮没失误", "desc": "从头通到尾且总失误为 0"},
	{"id": "m3_first", "stat": "m3_cleared", "goal": 1, "name": "消消乐开张", "desc": "消消乐通关一关"},
	{"id": "m3_half", "stat": "m3_cleared", "goal": 10, "name": "手感来了", "desc": "消消乐通关 10 关"},
	{"id": "m3_chain", "stat": "m3_chain", "goal": 5, "name": "连锁反应", "desc": "一次消掉引发 5 层连锁"},
	{"id": "m3_score", "stat": "m3_best", "goal": 20000, "name": "两万分", "desc": "消消乐单局破 20000"},
	{"id": "m3_stars", "stat": "m3_stars_total", "goal": 45, "name": "满屏都是星", "desc": "消消乐拿到全部 45 星"},
]

var screen_state: int = Screen.TITLE
var mode: int = Mode.PLATFORM
var level_index: int = 0
var deaths: int = 0
var coins: int = 0
var run_time: float = 0.0
var tick := false
var best_time: float = 0.0
var unlocked: int = 1

# Per-level records that survive across runs: index -> {"time": float, "coins": int}
var level_best: Dictionary = {}
# What this run has banked so far, so the victory page can show one row per level.
var run_results: Array[Dictionary] = []

var settings: Dictionary = {}
var stats: Dictionary = {}
var achievements: Dictionary = {}
var m3_unlocked: int = 1
var m3_best: Dictionary = {}
var m3_level_best: Dictionary = {}
var m3_screen: int = M3Screen.HOME
var m3_index: int = 0

var _level_time := 0.0
var _level_coins := 0
var _level_deaths := 0
var _names: PackedStringArray = []
var _biomes: PackedStringArray = []
var _page_return: int = Screen.TITLE


func _ready() -> void:
	_defaults()
	_load()
	_apply_settings()


func _defaults() -> void:
	settings = {
		"volume": 0.8, "muted": false, "fullscreen": false,
		"shake": true, "bump": true, "music": true,
		"keys": DEFAULT_KEYS.duplicate(true),
	}
	for a: Dictionary in ACHIEVEMENTS:
		stats[String(a.stat)] = 0
	achievements = {}


func _process(delta: float) -> void:
	if tick:
		run_time += delta


# Settings, achievements and the how-to page are mounted over whatever screen asked
# for them, exactly like the pause menu: the level stays alive and simply stops
# being `playing()`, so leaving the page resumes with nothing to reload.
func set_screen(to: int) -> void:
	if screen_state == to:
		return
	if not is_page(to) and not is_page(screen_state):
		_page_return = screen_state
	screen_state = to
	tick = to == Screen.PLAYING
	if to == Screen.SETTINGS:
		_apply_settings()
	screen_changed.emit(to)


func is_page(to: int) -> bool:
	return to == Screen.SETTINGS or to == Screen.ACHIEVES or to == Screen.HOWTO


func page_open() -> bool:
	return is_page(screen_state)


func close_page() -> void:
	if is_page(screen_state):
		set_screen(_page_return)



func playing() -> bool:
	return screen_state == Screen.PLAYING


func in_match3() -> bool:
	return mode == Mode.MATCH3


func go_match3() -> void:
	mode = Mode.MATCH3
	m3_screen = M3Screen.HOME
	set_screen(Screen.MATCH3)
	mode_changed.emit(mode)


func m3_home() -> void:
	m3_screen = M3Screen.HOME
	set_screen(Screen.MATCH3)
	m3_changed.emit()


func open_m3_pick() -> void:
	m3_screen = M3Screen.PICK
	set_screen(Screen.MATCH3)
	m3_changed.emit()


func open_m3(index: int) -> void:
	m3_index = clampi(index, 0, M3Levels.count() - 1)
	m3_screen = M3Screen.PLAY
	set_screen(Screen.MATCH3)
	m3_changed.emit()


func go_platform() -> void:
	mode = Mode.PLATFORM
	set_screen(Screen.TITLE)
	mode_changed.emit(mode)


func start_run(from_index: int = 0) -> void:
	mode = Mode.PLATFORM
	level_index = clampi(from_index, 0, LEVELS.size() - 1)
	deaths = 0
	coins = 0
	run_time = 0.0
	run_results.clear()
	set_screen(Screen.PLAYING)
	_open_level()


func complete_level(stars: int = 1) -> void:
	_bank_level(true, stars)
	# A chapter is only counted once, so replaying chapter 1 twice does not read as
	# having reached chapter 2 twice.
	note_max("max_chapter", level_index + 1)
	note("levels_cleared")
	if deaths == 0 and level_index + 1 >= LEVELS.size():
		note("clean_runs")
	if stars >= 3:
		note("flawless")
	if float(_levels_par(level_index)) > 0.0 and level_time() <= float(_levels_par(level_index)) * 0.6:
		note("fast")
	note_max("stars_total", total_stars())
	if level_index + 1 >= LEVELS.size():
		_record_best()
		set_screen(Screen.VICTORY)
	else:
		level_index += 1
		# `unlocked` counts playable levels, so clearing index N opens N + 1 of them.
		unlocked = maxi(unlocked, level_index + 1)
		note_max("stars_total", total_stars())
		_save()
		set_screen(Screen.PLAYING)
		level_started.emit(level_index)


func restart_level() -> void:
	_bank_level(false, 0)
	level_started.emit(level_index)


func set_paused(yes: bool) -> void:
	if screen_state == Screen.PLAYING and yes:
		set_screen(Screen.PAUSED)
	elif screen_state == Screen.PAUSED and not yes:
		set_screen(Screen.PLAYING)


func go_to_title() -> void:
	set_screen(Screen.TITLE)


func go_to_levels() -> void:
	mode = Mode.PLATFORM
	set_screen(Screen.LEVELS)


func level_count() -> int:
	return LEVELS.size()


func is_unlocked(index: int) -> bool:
	return index >= 0 and index < unlocked


# The select screen needs every chapter title at once, so the scenes are
# instantiated a single time here rather than per frame.
func level_name(index: int) -> String:
	_read_metas()
	return _names[clampi(index, 0, LEVELS.size() - 1)]


# The select screen paints a biome thumbnail per card, which is the same lookup
# done through the scene file rather than a second table that can drift.
func level_biome(index: int) -> String:
	_read_metas()
	return _biomes[clampi(index, 0, LEVELS.size() - 1)]


func _read_metas() -> void:
	if not _names.is_empty():
		return
	for path: String in LEVELS:
		var node := (load(path) as PackedScene).instantiate()
		var d: Dictionary = (node as LevelBase).level_data()
		_names.append(String(d.get("name", "")))
		_biomes.append(String(d.get("biome", "meadow")))
		node.free()


func _levels_par(index: int) -> float:
	_pars_ready()
	return float(_pars[clampi(index, 0, LEVELS.size() - 1)])


var _pars: PackedFloat64Array = []


func _pars_ready() -> void:
	if not _pars.is_empty():
		return
	for path: String in LEVELS:
		var node := (load(path) as PackedScene).instantiate()
		var d: Dictionary = (node as LevelBase).level_data()
		_pars.append(float(d.get("par", 60.0)))
		node.free()


func format_time(t: float) -> String:
	var total := int(t)
	return "%02d:%02d" % [int(total / 60.0), total % 60]


func _open_level() -> void:
	_level_time = run_time
	_level_coins = coins
	_level_deaths = deaths
	level_started.emit(level_index)


func level_time() -> float:
	return maxf(0.0, run_time - _level_time)


func world_of(index: int) -> int:
	for w: int in range(WORLDS.size()):
		if index >= int(WORLDS[w].from) and index <= int(WORLDS[w].to):
			return w
	return WORLDS.size() - 1


func world_name(index: int) -> String:
	return String(WORLDS[world_of(index)].name)


func total_stars() -> int:
	var n := 0
	for key: int in level_best:
		n += int(level_best[key].stars)
	return n


func stars_of(index: int) -> int:
	var rec: Dictionary = level_best.get(index, {})
	return int(rec.stars) if not rec.is_empty() else 0


# Snapshots what the just-finished attempt was worth. `banked` is false when the
# player pressed R, so a retry never overwrites the record with a worse slice —
# and the coins it collected are handed back, otherwise R becomes a coin farm.
func _bank_level(banked: bool, stars: int) -> void:
	var result := {
		"index": level_index,
		"time": maxf(0.0, run_time - _level_time),
		"coins": maxi(0, coins - _level_coins),
		"deaths": maxi(0, deaths - _level_deaths),
		"stars": stars,
		"banked": banked,
	}
	if level_index < run_results.size():
		run_results[level_index] = result
	else:
		while run_results.size() < level_index:
			run_results.append(
				{"index": run_results.size(), "time": 0.0, "coins": 0, "deaths": 0, "stars": 0, "banked": false}
			)
		run_results.append(result)

	var next_coins := coins
	if not banked:
		next_coins = _level_coins
	_level_time = run_time
	_level_coins = next_coins
	_level_deaths = deaths
	coins = next_coins
	if not banked:
		return
	note("coins_banked", maxi(0, int(result.coins)))
	# The record keeps the fastest run and the best star count separately: a slow
	# three-star run should not erase an earlier one-star speed record, and vice
	# versa, or the only way to keep a record is never to play for collectibles.
	var prev: Dictionary = level_best.get(level_index, {})
	var entry := {
		"time": float(result.time),
		"coins": int(result.coins),
		"stars": maxi(stars, int(prev.get("stars", 0))),
	}
	if prev.is_empty() or float(prev.time) > float(result.time):
		entry["time"] = float(result.time)
		entry["coins"] = int(result.coins)
	else:
		entry["time"] = float(prev.time)
		entry["coins"] = int(prev.coins)
	level_best[level_index] = entry
	_save()


func _record_best() -> void:
	if best_time <= 0.0 or run_time < best_time:
		best_time = run_time
		_save()


# --------------------------------------------------------------------------------
# Stats, achievements, settings
# --------------------------------------------------------------------------------

func note(stat: String, by: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + by
	_check_achievements()


func note_max(stat: String, value: int) -> void:
	if value > int(stats.get(stat, 0)):
		stats[stat] = value
		_check_achievements()


func stat_of(stat: String) -> int:
	return int(stats.get(stat, 0))


func ach_done(id: String) -> bool:
	return bool(achievements.get(id, false))


func ach_progress(a: Dictionary) -> Dictionary:
	return {"now": stat_of(String(a.stat)), "goal": int(a.goal)}


func _check_achievements() -> void:
	var fresh := false
	for a: Dictionary in ACHIEVEMENTS:
		var id := String(a.id)
		if bool(achievements.get(id, false)):
			continue
		if stat_of(String(a.stat)) >= int(a.goal):
			achievements[id] = true
			achievement_unlocked.emit(a)
			fresh = true
	# Writing the save file is the only thing here slow enough to matter, so it runs
	# when something was actually earned rather than on every coin and stomp.
	if fresh:
		_save()


func save_now() -> void:
	_save()


func ach_count() -> int:
	var n := 0
	for a: Dictionary in ACHIEVEMENTS:
		if bool(achievements.get(String(a.id), false)):
			n += 1
	return n


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_apply_settings()
	_save()
	settings_changed.emit()


func key_of(player_index: int, action: String) -> int:
	var list: Array = settings.get("keys", DEFAULT_KEYS)
	if player_index < 0 or player_index >= list.size():
		return int(DEFAULT_KEYS[0][action])
	return int(list[player_index].get(action, DEFAULT_KEYS[player_index % DEFAULT_KEYS.size()][action]))


func set_key(player_index: int, action: String, keycode: int) -> void:
	var list: Array = settings.get("keys", DEFAULT_KEYS).duplicate(true)
	while list.size() <= player_index:
		list.append(DEFAULT_KEYS[list.size()])
	list[player_index][action] = keycode
	settings["keys"] = list
	_save()
	settings_changed.emit()


func reset_keys() -> void:
	settings["keys"] = DEFAULT_KEYS.duplicate(true)
	_save()
	settings_changed.emit()


func reset_save() -> void:
	unlocked = 1
	level_best = {}
	best_time = 0.0
	stats = {}
	achievements = {}
	m3_unlocked = 1
	m3_best = {}
	m3_level_best = {}
	_defaults()
	DirAccess.remove_absolute(SAVE_PATH)
	_save()
	settings_changed.emit()


func _apply_settings() -> void:
	var root := get_tree().root if is_inside_tree() else null
	if root != null:
		var want_full: bool = bool(settings.get("fullscreen", false))
		var is_full: bool = root.mode == Window.MODE_FULLSCREEN or root.mode == Window.MODE_MAXIMIZED
		if want_full and not is_full:
			root.mode = Window.MODE_FULLSCREEN
		elif not want_full and is_full:
			root.mode = Window.MODE_WINDOWED


# --------------------------------------------------------------------------------
# Match-3 records
# --------------------------------------------------------------------------------

func m3_is_unlocked(index: int) -> bool:
	return index >= 0 and index < m3_unlocked


func m3_stars_of(index: int) -> int:
	return int(m3_level_best.get(index, {}).get("stars", 0))


func m3_score_of(index: int) -> int:
	return int(m3_level_best.get(index, {}).get("score", 0))


func m3_total_stars() -> int:
	var n := 0
	for key: int in m3_level_best:
		n += int(m3_level_best[key].stars)
	return n


func m3_complete(index: int, stars: int, score: int) -> void:
	var prev: Dictionary = m3_level_best.get(index, {})
	m3_level_best[index] = {
		"stars": maxi(stars, int(prev.get("stars", 0))),
		"score": maxi(score, int(prev.get("score", 0))),
	}
	m3_unlocked = maxi(m3_unlocked, index + 2)
	m3_best["score"] = maxi(score, int(m3_best.get("score", 0)))
	note_max("m3_cleared", m3_level_best.size())
	note_max("m3_best", int(m3_best.get("score", 0)))
	note_max("m3_stars_total", m3_total_stars())
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best_time", best_time)
	cfg.set_value("run", "unlocked", unlocked)
	for key: int in level_best:
		var entry: Dictionary = level_best[key]
		cfg.set_value("levels", "time_%d" % key, float(entry.time))
		cfg.set_value("levels", "coins_%d" % key, int(entry.coins))
		cfg.set_value("levels", "stars_%d" % key, int(entry.stars))
	for key: String in settings:
		if key == "keys":
			for p: int in range((settings[key] as Array).size()):
				for a: String in KEY_ACTIONS:
					cfg.set_value("keys", "p%d_%s" % [p, a], int((settings[key] as Array)[p][a]))
			continue
		cfg.set_value("set", key, settings[key])
	for key: String in stats:
		cfg.set_value("stat", key, int(stats[key]))
	for id: String in achievements:
		if bool(achievements[id]):
			cfg.set_value("ach", id, true)
	cfg.set_value("m3", "unlocked", m3_unlocked)
	for key: int in m3_level_best:
		cfg.set_value("m3", "stars_%d" % key, int(m3_level_best[key].stars))
		cfg.set_value("m3", "score_%d" % key, int(m3_level_best[key].score))
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_time = float(cfg.get_value("run", "best_time", 0.0))
	unlocked = clampi(int(cfg.get_value("run", "unlocked", 1)), 1, LEVELS.size())
	level_best = {}
	for i: int in range(LEVELS.size()):
		var t: float = float(cfg.get_value("levels", "time_%d" % i, -1.0))
		if t < 0.0:
			continue
		level_best[i] = {
			"time": t,
			"coins": int(cfg.get_value("levels", "coins_%d" % i, 0)),
			"stars": int(cfg.get_value("levels", "stars_%d" % i, 1)),
		}
	for d: Dictionary in SETTINGS:
		var key := String(d.key)
		if d.kind == "range":
			settings[key] = float(cfg.get_value("set", key, float(settings[key])))
		else:
			settings[key] = bool(cfg.get_value("set", key, bool(settings[key])))
	var keys: Array = []
	for p: int in range(DEFAULT_KEYS.size()):
		var row := {}
		for a: String in KEY_ACTIONS:
			row[a] = int(cfg.get_value("keys", "p%d_%s" % [p, a], int(DEFAULT_KEYS[p][a])))
		keys.append(row)
	settings["keys"] = keys
	if cfg.has_section("stat"):
		for key: String in cfg.get_section_keys("stat"):
			stats[key] = int(cfg.get_value("stat", key, 0))
	if cfg.has_section("ach"):
		for id: String in cfg.get_section_keys("ach"):
			achievements[id] = true
	m3_unlocked = clampi(int(cfg.get_value("m3", "unlocked", 1)), 1, 99)
	m3_level_best = {}
	if cfg.has_section("m3"):
		for i: int in range(40):
			var s: int = int(cfg.get_value("m3", "stars_%d" % i, 0))
			if s <= 0:
				continue
			m3_level_best[i] = {"stars": s, "score": int(cfg.get_value("m3", "score_%d" % i, 0))}
	var best := 0
	for key: int in m3_level_best:
		best = maxi(best, int(m3_level_best[key].score))
	if best > 0:
		m3_best["score"] = best
	# Re-derive the counter-style stats from the records they can be read off, so a
	# save written before a stat existed still shows honest progress.
	note_max("stars_total", total_stars())
	note_max("max_chapter", unlocked)
	note_max("m3_cleared", m3_level_best.size())
	note_max("m3_stars_total", m3_total_stars())
	note_max("m3_best", int(m3_best.get("score", 0)))
