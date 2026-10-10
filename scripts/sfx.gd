extends Node

const RATE := 44100

const RECIPES := {
	"jump": [{"f": 430.0, "f2": 780.0, "d": 0.13, "type": "tri", "v": 0.42}],
	"land": [{"f": 165.0, "f2": 62.0, "d": 0.10, "type": "sine", "v": 0.30}],
	"boing": [{"f": 280.0, "f2": 980.0, "d": 0.24, "type": "square", "v": 0.26}],
	"press": [{"f": 620.0, "f2": 180.0, "d": 0.13, "type": "sine", "v": 0.28}],
	"sync": [
		{"f": 660.0, "f2": 990.0, "d": 0.16, "type": "tri", "v": 0.24, "at": 0.00},
		{"f": 990.0, "f2": 1320.0, "d": 0.26, "type": "tri", "v": 0.22, "at": 0.07},
	],
	"taut": [{"f": 240.0, "f2": 150.0, "d": 0.09, "type": "square", "v": 0.14}],
	"swing": [
		{"f": 300.0, "f2": 940.0, "d": 0.17, "type": "saw", "v": 0.13, "at": 0.00},
		{"f": 520.0, "f2": 1180.0, "d": 0.20, "type": "tri", "v": 0.16, "at": 0.03},
	],
	"coin": [{"f": 1046.0, "f2": 1568.0, "d": 0.11, "type": "square", "v": 0.16}],
	"plate": [{"f": 660.0, "f2": 660.0, "d": 0.07, "type": "square", "v": 0.20}],
	"door": [{"f": 300.0, "f2": 700.0, "d": 0.55, "type": "tri", "v": 0.28}],
	"die": [{"f": 420.0, "f2": 80.0, "d": 0.50, "type": "saw", "v": 0.30}],
	"win": [
		{"f": 523.0, "f2": 523.0, "d": 0.16, "type": "tri", "v": 0.26, "at": 0.00},
		{"f": 659.0, "f2": 659.0, "d": 0.16, "type": "tri", "v": 0.26, "at": 0.12},
		{"f": 784.0, "f2": 784.0, "d": 0.16, "type": "tri", "v": 0.26, "at": 0.24},
		{"f": 1046.0, "f2": 1046.0, "d": 0.42, "type": "tri", "v": 0.30, "at": 0.36},
	],
	"start": [
		{"f": 392.0, "f2": 392.0, "d": 0.12, "type": "square", "v": 0.20, "at": 0.00},
		{"f": 587.0, "f2": 587.0, "d": 0.20, "type": "square", "v": 0.20, "at": 0.10},
	],
	"select": [{"f": 880.0, "f2": 880.0, "d": 0.05, "type": "square", "v": 0.12}],
}

