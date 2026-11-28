## 마을 창 하나 (여관·상점·조합 회관·의뢰판이 같이 씀): 제목, 본문(BBCode), 버튼 줄.
## open()으로 내용을 채워 띄우고, 닫기 버튼·Esc·B로 닫히면 closed 신호. 게임패드는 버튼 포커스로 고름.
extends CanvasLayer

signal closed

var panel: PanelContainer
var body: RichTextLabel
var row: HBoxContainer


func _ready() -> void:
	layer = 5
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.07, 0.96)
	bg.border_color = Color(0.55, 0.42, 0.25)
	bg.set_border_width_all(2)
	bg.set_content_margin_all(16)
	bg.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size.x = 520
	body.add_theme_font_size_override("normal_font_size", 17)
	body.add_theme_font_size_override("bold_font_size", 22)
	box.add_child(body)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	visible = false


func is_open() -> bool:
	return visible


## buttons: [[글, Callable, 누를 수 있나], ...]. 닫기 버튼은 끝에 자동으로 붙음
func open(text: String, buttons: Array = []) -> void:
	body.text = text
	for c in row.get_children():
		c.queue_free()
	var first: Button = null
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.disabled = not bool(b[2]) if b.size() > 2 else false
		btn.pressed.connect(b[1])
		row.add_child(btn)
		if first == null and not btn.disabled:
			first = btn
	var done := Button.new()
	done.text = "닫기 (Esc)"
	done.pressed.connect(close)
	row.add_child(done)
	if first == null:
		first = done
	visible = true
	first.grab_focus.call_deferred()


## 본문만 바꿈 (버튼 그대로)
func refresh(text: String, enabled: Array = []) -> void:
	body.text = text
	var i := 0
	for c in row.get_children():
		if c is Button and i < enabled.size():
			(c as Button).disabled = not bool(enabled[i])
		i += 1


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("back")):
		get_viewport().set_input_as_handled()
		close()
