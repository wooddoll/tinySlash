## 던전 생성기 미리보기. 왼쪽 패널에서 파라미터를 바꾸면 바로 다시 만들고,
## 방을 클릭해서 고른 뒤 B(또는 버튼)로 그 방에서 전투를 시작합니다.
extends Node3D

const SpriteFactory = preload("res://scripts/sprite_factory.gd")
const InputSetup = preload("res://scripts/input_setup.gd")
const Battle = preload("res://scripts/battle.gd")

const ALGO_NAMES := ["BSP (고르게 나눈 방)", "흩뿌린 방", "동굴"]
const DIFF_NAMES := ["낮음 (Low)", "보통 (Moderate)", "높음 (High)"]
const THEME_IDS := ["mixed", "goblin", "undead", "beast"]
const THEME_NAMES := ["섞어서", "고블린", "언데드", "야수"]
const KIND_NAMES := {"start": "시작 방", "exit": "출구 방", "normal": "방"}

## 전투에 다녀와도 같은 던전이 나오도록 장면 밖에 보관
static var saved: DungeonParams = null
static var selected := -1
static var cleared := {}

@onready var focus: Node3D = $Focus
@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var params: DungeonParams
var dungeon: Dungeon
var world: Node3D
var select_mesh: MultiMeshInstance3D
var hover_mesh: MultiMeshInstance3D
var hover_room := -1
var _regen_in := -1.0
var _syncing := false
var _last_size := Vector2i.ZERO

# UI
var controls := {}
var info_label: RichTextLabel
var room_label: RichTextLabel
var fight_button: Button
var seed_box: SpinBox


func _ready() -> void:
	InputSetup.register()
	if saved == null:
		saved = DungeonParams.new()
		saved.rng_seed = randi_range(1, 999999)
	params = saved
	_take_battle_result()
	_build_ui()
	_generate()


func _take_battle_result() -> void:
	if Battle.custom.get("result", "") == "win":
		cleared[int(Battle.custom.room_id)] = true
	Battle.custom = {}


# =====================================================================
# 생성과 3D 표시
# =====================================================================

func _generate() -> void:
	dungeon = DungeonGenerator.generate(params)
	if selected >= dungeon.rooms.size():
		selected = -1
	if world:
		world.queue_free()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_build_world()
	focus.position = Vector3(dungeon.width / 2.0, 0, dungeon.height / 2.0)
	var sz := Vector2i(dungeon.width, dungeon.height)
	if sz != _last_size:
		# 크기가 바뀌면 던전 전체가 보이게 줌을 맞춤
		_last_size = sz
		rig.ortho_size = clampf(maxf(sz.x, sz.y) * 0.72, rig.min_ortho_size, rig.max_ortho_size)
	_update_info()
	_update_selection()


