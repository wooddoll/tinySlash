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
## 방 주제 보기 이름 (생성기 THEMES + 보물창고)
const ROOM_THEME_NAMES := {"library": "서재", "smithy": "대장간", "alchemy": "연금술실", "storage": "창고", "barracks": "막사", "treasury": "보물창고"}

const Explorer = preload("res://scripts/dungeon_explorer.gd")
const Sfx = preload("res://scripts/sfx.gd")
const PartyPanel = preload("res://scripts/party_panel.gd")
const LevelUpDialog = preload("res://scripts/level_up_dialog.gd")
const ActionLayer = preload("res://scripts/action_layer.gd")
const Game = preload("res://scripts/game.gd")
const Quests = preload("res://rules/quests.gd")

## 전투에 다녀와도 같은 던전이 나오도록 장면 밖에 보관
static var saved: DungeonParams = null
static var selected := -1
static var cleared := {}
## 탐험 모드 상태 (전투에 다녀와도 이어짐)
static var exploring := false
## 바깥 지형의 던전 입구로 들어왔을 때 그 던전 시드 (0이 아니면 그 던전에서 바로 탐험을 시작)
static var enter_seed := 0
## 바깥 입구로 들어올 때 그 던전의 몬스터 주제·생성 방식·이름 (rules/region.gd, M5)
static var enter_theme := "mixed"
static var enter_algorithm := 0
static var enter_name := ""
## 바깥에서 들어온 탐험인가, 그리고 들어온 층 (그 층 시작 칸이 바깥으로 나가는 출구)
static var from_outside := false
static var entry_floor := 1
## 지나온 층 기억: 층 번호 → {params, cleared, opened, used_fires, seen}. 계단을 다시 오르내리면 그 층 그대로
static var floor_memory := {}
## 위층으로 올라와서 이 층 내려가는 계단 위에서 시작
static var _arrive_down := false
## 탐험을 다시 시작할 칸 (-1이면 시작 지점)
static var explore_cell := Vector2i(-1, -1)
## 방에 들어서기 직전 칸. 전투에서 도망치면(Esc) 여기로 돌아옴
static var retreat_cell := Vector2i(-1, -1)
static var opened := {}
## 금화와 파티는 한 판 전체 상태(Game)에 있음. 여기 이름으로도 그대로 씀
static var gold: int:
	get: return Game.gold
	set(v): Game.gold = v
static var floor_no := 1
## 전투 사이에 이어지는 주인공 상태
static var hero: HeroState:
	get: return Game.hero
	set(v): Game.hero = v
## 동료 클레릭
static var ally: HeroState:
	get: return Game.ally
	set(v): Game.ally = v
## 지금 떠 있는 던전 화면 (저장할 때 탐험 중인 칸을 읽음)
static var _view: WeakRef = null
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
## 탐험 중 보이는 거리 (칸, 일직선 시야). 방 안이면 그 방은 거리와 상관없이 보임 (횃불)
const SIGHT := 6

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
## 플레이어를 따라 걷는 동료 모델
var follower: CharacterModel
## 탐험 중 왼쪽 파티 창
var party_panel: PartyPanel
var _trail: Array[Vector3] = []
var chests := {}
var _leaving := false
var fires := {}  # 칸 -> 불꽃 노드들
## 칸 -> 그 칸에 속한 것들 ([MultiMesh, 번호, 원래 변환] 또는 [노드])
var _fog_index := {}
var rest_panel: PanelContainer
## 레벨업 고르기 창과, 고를 것이 남았는지 다시 볼 때까지 남은 시간
var level_dialog: LevelUpDialog
## 실시간 액션 전투 (탐험 중에만). members: party()와 같은 순서의 Actor
var action: ActionLayer
var members: Array = []
## 생성기 화면용 몬스터 모델과 자리 [노드, 몬스터 id, 칸, 방]
var foe_spots: Array = []
## 이미 "몬스터 발견!"을 알린 방
var _woke := {}
var _level_poll := 0.0
var rest_label: RichTextLabel
var rest_roll: Button
var rest_fire := Vector2i(-1, -1)
var rest_log := PackedStringArray()
var rest_dice := Dice.new()
var shelter := Vector2i(-1, -1)
var merchant := Vector2i(-1, -1)
## 의뢰 물건(찾아오기 의뢰)이 놓인 칸과 그 노드들 (없으면 -1)
var quest_item_cell := Vector2i(-1, -1)
var _quest_item_nodes: Array = []
var shop_panel: PanelContainer
var shop_label: RichTextLabel
var shop_rest: Button
var shop_buy: Button


