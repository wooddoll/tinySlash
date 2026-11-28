## 게임 안 메뉴 (Esc / Start, M7): 계속하기, 음량 4개, 저장하고 시작 화면으로, 저장하고 끝내기.
## 여는 동안 장면 트리를 멈춤(get_tree().paused). 메뉴는 멈춰도 돎(PROCESS_MODE_ALWAYS).
extends CanvasLayer

const AudioSettings = preload("res://scripts/audio_settings.gd")
const Sfx = preload("res://scripts/sfx.gd")

signal closed
## 시작 화면·끝내기 전에 부름 (저장)
var save_fn: Callable

var panel: PanelContainer
var _first: Button
var _closed_at := -1


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.07, 0.97)
	bg.border_color = Color(0.55, 0.42, 0.25)
	bg.set_border_width_all(2)
	bg.set_content_margin_all(20)
	bg.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 360
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var t := Label.new()
	t.text = "잠깐 멈춤"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	box.add_child(t)
	_first = _button(box, "계속하기", close)
	AudioSettings.build_sliders(box)
	_button(box, "저장하고 시작 화면으로", func() -> void:
		_save()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/title.tscn"))
	_button(box, "저장하고 끝내기", func() -> void:
		_save()
		get_tree().quit())
	Sfx.wire_buttons(self)
	visible = false


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _save() -> void:
	if save_fn.is_valid():
		save_fn.call()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	_first.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	_closed_at = Engine.get_process_frames()
	closed.emit()


## 이번 프레임에 닫혔나 (닫은 Esc로 다시 열리지 않게)
func just_closed() -> bool:
	return Engine.get_process_frames() == _closed_at


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("back") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
