## 음량 설정 (M7): 버스 넷(Master, Music 음악, SFX 효과음, Ambient 환경음)과 user://settings.cfg에 저장한 음량(0~1).
## 처음 쓸 때 버스를 만들고 저장한 음량을 적용합니다. 다른 스크립트는 const AudioSettings = preload("res://scripts/audio_settings.gd").
extends RefCounted

const PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX", "Ambient"]
const LABELS := {"Master": "전체", "Music": "음악", "SFX": "효과음", "Ambient": "환경음"}
const DEFAULTS := {"Master": 0.8, "Music": 0.6, "SFX": 1.0, "Ambient": 0.7}

static var _ready := false
static var volumes := {}


## 버스를 만들고 저장된 음량 적용 (여러 번 불러도 됨)
static func ensure() -> void:
	if _ready:
		return
	_ready = true
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for b in BUSES:
		set_volume(b, float(cfg.get_value("audio", b, DEFAULTS[b])), false)


static func get_volume(bus: String) -> float:
	ensure()
	return float(volumes.get(bus, DEFAULTS.get(bus, 1.0)))


## 음량(0~1)을 바꾸고 저장
static func set_volume(bus: String, v: float, save := true) -> void:
	v = clampf(v, 0.0, 1.0)
	volumes[bus] = v
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("audio", bus, v)
		cfg.save(PATH)


## 음량 슬라이더 줄들을 만들어 parent에 붙임 (시작 화면)
static func build_sliders(parent: Control) -> void:
	ensure()
	for b in BUSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = LABELS[b]
		l.custom_minimum_size.x = 70
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = get_volume(b)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(func(v: float) -> void: set_volume(b, v))
		row.add_child(s)
		parent.add_child(row)
