## 원형 선택 메뉴. open()으로 항목을 원 위에 늘어놓고, 고르면 chosen(id)를 보냅니다.
## 바깥 클릭, 우클릭, Esc로 닫힙니다. 숫자 키 1~9로도 고를 수 있습니다.
extends Control

signal chosen(id: String)

const ITEM_SIZE := Vector2(132, 50)
const HUB := 58.0

var _center := Vector2.ZERO
var _radius := 120.0
var _buttons: Array[Button] = []
var _items: Array = []
var _title: Label
var _desc: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 16)
	_title.size = Vector2(HUB * 1.8, HUB * 1.4)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_desc = Label.new()
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 13)
	_desc.add_theme_constant_override("outline_size", 5)
	_desc.add_theme_color_override("font_outline_color", Color.BLACK)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	_desc.add_theme_stylebox_override("normal", box)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc)


func is_open() -> bool:
	return visible


## anchor: 메뉴를 연 버튼의 위쪽 가운데. 원은 그 위에 뜹니다 (화면 밖으로 나가지 않게 맞춤)
## items: [{id, text, sub, desc, disabled, reason}]
func open(anchor: Vector2, title: String, items: Array) -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_items = items
	var n := items.size()
	_radius = clampf(60.0 + n * 16.0, 105.0, 175.0)
	var vs := get_viewport_rect().size
	var mx := _radius + ITEM_SIZE.x / 2.0 + 8.0
	var my := _radius + ITEM_SIZE.y / 2.0 + 8.0
	_center = anchor - Vector2(0, _radius + ITEM_SIZE.y / 2.0 + 16.0)
	_center.x = clampf(_center.x, mx, vs.x - mx)
	_center.y = clampf(_center.y, my, vs.y - my - 60.0)
	for i in n:
		var it: Dictionary = items[i]
		var ang := -PI / 2.0 + TAU * i / maxi(n, 1)
		var b := Button.new()
		var sub: String = it.get("sub", "")
		b.text = "%d %s%s" % [i + 1, it.text, ("\n" + sub) if sub != "" else ""]
		b.disabled = it.get("disabled", false)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _pill(st))
		add_child(b)
		b.size = ITEM_SIZE
		b.position = _center + Vector2(cos(ang), sin(ang)) * _radius - ITEM_SIZE / 2.0
		b.mouse_entered.connect(func() -> void: _show_desc(it))
		b.mouse_exited.connect(func() -> void: _desc.visible = false)
		var id: String = it.id
		b.pressed.connect(func() -> void: _choose(id))
		_buttons.append(b)
	_title.text = title
	_title.position = _center - _title.size / 2.0
	# 설명은 원 오른쪽 (자리가 없으면 왼쪽)
	_desc.text = ""
	_desc.visible = false
	_desc.size = Vector2(300, 0)
	var side := _radius + ITEM_SIZE.x / 2.0 + 18.0
	if _center.x + side + _desc.size.x <= vs.x:
		_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_desc.position = Vector2(_center.x + side, _center.y - 20.0)
	else:
		_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_desc.position = Vector2(_center.x - side - _desc.size.x, _center.y - 20.0)
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _choose(id: String) -> void:
	close()
	chosen.emit(id)


func _show_desc(it: Dictionary) -> void:
	var t: String = it.get("desc", "")
	if it.get("disabled", false) and it.get("reason", "") != "":
		t = "쓸 수 없음: %s%s" % [it.reason, ("\n" + t) if t != "" else ""]
	_desc.text = t
	_desc.visible = t != ""
	_desc.size.y = 0  # 글 길이에 맞게 다시 줄임


func _pill(state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(int(ITEM_SIZE.y / 2.0))
	s.set_border_width_all(2)
	match state:
		"hover":
			s.bg_color = Color(0.25, 0.3, 0.42, 0.97)
			s.border_color = Color(1.0, 0.85, 0.35)
		"pressed":
			s.bg_color = Color(0.35, 0.4, 0.55, 0.97)
			s.border_color = Color(1.0, 0.85, 0.35)
		"disabled":
			s.bg_color = Color(0.12, 0.12, 0.14, 0.85)
			s.border_color = Color(0.3, 0.3, 0.32)
		_:
			s.bg_color = Color(0.14, 0.16, 0.22, 0.95)
			s.border_color = Color(0.55, 0.6, 0.75)
	return s


func _draw() -> void:
	if not visible:
		return
	draw_circle(_center, _radius + ITEM_SIZE.x * 0.55, Color(0, 0, 0, 0.35))
	draw_arc(_center, _radius, 0.0, TAU, 96, Color(1, 1, 1, 0.18), 3.0, true)
	draw_circle(_center, HUB, Color(0.08, 0.08, 0.11, 0.95))
	draw_arc(_center, HUB, 0.0, TAU, 64, Color(1.0, 0.85, 0.35, 0.8), 2.0, true)


func _gui_input(event: InputEvent) -> void:
	# 버튼이 아닌 곳을 누르면 닫힘
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode
	if key == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_9:
		var i: int = key - KEY_1
		if i < _items.size() and not _items[i].get("disabled", false):
			_choose(_items[i].id)
		get_viewport().set_input_as_handled()