func _ready() -> void:
	InputSetup.register()
	_view = weakref(self)
	var came_in := enter_seed != 0
	if came_in:
		# 같은 입구는 늘 같은 던전. 이전 탐험 기록은 비움
		from_outside = true
		saved = DungeonParams.new()
		saved.rng_seed = enter_seed
		saved.theme = enter_theme
		saved.algorithm = enter_algorithm as DungeonParams.Algorithm
		enter_seed = 0
		exploring = false
		cleared.clear()
		opened.clear()
		used_fires.clear()
		seen.clear()
		floor_memory.clear()
		selected = -1
		explore_cell = Vector2i(-1, -1)
		retreat_cell = Vector2i(-1, -1)
		floor_no = saved.floor_depth
		entry_floor = floor_no
		_pending_toast = "%s — 들어온 곳(햇빛 비치는 칸)에서 Enter: 바깥으로" % enter_name if enter_name != "" else "들어온 곳(햇빛 비치는 칸)에서 Enter: 바깥으로"
	if saved == null:
		saved = DungeonParams.new()
		saved.rng_seed = randi_range(1, 999999)
	_take_battle_result()
	params = saved  # 지면 저장한 층의 파라미터로 바뀜
	_build_ui()
	Sfx.wire_buttons(self)
	_generate()
	if came_in:
		_set_exploring(true)
		_autosave()


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
	foe_spots.clear()
	action = null
	members.clear()
	_woke.clear()
	dungeon = DungeonGenerator.generate(params)
	if selected >= dungeon.rooms.size():
		selected = -1
	if world:
		world.queue_free()
	explorer = null
	follower = null
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
					add.call(Kenney.pick(Kenney.CAVE_FLOORS, c), Transform3D(spin.call(), pos), c)
				else:
					add.call(Kenney.pick(Kenney.FLOOR_DETAILS, c) if rng.randf() < 0.15 else "floor", Transform3D(spin.call(), pos), c)
				if d.difficult.has(c):
					if cave:
						add.call("nature-kit/" + Kenney.pick(Kenney.CAVE_RUBBLE, c), Transform3D(spin.call() * Basis.from_scale(Vector3.ONE * 1.5), pos), c)
					else:
						add.call("stones", Transform3D(spin.call(), pos), c)
	_fill(bases, base_xf)
	for i in base_cells.size():
		_fog_add(base_cells[i], [bases.multimesh, i, base_xf[i][0]])
	for part in Kenney.build_edge_walls(world, floors, d.is_floor, d.get_height, cave):
		for i in (part[1] as Array).size():
			_fog_add(part[1][i], [part[0], i, part[2][i]])
	# 꾸미기: 출입구, 장애물, 보물, 모닥불 칸은 비워 둠
	var busy := {d.start: true, d.exit: true}
	for r in d.rooms:
		for t in r.treasure:
			busy[t.cell] = true
	for c in d.campfires:
		busy[c] = true
	var deco := Kenney.decorate(world, floors, d.is_floor, d.get_height, cave,
			func(c: Vector2i) -> bool: return busy.has(c) or d.obstacles.has(c) or d.difficult.has(c), d.theme_at)
	for part in deco.parts:
		for i in (part[1] as Array).size():
			_fog_add(part[1][i], [part[0], i, part[2][i]])
	for l in deco.lights:
		_fog_add(l[1], [l[0]])

	for c in d.obstacles:
		if cave:
			# 동굴은 갈색 바위: 기둥은 키 큰 바위, 낮은 바위는 납작한 큰 바위를 세로로 늘림
			if d.obstacles[c] >= 2.0:
				add.call("nature-kit/" + Kenney.pick(Kenney.CAVE_PILLARS, c), Transform3D(spin.call() * Basis.from_scale(Vector3(1.0, 1.7, 1.0)), _top(c)), c)
			else:
				add.call("nature-kit/" + Kenney.pick(Kenney.CAVE_ROCKS, c), Transform3D(spin.call() * Basis.from_scale(Vector3(1.0, 2.6, 1.0)), _top(c)), c)
		elif d.obstacles[c] >= 2.0:
			add.call("column", Transform3D(Basis.IDENTITY, _top(c)), c)
		else:
			add.call("rocks", Transform3D(spin.call(), _top(c)), c)
	add.call("stairs", Transform3D(Basis.IDENTITY, _top(d.exit)), d.exit)
	if _up_stairs_here():
		add.call("stairs", Transform3D(Basis(Vector3.UP, PI), _top(d.start)), d.start)

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

	# 시작 지점 (파란 원판). 바깥에서 들어온 층이면 바깥 출구: 위에서 햇빛이 비침
	# 탐험을 시작한 층보다 깊으면 시작 칸은 오르는 계단 (모델은 위에서 놓음)
	if _outside_exit_here():
		var disc := _marker_disc(d.start, Color(1.0, 0.92, 0.7))
		var sun := OmniLight3D.new()
		sun.light_color = Color(1.0, 0.95, 0.8)
		sun.light_energy = 2.5
		sun.omni_range = 3.5
		sun.position = Vector3(0, 1.6, 0)
		disc.add_child(sun)
		_fog_add(d.start, [disc])
	elif _up_stairs_here():
		_fog_add(d.start, [_marker_disc(d.start, Color(0.75, 0.7, 0.55))])  # 오르는 계단: 흐린 돌빛
	else:
		_fog_add(d.start, [_marker_disc(d.start, Color(0.3, 0.6, 1.0))])

	# 몬스터, 보물, 방 번호
	for r in d.rooms:
		var done: bool = cleared.has(r.id)
		if not r.encounter.is_empty() and not done:
			for f in r.encounter.foes:
				if exploring:
					foe_spots.append([null, f[0], f[1], r.id])  # 탐험 중이면 액션 전투가 모델을 만듦
					continue
				var st := Catalog.monster(f[0])
				var m := CharacterModel.new()
				world.add_child(m)
				m.setup(st.model, st.sprite_scale, st.weapon_model)
				m.tint(st.tint)
				m.position = _top(f[1])
				m.face(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), true)
				_fog_add(f[1], [m])
				foe_spots.append([m, f[0], f[1], r.id])
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
		lbl.add_to_group("room_label")
		world.add_child(lbl)
		_fog_add(r.center, [lbl])

	for c in d.campfires:
		_add_campfire(c)
	shelter = Vector2i(-1, -1)
	merchant = Vector2i(-1, -1)
	if is_save_floor(params.floor_depth):
		shelter = shelter_cell(d)
		if shelter != Vector2i(-1, -1):
			_add_shelter(shelter)
			merchant = shelter_cell(d, {shelter: true})
			if merchant != Vector2i(-1, -1):
				_add_merchant(merchant)

	_place_quest_item(d)

	select_mesh = _overlay_layer(Color(1.0, 0.85, 0.2, 0.4))
	hover_mesh = _overlay_layer(Color(1, 1, 1, 0.18))


