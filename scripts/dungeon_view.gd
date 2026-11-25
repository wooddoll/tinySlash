## 던전 생성기 미리보기. 왼쪽 패널에서 파라미터를 바꾸면 바로 다시 만들고,
## 방을 클릭해서 고른 뒤 B(또는 버튼)로 그 방에서 전투를 시작합니다.
extends Node3D

const InputSetup = preload("res://scripts/input_setup.gd")
const Battle = preload("res://scripts/battle.gd")
const Kenney = preload("res://scripts/kenney.gd")
const CharacterModel = preload("res://scripts/character_model.gd")

const ALGO_NAMES := ["BSP (고르게 나눈 방)", "흩뿌린 방", "동굴"]
const DIFF_NAMES := ["낮음 (Low)", "보통 (Moderate)", "높음 (High)"]
const THEME_IDS := ["mixed", "goblin", "undead", "beast"]
const THEME_NAMES := ["섞어서", "고블린", "언데드", "야수"]
const KIND_NAMES := {"start": "시작 방", "exit": "출구 방", "normal": "방"}

const Explorer = preload("res://scripts/dungeon_explorer.gd")
const Sfx = preload("res://scripts/sfx.gd")

## 전투에 다녀와도 같은 던전이 나오도록 장면 밖에 보관
static var saved: DungeonParams = null
static var selected := -1
static var cleared := {}
## 탐험 모드 상태 (전투에 다녀와도 이어짐)
static var exploring := false
## 탐험을 다시 시작할 칸 (-1이면 시작 지점)
static var explore_cell := Vector2i(-1, -1)
## 방에 들어서기 직전 칸. 전투에서 도망치면(Esc) 여기로 돌아옴
static var retreat_cell := Vector2i(-1, -1)
static var opened := {}
static var gold := 0
static var floor_no := 1
## 전투 사이에 이어지는 파이터 상태
static var hero: HeroState = null
## 쉼터(세이브 지점)는 1, 4, 7...층 시작 방에 있음. 지면 마지막 저장으로 돌아감 (rules 3.6)
const SAVE_EVERY := 3
## 마지막 저장: {params, floor, hero, gold, rested}
static var save := {}
## 이 층 쉼터에서 긴 휴식을 했는지 (쉼터마다 한 번)
static var rested_here := false
static var _pending_toast := ""
## 짧은 휴식을 한 모닥불 (꺼짐)
static var used_fires := {}
## 전장의 안개: 탐험 중 본 칸
static var seen := {}

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
var left_panel: Control
var help_label: Label
var toast: Label

# 탐험
var explorer: Explorer
var chests := {}
var _leaving := false
var fires := {}  # 칸 -> 불꽃 노드들
## 칸 -> 그 칸에 속한 것들 ([MultiMesh, 번호, 원래 변환] 또는 [노드])
var _fog_index := {}
var rest_panel: PanelContainer
var rest_label: RichTextLabel
var rest_roll: Button
var rest_fire := Vector2i(-1, -1)
var rest_log := PackedStringArray()
var rest_dice := Dice.new()
var shelter := Vector2i(-1, -1)


func _ready() -> void:
	InputSetup.register()
	if saved == null:
		saved = DungeonParams.new()
		saved.rng_seed = randi_range(1, 999999)
	_take_battle_result()
	params = saved  # 지면 저장한 층의 파라미터로 바뀜
	_build_ui()
	Sfx.wire_buttons(self)
	_generate()


func _take_battle_result() -> void:
	if Battle.custom.has("room_id"):
		match Battle.custom.get("result", ""):
			"win":
				cleared[int(Battle.custom.room_id)] = true  # 들어선 칸에서 계속
			"lose":
				_load_save()
				_pending_toast = "쓰러졌어요… %d층 쉼터에서 다시 시작" % floor_no
			_:
				explore_cell = retreat_cell  # 도망침
		if Battle.custom.has("level_up"):
			_pending_toast = "레벨 업! %d레벨" % Battle.custom.level_up
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
	explorer = null
	chests.clear()
	fires.clear()
	_fog_index.clear()
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
	_apply_mode()