func _build_world() -> void:
	var d := dungeon
	var tiles := _multimesh(BoxMesh.new())
	var walls := _multimesh(BoxMesh.new())
	var rubble_box := BoxMesh.new()
	rubble_box.size = Vector3(0.22, 0.12, 0.22)
	var rubble := _multimesh(rubble_box)
	var tile_xf: Array = []
	var wall_xf: Array = []
	var rub_xf: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = d.seed_used

	for y in d.height:
		for x in d.width:
			var c := Vector2i(x, y)
			if d.is_floor(c):
				var h := d.get_height(c)
				var col := Color(0.47, 0.45, 0.43) if (x + y) % 2 == 0 else Color(0.43, 0.41, 0.4)
				if d.get_tile(c) == Dungeon.Tile.DOOR:
					col = Color(0.5, 0.36, 0.22)
				elif d.room_at(c) == -1:
					col = col.darkened(0.15)
				if h > 0.0:
					col = Color(0.56, 0.53, 0.49) if h < 1.0 else Color(0.63, 0.6, 0.55)
				if d.difficult.has(c):
					col = col.darkened(0.12)
					for i in 3:
						rub_xf.append([Transform3D(Basis.IDENTITY.rotated(Vector3.UP, rng.randf() * TAU),
								Vector3(x + rng.randf_range(0.2, 0.8), h + 0.06, y + rng.randf_range(0.2, 0.8))),
								Color(0.4, 0.37, 0.34)])
				var bh := h + 0.5
				tile_xf.append([Transform3D(Basis.from_scale(Vector3(1, bh, 1)),
						Vector3(x + 0.5, h - bh / 2.0, y + 0.5)), col])
			elif _touches_floor(c):
				wall_xf.append([Transform3D(Basis.from_scale(Vector3(1, 1.2, 1)),
						Vector3(x + 0.5, 0.1, y + 0.5)), Color(0.3, 0.29, 0.33)])
	_fill(tiles, tile_xf)
	_fill(walls, wall_xf)
	_fill(rubble, rub_xf)

	# 기둥과 바위
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.36
	cyl.height = 1.8
	var pillars := _multimesh(cyl)
	var rock_box := BoxMesh.new()
	rock_box.size = Vector3(0.75, 0.6, 0.75)
	var rocks := _multimesh(rock_box)
	var p_xf: Array = []
	var r_xf: Array = []
	for c in d.obstacles:
		var top := Vector3(c.x + 0.5, d.get_height(c), c.y + 0.5)
		if d.obstacles[c] >= 2.0:
			p_xf.append([Transform3D(Basis.IDENTITY, top + Vector3(0, 0.9, 0)), Color(0.62, 0.6, 0.56)])
		else:
			r_xf.append([Transform3D(Basis.IDENTITY.rotated(Vector3.UP, rng.randf()), top + Vector3(0, 0.3, 0)),
					Color(0.5, 0.48, 0.45)])
	_fill(pillars, p_xf)
	_fill(rocks, r_xf)

	# 시작(파란 원판), 출구(계단)
	_marker_disc(d.start, Color(0.3, 0.6, 1.0))
	for i in 3:
		var step := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.8 - i * 0.22, 0.18, 0.8 - i * 0.22)
		step.mesh = sb
		step.material_override = _mat(Color(0.35, 0.85, 0.45), true)
		step.position = _top(d.exit) + Vector3(0, 0.09 + i * 0.18, 0)
		world.add_child(step)

	# 몬스터, 보물, 방 번호
	var sheet := SpriteFactory.make_character_sheet()
	for r in d.rooms:
		var done: bool = cleared.has(r.id)
		if not r.encounter.is_empty() and not done:
			for f in r.encounter.foes:
				var st := Catalog.monster(f[0])
				var s := Sprite3D.new()
				s.texture = sheet
				s.hframes = SpriteFactory.FRAMES
				s.vframes = SpriteFactory.DIRECTIONS
				s.frame = 0
				s.pixel_size = 0.0625 * st.sprite_scale
				s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				s.shaded = true
				s.modulate = st.tint
				s.position = _top(f[1]) + Vector3(0, 0.75 * st.sprite_scale, 0)
				world.add_child(s)
		for t in r.treasure:
			var chest := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(0.55, 0.38, 0.4)
			chest.mesh = cb
			chest.material_override = _mat(Color(0.95, 0.75, 0.2), true)
			chest.position = _top(t.cell) + Vector3(0, 0.19, 0)
			world.add_child(chest)
		var lbl := Label3D.new()
		lbl.text = str(r.id) + (" ✓" if done else "")
		lbl.font_size = 64
		lbl.pixel_size = 0.025
		lbl.outline_size = 12
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color(0.6, 1.0, 0.6) if done else Color(1, 1, 1, 0.85)
		var rc: Rect2i = r.rect
		lbl.position = Vector3(rc.position.x + rc.size.x / 2.0, 2.2, rc.position.y + rc.size.y / 2.0)
		world.add_child(lbl)

	select_mesh = _overlay_layer(Color(1.0, 0.85, 0.2, 0.4))
	hover_mesh = _overlay_layer(Color(1, 1, 1, 0.18))


func _touches_floor(c: Vector2i) -> bool:
	for dd in Dungeon.DIRS8:
		if dungeon.is_floor(c + dd):
			return true
	return false


func _top(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, dungeon.get_height(c), c.y + 0.5)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.4
	return m


func _multimesh(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	inst.material_override = m
	world.add_child(inst)
	return inst


func _fill(inst: MultiMeshInstance3D, items: Array) -> void:
	var mm := inst.multimesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])


func _overlay_layer(col: Color) -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.96, 0.96)
	var inst := _multimesh(plane)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	inst.material_override = m
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _marker_disc(c: Vector2i, col: Color) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = 0.08
	disc.mesh = cm
	disc.material_override = _mat(col, true)
	disc.position = _top(c) + Vector3(0, 0.04, 0)
	world.add_child(disc)


func _show_room(inst: MultiMeshInstance3D, room: int) -> void:
	var items: Array = []
	if room >= 0:
		for c in dungeon.rooms[room].cells:
			items.append([Transform3D(Basis.IDENTITY, _top(c) + Vector3(0, 0.04, 0)), Color.WHITE])
	_fill(inst, items)