## 찾아오기 의뢰(rules/quests.gd)의 물건: 바깥 입구로 들어온 던전에서 그 층이면, 시작 칸에서 가장 먼 방 가운데에 둠
func _place_quest_item(d: Dungeon) -> void:
	quest_item_cell = Vector2i(-1, -1)
	_quest_item_nodes.clear()
	if not from_outside:
		return
	var q := Quests.item_on_floor(Game.quests, Game.dungeon_id, params.floor_depth)
	if q.is_empty():
		return
	var best := -1.0
	for r in d.rooms:
		if r.kind == "start":
			continue
		var c: Vector2i = r.center
		if not d.is_walkable(c):
			continue
		var dist := Vector2(c).distance_to(Vector2(d.start))
		if dist > best:
			best = dist
			quest_item_cell = c
	if quest_item_cell == Vector2i(-1, -1):
		return
	var item := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.12, 0.2)
	item.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 1.5
	item.material_override = mat
	item.position = _top(quest_item_cell) + Vector3(0, 0.08, 0)
	item.rotation.y = 0.6
	world.add_child(item)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.75, 0.35)
	glow.light_energy = 1.2
	glow.omni_range = 2.5
	glow.position = _top(quest_item_cell) + Vector3(0, 0.6, 0)
	world.add_child(glow)
	_quest_item_nodes = [item, glow, _marker_disc(quest_item_cell, Color(1.0, 0.75, 0.3))]
	for n in _quest_item_nodes:
		_fog_add(quest_item_cell, [n])


func _pick_quest_item() -> void:
	var q := Quests.item_on_floor(Game.quests, Game.dungeon_id, floor_no)
	quest_item_cell = Vector2i(-1, -1)
	for n in _quest_item_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_quest_item_nodes.clear()
	if q.is_empty():
		return
	Quests.on_item(Game.quests, Game.dungeon_id, floor_no)
	Sfx.play(self, "chest")
	_toast("찾았어요: %s — 의뢰판에서 보상 받기" % q.item)
	_autosave()


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
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	level_dialog = LevelUpDialog.new()
	top.add_child(level_dialog)
	level_dialog.finished.connect(func() -> void:
		if explorer and exploring:
			explorer.active = true
			_heroes_changed()
		_update_info())

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
	_party_options(box)
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
	_slider(box, "corridor_width", "복도 폭", 2, 3, 1)
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
	_build_shop_panel(layer)
	party_panel = PartyPanel.new()
	party_panel.position = Vector2(12, 12)
	party_panel.visible = false
	layer.add_child(party_panel)
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


## 주인공·동료 클래스 고르기. 다음에 탐험을 새로 시작할 때 적용
func _party_options(parent: Control) -> void:
	for i in 2:
		var row := _row(parent, "주인공" if i == 0 else "동료")
		var o := OptionButton.new()
		for cls in Catalog.CLASSES:
			o.add_item(HeroState.NAMES[cls])
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o.selected = maxi(Catalog.CLASSES.find(HeroState.party_classes[i]), 0)
		o.item_selected.connect(func(k: int) -> void:
			HeroState.party_classes[i] = Catalog.CLASSES[k]
			_toast("파티: %s + %s (탐험을 새로 시작하면 적용)" % [HeroState.NAMES[HeroState.party_classes[0]], HeroState.NAMES[HeroState.party_classes[1]]]))
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
	if ROOM_THEME_NAMES.has(r.get("theme", "")):
		lines.append("[color=#c9a]%s[/color]" % ROOM_THEME_NAMES[r.theme])
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
	if action:
		action.paused = explorer == null or not explorer.active or level_dialog.visible
	if level_dialog.visible:
		return
	_level_poll -= delta
	if _level_poll <= 0.0 and not rest_panel.visible and not shop_panel.visible and not _leaving:
		_level_poll = 0.5
		if level_dialog.open(party()):
			if explorer:
				explorer.active = false
			return
	if exploring:
		camera.h_offset = 0.0
		_update_follower(delta)
		if _leaving:
			return
		if rest_panel.visible:
			if Input.is_action_just_pressed("end_turn"):
				_rest_roll()
			elif Input.is_action_just_pressed("explore") or Input.is_action_just_pressed("back") 					or Input.is_action_just_pressed("skill"):
				_finish_rest()
			return
		if shop_panel.visible:
			if Input.is_action_just_pressed("explore") or Input.is_action_just_pressed("back") \
					or Input.is_action_just_pressed("skill"):
				_close_shop()
			elif Input.is_action_just_pressed("attack"):
				_buy_potion()
			elif Input.is_action_just_pressed("end_turn"):
				_long_rest()
				_update_shop()
			return
		if Input.is_action_just_pressed("explore") or Input.is_action_just_pressed("back"):
			_set_exploring(false)
		elif Input.is_action_just_pressed("end_turn") and explorer and action and action.ac.fighting():
			_toast("싸우는 중이에요!")
		elif Input.is_action_just_pressed("end_turn") and explorer:
			var fire := _fire_near(explorer.cell)
			if _outside_exit_here() and explorer.cell == dungeon.start:
				_go_outside()
			elif _up_stairs_here() and explorer.cell == dungeon.start:
				_change_floor(floor_no - 1)
			elif fire != Vector2i(-1, -1):
				_open_rest(fire)
			elif _near(shelter, explorer.cell) or _near(merchant, explorer.cell):
				_open_shop()
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
		# 생성기에서 새로 시작하면 금화, 층 수, 파티 상태를 처음부터 (바깥에서 들어왔으면 금화·파티는 그대로)
		if not from_outside:
			gold = 0
		floor_no = params.floor_depth
		entry_floor = floor_no
		floor_memory.clear()
		# 바깥에서 들어왔으면 바깥 전투에서 키운 파티 그대로
		if not from_outside or hero == null:
			hero = _fresh_member(0)
		if not from_outside or ally == null:
			ally = _fresh_member(1)
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
## 탐험 중에는 어둡게: 달빛 같은 약한 해, 어두운 주변광, 안개. 생성기 화면은 밝게 (전체를 봐야 하므로)
func _set_mood(dark: bool) -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun:
		sun.light_energy = 0.12 if dark else 0.9
		sun.light_color = Color(0.6, 0.7, 1.0) if dark else Color.WHITE
		sun.shadow_enabled = not dark  # 어두울 때는 등불 빛이 주인공, 그림자 계산 아낌
	# 캐릭터 보조광: 카메라 쪽에서 캐릭터(렌더 층 2)만 비춤. 어두운 배경에서 몸이 보이게
	var fill := rig.get_node_or_null("CharFill") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "CharFill"
		fill.light_cull_mask = CharacterModel.CHAR_LAYER
		fill.light_color = Color(0.85, 0.85, 1.0)
		fill.shadow_enabled = false
		rig.add_child(fill)
		fill.rotation_degrees = Vector3(-35, 20, 0)
	fill.light_energy = 1.6
	fill.visible = dark
	if we and we.environment:
		var e := we.environment
		e.ambient_light_color = Color(0.32, 0.34, 0.45) if dark else Color(0.55, 0.55, 0.65)
		e.ambient_light_energy = 0.45 if dark else 0.6
		e.background_color = Color(0.02, 0.02, 0.03) if dark else Color(0.06, 0.06, 0.08)
		e.fog_enabled = dark
		e.fog_light_color = Color(0.05, 0.05, 0.08)
		e.fog_density = 0.02