func _build_world() -> void:
	var d := dungeon
	var rng := RandomNumberGenerator.new()
	rng.seed = d.seed_used
	# 높은 칸의 옆면만 상자로, 윗면과 나머지는 Kenney Mini Dungeon 모델
	var bases := _multimesh(BoxMesh.new())
	var base_xf: Array = []
	var floors: Array = []
	var cave := params.algorithm == DungeonParams.Algorithm.CAVE
	var quarter := Basis.from_scale(Vector3.ONE * 0.25)
	var model_xf := {}  # 모델 이름 -> [[Transform3D, 칸]]
	var add := func(model: String, xf: Transform3D, cell: Vector2i) -> void:
		if not model_xf.has(model):
			model_xf[model] = []
		model_xf[model].append([xf, cell])
	var base_cells: Array = []
	var spin := func() -> Basis:
		return Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0)

	for y in d.height:
		for x in d.width:
			var c := Vector2i(x, y)
			var pos := Vector3(x + 0.5, 0.0, y + 0.5)
			if d.is_floor(c):
				var h := d.get_height(c)
				pos.y = h
				if h > 0.0:
					base_xf.append([Transform3D(Basis.from_scale(Vector3(1, h, 1)), pos - Vector3(0, h / 2.0, 0)),
							Color(0.45, 0.33, 0.27) if cave else Color(0.42, 0.4, 0.45)])
					base_cells.append(c)
				floors.append(c)
				if cave:
					# Cave Kit 바닥 (4x4 조각을 1/4로)
					add.call("modular-cave-kit/template-floor", Transform3D(spin.call() * quarter, pos), c)
				else:
					add.call("floor-detail" if rng.randf() < 0.15 else "floor", Transform3D(spin.call(), pos), c)
				if d.difficult.has(c):
					add.call("stones", Transform3D(spin.call(), pos), c)
	_fill(bases, base_xf)
	for i in base_cells.size():
		_fog_add(base_cells[i], [bases.multimesh, i, base_xf[i][0]])
	for part in Kenney.build_edge_walls(world, floors, d.is_floor, d.get_height, cave):
		for i in (part[1] as Array).size():
			_fog_add(part[1][i], [part[0], i, part[2][i]])

	for c in d.obstacles:
		if d.obstacles[c] >= 2.0:
			add.call("column", Transform3D(Basis.IDENTITY, _top(c)), c)
		else:
			add.call("rocks", Transform3D(spin.call(), _top(c)), c)
	add.call("stairs", Transform3D(Basis.IDENTITY, _top(d.exit)), d.exit)

	for model in model_xf:
		var parts: PackedStringArray = model.split("/")
		var m := Kenney.mesh(parts[-1], parts[0] if parts.size() > 1 else Kenney.DUNGEON)
		var inst := _multimesh(m, false)
		var mm := inst.multimesh
		var list: Array = model_xf[model]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			_fog_add(list[i][1], [mm, i, list[i][0]])

	# 시작 지점 (파란 원판)
	_fog_add(d.start, [_marker_disc(d.start, Color(0.3, 0.6, 1.0))])

	# 몬스터, 보물, 방 번호
	for r in d.rooms:
		var done: bool = cleared.has(r.id)
		if not r.encounter.is_empty() and not done:
			for f in r.encounter.foes:
				var st := Catalog.monster(f[0])
				var m := CharacterModel.new()
				world.add_child(m)
				m.setup(st.model, st.sprite_scale, st.weapon_model)
				m.position = _top(f[1])
				m.face(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), true)
				_fog_add(f[1], [m])
		for t in r.treasure:
			var chest := Kenney.instance("chest")
			chest.position = _top(t.cell)
			chest.rotation.y = rng.randi_range(0, 3) * PI / 2.0
			world.add_child(chest)
			chests[t.cell] = chest
			_fog_add(t.cell, [chest])
			if opened.has(t.cell):
				_open_chest_anim(chest, true)
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
		_fog_add(r.center, [lbl])

	for c in d.campfires:
		_add_campfire(c)
	shelter = Vector2i(-1, -1)
	if is_save_floor(params.floor_depth):
		shelter = shelter_cell(d)
		if shelter != Vector2i(-1, -1):
			_add_shelter(shelter)

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


