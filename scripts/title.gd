## 시작 화면: 저장이 있으면 이어하기 / 새로 시작, 없으면 바로 새 게임.
extends Control

const InputSetup = preload("res://scripts/input_setup.gd")
const Game = preload("res://scripts/game.gd")
const Sfx = preload("res://scripts/sfx.gd")

const PLACE_NAMES := {"outside": "바깥", "dungeon": "던전"}

var _new_btn: Button
var _confirm_new := false


func _ready() -> void:
	InputSetup.register()
	if not Game.has_save():
		_start_new.call_deferred()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "tinySlash"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	var info := Label.new()
	info.text = _save_line()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(0.75, 0.75, 0.8)
	box.add_child(info)
	var cont := _button(box, "이어하기", _continue)
	_new_btn = _button(box, "새로 시작", _on_new)
	_button(box, "끝내기", func() -> void: get_tree().quit())
	cont.grab_focus()
	Sfx.wire_buttons(self)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## 저장 파일 한 줄 요약 (어디, 레벨, 금화, 언제)
func _save_line() -> String:
	var f := FileAccess.open(Game.save_path, FileAccess.READ)
	if f == null:
		return ""
	var d = f.get_var(false)
	if not (d is Dictionary):
		return "저장 파일을 읽지 못했어요"
	var lv := 1
	if not (d.get("hero", {}) as Dictionary).is_empty():
		lv = HeroState.from_dict(d.hero).level()
	var where: String = PLACE_NAMES.get(str(d.get("place", "outside")), "바깥")
	if str(d.get("place", "")) == "dungeon":
		where += " %d층" % int((d.get("dungeon", {}) as Dictionary).get("floor_no", 1))
	var when := Time.get_datetime_string_from_unix_time(int(d.get("saved_at", 0)) + _tz_bias(), true)
	return "%s · %d레벨 · 금화 %d · %s 저장" % [where, lv, int(d.get("gold", 0)), when]


func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _continue() -> void:
	var scene := Game.load_game()
	if scene == "":
		_start_new()
		return
	get_tree().change_scene_to_file(scene)


func _on_new() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_btn.text = "정말 새로 시작? (기존 저장은 덮어써요)"
		return
	_start_new()


func _start_new() -> void:
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