## 주인공이 든 등불: 따뜻한 빛이 주변 몇 칸을 비춤 (그림자 없음, 가벼움)
func _add_lantern(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.name = "Lantern"
	l.position = Vector3(0, 2.4, 0)
	l.light_color = Color(1.0, 0.72, 0.42)
	l.light_energy = 3.0
	l.omni_range = 9.0
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	n.add_child(l)


func _apply_mode() -> void:
	left_panel.visible = not exploring
	party_panel.visible = exploring
	fight_button.visible = not exploring
	_show_room(hover_mesh, -1)
	if exploring:
		_show_room(select_mesh, -1)
		if hero == null:
			hero = _fresh_member(0)
		if ally == null:
			ally = _fresh_member(1)
		if save.is_empty():
			_write_save()
		if _pending_toast != "":
			_toast(_pending_toast)
			_pending_toast = ""
		if explorer == null:
			var at := explore_cell if dungeon.is_walkable(explore_cell) else dungeon.start
			if _arrive_down:
				at = dungeon.exit
				_arrive_down = false
			explorer = Explorer.new()
			world.add_child(explorer)
			explorer.setup(dungeon, at, hero.stats().model, hero.stats().weapon_model)
			explorer.camera_rig = rig
			for c in [shelter, merchant]:
				if c != Vector2i(-1, -1):
					explorer.blocked[c] = true
			explorer.entered_cell.connect(_on_entered_cell)
			_start_action()
			_add_lantern(explorer)
		_set_mood(true)
		_reveal(explorer.cell)
		_fog_apply_all()
		rig.target = explorer
		rig.ortho_size = 10.0
		get_tree().call_group("room_label", "hide")  # 액션 중에는 방 번호를 숨김
		help_label.text = "이동: 왼쪽 스틱/WASD · 공격: X/J (누르고 있으면 계속) · 구르기: A/Space · 기술: B/K · 기술2: 십자→/L · 물약: 십자↑/1 · 상호작용: Y/Enter · 카메라: LB·RB/Q·E · 생성기로: Back/Tab"
		_update_explore_info()
	else:
		var had_action := action != null
		if explorer:
			explorer.queue_free()
			explorer = null
		if follower:
			follower.queue_free()
			follower = null
		if had_action:
			_generate()  # 움직인 몬스터를 제자리로
		rig.target = focus
		rig.look_offset = Vector3.ZERO
		rig.zoom_bonus = 0.0
		_set_mood(false)
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
	if quest_item_cell != Vector2i(-1, -1) and maxi(absi(quest_item_cell.x - to.x), absi(quest_item_cell.y - to.y)) <= 1:
		_pick_quest_item()
	var r := dungeon.room_at(to)
	if r >= 0 and not cleared.has(r) and not dungeon.rooms[r].encounter.is_empty() and action:
		action.ac.wake_room(r)
	if to == dungeon.exit:
		_toast("출구 계단 — Enter: 다음 층으로")
	elif to == dungeon.start and _outside_exit_here():
		_toast("바깥 출구 — Enter: 밖으로")
	elif to == dungeon.start and _up_stairs_here():
		_toast("오르는 계단 — Enter: %d층으로" % (floor_no - 1))
	elif _fire_near(to) != Vector2i(-1, -1) and _fire_near(from) == Vector2i(-1, -1):
		_toast("모닥불 — Enter: 짧은 휴식")
	elif (_near(shelter, to) or _near(merchant, to)) and not (_near(shelter, from) or _near(merchant, from)):
		_toast("쉼터 — Enter: 휴식과 상점")
	_update_explore_info()


# --- 실시간 액션 전투 (rules 10장) ---

func _start_action() -> void:
	for spot in foe_spots:
		if spot[0] != null and is_instance_valid(spot[0]):
			(spot[0] as Node3D).queue_free()
	action = ActionLayer.new()
	world.add_child(action)
	action.camera_rig = rig
	action.setup(dungeon, explorer.blocked)
	members.clear()
	var heroes := party()
	for i in heroes.size():
		var h: HeroState = heroes[i]
		var cell := explorer.cell
		if i > 0:
			cell = _free_near(explorer.cell)
		var a = action.add_member(h.make_creature(), cell, "player" if i == 0 else "ally", explorer.body if i == 0 else null)
		members.append(a)
	explorer.actor = members[0]
	for spot in foe_spots:
		if cleared.has(spot[3]):
			continue
		var m: Node3D = action.add_foe(spot[1], spot[2], spot[3])
		_fog_add(spot[2], [m])
	action.message.connect(_toast)
	action.party_changed.connect(_party_from_action)
	action.fight_over.connect(_on_fight_over)
	action.defeated.connect(_on_defeated)
	action.ac.event.connect(func(ev: Dictionary) -> void:
		if ev.type == "wake":
			var room: int = (ev.actor as ActionCombat.Actor).room
			if room >= 0 and not _woke.has(room):
				_woke[room] = true
				_toast("몬스터 발견! — " + str(dungeon.rooms[room].encounter.label))
				Sfx.play(self, "alert"))


## c 옆의 서 있을 수 있는 빈 칸
func _free_near(c: Vector2i) -> Vector2i:
	for d in Dungeon.DIRS8:
		var n: Vector2i = c + d
		if dungeon.is_walkable(n) and not explorer.blocked.has(n):
			return n
	return c


## 전투 중 크리처 상태를 HeroState에 담아 화면 정보를 고침
func _party_from_action() -> void:
	var heroes := party()
	for i in mini(heroes.size(), members.size()):
		var h: HeroState = heroes[i]
		var c: Creature = members[i].c
		h.hp = maxi(c.hp, 0)
		h.resources = c.resources.duplicate()
	_update_explore_info()


## HeroState가 바뀐 뒤 (휴식, 상점, 레벨업 고르기) 크리처를 다시 만듦
func _heroes_changed() -> void:
	if action:
		var heroes := party()
		for i in mini(heroes.size(), members.size()):
			action.refresh_member(members[i], (heroes[i] as HeroState).make_creature())
	_update_explore_info()


func _on_fight_over(xp: int) -> void:
	var heroes := party()
	var share := xp / maxi(heroes.size(), 1)
	var level_up := 0
	for i in mini(heroes.size(), members.size()):
		var up: Dictionary = (heroes[i] as HeroState).absorb(members[i].c, share)
		if up.has("level_up"):
			level_up = up.level_up
	var news := PackedStringArray()
	for r in dungeon.rooms:
		if not r.encounter.is_empty() and not cleared.has(r.id) and action.ac.room_clear(r.id):
			cleared[r.id] = true
			if from_outside and r.encounter.get("boss", false):
				for q in Quests.on_boss(Game.quests, Game.dungeon_id, floor_no):
					news.append("의뢰 끝: %s — 의뢰판에서 보상 받기" % q.title)
	if not news.is_empty():
		get_tree().create_timer(2.5).timeout.connect(func() -> void: _toast("\n".join(news)))
	_heroes_changed()
	if xp > 0:
		_toast("전투 끝! XP +%d씩%s" % [share, ("  — 레벨 업! %d레벨" % level_up) if level_up > 0 else ""])
		Sfx.play(self, "level_up" if level_up > 0 else "win")


func _on_defeated() -> void:
	_toast("파티가 모두 쓰러졌어요…")
	Sfx.play(self, "lose")
	await get_tree().create_timer(2.0).timeout
	Battle.custom = {"room_id": -1, "result": "lose"}
	get_tree().change_scene_to_file("res://scenes/dungeon.tscn")


func _start_battle(room: int, from: Vector2i, to: Vector2i) -> void:
	_leaving = true
	explorer.active = false
	explore_cell = to
	retreat_cell = from if dungeon.is_walkable(from) else dungeon.start
	_toast("몬스터 발견! — " + str(dungeon.rooms[room].encounter.label))
	Sfx.play(self, "alert")
	Battle.custom = dungeon.battle_setup(room, to)
	Battle.custom["party"] = party()
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
	_change_floor(floor_no + 1)


## 계단으로 층을 옮김. 처음 가는 아래층은 새로 만들고, 지나온 층은 기억한 그대로 (오르면 내려가는 계단 위에 섬)
func _change_floor(to: int) -> void:
	var keep_gold := gold
	var up := to < floor_no
	floor_memory[floor_no] = {"params": params.duplicate_params(), "cleared": cleared.duplicate(),
			"opened": opened.duplicate(), "used_fires": used_fires.duplicate(), "seen": seen.duplicate()}
	floor_no = to
	Sfx.play(self, "stairs")
	rested_here = false
	var mem: Dictionary = floor_memory.get(to, {})
	_syncing = true
	if mem.is_empty():
		# 몬스터 예산을 파티 레벨, 인원, 층 깊이에 맞춤
		params.party_level = hero.level()
		params.party_size = party().size()
		params.floor_depth = floor_no
		params.rng_seed = randi_range(1, 999999)
	else:
		var p: DungeonParams = mem.params
		for prop in ["rng_seed", "floor_depth", "party_level", "party_size"]:
			params.set(prop, p.get(prop))
	(controls["party_level"] as HSlider).value = params.party_level
	(controls["party_size"] as HSlider).value = params.party_size
	(controls["floor_depth"] as HSlider).value = params.floor_depth
	seed_box.value = params.rng_seed
	_syncing = false
	_set_param("rng_seed", params.rng_seed)  # 탐험 상태를 비우고 다시 만듦
	if not mem.is_empty():
		cleared = (mem.cleared as Dictionary).duplicate()
		opened = (mem.opened as Dictionary).duplicate()
		used_fires = (mem.used_fires as Dictionary).duplicate()
		seen = (mem.seen as Dictionary).duplicate()
	_arrive_down = up
	gold = keep_gold
	if up:
		_toast("%d층 (올라옴)" % floor_no if floor_no != entry_floor or not from_outside else "%d층 — 햇빛 비치는 칸에서 Enter: 바깥으로" % floor_no)
	elif is_save_floor(floor_no) and mem.is_empty():
		_write_save()  # 쉼터가 있는 층에 처음 도착하면 저장
		_toast("%d층 — 쉼터가 있어요 (저장했어요)" % floor_no)
	else:
		_toast("%d층" % floor_no)
	_autosave.call_deferred()  # 새 층이 만들어진 뒤 (탐험 칸은 새 층 기준)


# --- 전장의 안개: 탐험 중에는 본 칸만 그림 ---

func _fog_add(c: Vector2i, entry: Array) -> void:
	if not _fog_index.has(c):
		_fog_index[c] = []
	_fog_index[c].append(entry)


func _fog_show(entry: Array, on: bool) -> void:
	if entry.size() == 1:
		if is_instance_valid(entry[0]):
			(entry[0] as Node3D).visible = on and not (exploring and (entry[0] as Node).is_in_group("room_label"))
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
	# 일직선 시야: 칸 가운데에서 칸 가운데로 그은 선이 벽(바닥이 아닌 칸)에 막히지 않으면 보임.
	# 거리는 SIGHT칸(원 모양) 안. 방 안이면 횃불로 밝아서 그 방 칸은 거리와 상관없이 (선이 막히지 않으면) 보임.
	var out: Array = []
	var room := d.room_at(c)
	var reach := SIGHT
	if room >= 0:
		var rect: Rect2i = d.rooms[room].rect
		reach = maxi(reach, maxi(rect.size.x, rect.size.y))
	for y in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			var t := Vector2i(x, y)
			if not d.is_floor(t):
				continue
			var near := (t - c).length_squared() <= SIGHT * SIGHT
			if not near and not (room >= 0 and d.room_at(t) == room):
				continue
			if line_clear(d, c, t):
				out.append(t)
	return out


## 두 칸 사이에 벽이 없는가 (선을 1/4칸씩 따라가며 지나는 칸이 모두 바닥인지)
static func line_clear(d: Dungeon, a: Vector2i, b: Vector2i) -> bool:
	var from := Vector2(a) + Vector2(0.5, 0.5)
	var to := Vector2(b) + Vector2(0.5, 0.5)
	var steps := int(ceil(from.distance_to(to) * 4.0))
	for k in range(1, steps):
		var p := from.lerp(to, float(k) / steps)
		var cell := Vector2i(floori(p.x), floori(p.y))
		if cell != b and not d.is_floor(cell):
			return false
	return true


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


## 고른 파티의 i번째로 새 파티원 (주인공이 물약을 듦)
static func _fresh_member(i: int) -> HeroState:
	return HeroState.fresh(str(HeroState.party_classes[i]), 1 if i == 0 else 0)


static func party() -> Array:
	return [hero, ally].filter(func(h: HeroState) -> bool: return h != null)


## 정보 창의 파티원 두 줄: 레벨, HP, XP, 히트 다이스 / 남은 기능과 주문 슬롯
func _member_line(h: HeroState) -> String:
	var lv := h.level()
	var next_xp := "최고" if lv >= HeroState.MAX_LEVEL else str(Rules.XP_THRESHOLDS[lv])
	var hp := h.current_hp()
	var probe := h.make_creature()
	var res: Array[String] = ["히트 다이스 %d/%d" % [h.hit_dice_left(), lv]]
	for t in ClassFeatures.resource_labels(probe):
		if not t.begins_with("Channel"):
			res.append(t)
	var slots: Array[String] = []
	for l in range(1, probe.stats.spell_slots.size() + 1):
		slots.append("%d레벨 %d/%d" % [l, probe.resources.get("slot%d" % l, 0), probe.stats.spell_slots[l - 1]])
	if not slots.is_empty():
		res.append("슬롯 " + " ".join(slots))
	if probe.resources.has("channel"):
		res.append("Channel %d" % probe.resources.channel)
	return "[b]%s[/b] %d레벨 · [color=%s]HP %d/%d[/color] · XP %d/%s\n   %s" % [h.display_name(), lv,
		"#f66" if hp * 2 <= h.max_hp() else "#ddd", hp, h.max_hp(), h.xp, next_xp, " · ".join(res)]


# 동료 모델: 플레이어가 지나간 길을 0.9유닛 뒤에서 따라감
func _spawn_follower() -> void:
	follower = CharacterModel.new()
	world.add_child(follower)
	var st := ally.stats()
	follower.setup(st.model, 1.0, st.weapon_model)
	follower.position = explorer.position
	_trail = [explorer.position]


func _update_follower(delta: float) -> void:
	if follower == null or explorer == null:
		return
	var p := explorer.position
	if _trail.is_empty() or p.distance_to(_trail[-1]) > 0.12:
		_trail.append(p)
		if _trail.size() > 60:
			_trail.pop_front()
	var target := _trail[0]
	var acc := 0.0
	for i in range(_trail.size() - 1, 0, -1):
		acc += _trail[i].distance_to(_trail[i - 1])
		if acc >= 0.9:
			target = _trail[i - 1]
			break
	var to := target - follower.position
	to.y = 0.0
	var moving := to.length() > 0.05 and follower.position.distance_to(p) > 0.7
	if moving:
		follower.position += to.normalized() * minf(to.length(), 5.0 * delta)
		follower.face(to)
	follower.position.y = lerpf(follower.position.y, target.y, 1.0 - exp(-14.0 * delta))
	follower.set_base("sprint" if moving else "idle")


## 시작 방에서 시작 칸에 가장 가까운 빈 칸 (시작 칸, 모닥불, 상자, 몬스터 칸, exclude는 피함)
static func shelter_cell(d: Dungeon, exclude := {}) -> Vector2i:
	var taken := exclude.duplicate()
	taken[d.start] = true
	taken[d.exit] = true
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


func _add_merchant(c: Vector2i) -> void:
	var m := CharacterModel.new()
	world.add_child(m)
	m.setup("mini-characters/character-worker", 1.0)
	m.position = _top(c)
	m.face(Vector3(_top(dungeon.start) - _top(c)).normalized() if c != dungeon.start else Vector3(0, 0, 1), true)
	var lbl := Label3D.new()
	lbl.text = "상인"
	lbl.font_size = 48
	lbl.pixel_size = 0.006
	lbl.outline_size = 10
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, m.height + 0.3, 0)
	m.add_child(lbl)
	_fog_add(c, [m])