func _multimesh(mesh: Mesh, colored := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	world.add_child(inst)
	if not colored:
		return inst  # 모델 자체 재질(colormap 텍스처)을 그대로 씀
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	inst.material_override = m
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


func _marker_disc(c: Vector2i, col: Color) -> Node3D:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = 0.08
	disc.mesh = cm
	disc.material_override = _mat(col, true)
	disc.position = _top(c) + Vector3(0, 0.04, 0)
	world.add_child(disc)
	return disc


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
	left_panel = panel
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)

	_title(box, "던전 생성기")
	var go := Button.new()
	go.text = "이 던전 탐험하기 (Tab)"
	go.pressed.connect(func() -> void: _set_exploring(true))
	box.add_child(go)
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
	_slider(box, "floor_depth", "층 (깊이)", 1, 20, 1)
	_slider(box, "campfire_count", "모닥불", 0, 4, 1)

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

	_build_rest_panel(layer)
	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = 140
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 28)
	toast.add_theme_constant_override("outline_size", 8)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.modulate.a = 0.0
	layer.add_child(toast)

	var help := Label.new()
	help_label = help
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
	opened.clear()
	used_fires.clear()
	seen.clear()
	explore_cell = Vector2i(-1, -1)
	retreat_cell = Vector2i(-1, -1)
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
			+ "몬스터 %d (XP 합계 %d) · 보물 %d골드\n[color=#6af]●[/color] 시작  계단 출구 · 상자 보물") % [
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
	if _regen_in > 0.0:
		_regen_in -= delta
		if _regen_in <= 0.0:
			_generate()
	if exploring:
		camera.h_offset = 0.0
		if _leaving:
			return
		if rest_panel.visible:
			if Input.is_action_just_pressed("end_turn"):
				_rest_roll()
			elif Input.is_action_just_pressed("explore") or Input.is_action_just_pressed("back"):
				_finish_rest()
			return
		if Input.is_action_just_pressed("explore") or Input.is_action_just_pressed("back"):
			_set_exploring(false)
		elif Input.is_action_just_pressed("end_turn") and explorer:
			var fire := _fire_near(explorer.cell)
			if fire != Vector2i(-1, -1):
				_open_rest(fire)
			elif _near(shelter, explorer.cell):
				_long_rest()
			elif explorer.cell == dungeon.exit:
				_next_floor()
		return
	# 왼쪽 패널(300px)에 가리지 않게 화면 중심을 오른쪽으로 옮김
	camera.h_offset = -150.0 * camera.size / get_viewport().get_visible_rect().size.y
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v != Vector2.ZERO:
		focus.position += Vector3(v.x, 0, v.y).rotated(Vector3.UP, rig.rotation.y) * 14.0 * delta
	if Input.is_action_just_pressed("start_battle"):
		_fight()
	elif Input.is_action_just_pressed("explore"):
		_set_exploring(true)
	elif Input.is_action_just_pressed("back"):
		get_tree().change_scene_to_file("res://scenes/main.tscn")


# =====================================================================
# 탐험 모드: 던전 안을 걸어 다니다가 몬스터 방에 들어서면 전투
# =====================================================================

func _set_exploring(on: bool) -> void:
	if on == exploring:
		return
	exploring = on
	Sfx.play(self, "switch")
	if on:
		# 생성기에서 새로 시작하면 금화, 층 수, 파이터 상태를 처음부터
		gold = 0
		floor_no = params.floor_depth
		hero = HeroState.fresh()
		rested_here = false
		_write_save()  # 탐험을 시작한 곳이 첫 저장
	else:
		if explorer:
			explore_cell = explorer.cell
			focus.position = explorer.position
		rig.ortho_size = clampf(maxf(dungeon.width, dungeon.height) * 0.72, rig.min_ortho_size, rig.max_ortho_size)
	get_viewport().gui_release_focus()
	_apply_mode()


## 지금 모드에 맞게 플레이어, 카메라, UI를 맞춤
func _apply_mode() -> void:
	left_panel.visible = not exploring
	fight_button.visible = not exploring
	_show_room(hover_mesh, -1)
	if exploring:
		_show_room(select_mesh, -1)
		if hero == null:
			hero = HeroState.fresh()
		if save.is_empty():
			_write_save()
		if _pending_toast != "":
			_toast(_pending_toast)
			_pending_toast = ""
		if explorer == null:
			var at := explore_cell if dungeon.is_walkable(explore_cell) else dungeon.start
			explorer = Explorer.new()
			world.add_child(explorer)
			explorer.setup(dungeon, at)
			explorer.camera_rig = rig
			explorer.entered_cell.connect(_on_entered_cell)
		_reveal(explorer.cell)
		_fog_apply_all()
		rig.target = explorer
		rig.ortho_size = 13.0
		help_label.text = "WASD: 이동 · Q/E: 카메라 회전 · 휠: 줌 · Tab/Esc: 생성기로"
		_update_explore_info()
	else:
		if explorer:
			explorer.queue_free()
			explorer = null
		rig.target = focus
		_fog_apply_all()
		help_label.text = "좌클릭: 방 고르기 · WASD: 카메라 이동 · Q/E: 회전 · 휠: 줌 · B: 전투 · Tab: 탐험 · Esc: 바깥으로"
		_update_info()
		_update_selection()


func _on_entered_cell(from: Vector2i, to: Vector2i) -> void:
	_reveal(to)
	# 상자는 옆 칸(대각선 포함)에 서면 열림
	for c in chests:
		if not opened.has(c) and maxi(absi(c.x - to.x), absi(c.y - to.y)) <= 1:
			_open_chest(c)
	var r := dungeon.room_at(to)
	if r >= 0 and not cleared.has(r) and not dungeon.rooms[r].encounter.is_empty():
		_start_battle(r, from, to)
		return
	if to == dungeon.exit:
		_toast("출구 계단 — Enter: 다음 층으로")
	elif _fire_near(to) != Vector2i(-1, -1) and _fire_near(from) == Vector2i(-1, -1):
		_toast("모닥불 — Enter: 짧은 휴식")
	elif _near(shelter, to) and not _near(shelter, from):
		_toast("이미 쉬었어요" if rested_here else "쉼터 — Enter: 긴 휴식")
	_update_explore_info()


func _start_battle(room: int, from: Vector2i, to: Vector2i) -> void:
	_leaving = true
	explorer.active = false
	explore_cell = to
	retreat_cell = from if dungeon.is_walkable(from) else dungeon.start
	_toast("몬스터 발견! — " + str(dungeon.rooms[room].encounter.label))
	Sfx.play(self, "alert")
	Battle.custom = dungeon.battle_setup(room, to)
	Battle.custom["hero"] = hero
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _open_chest(c: Vector2i) -> void:
	opened[c] = true
	var amount := 0
	for r in dungeon.rooms:
		for t in r.treasure:
			if t.cell == c:
				amount = int(t.gold)
	gold += amount
	_open_chest_anim(chests[c], false)
	Sfx.play(self, "chest")
	get_tree().create_timer(0.35).timeout.connect(func() -> void: Sfx.play(self, "coins"))
	_toast("보물 상자: %d골드" % amount)


func _open_chest_anim(chest: Node3D, instant: bool) -> void:
	var ap := chest.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null or not ap.has_animation("open"):
		return
	ap.play("open")
	if instant:
		ap.seek(ap.current_animation_length, true)


func _next_floor() -> void:
	var keep_gold := gold
	floor_no += 1
	Sfx.play(self, "stairs")
	rested_here = false
	# 몬스터 예산을 파이터 레벨과 층 깊이에 맞춤
	params.party_level = hero.level()
	params.floor_depth = floor_no
	_syncing = true
	(controls["party_level"] as HSlider).value = hero.level()
	(controls["floor_depth"] as HSlider).value = floor_no
	_syncing = false
	seed_box.value = randi_range(1, 999999)  # _set_param이 탐험 상태를 비우고 다시 만듦
	gold = keep_gold
	if is_save_floor(floor_no):
		_write_save()  # 쉼터가 있는 층에 도착하면 저장
		_toast("%d층 — 쉼터가 있어요 (저장했어요)" % floor_no)
	else:
		_toast("%d층" % floor_no)


# --- 전장의 안개: 탐험 중에는 본 칸만 그림 ---

func _fog_add(c: Vector2i, entry: Array) -> void:
	if not _fog_index.has(c):
		_fog_index[c] = []
	_fog_index[c].append(entry)


func _fog_show(entry: Array, on: bool) -> void:
	if entry.size() == 1:
		(entry[0] as Node3D).visible = on
		return
	var xf: Transform3D = entry[2]
	(entry[0] as MultiMesh).set_instance_transform(entry[1], xf if on else Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))


