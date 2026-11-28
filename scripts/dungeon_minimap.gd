## 던전 미니맵 (탐험 중 오른쪽 패널 위): 본 칸만 그림 (전쟁 안개).
## 지금 보이는 칸은 밝게, 전에 본 칸은 어둡게, 새로 본 칸은 0.5초에 걸쳐 서서히 나타남.
## 본 칸 옆의 아직 못 본 바닥은 아주 옅게 (길이 이어진다는 것만). 벽은 본 바닥 둘레만.
## 화면 위 = 카메라가 보는 쪽 (바깥 미니맵과 같음). 층이 작으면 층 전체, 크면 나를 가운데로.
## 표시: 나(화살표), 시작·출구 계단, 안 연 상자, 모닥불, 쉼터, 상인, 의뢰 물건, 지금 보이는 몬스터.
extends Control

const Minimap = preload("res://scripts/minimap.gd")
const SIDE := 290.0
## 칸 하나가 이 픽셀보다 작아지면 층 전체 대신 나를 가운데로
const MIN_CELL := 6.5
const FADE := 0.5

var view: Node  # dungeon_view.gd (인스턴스)
var dv: Script  # dungeon_view.gd 스크립트 (seen·opened·used_fires·floor_no는 static)
var _tex: ImageTexture = null
var _img: Image = null
var _dungeon = null
var _seen_count := -1
var _cell := Vector2i(-99, -99)
var _visible := {}
var _born := {}  # 칸 → 처음 본 시각 (서서히 나타나기)
var _fading := false


func _init() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or view == null or view.dungeon == null:
		return
	if dv == null:
		dv = view.get_script()
	var d = view.dungeon
	if d != _dungeon:
		_dungeon = d
		_img = Image.create_empty(d.width, d.height, false, Image.FORMAT_RGBA8)
		_tex = null
		_seen_count = -1
		_cell = Vector2i(-99, -99)
		_born.clear()
		for c in dv.seen:
			_born[c] = -100.0  # 이미 본 칸 (층 기억)은 바로
	var cell: Vector2i = _me_cell()
	var now := Time.get_ticks_msec() / 1000.0
	var dirty := _fading
	if cell != _cell:
		_cell = cell
		_visible.clear()
		if d.is_floor(cell):
			for c in dv.visible_from(d, cell):
				_visible[c] = true
		dirty = true
	if dv.seen.size() != _seen_count:
		_seen_count = dv.seen.size()
		for c in dv.seen:
			if not _born.has(c):
				_born[c] = now
		dirty = true
	if dirty:
		_paint(d, now)
	queue_redraw()


func _me_cell() -> Vector2i:
	if view.action and view.action.player:
		var p: Vector2 = view.action.player.pos
		return Vector2i(floori(p.x), floori(p.y))
	return view.explorer.cell if view.explorer else Vector2i(-1, -1)


func _me_pos() -> Vector2:
	if view.action and view.action.player:
		return view.action.player.pos
	var c: Vector2i = _me_cell()
	return Vector2(c) + Vector2(0.5, 0.5)