# 쉼터 창: 긴 휴식과 상점
func _open_shop() -> void:
	explorer.active = false
	shop_panel.visible = true
	Sfx.play(self, "open")
	_update_shop()


func _close_shop() -> void:
	shop_panel.visible = false
	explorer.active = true
	Sfx.play(self, "close")


func _buy_potion() -> void:
	if not hero.can_buy_potion(gold):
		Sfx.play(self, "click")
		return
	gold = hero.buy_potion(gold)
	_write_save()  # 쉼터에서 한 일은 저장
	Sfx.play(self, "coins")
	_update_shop()
	_heroes_changed()


func _update_shop() -> void:
	shop_rest.disabled = rested_here
	shop_buy.disabled = not hero.can_buy_potion(gold)
	var lines := PackedStringArray()
	lines.append("[b]쉼터[/b] (%d층 · 여기서 한 일은 저장돼요)" % floor_no)
	for h in party():
		lines.append("%s HP %d/%d · 히트 다이스 %d/%d" % [h.display_name(), h.current_hp(), h.max_hp(), h.hit_dice_left(), h.level()])
	lines.append("물약 %d/%d (%s가 들고 다님) · 금화 %d" % [hero.potions(), HeroState.MAX_POTIONS, hero.display_name(), gold])
	lines.append("긴 휴식: 파티 모두 HP, 히트 다이스, 기능, 주문 슬롯 회복 (쉼터마다 한 번)%s" % (
		" [color=gray]— 이미 쉬었어요[/color]" if rested_here else ""))
	lines.append("상인: 회복 물약 (2d4+2 회복) %d골드%s" % [HeroState.POTION_PRICE,
		" [color=gray]— 가득 찼어요[/color]" if hero.potions() >= HeroState.MAX_POTIONS
		else (" [color=gray]— 금화가 모자라요[/color]" if gold < HeroState.POTION_PRICE else "")])
	shop_label.text = "\n".join(lines)


