## 환경음 (M7): 소리 파일 없이 만든 바람 소리. 갈색 잡음을 낮은 쪽만 남기고 천천히 세졌다 약해지게(돌풍).
## "wind" 바깥(밤엔 조금 잔잔), "cave" 던전(더 낮고 웅웅거림). Ambient 버스로 나감 (scripts/audio_settings.gd).
extends AudioStreamPlayer

const AudioSettings = preload("res://scripts/audio_settings.gd")
const RATE := 22050.0

var mode := "wind"
## 0~1, 바깥 시각에 따라 main이 바꿈 (밤엔 낮게)
var strength := 1.0

var _gen: AudioStreamGeneratorPlayback
var _brown := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _t := 0.0
var _gust := 0.5
var _gust_to := 0.5
var _gust_in := 0.0


func _ready() -> void:
	AudioSettings.ensure()
	bus = "Ambient"
	var s := AudioStreamGenerator.new()
	s.mix_rate = RATE
	s.buffer_length = 0.25
	stream = s
	volume_db = -8.0 if mode == "wind" else -4.0
	play()
	_gen = get_stream_playback()


func _process(delta: float) -> void:
	if _gen == null:
		return
	var n := _gen.get_frames_available()
	if n <= 0:
		return
	var cave := mode == "cave"
	# 돌풍: 몇 초마다 다음 세기를 고르고 천천히 따라감
	_gust_in -= float(n) / RATE
	if _gust_in <= 0.0:
		_gust_in = randf_range(2.0, 6.0)
		_gust_to = randf_range(0.15, 1.0) if not cave else randf_range(0.5, 0.8)
	var buf := PackedVector2Array()
	buf.resize(n)
	var cut := 0.02 if cave else 0.06
	for i in n:
		_gust = lerpf(_gust, _gust_to, 0.00002)
		_brown = clampf(_brown + randf_range(-1.0, 1.0) * 0.04, -1.0, 1.0) * 0.999
		# 거르개를 바람 세기에 따라 조금 열어 휘이잉 하는 느낌
		var c := cut * (0.6 + _gust * 0.8)
		_lp += (_brown - _lp) * c
		_lp2 += (_lp - _lp2) * c
		var v := _lp2 * (0.35 + _gust * 0.9) * strength * 3.0
		buf[i] = Vector2(v, v)
	_gen.push_buffer(buf)