func _fog_apply_all() -> void:
	for c in _fog_index:
		var on := not exploring or seen.has(c)
		for e in _fog_index[c]:
			_fog_show(e, on)


## 들어선 칸에서 보이는 칸: 방이면 방 전체, 통로면 바닥을 따라 3걸음까지
static func visible_from(d: Dungeon, c: Vector2i) -> Array:
	var room := d.room_at(c)
	if room >= 0:
		return (d.rooms[room].cells as Array).duplicate()
	var out: Array = [c]
	var dist := {c: 0}
	var q: Array = [c]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if dist[cur] >= 3:
			continue
		for dd in Dungeon.DIRS4:
			var n: Vector2i = cur + dd
			if dist.has(n) or not d.is_floor(n):
				continue
			dist[n] = dist[cur] + 1
			out.append(n)
			q.append(n)
	return out


func _reveal(c: Vector2i) -> void:
	for n in visible_from(dungeon, c):
		if seen.has(n):
			continue
		seen[n] = true
		if exploring:
			for e in _fog_index.get(n, []):
				_fog_show(e, true)


# --- 쉼터: 긴 휴식과 저장 (rules 3.6, 5.3) ---

static func is_save_floor(n: int) -> bool:
	return (n - 1) % SAVE_EVERY == 0


## 시작 방에서 시작 칸에 가장 가까운 빈 칸 (시작 칸, 모닥불, 상자, 몬스터 칸은 피함)
static func shelter_cell(d: Dungeon) -> Vector2i:
	var taken := {d.start: true, d.exit: true}
	for c in d.campfires:
		taken[c] = true
	for r in d.rooms:
		for t in r.treasure:
			taken[t.cell] = true
		if not r.encounter.is_empty():
			for f in r.encounter.foes:
				taken[f[1]] = true
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for c in d.rooms[d.start_room].cells:
		if d.is_walkable(c) and not taken.has(c):
			var dd: int = (c - d.start).length_squared()
			if dd < best_d:
				best_d = dd
				best = c
	return best