func _build_shop_panel(layer: CanvasLayer) -> void:
	shop_panel = PanelContainer.new()
	shop_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	shop_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shop_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	shop_panel.offset_bottom = -40
	shop_panel.add_theme_stylebox_override("panel", _panel_style())
	shop_panel.visible = false
	layer.add_child(shop_panel)
	var box := VBoxContainer.new()
	shop_panel.add_child(box)
	shop_label = _rich(box)
	shop_label.custom_minimum_size.x = 460
	var row := HBoxContainer.new()
	box.add_child(row)
	shop_rest = Button.new()
	shop_rest.text = "긴 휴식 (Y / Enter)"
	shop_rest.focus_mode = Control.FOCUS_NONE
	shop_rest.pressed.connect(func() -> void:
		_long_rest()
		_update_shop())
	row.add_child(shop_rest)
	shop_buy = Button.new()
	shop_buy.text = "물약 사기 %d골드 (X / J)" % HeroState.POTION_PRICE
	shop_buy.focus_mode = Control.FOCUS_NONE
	shop_buy.pressed.connect(_buy_potion)
	row.add_child(shop_buy)
	var done := Button.new()
	done.text = "닫기 (B / Esc)"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(_close_shop)
	row.add_child(done)


func _write_save() -> void:
	save = {"params": params.duplicate_params(), "floor": floor_no, "hero": hero.duplicate_state(),
			"ally": ally.duplicate_state(), "gold": gold, "rested": rested_here}
	_autosave()


