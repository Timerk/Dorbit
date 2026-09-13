class_name FeedbackAudio
extends Node
## Original synthesized cues. This node is never created by a dedicated server.

const SETTINGS := "user://audio.cfg"
var master: float = 0.7
var effects: float = 0.7
var muted: bool = false
var voices: Array[AudioStreamPlayer] = []
var clips: Dictionary[String, AudioStreamWAV] = {}
var last_played: Dictionary[String, int] = {}


func _ready() -> void:
	add_to_group("feedback_audio")
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		master = clampf(float(config.get_value("audio", "master", master)), 0.0, 1.0)
		effects = clampf(float(config.get_value("audio", "effects", effects)), 0.0, 1.0)
		muted = bool(config.get_value("audio", "muted", false))
	for cue in ["laser", "shield", "hull", "destruction", "purchase"]:
		clips[cue] = synthesize(cue)
	for index in range(6):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)


func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master)
	config.set_value("audio", "effects", effects)
	config.set_value("audio", "muted", muted)
	if config.save(SETTINGS) != OK:
		push_warning("Could not save audio preferences.")
	for voice in voices:
		voice.volume_linear = 0.0 if muted else master * effects


func play(cue: String, location: Vector3) -> void:
	if muted or master * effects <= 0.0 or not clips.has(cue):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(location)
	if distance > 350.0:
		return
	var now := Time.get_ticks_msec()
	var interval := 180 if cue == "laser" else 100
	if now - last_played.get(cue, -1000) < interval:
		return
	for voice in voices:
		if not voice.playing:
			last_played[cue] = now
			voice.stream = clips[cue]
			voice.volume_linear = master * effects * lerpf(1.0, 0.15, clampf(distance / 350.0, 0, 1))
			voice.play()
			return


static func synthesize(cue: String) -> AudioStreamWAV:
	var duration := 0.12
	if cue == "destruction":
		duration = 0.5
	elif cue == "purchase":
		duration = 0.25
	var samples := PackedByteArray()
	var count := int(22050 * duration)
	samples.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 431
	var phase := 0.0
	for index in range(count):
		var progress := float(index) / count
		var frequency := lerpf(1100, 260, progress)
		if cue == "shield":
			frequency = lerpf(680, 420, progress)
		elif cue == "hull" or cue == "destruction":
			frequency = lerpf(150, 40, progress)
		elif cue == "purchase":
			frequency = 660.0 if progress < 0.5 else 880.0
		phase += TAU * frequency / 22050.0
		var sample := sin(phase)
		if cue == "hull" or cue == "destruction":
			sample = sample * 0.35 + rng.randf_range(-1, 1) * 0.65
		var envelope := minf(progress * 40.0, 1.0) * pow(1.0 - progress, 2.0)
		samples.encode_s16(index * 2, int(sample * envelope * 7000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = samples
	return stream