func _near(target: Vector2i, c: Vector2i) -> bool:
	return target != Vector2i(-1, -1) and maxi(absi(target.x - c.x), absi(target.y - c.y)) <= 1


func _add_shelter(c: Vector2i) -> void:
	var root := Node3D.new()
	root.position = _top(c)
	world.add_child(root)
	var tent := Kenney.instance("tent-canvas", "survival-kit")
	tent.scale = Vector3.ONE * 1.7
	root.add_child(tent)
	_fog_add(c, [root])


func _write_save() -> void:
	save = {"params": params.duplicate_params(), "floor": floor_no, "hero": hero.duplicate_state(),
			"gold": gold, "rested": rested_here}


## 마지막 저장으로 돌아감: 그 층을 처음 상태로 다시 만들고 파이터 상태, 금화도 그때로
static func _load_save() -> void:
	if save.is_empty():
		explore_cell = Vector2i(-1, -1)
		return
	saved = (save.params as DungeonParams).duplicate_params()
	floor_no = save.floor
	hero = (save.hero as HeroState).duplicate_state()
	gold = save.gold
	rested_here = save.rested
	cleared.clear()
	opened.clear()
	used_fires.clear()
	seen.clear()
	explore_cell = Vector2i(-1, -1)
	retreat_cell = Vector2i(-1, -1)