## 칸 색을 그림에 칠함 (본 칸·벽·옅은 길)
func _paint(d, now: float) -> void:
	_img.fill(Color(0, 0, 0, 0))
	_fading = false
	var seen: Dictionary = dv.seen
	var lit := Color(0.82, 0.75, 0.6)
	var dim := Color(0.42, 0.39, 0.35)
	var wall := Color(0.24, 0.21, 0.18)
	for c in seen:
		var a := clampf((now - float(_born.get(c, -100.0))) / FADE, 0.0, 1.0)
		if a < 1.0:
			_fading = true
		var col: Color = lit if _visible.has(c) else dim
		col.a = a
		_img.set_pixelv(c, col)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= d.width or n.y >= d.height or seen.has(n):
					continue
				if not d.is_floor(n):
					var w := wall
					w.a = a
					if _img.get_pixelv(n).a < w.a:
						_img.set_pixelv(n, w)
				elif (dx == 0 or dy == 0) and _img.get_pixelv(n).a < 0.22 * a:
					# 못 본 바닥이 이어짐: 아주 옅게
					_img.set_pixelv(n, Color(dim.r, dim.g, dim.b, 0.22 * a))
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05, 0.92))
	if _tex == null or _dungeon == null or dv == null:
		return
	var d = _dungeon
	var rig: Node3D = view.rig
	var yaw: float = rig.global_rotation.y if rig else 0.0
	var target_yaw: float = rig.get("_target_yaw") if rig and rig.get("_target_yaw") != null else yaw
	# 층 전체가 들어가는 크기 (돌아간 모양 기준, 돌아가는 도중엔 목표 각도로 재서 흔들리지 않게)
	var bw := absf(d.width * cos(target_yaw)) + absf(d.height * sin(target_yaw))
	var bh := absf(d.width * sin(target_yaw)) + absf(d.height * cos(target_yaw))
	var s := minf((size.x - 12.0) / bw, (size.y - 12.0) / bh)
	var focus := Vector2(d.width, d.height) / 2.0
	if s < MIN_CELL:
		s = MIN_CELL
		focus = _me_pos()
	var c := size / 2.0
	draw_set_transform(c, yaw, Vector2(s, s))
	draw_texture_rect(_tex, Rect2(-focus, Vector2(d.width, d.height)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := get_theme_default_font()
	var at := func(p: Vector2) -> Vector2: return c + Minimap.turn(p - focus, yaw) * s
	var seen: Dictionary = dv.seen
	var k := clampf(s / 9.0, 0.55, 1.0)
	# 계단·물건
	var marks := []
	if seen.has(d.start):
		marks.append([d.start, Color(0.35, 0.65, 1.0), "door"])
	if seen.has(d.exit):
		marks.append([d.exit, Color(1.0, 0.82, 0.35), "stairs"])
	for ch in view.chests:
		if seen.has(ch) and not dv.opened.has(ch):
			marks.append([ch, Color(0.95, 0.8, 0.3), "chest"])
	for f in d.campfires:
		if seen.has(f):
			marks.append([f, Color(0.5, 0.5, 0.5) if dv.used_fires.has(f) else Color(1.0, 0.55, 0.2), "fire"])
	if view.shelter != Vector2i(-1, -1) and seen.has(view.shelter):
		marks.append([view.shelter, Color(0.45, 0.85, 0.45), "tent"])
	if view.merchant != Vector2i(-1, -1) and seen.has(view.merchant):
		marks.append([view.merchant, Color(0.75, 0.55, 0.95), "tent"])
	if view.quest_item_cell != Vector2i(-1, -1) and seen.has(view.quest_item_cell):
		marks.append([view.quest_item_cell, Color(1.0, 0.85, 0.2), "quest"])
	for m in marks:
		_mark(at.call(Vector2(m[0]) + Vector2(0.5, 0.5)), m[1], m[2], k, font)
	# 지금 보이는 몬스터
	if view.action and view.action.ac:
		for a in view.action.ac.actors:
			if a.c.team == 0 or not a.alive():
				continue
			if _visible.has(Vector2i(floori(a.pos.x), floori(a.pos.y))):
				var sp: Vector2 = at.call(a.pos)
				draw_circle(sp, 3.5 * k + 1.0, Color(0, 0, 0, 0.8))
				draw_circle(sp, 3.5 * k, Color(0.9, 0.18, 0.12))
	# 나
	var me: Vector2 = at.call(_me_pos())
	var f := Vector2(0, 1)
	if view.action and view.action.player:
		f = view.action.player.facing
	var dir := Minimap.turn(f.normalized(), yaw)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([me + dir * 8.0, me - dir * 5.0 + side * 5.5, me - dir * 2.5, me - dir * 5.0 - side * 5.5])
	draw_colored_polygon(pts, Color(1, 1, 1))
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0), 1.5)
	# 북쪽 · 층
	var n := c + Minimap.turn(Vector2(0, -1), yaw) * (minf(size.x, size.y) / 2.0 - 11.0)
	draw_circle(n, 8.0, Color(0, 0, 0, 0.6))
	draw_string(font, n + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.85))
	draw_string_outline(font, Vector2(8, size.y - 8), "%d층" % dv.floor_no, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0))
	draw_string(font, Vector2(8, size.y - 8), "%d층" % dv.floor_no, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.85, 0.75))


func _mark(p: Vector2, col: Color, kind: String, k: float, font: Font) -> void:
	var r := 5.5 * k
	var ink := Color(0.1, 0.08, 0.05)
	draw_circle(p, r + 1.3, Color(0, 0, 0, 0.8))
	draw_circle(p, r, col)
	match kind:
		"stairs":
			for i in 3:
				draw_line(p + Vector2(-3 + i * 2, 2 - i * 2) * k, p + Vector2(-1 + i * 2, 2 - i * 2) * k, ink, 1.4)
		"chest":
			draw_rect(Rect2(p + Vector2(-3, -2) * k, Vector2(6, 4) * k), ink)
		"fire":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3.5) * k, p + Vector2(2.5, 2.5) * k, p + Vector2(-2.5, 2.5) * k]), ink)
		"tent":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3.5) * k, p + Vector2(3.5, 2.5) * k, p + Vector2(-3.5, 2.5) * k]), ink)
		"quest":
			draw_string(font, p + Vector2(-2.2, 4.5) * k, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k), ink)
		_:
			draw_circle(p, 2.0 * k, ink)
