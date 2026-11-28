## 지방 지도 창 (M): 지방 전체를 북쪽이 위로 그린 진짜 지도 (높이 음영·등고선·숲·마을, outdoor_terrain.gd map_image).
## 내 자리와 보는 쪽(흰 화살표), 칸 경계와 이름, 마을·던전 입구, 진행 중인 의뢰 대상(노란 !)을 표시.
## 다른 칸을 누르면(또는 방향키로 고르고 Enter) 빠른 이동(travel 신호, 시간이 흐름). Esc·B·M으로 닫음.
extends CanvasLayer

const Region = preload("res://rules/region.gd")
const Game = preload("res://scripts/game.gd")
const Outdoor = preload("res://scripts/outdoor_terrain.gd")
const Minimap = preload("res://scripts/minimap.gd")

signal travel(tile: Vector2i)
signal closed

## 지도 그림 한 변 (픽셀)
const SIDE := 540.0

var panel: PanelContainer
var title: Label
var info: Label
var view: Control
var outdoor: Node3D
var player: Node3D
var monsters: Node
var buildings: Array = []
var _region
var _here := Vector2i.ZERO
var _sel := Vector2i(-1, -1)
var _tex: ImageTexture = null
var _closed_at := -1


func setup(o: Node3D, p: Node3D, mons: Node, village_buildings: Array) -> void:
	outdoor = o
	player = p
	monsters = mons
	buildings = village_buildings


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
	bg.set_content_margin_all(14)
	bg.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	view = Control.new()
	view.custom_minimum_size = Vector2(SIDE, SIDE)
	view.clip_contents = true
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.draw.connect(_draw_view)
	view.gui_input.connect(_on_view_input)
	box.add_child(view)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 16)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var foot := Label.new()
	foot.text = "칸을 누르면 빠른 이동 (시간이 흘러요) · 방향키로 고르고 Enter · Esc / M: 닫기"
	foot.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	foot.add_theme_font_size_override("font_size", 14)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)
	visible = false


func is_open() -> bool:
	return visible


func open(region, here: Vector2i, time_text: String) -> void:
	_region = region
	_here = here
	_sel = here
	title.text = "재너머 골짜기 지방 — %s" % time_text
	if _tex == null and outdoor:
		var img: Image = outdoor.map_image(buildings)
		if img:
			_tex = ImageTexture.create_from_image(img)
	_update_info()
	visible = true
	view.queue_redraw()


## 세계 좌표 → 지도 창 픽셀
func _to_view(w: Vector2) -> Vector2:
	var o := Outdoor.map_origin()
	return (w - o) / (-2.0 * o.x) * SIDE


func _tile_at(v: Vector2) -> Vector2i:
	var t := Vector2i(floori(v.x / SIDE * Region.W), floori(v.y / SIDE * Region.H))
	return t if Region.inside(t) else Vector2i(-1, -1)