# =====================================================================
# UI
# =====================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 300
	panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)

	_title(box, "던전 생성기")
	_option(box, "algorithm", "방식", ALGO_NAMES)

	var seed_row := HBoxContainer.new()
	var seed_lbl := Label.new()
	seed_lbl.text = "시드"
	seed_lbl.custom_minimum_size.x = 110
	seed_row.add_child(seed_lbl)
	seed_box = SpinBox.new()
	seed_box.min_value = 1
	seed_box.max_value = 999999
	seed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_box.value = params.rng_seed
	seed_box.value_changed.connect(func(v: float) -> void: _set_param("rng_seed", int(v)))
	seed_row.add_child(seed_box)
	var dice := Button.new()
	dice.text = "새 시드"
	dice.pressed.connect(_new_seed)
	seed_row.add_child(dice)
	box.add_child(seed_row)

	_title(box, "크기")
	_slider(box, "width", "가로", 20, 100, 1)
	_slider(box, "height", "세로", 16, 100, 1)
	_title(box, "방")
	_slider(box, "room_count", "방 개수", 2, 40, 1)
	_slider(box, "room_min", "최소 크기", 3, 15, 1)
	_slider(box, "room_max", "최대 크기", 3, 20, 1)
	_slider(box, "corridor_width", "복도 폭", 1, 3, 1)
	_slider(box, "loop_chance", "순환로", 0.0, 1.0, 0.05)
	_slider(box, "cave_fill", "동굴 벽 비율", 0.35, 0.55, 0.01)
	_title(box, "지형")
	_slider(box, "pillar_density", "기둥", 0.0, 0.2, 0.01)
	_slider(box, "rubble_density", "잔해(험지)", 0.0, 0.4, 0.01)
	_slider(box, "height_variation", "높낮이", 0.0, 1.0, 0.05)
	_title(box, "조우 (SRD XP 예산)")
	_slider(box, "party_level", "파티 레벨", 1, 5, 1)
	_slider(box, "party_size", "파티 인원", 1, 6, 1)
	_option(box, "difficulty", "난이도", DIFF_NAMES)
	_check(box, "difficulty_ramp", "깊을수록 한 단계 어렵게")
	_theme_option(box)
	_slider(box, "encounter_ratio", "몬스터 방 비율", 0.0, 1.0, 0.05)
	_slider(box, "treasure_ratio", "보물 방 비율", 0.0, 1.0, 0.05)
	_check(box, "boss_room", "출구 방에 보스")

	var copy := Button.new()
	copy.text = "텍스트 지도 복사"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(dungeon.to_ascii())
		_flash(copy, "복사했어요"))
	box.add_child(copy)

	# 오른쪽: 던전 정보와 고른 방
	var right := PanelContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -340
	right.offset_right = -8
	right.offset_top = 8
	right.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(right)
	var rbox := VBoxContainer.new()
	right.add_child(rbox)
	info_label = _rich(rbox)
	room_label = _rich(rbox)
	fight_button = Button.new()
	fight_button.text = "이 방에서 전투 (B)"
	fight_button.pressed.connect(_fight)
	rbox.add_child(fight_button)

	var help := Label.new()
	help.text = "좌클릭: 방 고르기 · WASD: 카메라 이동 · Q/E: 회전 · 휠: 줌 · B: 전투 · Esc: 탐험으로"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_right = -12
	help.offset_bottom = -8
	help.add_theme_constant_override("outline_size", 6)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(help)


func _panel_style() -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.set_content_margin_all(10)
	bg.set_corner_radius_all(4)
	return bg


func _rich(parent: Control) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size.x = 310
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	parent.add_child(r)
	return r


func _title(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	parent.add_child(l)


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 110
	l.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	parent.add_child(row)
	return row


func _slider(parent: Control, prop: String, text: String, lo: float, hi: float, step: float) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = params.get(prop)
	var val := Label.new()
	val.custom_minimum_size.x = 40
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 14)
	var fmt := "%d" if step >= 1.0 else "%.2f"
	val.text = fmt % s.value
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % v
		_set_param(prop, int(v) if step >= 1.0 else v))
	row.add_child(s)
	row.add_child(val)
	controls[prop] = s


func _option(parent: Control, prop: String, text: String, names: Array) -> void:
	var row := _row(parent, text)
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.selected = params.get(prop)
	o.item_selected.connect(func(i: int) -> void: _set_param(prop, i))
	row.add_child(o)


