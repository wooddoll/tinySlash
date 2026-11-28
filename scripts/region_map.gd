## 지방 지도 창 (M, M5): 3x3 칸 버튼. 칸마다 이름, 마을·던전, 의뢰 표시, 걸리는 시간.
## 다른 칸을 누르면 빠른 이동(travel 신호, 시간이 흐름). Esc·B·M으로 닫음.
extends CanvasLayer

const Region = preload("res://rules/region.gd")
const Game = preload("res://scripts/game.gd")

signal travel(tile: Vector2i)
signal closed

var panel: PanelContainer
var title: Label
var grid: GridContainer
var _closed_at := -1


func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.13, 0.11, 0.08, 0.97)
	bg.border_color = Color(0.6, 0.47, 0.28)
	bg.set_border_width_all(3)
	bg.set_content_margin_all(18)
	bg.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	grid = GridContainer.new()
	grid.columns = Region.W
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var foot := Label.new()
	foot.text = "칸을 누르면 빠른 이동 (시간이 흘러요) · Esc / M: 닫기"
	foot.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)
	visible = false


func is_open() -> bool:
	return visible


func open(region, here: Vector2i, time_text: String) -> void:
	title.text = "재너머 골짜기 지방 — %s" % time_text
	for c in grid.get_children():
		c.queue_free()
	var focus: Button = null
	for y in Region.H:
		for x in Region.W:
			var t := Vector2i(x, y)
			var info: Dictionary = region.tiles[t]
			var lines := PackedStringArray([str(info.name)])
			if info.kind == "village":
				lines.append("마을")
			var dg: Dictionary = region.dungeon_at(t)
			if not dg.is_empty():
				lines.append("던전: " + str(dg.name))
			if _has_quest(region, t):
				lines.append("★ 의뢰")
			lines.append("— 여기 —" if t == here else "걸어서 %s시간" % _hours(Region.travel_hours(here, t)))
			var b := Button.new()
			b.text = "\n".join(lines)
			b.custom_minimum_size = Vector2(190, 118)
			b.add_theme_font_size_override("font_size", 15)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.32, 0.42, 0.25) if info.kind == "village" else (Color(0.3, 0.27, 0.22) if not dg.is_empty() else Color(0.24, 0.3, 0.2))
			if t == here:
				sb.border_color = Color(1.0, 0.85, 0.4)
				sb.set_border_width_all(3)
			sb.set_corner_radius_all(4)
			b.add_theme_stylebox_override("normal", sb)
			var hov := sb.duplicate() as StyleBoxFlat
			hov.bg_color = sb.bg_color.lightened(0.15)
			b.add_theme_stylebox_override("hover", hov)
			b.add_theme_stylebox_override("focus", hov)
			b.pressed.connect(_pick.bind(t, here))
			grid.add_child(b)
			if t == here:
				focus = b
	visible = true
	if focus:
		focus.grab_focus.call_deferred()


static func _hours(h: float) -> String:
	return str(int(h)) if is_equal_approx(h, roundf(h)) else "%.1f" % h


## 진행 중인 의뢰가 이 칸을 겨냥하나 (던전 의뢰, 또는 이 칸 몬스터 무리 — 무리 번호 앞자리가 칸 번호)
func _has_quest(region, t: Vector2i) -> bool:
	for q in Game.quests:
		if q.state != "active":
			continue
		if q.kind == "group" and int(q.target) / 100 == Region.index(t):
			return true
		if q.kind != "group":
			var d: int = int(q.get("dungeon", 0))
			if d < region.dungeons.size() and region.dungeons[d].tile == t:
				return true
	return false


func _pick(t: Vector2i, here: Vector2i) -> void:
	if t == here:
		return
	close()
	travel.emit(t)


func close() -> void:
	if not visible:
		return
	visible = false
	_closed_at = Engine.get_process_frames()
	closed.emit()


## 방금(이번 프레임) 닫혔나 — 닫은 M 키로 바로 다시 열리지 않게
func just_closed() -> bool:
	return Engine.get_process_frames() == _closed_at


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("back") or event.is_action_pressed("map")):
		get_viewport().set_input_as_handled()
		close()