func _draw_view() -> void:
	var cell := SIDE / Region.W
	if _tex:
		view.draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), false)
	else:
		view.draw_rect(Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color(0.25, 0.32, 0.2))
	var font := view.get_theme_default_font()
	# 칸 경계와 이름
	for k in range(1, Region.W):
		view.draw_line(Vector2(k * cell, 0), Vector2(k * cell, SIDE), Color(0, 0, 0, 0.45), 2.0)
		view.draw_line(Vector2(0, k * cell), Vector2(SIDE, k * cell), Color(0, 0, 0, 0.45), 2.0)
	for t in _region.tiles:
		var r := Rect2(Vector2(t) * cell, Vector2(cell, cell))
		if t == _sel and t != _here:
			view.draw_rect(r.grow(-2), Color(1, 1, 1, 0.9), false, 3.0)
		if t == _here:
			view.draw_rect(r.grow(-2), Color(1.0, 0.85, 0.4), false, 3.0)
		var name_txt := str(_region.tiles[t].name)
		var pos := r.position + Vector2(0, 24)
		view.draw_string_outline(font, pos, name_txt, HORIZONTAL_ALIGNMENT_CENTER, cell, 18, 6, Color(0, 0, 0, 0.85))
		view.draw_string(font, pos, name_txt, HORIZONTAL_ALIGNMENT_CENTER, cell, 18, Color(1, 0.95, 0.82))
	# 마을
	var vp := _to_view(Vector2.ZERO)
	Minimap.draw_icon(view, vp, "house", Color(1.0, 0.9, 0.6), 1.2, font)
	# 던전 입구와 이름
	for t in outdoor.tiles:
		var xf = outdoor.tiles[t].entrance
		if xf == null:
			continue
		var e: Vector3 = (xf as Transform3D).origin
		var s := _to_view(Vector2(e.x, e.z))
		Minimap.draw_icon(view, s, "door", Color(0.85, 0.75, 0.6), 1.1, font)
		var dg: Dictionary = _region.dungeon_at(t)
		if not dg.is_empty():
			var lp := s + Vector2(-80, 24)
			view.draw_string_outline(font, lp, str(dg.name), HORIZONTAL_ALIGNMENT_CENTER, 160, 14, 5, Color(0, 0, 0, 0.85))
			view.draw_string(font, lp, str(dg.name), HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(0.95, 0.88, 0.75))
	# 의뢰 대상
	for q in Minimap.quest_marks(_region, monsters, outdoor):
		Minimap.draw_icon(view, _to_view(q), "quest", Color(1.0, 0.85, 0.2), 1.1, font)
	# 나
	if player:
		var p := player.global_position
		var c := _to_view(Vector2(p.x, p.z))
		var f: Vector3 = player.get("facing") if player.get("facing") != null else Vector3(0, 0, -1)
		var d := Vector2(f.x, f.z).normalized()
		var side := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([c + d * 12.0, c - d * 8.0 + side * 8.0, c - d * 4.0, c - d * 8.0 - side * 8.0])
		view.draw_colored_polygon(pts, Color(1, 1, 1))
		pts.append(pts[0])
		view.draw_polyline(pts, Color(0, 0, 0), 2.0)
		view.draw_string_outline(font, c + Vector2(-40, -14), "나", HORIZONTAL_ALIGNMENT_CENTER, 80, 15, 5, Color(0, 0, 0, 0.9))
		view.draw_string(font, c + Vector2(-40, -14), "나", HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(1, 1, 1))
	# 북쪽
	view.draw_string_outline(font, Vector2(SIDE - 28, SIDE - 12), "북", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.9))
	view.draw_string(font, Vector2(SIDE - 28, SIDE - 12), "북", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.95, 0.85))


func _update_info() -> void:
	if not Region.inside(_sel):
		info.text = ""
		return
	var parts := PackedStringArray([str(_region.tiles[_sel].name)])
	if _region.tiles[_sel].kind == "village":
		parts.append("마을")
	var dg: Dictionary = _region.dungeon_at(_sel)
	if not dg.is_empty():
		parts.append("던전: " + str(dg.name))
	parts.append("— 여기 —" if _sel == _here else "걸어서 %s시간 — 누르면 빠른 이동" % _hours(Region.travel_hours(_here, _sel)))
	info.text = " · ".join(parts)


static func _hours(h: float) -> String:
	return str(int(h)) if is_equal_approx(h, roundf(h)) else "%.1f" % h


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var t := _tile_at((event as InputEventMouseMotion).position)
		if t != _sel and Region.inside(t):
			_sel = t
			_update_info()
			view.queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var t := _tile_at((event as InputEventMouseButton).position)
		if Region.inside(t):
			_pick(t)


func _pick(t: Vector2i) -> void:
	if t == _here:
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
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("back") or event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		close()
		return
	var move := Vector2i.ZERO
	if event.is_action_pressed("ui_left"):
		move = Vector2i.LEFT
	elif event.is_action_pressed("ui_right"):
		move = Vector2i.RIGHT
	elif event.is_action_pressed("ui_up"):
		move = Vector2i.UP
	elif event.is_action_pressed("ui_down"):
		move = Vector2i.DOWN
	if move != Vector2i.ZERO and Region.inside(_sel + move):
		_sel += move
		_update_info()
		view.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_pick(_sel)
