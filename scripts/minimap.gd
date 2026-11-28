## 미니맵 (오른쪽 위): 플레이어 둘레를 카메라 방향에 맞춰 돌려서 보여 줌 (화면 위 = 카메라가 보는 쪽).
## 땅 그림은 outdoor_terrain.gd map_image (높이 음영·등고선·숲·마을). 표시: 나(화살표), 북쪽(N), 던전 입구, 마을,
## 의뢰 대상(노란 별·느낌표), 가까운 몬스터 무리(빨간 점). 가장자리 밖 입구·의뢰는 테두리에 붙여 보여 줌.
extends CanvasLayer

const Outdoor = preload("res://scripts/outdoor_terrain.gd")
const Game = preload("res://scripts/game.gd")
const Region = preload("res://rules/region.gd")

## 미니맵 한 변 (픽셀), 1칸(미터)이 몇 픽셀인가
const SIDE := 200.0
const ZOOM := 1.5

var outdoor: Node3D
var player: Node3D
var rig: Node3D
var region
var monsters: Node
var buildings: Array = []
var frame: Panel
var view: Control
var _tex: ImageTexture = null


func setup(o: Node3D, p: Node3D, camera_rig: Node3D, reg, mons: Node, village_buildings: Array) -> void:
	outdoor = o
	player = p
	rig = camera_rig
	region = reg
	monsters = mons
	buildings = village_buildings


func _ready() -> void:
	layer = 4
	frame = Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -SIDE - 22
	frame.offset_right = -16
	frame.offset_top = 74
	frame.offset_bottom = 74 + SIDE + 6
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.07, 0.85)
	sb.border_color = Color(0.6, 0.47, 0.28)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)
	view = Control.new()
	view.position = Vector2(3, 3)
	view.size = Vector2(SIDE, SIDE)
	view.clip_contents = true
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_view)
	frame.add_child(view)


func _process(_delta: float) -> void:
	if not frame.visible or outdoor == null:
		return
	if _tex == null:
		var img: Image = outdoor.map_image(buildings)
		if img != null:
			_tex = ImageTexture.create_from_image(img)
	view.queue_redraw()


## 세계 방향(x, z) → 미니맵 화면 방향 (카메라가 보는 쪽이 위)
static func turn(v: Vector2, yaw: float) -> Vector2:
	return Vector2(v.x * cos(yaw) - v.y * sin(yaw), v.x * sin(yaw) + v.y * cos(yaw))


func _draw_view() -> void:
	if player == null:
		return
	var c := view.size / 2.0
	var yaw := rig.global_rotation.y if rig else 0.0
	var p := player.global_position
	var me := Vector2(p.x, p.z)
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0.16, 0.2, 0.13))
	if _tex:
		var o := Outdoor.map_origin()
		view.draw_set_transform(c, yaw, Vector2(ZOOM, ZOOM))
		view.draw_texture_rect(_tex, Rect2(o - me, Vector2(_tex.get_size()) * Outdoor.MAP_MPP), false)
		# 칸 경계 (옅은 선)
		for k in range(1, Region.W):
			var x := o.x + k * Outdoor.SIZE - me.x
			view.draw_line(Vector2(x, o.y - me.y), Vector2(x, -o.y - me.y), Color(0, 0, 0, 0.25), 1.0 / ZOOM)
		for k in range(1, Region.H):
			var y := o.y + k * Outdoor.SIZE - me.y
			view.draw_line(Vector2(o.x - me.x, y), Vector2(-o.x - me.x, y), Color(0, 0, 0, 0.25), 1.0 / ZOOM)
		view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := view.get_theme_default_font()
	# 가까운 몬스터 무리 (깨어 있는 것만)
	for g in monsters.groups:
		var ms: Array = g.models
		if ms.is_empty() or not is_instance_valid(ms[0]):
			continue
		var gp: Vector3 = (ms[0] as Node3D).global_position
		var s := c + turn(Vector2(gp.x, gp.z) - me, yaw) * ZOOM
		if Rect2(Vector2.ZERO, view.size).has_point(s):
			view.draw_circle(s, 3.5, Color(0.85, 0.15, 0.1))
			view.draw_arc(s, 3.5, 0, TAU, 12, Color(0, 0, 0, 0.7), 1.0)
	# 마을 (멀면 테두리에)
	_marker(c + turn(-me, yaw) * ZOOM, c, "house", Color(1.0, 0.9, 0.6), font)
	# 던전 입구
	for t in outdoor.tiles:
		var xf = outdoor.tiles[t].entrance
		if xf == null:
			continue
		var e: Vector3 = (xf as Transform3D).origin
		_marker(c + turn(Vector2(e.x, e.z) - me, yaw) * ZOOM, c, "door", Color(0.85, 0.75, 0.6), font)
	# 의뢰 대상
	for q in quest_marks(region, monsters, outdoor):
		_marker(c + turn((q as Vector2) - me, yaw) * ZOOM, c, "quest", Color(1.0, 0.85, 0.2), font)
	# 북쪽
	var n := c + turn(Vector2(0, -1), yaw) * (SIDE / 2.0 - 11.0)
	view.draw_circle(n, 8.0, Color(0, 0, 0, 0.55))
	view.draw_string(font, n + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.85))
	# 지금 지역 이름
	var here := str(region.tiles[Game.tile].name) if region else ""
	view.draw_string_outline(font, Vector2(8, SIDE - 8), here, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0))
	view.draw_string(font, Vector2(8, SIDE - 8), here, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.85))
	# 나 (보는 쪽 화살표)
	var f: Vector3 = player.get("facing") if player.get("facing") != null else Vector3(0, 0, -1)
	var d := turn(Vector2(f.x, f.z).normalized(), yaw)
	var side := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([c + d * 9.0, c - d * 6.0 + side * 6.0, c - d * 3.0, c - d * 6.0 - side * 6.0])
	view.draw_colored_polygon(pts, Color(1, 1, 1))
	pts.append(pts[0])
	view.draw_polyline(pts, Color(0, 0, 0), 1.5)