## 파일에도 저장 (탐험 중이면 던전 안, 생성기 화면이면 바깥으로)
func _autosave() -> void:
	Game.place = "dungeon" if exploring else "outside"
	Game.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


## 마지막 저장으로 돌아감: 그 층을 처음 상태로 다시 만들고 파티 상태, 금화도 그때로
static func _load_save() -> void:
	if save.is_empty():
		explore_cell = Vector2i(-1, -1)
		return
	saved = (save.params as DungeonParams).duplicate_params()
	floor_no = save.floor
	hero = (save.hero as HeroState).duplicate_state()
	ally = (save.ally as HeroState).duplicate_state() if save.has("ally") else _fresh_member(1)
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
	for h in party():
		h.long_rest()
	rested_here = true
	var failed := Game.advance_minutes(8 * 60)
	_write_save()
	Sfx.play(self, "confirm")
	_toast("긴 휴식 (8시간, %d일째): HP, 히트 다이스, 기능, 주문 슬롯 회복 · 저장했어요%s" % [Game.day,
		"".join(failed.map(func(q): return "\n의뢰 실패: %s (기한 지남)" % q.title))])
	_heroes_changed()


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


## 히트 다이스를 쓸 파티원: 쓸 수 있는 사람 중 HP 비율이 가장 낮은 사람
func _rest_target() -> HeroState:
	var best: HeroState = null
	for h in party():
		if h.hit_dice_left() > 0 and h.current_hp() < h.max_hp():
			if best == null or float(h.current_hp()) / h.max_hp() < float(best.current_hp()) / best.max_hp():
				best = h
	return best


func _rest_roll() -> void:
	var h := _rest_target()
	if h == null:
		return
	var r := h.spend_hit_die(rest_dice)
	if r.is_empty():
		return
	Sfx.play(self, "dice")
	rest_log.append("%s d%d → %d + CON %d = HP +%d" % [h.display_name(), h.hit_die(), r.roll, h.con_mod(), r.heal])
	_update_rest()
	_heroes_changed()


func _finish_rest() -> void:
	for h in party():
		h.finish_short_rest()
	used_fires[rest_fire] = true
	var f: Dictionary = fires[rest_fire]
	(f.flame as CPUParticles3D).emitting = false
	(f.light as OmniLight3D).visible = false
	rest_panel.visible = false
	explorer.active = true
	Sfx.play(self, "confirm")
	_toast("짧은 휴식을 마쳤어요 — 짧은 휴식으로 돌아오는 기능을 되찾았어요")
	_heroes_changed()


