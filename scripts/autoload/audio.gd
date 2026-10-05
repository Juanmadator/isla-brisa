extends Node
## Música y ambiente con fundido cruzado, y un pequeño grupo de reproductores de efectos.

const MUSIC := {
	"title": "res://assets/audio/music_title.wav",
	"day": "res://assets/audio/music_day.wav",
	"night": "res://assets/audio/music_night.wav",
	"village": "res://assets/audio/music_village.wav",
	"ending": "res://assets/audio/music_ending.wav",
}
const AMB := {
	"wind": "res://assets/audio/amb_wind.wav",
	"sea": "res://assets/audio/amb_sea.wav",
	"night": "res://assets/audio/amb_night.wav",
	"birds": "res://assets/audio/amb_birds.wav",
}
## Ajustes de volumen por efecto (dB), según el informe del generador de audio.
const SFX_GAIN := {
	"countdown": -6.0, "go": -4.0, "ring": -2.0, "kitten": -2.0, "ui_open": -2.0, "ui_close": -2.0,
	"beacon": 2.0, "splash": 2.0, "talk": -6.0, "ui_hover": -4.0,
}
const SFX_DIR := "res://assets/audio/sfx_%s.wav"
const POOL_SIZE := 12

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current_track := ""
var _amb := {}
var _amb_target := {}
var _pool: Array[AudioStreamPlayer] = []
var _cache := {}
var _last_play := {}
var _duck := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_loop_player()
	_music_b = _make_loop_player()
	for k in AMB:
		var p := _make_loop_player()
		_amb[k] = p
		_amb_target[k] = 0.0
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func _make_loop_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -80.0
	add_child(p)
	p.finished.connect(func() -> void:
		if p.volume_db > -70.0:
			p.play())
	return p


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_cache[path] = stream
	return stream


static func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func _music_db() -> float:
	return _db(SaveGame.setting("music")) - 6.0 - _duck


func play_music(track: String, fade := 2.0) -> void:
	if track == _current_track:
		return
	_current_track = track
	var stream := _load(MUSIC.get(track, ""))
	var outgoing := _music_a if _music_a.playing and _music_a.volume_db > -70.0 else _music_b
	var incoming := _music_b if outgoing == _music_a else _music_a
	if outgoing.playing:
		var tw := create_tween()
		tw.tween_property(outgoing, "volume_db", -80.0, fade)
		tw.tween_callback(outgoing.stop)
	if stream:
		incoming.stream = stream
		incoming.volume_db = -50.0
		incoming.play()
		var t2 := create_tween()
		t2.tween_property(incoming, "volume_db", _music_db(), fade * 1.2)


func current_music() -> String:
	return _current_track


## Fija el volumen relativo (0..1) de cada ambiente; se aproxima suavemente.
func set_ambience(levels: Dictionary) -> void:
	for k in _amb_target:
		_amb_target[k] = levels.get(k, 0.0)


func duck(amount_db: float) -> void:
	_duck = amount_db
	refresh_volumes()


func _process(delta: float) -> void:
	var base := _db(SaveGame.setting("ambience")) - 12.0
	for k in _amb:
		var p: AudioStreamPlayer = _amb[k]
		var lvl: float = _amb_target[k]
		var want := base + _db(lvl) if lvl > 0.001 else -80.0
		if lvl > 0.001 and not p.playing:
			var s := _load(AMB[k])
			if s:
				p.stream = s
				p.volume_db = -60.0
				p.play()
		p.volume_db = move_toward(p.volume_db, want, 18.0 * delta)
		if p.playing and p.volume_db <= -79.0:
			p.stop()


func refresh_volumes() -> void:
	for p in [_music_a, _music_b]:
		if p.playing and p.volume_db > -70.0:
			p.volume_db = _music_db()


func play(name: String, pitch_jitter := 0.0, volume_offset := 0.0, pitch := 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 30:
		return
	_last_play[name] = now
	var stream := _load(SFX_DIR % name)
	if stream == null:
		return
	var player: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _pool[0]
		_pool.push_back(_pool.pop_front())
	player.stream = stream
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	player.volume_db = _db(SaveGame.setting("sfx")) + volume_offset + float(SFX_GAIN.get(name, 0.0))
	player.play()
