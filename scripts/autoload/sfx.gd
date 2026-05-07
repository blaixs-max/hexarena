extends Node

const POOL_SIZE := 12
var _pool: Array[AudioStreamPlayer] = []
var whistle_short: AudioStreamWAV
var whistle_long: AudioStreamWAV

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	whistle_short = _make_whistle(0.42, 2400.0, 12.0)
	whistle_long = _make_whistle(0.85, 2200.0, 8.0)

func _make_whistle(duration: float, base_freq: float, vibrato_hz: float) -> AudioStreamWAV:
	var sw := AudioStreamWAV.new()
	sw.format = AudioStreamWAV.FORMAT_16_BITS
	sw.mix_rate = 44100
	sw.stereo = false
	var samples_n: int = int(44100 * duration)
	var data := PackedByteArray()
	data.resize(samples_n * 2)
	for i in samples_n:
		var t: float = float(i) / 44100.0
		var attack: float = 1.0 - exp(-t * 70.0)
		var release: float = exp(-(t / duration) * 2.6)
		var env: float = attack * release
		var freq: float = base_freq + sin(t * TAU * vibrato_hz) * 90.0
		var s: float = sin(t * TAU * freq) * env * 0.55
		s += sin(t * TAU * freq * 2.0) * env * 0.18
		var v: int = int(clamp(s * 32000.0, -32000.0, 32000.0))
		data.encode_s16(i * 2, v)
	sw.data = data
	return sw

func play_whistle_short() -> void:
	play(whistle_short, -2.0, 1.0)

func play_whistle_long() -> void:
	play(whistle_long, -1.0, 1.0)

func play(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return

func play_random(streams: Array, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if streams.is_empty():
		return
	var s = streams[randi() % streams.size()]
	play(s, volume_db, 1.0 + randf_range(-pitch_jitter, pitch_jitter))
