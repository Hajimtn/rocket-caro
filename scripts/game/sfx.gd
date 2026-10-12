class_name Sfx
extends Node
## Tiny sound bank. Every effect is synthesised at start-up so the game has sound with zero
## assets; drop a file at res://assets/audio/<name>.ogg|wav|mp3 to replace any of them.
## Names: launch (normal rocket), launch_erase, launch_steer, boom, mark, block, win, lose, tick.
## The launch_* variants fall back to the synthesised "launch" when no file is present.

const RATE := 22050
const EXTS := ["ogg", "wav", "mp3"]

var _streams: Dictionary = {}


func _ready() -> void:
	_streams["launch"] = _synth(0.5, func(t: float) -> float:
		return sin(TAU * 52.0 * (1.0 - exp(-5.0 * t))) * exp(-5.0 * t) * 0.6 \
			+ (randf() * 2.0 - 1.0) * exp(-9.0 * t) * 0.35)
	_streams["boom"] = _synth(0.7, func(t: float) -> float:
		return sin(TAU * 55.0 * t) * exp(-5.0 * t) * 0.8 + (randf() * 2.0 - 1.0) * exp(-8.0 * t) * 0.5)
	_streams["mark"] = _synth(0.35, func(t: float) -> float:
		return (sin(TAU * 660.0 * t) + sin(TAU * 990.0 * t) * 0.5) * exp(-9.0 * t) * 0.4)
	_streams["block"] = _synth(0.3, func(t: float) -> float:
		return sin(TAU * 80.0 * t) * exp(-12.0 * t) * 0.8 + (randf() * 2.0 - 1.0) * exp(-30.0 * t) * 0.5)
	_streams["win"] = _synth(0.8, func(t: float) -> float:
		var notes := [523.0, 659.0, 784.0, 1046.0]
		var i := mini(int(t / 0.15), 3)
		return sin(TAU * notes[i] * t) * exp(-(t - i * 0.15) * 6.0) * 0.5)
	_streams["lose"] = _synth(0.6, func(t: float) -> float:
		return sin(TAU * (300.0 * t - 150.0 * t * t)) * exp(-3.0 * t) * 0.5)
	_streams["tick"] = _synth(0.08, func(t: float) -> float:
		return sin(TAU * 880.0 * t) * exp(-30.0 * t) * 0.5)


func play(sfx_name: String, volume_db: float = -6.0) -> void:
	var stream := _stream_for(sfx_name)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _stream_for(sfx_name: String) -> AudioStream:
	for ext in EXTS:
		var path := "res://assets/audio/%s.%s" % [sfx_name, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	if _streams.has(sfx_name):
		return _streams[sfx_name] as AudioStream
	return _streams.get("launch") as AudioStream if sfx_name.begins_with("launch") else null


func _synth(duration: float, gen: Callable) -> AudioStreamWAV:
	var n := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s: float = clampf(gen.call(float(i) / RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
