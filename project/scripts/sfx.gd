extends Node

## Звук: одноразовые эффекты + эмбиент-петля. Терпим к отсутствию файлов.

const SOUNDS: = [
	"ui_click", "jump", "land", "round_ok", "round_fail", "layer_done",
	"hack_win", "hack_fail", "alarm", "hunter", "quarantine", "ability",
	"pickup", "chain", "trap", "ambient",
]

var _streams: = {}
var _ambient_player: AudioStreamPlayer
var _players: Array = []
var _next: = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SOUNDS:
		var path: = "res://audio/%s.wav" % s
		if ResourceLoader.exists(path):
			_streams[s] = load(path)
	for i in 10:
		var p: = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.volume_db = -14.0
	add_child(_ambient_player)

func play(sound_name: String, volume_db: = 0.0, pitch: = 1.0) -> void:
	if not _streams.has(sound_name):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()

func ambient(on: bool, pitch: = 1.0) -> void:
	if not _streams.has("ambient"):
		return
	if on:
		var st: AudioStreamWAV = _streams["ambient"]
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / 2  # 16-бит моно: сэмплов = байт / 2
		_ambient_player.stream = st
		_ambient_player.pitch_scale = pitch
		if not _ambient_player.playing:
			_ambient_player.play()
	else:
		_ambient_player.stop()