# 配乐和音效是同一台合成器：一个十六分音符的格子，排一段琶音加一条低音符。
# 调式跟着地貌走，所以每个地貌的那首曲子听上去就属于那片地面。每个数字都只是
# 音高和响度——曲子必须一直坐在音效底下，峰值压在 0.16 上下。
const MUSIC := {
	"title": {
		"bpm": 76.0, "root": 220.0, "scale": [0, 3, 5, 7, 10],
		"wave": "tri", "bass": "sine", "gain": 0.075, "bgain": 0.06, "len": 0.5,
		"prog": [0, 3, 4, 2],
		"arp": [0, -1, 2, -1, 4, -1, 2, 0, -1, 3, -1, 2, 4, -1, 5, -1],
	},
	"meadow": {
		"bpm": 104.0, "root": 261.63, "scale": [0, 2, 4, 7, 9],
		"wave": "tri", "bass": "sine", "gain": 0.07, "bgain": 0.055, "len": 0.42,
		"prog": [0, 4, 3, 2],
		"arp": [0, 2, 4, 2, 5, -1, 4, 2, 0, -1, 2, 4, 6, 4, 2, -1],
	},
	"canyon": {
		"bpm": 96.0, "root": 196.0, "scale": [0, 2, 4, 7, 10],
		"wave": "square", "bass": "tri", "gain": 0.042, "bgain": 0.06, "len": 0.34,
		"prog": [0, 2, 4, 1],
		"arp": [0, -1, 4, 3, -1, 4, -1, 2, 0, -1, 3, 4, 5, -1, 4, 2],
	},
	"forest": {
		"bpm": 84.0, "root": 220.0, "scale": [0, 3, 5, 7, 10],
		"wave": "sine", "bass": "sine", "gain": 0.075, "bgain": 0.065, "len": 0.7,
		"prog": [0, 2, 3, 1],
		"arp": [0, -1, -1, 2, -1, 4, -1, -1, 3, -1, 5, -1, 4, -1, -1, 2],
	},
	"cave": {
		"bpm": 78.0, "root": 174.61, "scale": [0, 3, 5, 6, 7, 10],
		"wave": "tri", "bass": "sine", "gain": 0.07, "bgain": 0.07, "len": 0.8,
		"prog": [0, 3, 5, 2],
		"arp": [0, -1, 2, -1, -1, 4, -1, 2, -1, 5, -1, -1, 3, -1, 1, -1],
	},
	"snow": {
		"bpm": 92.0, "root": 293.66, "scale": [0, 2, 4, 6, 7, 9, 11],
		"wave": "sine", "bass": "tri", "gain": 0.06, "bgain": 0.05, "len": 0.5,
		"prog": [0, 4, 6, 3],
		"arp": [0, 2, 4, 6, 4, 2, 0, -1, 2, 4, 6, 8, 6, 4, 2, -1],
	},
	"dusk": {
		"bpm": 72.0, "root": 246.94, "scale": [0, 2, 4, 7, 9],
		"wave": "tri", "bass": "sine", "gain": 0.075, "bgain": 0.065, "len": 0.9,
		"prog": [0, 3, 4, 2],
		"arp": [4, -1, 2, -1, 0, -1, 2, 4, 5, -1, 4, -1, 2, -1, 0, -1],
	},
	"m3": {
		"bpm": 126.0, "root": 329.63, "scale": [0, 2, 4, 7, 9],
		"wave": "square", "bass": "tri", "gain": 0.04, "bgain": 0.05, "len": 0.28,
		"prog": [0, 2, 4, 2],
		"arp": [0, 2, 4, 5, 4, 2, 0, 2, 5, 4, 2, 4, 0, -1, 2, -1],
	},
}

var _gen: AudioStreamGenerator
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array[Dictionary] = []
var _mvoices: Array[Dictionary] = []
var _muted := false

# 排程器：_mus_track 是当前要放的那首，_mus_time 只在门开着的时候往前走。
var _mus_track := ""
var _mus_time := 0.0
var _mus_step := 0
var _mus_left := 0.0
var _mus_open := false


func _ready() -> void:
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = RATE
	_gen.buffer_length = 0.25
	_player = AudioStreamPlayer.new()
	_player.stream = _gen
	_player.volume_db = -4.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	Game.settings_changed.connect(_on_settings_changed)
	# 谁在放哪一段曲子默认跟着画面走：main.gd 想自己指定就直接再调 set_music()，
	# 下一次画面切换之前它不会插嘴。
	Game.screen_changed.connect(_on_screen_changed)
	Game.level_started.connect(_on_level_started)
	_on_settings_changed()
	_pick_track()


func play(sound: String) -> void:
	if _muted or not RECIPES.has(sound):
		return
	for entry: Dictionary in RECIPES[sound]:
		_voices.append({
			"f": float(entry.f),
			"f2": float(entry.f2),
			"d": float(entry.d),
			"t": float(entry.get("at", 0.0)),
			"life": 0.0,
			"phase": 0.0,
			"kind": String(entry.get("type", "sine")),
			"v": float(entry.get("v", 0.3)),
		})