func _long_rest() -> void:
	if rested_here:
		_toast("이 쉼터에서는 이미 쉬었어요")
		return
	hero.long_rest()
	rested_here = true
	_write_save()
	Sfx.play(self, "confirm")
	_toast("긴 휴식: HP, 히트 다이스, 기능 회복 · 저장했어요")
	_update_explore_info()


# --- 모닥불과 짧은 휴식 (rules 5.3) ---

func _add_campfire(c: Vector2i) -> void:
	var root := Node3D.new()
	root.position = _top(c)
	world.add_child(root)
	var pit := Kenney.instance("campfire-pit", "survival-kit")
	pit.scale = Vector3.ONE * 2.6
	root.add_child(pit)
	var lit := not used_fires.has(c)
	var flame := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.55, 0.15)
	sm.material = fm
	flame.mesh = sm
	flame.amount = 18
	flame.lifetime = 0.7
	flame.position.y = 0.12
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.12
	flame.direction = Vector3.UP
	flame.spread = 15.0
	flame.gravity = Vector3(0, 1.2, 0)
	flame.initial_velocity_min = 0.2
	flame.initial_velocity_max = 0.5
	flame.scale_amount_min = 0.6
	flame.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	flame.scale_amount_curve = curve
	flame.emitting = lit
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 2.5
	light.omni_range = 5.0
	light.position.y = 0.6
	light.visible = lit
	root.add_child(light)
	fires[c] = {"flame": flame, "light": light}
	_fog_add(c, [root])


## 옆 칸(대각선 포함)에 아직 안 쓴 모닥불이 있으면 그 칸
func _fire_near(c: Vector2i) -> Vector2i:
	for f in fires:
		if not used_fires.has(f) and maxi(absi(f.x - c.x), absi(f.y - c.y)) <= 1:
			return f
	return Vector2i(-1, -1)


func _open_rest(fire: Vector2i) -> void:
	rest_fire = fire
	rest_log = PackedStringArray()
	explorer.active = false
	rest_panel.visible = true
	Sfx.play(self, "open")
	_update_rest()


func _rest_roll() -> void:
	var r := hero.spend_hit_die(rest_dice)
	if r.is_empty():
		return
	Sfx.play(self, "dice")
	rest_log.append("d%d → %d + CON %d = HP +%d" % [hero.hit_die(), r.roll, hero.con_mod(), r.heal])
	_update_rest()
	_update_explore_info()


func _finish_rest() -> void:
	hero.finish_short_rest()
	used_fires[rest_fire] = true
	var f: Dictionary = fires[rest_fire]
	(f.flame as CPUParticles3D).emitting = false
	(f.light as OmniLight3D).visible = false
	rest_panel.visible = false
	explorer.active = true
	Sfx.play(self, "confirm")
	_toast("짧은 휴식을 마쳤어요 — Second Wind 1회%s 회복" % (", Action Surge" if hero.level() >= 2 else ""))
	_update_explore_info()