func _update_rest() -> void:
	var can := _rest_target() != null
	rest_roll.disabled = not can
	var lines := PackedStringArray()
	lines.append("[b]짧은 휴식[/b] (모닥불은 한 번 쓰면 꺼져요)")
	for h in party():
		lines.append("%s HP %d/%d · 히트 다이스 %d/%d (d%d + CON %d)" % [h.display_name(),
			h.current_hp(), h.max_hp(), h.hit_dice_left(), h.level(), h.hit_die(), h.con_mod()])
	for l in rest_log:
		lines.append("  " + l)
	if not can:
		lines.append("[color=gray]더 굴릴 수 없어요 (HP가 가득 찼거나 히트 다이스가 없음)[/color]")
	else:
		lines.append("[color=gray]Y / Enter: 가장 많이 다친 파티원이 굴려요[/color]")
	lines.append("마치면 Second Wind 1회, Action Surge, Channel Divinity 1회가 돌아와요 (주문 슬롯은 긴 휴식에)")
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
	rest_roll.text = "히트 다이스 굴리기 (Y / Enter)"
	rest_roll.focus_mode = Control.FOCUS_NONE
	rest_roll.pressed.connect(_rest_roll)
	row.add_child(rest_roll)
	var done := Button.new()
	done.text = "휴식 마치기 (B / Esc)"
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
	var lines := PackedStringArray()
	lines.append("[b]탐험 중[/b]  %d층 · 시드 %d · 저장 %d층" % [floor_no, dungeon.seed_used, int(save.get("floor", floor_no))])
	for h in party():
		lines.append(_member_line(h))
	lines.append("금화 %d · 물약 %d · 남은 몬스터 방 %d" % [gold, hero.potions(), left])
	if from_outside:
		for q in Game.quests:
			if q.state == "active" and q.kind != "group":
				lines.append("[color=#fd8]의뢰: %s[/color]%s" % [q.title, " [color=gray](%d층)[/color]" % q.floor if int(q.floor) != floor_no else " [color=#fd8]← 이 층[/color]"])
			elif q.state == "done" and q.kind != "group":
				lines.append("[color=#9f9]의뢰 끝: %s[/color]" % q.title)
	lines.append("[color=#6af]●[/color] 시작 · 계단=출구 · 상자 · 모닥불 · 텐트=쉼터")
	info_label.text = "\n".join(lines)
	var members: Array = []
	for h in party():
		var st: CreatureStats = h.stats()
		var fx: Array = []
		if h.current_hp() * 2 <= h.max_hp():
			fx.append(["다침", "debuff", "HP가 절반 이하 — 모닥불이나 쉼터에서 쉬세요"])
		members.append({"key": h.cls, "name": "%s  %d레벨" % [h.display_name(), h.level()], "model": st.model,
			"weapon": st.weapon_model, "hp": h.current_hp(), "max_hp": h.max_hp(), "effects": fx})
	party_panel.show_members(members)
	var here := dungeon.room_at(explorer.cell) if explorer else -1
	if here < 0:
		room_label.text = "[color=gray]통로[/color]"
	else:
		var r: Dictionary = dungeon.rooms[here]
		var th: String = ROOM_THEME_NAMES.get(r.get("theme", ""), "")
		room_label.text = "%s %d%s%s" % [KIND_NAMES[r.kind], here, (" · " + th) if th != "" else "", "  [color=#6d6]정리함 ✓[/color]" if cleared.has(here) else ""]


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



# --- 저장 파일 (Game.snapshot / restore) ---

## 탐험 상태를 처음으로 (새 게임)
static func reset_run() -> void:
	saved = null
	selected = -1
	cleared = {}
	exploring = false
	enter_seed = 0
	from_outside = false
	entry_floor = 1
	floor_memory = {}
	_arrive_down = false
	explore_cell = Vector2i(-1, -1)
	retreat_cell = Vector2i(-1, -1)
	opened = {}
	floor_no = 1
	save = {}
	rested_here = false
	used_fires = {}
	seen = {}
	_pending_toast = ""


## 던전 탐험 상태를 값만 담은 사전으로
static func run_state() -> Dictionary:
	var v = _view.get_ref() if _view else null
	if v and is_instance_valid(v) and v.explorer and v.exploring:
		explore_cell = v.explorer.cell
		saved = v.params
	var mem := {}
	for f in floor_memory:
		var m: Dictionary = floor_memory[f].duplicate()
		m.params = (m.params as DungeonParams).to_dict()
		mem[f] = m
	var sv := {}
	if not save.is_empty():
		sv = {"params": (save.params as DungeonParams).to_dict(), "floor": save.floor, "hero": (save.hero as HeroState).to_dict(),
				"ally": (save.ally as HeroState).to_dict() if save.get("ally") else {}, "gold": save.gold, "rested": save.rested}
	return {"params": saved.to_dict() if saved else {}, "cleared": cleared.duplicate(), "exploring": exploring,
			"from_outside": from_outside, "entry_floor": entry_floor, "floor_memory": mem, "explore_cell": explore_cell,
			"opened": opened.duplicate(), "floor_no": floor_no, "save": sv, "rested_here": rested_here,
			"used_fires": used_fires.duplicate(), "seen": seen.duplicate()}


static func restore_run(d: Dictionary) -> void:
	reset_run()
	if not (d.get("params", {}) as Dictionary).is_empty():
		saved = DungeonParams.from_dict(d.params)
	cleared = (d.get("cleared", {}) as Dictionary).duplicate()
	exploring = bool(d.get("exploring", false))
	from_outside = bool(d.get("from_outside", false))
	entry_floor = int(d.get("entry_floor", 1))
	for f in d.get("floor_memory", {}):
		var m: Dictionary = (d.floor_memory[f] as Dictionary).duplicate()
		m.params = DungeonParams.from_dict(m.params)
		floor_memory[f] = m
	explore_cell = d.get("explore_cell", Vector2i(-1, -1))
	opened = (d.get("opened", {}) as Dictionary).duplicate()
	floor_no = int(d.get("floor_no", 1))
	var sv: Dictionary = d.get("save", {})
	if not sv.is_empty():
		save = {"params": DungeonParams.from_dict(sv.params), "floor": sv.floor, "hero": HeroState.from_dict(sv.hero),
				"ally": HeroState.from_dict(sv.ally) if not (sv.ally as Dictionary).is_empty() else null, "gold": sv.gold, "rested": sv.rested}
	rested_here = bool(d.get("rested_here", false))
	used_fires = (d.get("used_fires", {}) as Dictionary).duplicate()
	seen = (d.get("seen", {}) as Dictionary).duplicate()
	_pending_toast = "이어서 합니다 — %d층" % floor_no


## 이 층 시작 칸이 바깥으로 나가는 출구인가 (바깥 입구로 들어와 아직 그 층)
func _outside_exit_here() -> bool:
	return from_outside and floor_no == entry_floor


## 이 층 시작 칸이 위층으로 오르는 계단인가 (탐험을 시작한 층보다 깊음)
func _up_stairs_here() -> bool:
	return floor_no > entry_floor


## 들어온 바깥 지형의 입구 앞으로 (main.gd가 같은 시드로 지형을 다시 만듦)
func _go_outside() -> void:
	Sfx.play(self, "stairs")
	from_outside = false
	exploring = false
	Game.place = "outside"
	get_tree().change_scene_to_file("res://scenes/main.tscn")