func toggle_mute() -> bool:
	# 写进存档而不是只记在自己身上：M 键和设置页于是只可能是同一个开关。
	if Game != null:
		Game.set_setting("muted", not _muted)
		return _muted
	_muted = not _muted
	_on_settings_changed()
	return _muted


func set_music(track: String) -> void:
	var want := track if MUSIC.has(track) else "title"
	# 同一段曲子重复调用不许重来：关卡一进门、页面一关都会再叫一次。
	if want == _mus_track:
		return
	_mus_track = want
	_mus_time = 0.0
	_mus_step = 0
	_mus_left = 0.0
	_mvoices.clear()


func stop_music() -> void:
	_mus_track = ""
	_mus_time = 0.0
	_mus_step = 0
	_mvoices.clear()


func music_track() -> String:
	return _mus_track


func is_music_playing() -> bool:
	return not _mus_track.is_empty() and _music_wanted()


func _on_settings_changed() -> void:
	if Game != null:
		_muted = bool(Game.settings.get("muted", _muted))
	if _muted:
		_voices.clear()
		_mvoices.clear()
	_apply_volume()


func _on_screen_changed(_to: int) -> void:
	_pick_track()


func _on_level_started(_index: int) -> void:
	# 地貌要读关卡场景才知道，第一次读会把 12 关都实例化一遍；这件事放在
	# 关卡正在打开的那一帧做会咬一口，推后一步就没人感觉得到。
	_pick_track.call_deferred()


func _pick_track() -> void:
	if Game == null:
		return
	# 设置/成就/教学页是盖在画面上的，这时候该让音效独个儿说话；页面关掉之后
	# _music_wanted() 重新开门，同一段曲子从断掉的地方接着弹。
	if bool(Game.page_open()):
		return
	var screen: int = Game.screen_state
	if screen == Game.Screen.PLAYING or screen == Game.Screen.PAUSED:
		set_music(String(Game.level_biome(Game.level_index)))
	elif screen == Game.Screen.MATCH3 or int(Game.mode) == Game.Mode.MATCH3:
		set_music("m3")
	else:
		set_music("title")


func _apply_volume() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var v := 0.8
	var mute: bool = _muted
	if Game != null:
		v = clampf(float(Game.settings.get("volume", 0.8)), 0.0, 1.0)
		mute = mute or bool(Game.settings.get("muted", false))
	# linear_to_db(0.0) 是 -inf，静音和零音量都当成断掉处理，别把它交给播放器。
	_player.volume_db = -80.0 if mute or v <= 0.001 else linear_to_db(v)


func _music_wanted() -> bool:
	if _mus_track.is_empty() or _muted:
		return false
	if Game == null:
		return true
	if bool(Game.settings.get("muted", false)) or bool(Game.page_open()):
		return false
	return bool(Game.settings.get("music", true))


func _process(delta: float) -> void:
	_tick_music(delta)
	if _playback == null or not is_instance_valid(_playback):
		_playback = _player.get_stream_playback()
		if _playback == null:
			return
	var guard := 0
	while guard < 24:
		guard += 1
		var frames: int = _playback.get_frames_available()
		if frames <= 0:
			return
		var batch: int = mini(256, frames)
		var buffer := PackedVector2Array()
		buffer.resize(batch)
		for i: int in range(batch):
			var sample := _next_sample()
			buffer[i] = Vector2(sample, sample)
		_playback.push_buffer(buffer)