func _update_rest() -> void:
	var can := hero.hit_dice_left() > 0 and hero.current_hp() < hero.max_hp()
	rest_roll.disabled = not can
	var lines := PackedStringArray()
	lines.append("[b]짧은 휴식[/b] (모닥불은 한 번 쓰면 꺼져요)")
	lines.append("HP %d/%d · 히트 다이스 %d/%d (d%d + CON %d)" % [
		hero.current_hp(), hero.max_hp(), hero.hit_dice_left(), hero.level(), hero.hit_die(), hero.con_mod()])
	for l in rest_log:
		lines.append("  " + l)
	if not can:
		lines.append("[color=gray]%s[/color]" % ("HP가 가득 찼어요" if hero.current_hp() >= hero.max_hp() else "남은 히트 다이스가 없어요"))
	lines.append("마치면 Second Wind 1회와 Action Surge가 돌아와요")
	rest_label.text = "\n".join(lines)


func _build_rest_panel(layer: CanvasLayer) -> void:
	rest_panel = PanelContainer.new()
	# 플레이어와 모닥불을 가리지 않게 화면 아래쪽에
	rest_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	rest_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rest_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rest_panel.offset_bottom = -40
	rest_panel.add_theme_stylebox_override("panel", _panel_style())
	rest_panel.visible = false
	layer.add_child(rest_panel)
	var box := VBoxContainer.new()
	rest_panel.add_child(box)
	rest_label = _rich(box)
	rest_label.custom_minimum_size.x = 380
	var row := HBoxContainer.new()
	box.add_child(row)
	rest_roll = Button.new()
	rest_roll.text = "히트 다이스 굴리기 (Enter)"
	rest_roll.focus_mode = Control.FOCUS_NONE
	rest_roll.pressed.connect(_rest_roll)
	row.add_child(rest_roll)
	var done := Button.new()
	done.text = "휴식 마치기 (Esc)"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(_finish_rest)
	row.add_child(done)


func _toast(text: String) -> void:
	toast.text = text
	var tw := create_tween()
	toast.modulate.a = 1.0
	tw.tween_interval(1.6)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5)


func _update_explore_info() -> void:
	var left := 0
	for r in dungeon.rooms:
		if not r.encounter.is_empty() and not cleared.has(r.id):
			left += 1
	var lv := hero.level()
	var next_xp := "최고" if lv >= HeroState.MAX_LEVEL else str(Rules.XP_THRESHOLDS[lv])
	var hp := hero.current_hp()
	var hp_col := "#f66" if hp * 2 <= hero.max_hp() else "#ddd"
	var probe := hero.make_creature()
	info_label.text = ("[b]탐험 중[/b]  %d층 · 시드 %d · 저장 %d층\n"
			+ "[b]파이터[/b] %d레벨 · [color=%s]HP %d/%d[/color] · XP %d/%s\n"
			+ "히트 다이스 %d/%d · 물약 %d · Second Wind %d%s\n"
			+ "금화 %d · 남은 몬스터 방 %d\n[color=#6af]●[/color] 시작  계단 출구 · 상자 보물 · 불 모닥불 · 텐트 쉼터") % [
		floor_no, dungeon.seed_used, int(save.get("floor", floor_no)), lv, hp_col, hp, hero.max_hp(), hero.xp, next_xp,
		hero.hit_dice_left(), lv, probe.resources.get("potion", 0), probe.resources.get("second_wind", 0),
		(" · Action Surge %d" % probe.resources.action_surge) if probe.resources.has("action_surge") else "",
		gold, left]
	var here := dungeon.room_at(explorer.cell) if explorer else -1
	if here < 0:
		room_label.text = "[color=gray]통로[/color]"
	else:
		var r: Dictionary = dungeon.rooms[here]
		room_label.text = "%s %d%s" % [KIND_NAMES[r.kind], here, "  [color=#6d6]정리함 ✓[/color]" if cleared.has(here) else ""]


func _unhandled_input(event: InputEvent) -> void:
	if exploring:
		return
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