## 표시 하나. 미니맵 밖이면 테두리에 붙이고 작게
func _marker(s: Vector2, c: Vector2, kind: String, col: Color, font: Font) -> void:
	var half := SIDE / 2.0 - 8.0
	var rel := s - c
	var edge := false
	if absf(rel.x) > half or absf(rel.y) > half:
		if kind == "door" and rel.length() > SIDE * 1.5:
			return  # 입구는 아주 멀면 생략 (마을·의뢰는 늘 보여 줌)
		rel *= half / maxf(absf(rel.x), absf(rel.y))
		s = c + rel
		edge = true
	draw_icon(view, s, kind, col, 0.75 if edge else 1.0, font)


## 표시 모양 (지도 창도 같이 씀): house 집, door 동굴 문, quest 느낌표
static func draw_icon(ci: CanvasItem, s: Vector2, kind: String, col: Color, k: float, font: Font) -> void:
	var r := 7.0 * k
	ci.draw_circle(s, r + 1.5, Color(0, 0, 0, 0.75))
	ci.draw_circle(s, r, col)
	var ink := Color(0.12, 0.09, 0.06)
	match kind:
		"house":
			ci.draw_colored_polygon(PackedVector2Array([s + Vector2(-4, 4) * k, s + Vector2(-4, -1) * k, s + Vector2(0, -5) * k,
				s + Vector2(4, -1) * k, s + Vector2(4, 4) * k]), ink)
		"door":
			ci.draw_rect(Rect2(s + Vector2(-3, -1) * k, Vector2(6, 5) * k), ink)
			ci.draw_circle(s + Vector2(0, -1) * k, 3.0 * k, ink)
		_:
			ci.draw_string(font, s + Vector2(-2.5, 5) * k, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), ink)


## 진행 중인 의뢰가 가리키는 세계 자리들 (몬스터 무리 집, 던전 입구)
static func quest_marks(reg, mons: Node, o: Node3D) -> Array:
	var out := []
	var homes := {}
	for g in mons.alive():
		homes[int(g.id)] = g.home
	for q in Game.quests:
		if q.state != "active":
			continue
		if q.kind == "group":
			if homes.has(int(q.target)):
				var h: Vector3 = homes[int(q.target)]
				out.append(Vector2(h.x, h.z))
		else:
			var d := int(q.get("dungeon", -1))
			if d >= 0 and d < reg.dungeons.size():
				var t: Vector2i = reg.dungeons[d].tile
				var xf = o.tiles[t].entrance if o.tiles.has(t) else null
				if xf != null:
					out.append(Vector2((xf as Transform3D).origin.x, (xf as Transform3D).origin.z))
	return out