# 排程器住在 _process 而不是采样回路里，为的是无头模式（没有任何播放器）也能把
# 一整段曲子走完，也让“页面开着就闭嘴”这件事在一步之内生效。
func _tick_music(delta: float) -> void:
	if not _music_wanted():
		# 关门要把已经排出去的几个音一起抹掉：页面开着还余一串尾音，比断了更烦人。
		if _mus_open:
			_mus_open = false
			_mvoices.clear()
		return
	if not _mus_open:
		_mus_open = true
		_mus_left = 0.0
	var def: Dictionary = MUSIC.get(_mus_track, MUSIC.title)
	_mus_time += delta
	_mus_left -= delta
	if _mus_left > 0.0:
		return
	var step_len: float = 60.0 / float(def.bpm) / 4.0
	# 一次卡顿会在这条线上堆出几十个步子；只追平当下，落后的那几个直接扔掉，
	# 否则回到前台时音乐会像快进一样把刚才那一段赶完。
	_mus_left = step_len if _mus_left <= -step_len else _mus_left + step_len
	var arp: Array = def.arp
	var d: int = int(arp[_mus_step % arp.size()])
	if d >= 0:
		_mnote(_freq(def, d, 0.0), step_len * float(def.len), String(def.wave), float(def.gain))
	# 低音符每两个步子一次，小节换了就换 prog 里的那个音级。
	if _mus_step % 4 == 0:
		var prog: Array = def.prog
		var bar: int = floori(float(_mus_step) / float(arp.size()))
		var bd: int = int(prog[bar % prog.size()])
		_mnote(_freq(def, bd, -12.0), step_len * 2.2, String(def.bass), float(def.bgain))
	_mus_step += 1


func _mnote(freq: float, dur: float, kind: String, gain: float) -> void:
	# 采样没被消费掉的时候（无头、或者播放器卡住）音符只会堆着，堆够了就不再排：
	# 一串排到未来的音符比丢几个音更糟。
	if _mvoices.size() > 20:
		return
	_mvoices.append({
		"f": freq, "d": maxf(0.05, dur), "v": gain,
		"life": 0.0, "phase": randf(), "kind": kind,
	})


func _freq(def: Dictionary, degree: int, semis: float) -> float:
	var scale: Array = def.scale
	var n: int = scale.size()
	var oct: int = floori(float(degree) / float(n))
	var idx: int = posmod(degree, n)
	return float(def.root) * pow(2.0, (float(scale[idx]) + 12.0 * float(oct) + semis) / 12.0)


func _next_sample() -> float:
	var out := 0.0
	var step := 1.0 / float(RATE)
	var i := _voices.size()
	while i > 0:
		i -= 1
		var v: Dictionary = _voices[i]
		v.life += step
		if v.life < v.t:
			continue
		var p: float = (v.life - v.t) / v.d
		if p >= 1.0:
			_voices.remove_at(i)
			continue
		var freq: float = lerpf(v.f, v.f2, p)
		v.phase += freq * step
		var env: float = (1.0 - p) * (1.0 - p)
		var attack: float = minf(1.0, (v.life - v.t) / 0.008)
		out += _shape(v.kind, v.phase) * env * attack * v.v
		_voices[i] = v
	out += _mix_music(step)
	return clampf(out, -1.0, 1.0) * 0.8


# 音乐走的是第二条通路，自己的上限压得比音效低得多：它要坐在音效底下，几个音
# 叠在一起也只能到 0.16 上下，并且尾巴比平方衰减更黏一点、起音慢一点，否则
# 一个音一个音听下来就是咔哒声。
func _mix_music(step: float) -> float:
	var out := 0.0
	var i := _mvoices.size()
	while i > 0:
		i -= 1
		var v: Dictionary = _mvoices[i]
		v.life += step
		var p: float = v.life / v.d
		if p >= 1.0:
			_mvoices.remove_at(i)
			continue
		v.phase += v.f * step
		var env: float = pow(1.0 - p, 1.6)
		var attack: float = minf(1.0, v.life / 0.018)
		out += _shape(v.kind, v.phase) * env * attack * v.v
		_mvoices[i] = v
	return clampf(out, -0.34, 0.34)


func _shape(kind: String, phase: float) -> float:
	var frac: float = phase - floor(phase)
	match kind:
		"sine":
			return sin(phase * TAU)
		"square":
			return 1.0 if frac < 0.5 else -1.0
		"tri":
			return 1.0 - 4.0 * absf(frac - 0.5)
		"saw":
			return 2.0 * frac - 1.0
	return sin(phase * TAU)