func _theme_option(parent: Control) -> void:
	var row := _row(parent, "몬스터 종류")
	var o := OptionButton.new()
	for n in THEME_NAMES:
		o.add_item(n)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.selected = maxi(THEME_IDS.find(params.theme), 0)
	o.item_selected.connect(func(i: int) -> void: _set_param("theme", THEME_IDS[i]))
	row.add_child(o)


func _check(parent: Control, prop: String, text: String) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = params.get(prop)
	c.toggled.connect(func(on: bool) -> void: _set_param(prop, on))
	parent.add_child(c)


func _flash(b: Button, text: String) -> void:
	var old := b.text
	b.text = text
	get_tree().create_timer(1.2).timeout.connect(func() -> void: b.text = old)


func _set_param(prop: String, value: Variant) -> void:
	if _syncing:
		return
	params.set(prop, value)
	cleared.clear()
	selected = -1
	_regen_in = 0.2  # 슬라이더를 끄는 동안 너무 자주 만들지 않게


func _new_seed() -> void:
	seed_box.value = randi_range(1, 999999)


func _update_info() -> void:
	var d := dungeon
	var tot := d.encounter_totals()
	var gold := 0
	for r in d.rooms:
		for t in r.treasure:
			gold += int(t.gold)
	var floor_pct := 100.0 * d.floor_count() / (d.width * d.height)
	info_label.text = ("[b]%s[/b]  %d x %d · 시드 %d\n방 %d · 통로 연결 %d · 바닥 %.0f%%\n"
			+ "몬스터 %d (XP 합계 %d) · 보물 %d골드\n[color=#6af]●[/color] 시작  [color=#5d7]▲[/color] 출구  [color=#fc4]■[/color] 보물") % [
		ALGO_NAMES[params.algorithm], d.width, d.height, d.seed_used,
		d.rooms.size(), d.edges.size(), floor_pct, tot.foes, tot.xp, gold]


func _update_selection() -> void:
	_show_room(select_mesh, selected)
	fight_button.disabled = selected < 0
	if selected < 0:
		room_label.text = "[color=gray]방을 클릭하면 자세한 정보가 나와요[/color]"
		return
	var r: Dictionary = dungeon.rooms[selected]
	var rc: Rect2i = r.rect
	var lines := PackedStringArray()
	lines.append("[b]%s %d[/b]  (%d x %d, 깊이 %.0f%%)" % [KIND_NAMES[r.kind], r.id, rc.size.x, rc.size.y, r.depth * 100.0])
	if cleared.has(r.id):
		lines.append("[color=#6d6]정리함 ✓[/color]")
	elif r.encounter.is_empty():
		lines.append("몬스터 없음")
	else:
		var e: Dictionary = r.encounter
		lines.append("%s" % e.label)
		lines.append("XP %d / 예산 %d" % [e.xp, e.budget])
	for t in r.treasure:
		lines.append("보물 상자: %d골드" % t.gold)
	room_label.text = "\n".join(lines)


# =====================================================================
# 입력
# =====================================================================

func _process(delta: float) -> void:
	# 왼쪽 패널(300px)에 가리지 않게 화면 중심을 오른쪽으로 옮김
	camera.h_offset = -150.0 * camera.size / get_viewport().get_visible_rect().size.y
	if _regen_in > 0.0:
		_regen_in -= delta
		if _regen_in <= 0.0:
			_generate()
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v != Vector2.ZERO:
		focus.position += Vector3(v.x, 0, v.y).rotated(Vector3.UP, rig.rotation.y) * 14.0 * delta
	if Input.is_action_just_pressed("start_battle"):
		_fight()
	elif Input.is_action_just_pressed("back"):
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var room := _room_under(event.position)
		if room != hover_room:
			hover_room = room
			_show_room(hover_mesh, room)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = _room_under(event.position)
		_update_selection()


## 마우스 아래 칸 -> 방 번호. 바닥 높이 0과 0.5/1.0 평면을 차례로 시험
func _room_under(screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return -1
	for plane_y in [1.0, 0.5, 0.0]:
		var t: float = (plane_y - origin.y) / dir.y
		var hit := origin + dir * t
		var c := Vector2i(floori(hit.x), floori(hit.z))
		if dungeon.is_floor(c) and is_equal_approx(dungeon.get_height(c), plane_y):
			var room := dungeon.room_at(c)
			if room >= 0:
				return room
			if plane_y == 0.0:
				return -1
	return -1


func _fight() -> void:
	if selected < 0 or cleared.has(selected):
		return
	if dungeon.rooms[selected].encounter.is_empty():
		_flash(fight_button, "이 방엔 몬스터가 없어요")
		return
	Battle.custom = dungeon.battle_setup(selected)
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
