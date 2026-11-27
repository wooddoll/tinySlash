## 시나리오(데이터로 만든 모험) 탐험 화면. 규칙과 진행은 rules/scenario.gd가 하고,
## 여기서는 집을 3D로 그리고, 걸어 다니게 하고, 글·문서·대화 창을 보여 줍니다.
## F: 조사·문 열기·말 걸기 · R: 방 수색 · J: 일지 · Esc: 창 닫기 / 바깥으로
extends Node3D

const InputSetup = preload("res://scripts/input_setup.gd")
const Battle = preload("res://scripts/battle.gd")
const Kenney = preload("res://scripts/kenney.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const Explorer = preload("res://scripts/dungeon_explorer.gd")
const Sfx = preload("res://scripts/sfx.gd")
const PartyPanel = preload("res://scripts/party_panel.gd")
const LevelUpDialog = preload("res://scripts/level_up_dialog.gd")
const ActionLayer = preload("res://scripts/action_layer.gd")
const HELP_EXPLORE := "WASD: 이동 · F: 조사/문/대화 · R: 방 수색 · J: 일지 · Q/E: 카메라 회전 · 휠: 줌 · Esc: 바깥으로"
const HELP_FIGHT := "이동: 왼쪽 스틱/WASD · 공격: X/J (누르고 있으면 계속) · 구르기: A/Space · 기술: B/K · 물약: 십자↑/1 · 카메라: LB·RB/Q·E"

const SCENE := "res://scenes/scenario.tscn"

## 전투에 다녀와도 이어지도록 장면 밖에 보관
static var scn: Scenario = null
## 지금 시나리오 팩의 scenario.json 경로. 비어 있으면 시작할 때 고름
##   (명령줄 -- --scenario=<폴더 또는 scenario.json> 으로도 지정)
static var file := ""
## 방에 들어서기 직전 칸 (전투에서 도망치면 여기로)
static var retreat := Vector2i(-1, -1)

@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var world: Node3D
var explorer: Explorer
var follower: CharacterModel
var torch: OmniLight3D
var _trail: Array[Vector3] = []
var _fog := {}  # 칸 -> [항목]
var _shown := {}  # 안개를 걷은 칸
var _busy := false  # 전투 중
## 실시간 액션 전투 (전투 중에만). members: scn.heroes와 같은 순서의 Actor
var action: ActionLayer
var members: Array = []
var _fight_group := ""
## 표식 키 → 서 있는 몬스터 모델 (전투가 시작되면 액션 전투 몬스터로 바꿈)
var _foe_nodes := {}
## 레벨업 고르기 창과, 고를 것이 남았는지 다시 볼 때까지 남은 시간
var level_dialog: LevelUpDialog
var _level_poll := 0.0
var _prompt_key := ""

# UI
var party_panel: PartyPanel
var info_label: RichTextLabel
var prompt_label: Label
var help_label: Label
var log_box: RichTextLabel
var _log_lines := PackedStringArray()
var msg_panel: PanelContainer
var msg_title: Label
var msg_text: RichTextLabel
var msg_hint: Label
var choice_box: VBoxContainer
var doc_panel: PanelContainer
var doc_title: Label
var doc_text: RichTextLabel
var journal_panel: PanelContainer
var journal_list: VBoxContainer
var end_panel: PanelContainer
var end_title: Label
var end_text: RichTextLabel
var _end_result := ""
var _choices: Array = []


func _ready() -> void:
	InputSetup.register()
	if scn == null:
		var path := _pick_path()
		if path == "":
			_show_picker()
			return
		if not _open_pack(path):
			return
	_start()


## 고를 필요 없이 정해지는 팩 경로: 명령줄 > 지난번 팩 > 팩이 하나뿐이면 그것. 아니면 ""
func _pick_path() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i].begins_with("--scenario="):
			return args[i].trim_prefix("--scenario=")
		if args[i] == "--scenario" and i + 1 < args.size():
			return args[i + 1]
	if file != "":
		return file
	var packs := Scenario.list_packs()
	return str(packs[0].path) if packs.size() == 1 else ""


func _open_pack(path: String) -> bool:
	scn = Scenario.load_pack(path)
	if scn == null:
		file = ""
		_show_picker("시나리오를 읽을 수 없습니다: " + path)
		return false
	file = path
	scn.new_game()
	return true


## 시나리오 고르기 창 (팩이 여럿이거나 읽기에 실패했을 때)
func _show_picker(error := "") -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.07, 0.09, 0.95)))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := Label.new()
	head.text = "시나리오 고르기"
	head.add_theme_font_size_override("font_size", 24)
	box.add_child(head)
	if error != "":
		var err := Label.new()
		err.text = error
		err.modulate = Color(1, 0.5, 0.45)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(err)
	# 파티 고르기: 비워 두면(시나리오 기본) 시나리오 파일의 파티
	var party_row := HBoxContainer.new()
	var plbl := Label.new()
	plbl.text = "파티"
	party_row.add_child(plbl)
	var opts: Array[OptionButton] = []
	for i in 2:
		var o := OptionButton.new()
		o.add_item("시나리오 기본")
		for cls in Catalog.CLASSES:
			o.add_item(HeroState.NAMES[cls])
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Scenario.party_override.size() == 2:
			o.selected = Catalog.CLASSES.find(Scenario.party_override[i]) + 1
		o.item_selected.connect(func(k: int) -> void:
			if k == 0:
				Scenario.party_override = []
			else:
				if Scenario.party_override.size() != 2:
					Scenario.party_override = HeroState.party_classes.duplicate()
				Scenario.party_override[i] = Catalog.CLASSES[k - 1]
				HeroState.party_classes = Scenario.party_override.duplicate()
			for j in opts.size():
				opts[j].selected = 0 if Scenario.party_override.is_empty() else Catalog.CLASSES.find(Scenario.party_override[j]) + 1)
		opts.append(o)
		party_row.add_child(o)
	box.add_child(party_row)
	var packs := Scenario.list_packs()
	if packs.is_empty():
		var none := Label.new()
		none.text = "scenarios/ 또는 user://scenarios/ 에 시나리오 폴더(scenario.json)가 없습니다."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(none)
	for i in packs.size():
		var p: Dictionary = packs[i]
		var b := Button.new()
		b.text = "%d. %s%s\n%s" % [i + 1, p.title, ("  v" + p.version) if p.version != "" else "", p.description]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(520, 0)
		b.pressed.connect(func():
			layer.queue_free()
			if _open_pack(str(p.path)):
				_start())
		box.add_child(b)
	var back := Button.new()
	back.text = "나가기"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	box.add_child(back)
	Sfx.wire_buttons(layer)


func _start() -> void:
	_build_ui()
	for e in scn.errors:
		_log("[color=orange]시나리오 파일 문제: %s[/color]" % e)
	Sfx.wire_buttons(self)
	_take_battle_result()
	_build_world()
	_place_party(scn.cell)
	_refresh_info()
	_pump()


func _take_battle_result() -> void:
	if not Battle.custom.has("group"):
		Battle.custom = {}
		return
	var g := str(Battle.custom.group)
	var result := str(Battle.custom.get("result", ""))
	Battle.custom = {}
	scn.battle_result(g, result, retreat if retreat.x >= 0 else scn.cell)


# =====================================================================
# 3D
# =====================================================================

func _build_world() -> void:
	if world:
		world.queue_free()
	_fog.clear()
	_shown.clear()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var d := scn.dungeon()
	var cave := scn.level_style() == "cave"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(scn.level)
	var floors: Array = []
	var model_xf := {}
	var add := func(model: String, xf: Transform3D, c: Vector2i) -> void:
		if not model_xf.has(model):
			model_xf[model] = []
		model_xf[model].append([xf, c])
	var spin := func() -> Basis:
		return Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0)
	var bases: Array = []
	for y in d.height:
		for x in d.width:
			var c := Vector2i(x, y)
			if not _is_floor(c):
				continue
			floors.append(c)
			var pos := _top(c)
			var h := d.get_height(c)
			if h > 0.0:
				bases.append([Transform3D(Basis.from_scale(Vector3(1, h, 1)), pos - Vector3(0, h / 2.0, 0)), c])
			if cave:
				add.call(Kenney.pick(Kenney.CAVE_FLOORS, c), Transform3D(spin.call(), pos), c)
			else:
				add.call(Kenney.pick(Kenney.FLOOR_DETAILS, c) if rng.randf() < 0.12 else "floor", Transform3D(spin.call(), pos), c)
			if d.difficult.has(c) and not scn.water[scn.level].has(c):
				if true:
					add.call("nature-kit/" + Kenney.pick(Kenney.CAVE_RUBBLE, c) if cave else "stones", Transform3D(spin.call(), pos), c)
			if d.obstacles.has(c):
				if d.obstacles[c] >= 2.0:
					if cave:
						add.call("nature-kit/" + Kenney.pick(Kenney.CAVE_PILLARS, c), Transform3D(spin.call() * Basis.from_scale(Vector3(1.0, 1.7, 1.0)), pos), c)
					else:
						add.call("column", Transform3D(Basis.IDENTITY, pos), c)
				else:
					var furn := ["table", "barrel", "chair", "pot"]
					if cave:
						add.call("nature-kit/" + Kenney.pick(Kenney.CAVE_ROCKS, c), Transform3D(spin.call() * Basis.from_scale(Vector3(1.0, 2.6, 1.0)), pos), c)
					else:
						add.call(Kenney.pick(furn, c), Transform3D(spin.call(), pos), c)
	if not bases.is_empty():
		var bm := MultiMesh.new()
		bm.transform_format = MultiMesh.TRANSFORM_3D
		bm.mesh = BoxMesh.new()
		bm.instance_count = bases.size()
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = bm
		inst.material_override = _mat(Color(0.35, 0.3, 0.3))
		world.add_child(inst)
		for i in bases.size():
			bm.set_instance_transform(i, bases[i][0])
			_fog_add(bases[i][1], [bm, i, bases[i][0]])
	for part in Kenney.build_edge_walls(world, floors, _is_floor, d.get_height, cave):
		for i in (part[1] as Array).size():
			_fog_add(part[1][i], [part[0], i, part[2][i]])
	var marked: Dictionary = scn.mark_at[scn.level]
	var water: Dictionary = scn.water[scn.level]
	var deco := Kenney.decorate(world, floors, _is_floor, d.get_height, cave,
			func(c: Vector2i) -> bool: return marked.has(c) or water.has(c) or d.obstacles.has(c) or d.difficult.has(c))
	for part in deco.parts:
		for i in (part[1] as Array).size():
			_fog_add(part[1][i], [part[0], i, part[2][i]])
	for l in deco.lights:
		_fog_add(l[1], [l[0]])
	for model in model_xf:
		var parts: PackedStringArray = model.split("/")
		var m := Kenney.mesh(parts[-1], parts[0] if parts.size() > 1 else Kenney.DUNGEON)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		var list: Array = model_xf[model]
		mm.instance_count = list.size()
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		world.add_child(inst)
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			_fog_add(list[i][1], [mm, i, list[i][0]])
	_build_marks()
	_build_water()
	_apply_fog()


## 물 칸 (~): 반투명 파란 판
func _build_water() -> void:
	var lv: Dictionary = scn.data.levels[scn.level]
	var rows: Array = lv.map
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var c := Vector2i(x, y)
			if not scn.water[scn.level].has(c):
				continue
			var p := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(1, 1)
			p.mesh = pm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.12, 0.22, 0.3, 0.75)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.3
			mat.roughness = 0.15
			p.material_override = mat
			p.position = _top(c) + Vector3(0, 0.12, 0)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(p)
			_fog_add(c, [p])


func _build_marks() -> void:
	var d := scn.dungeon()
	for key in scn.marks:
		var m: Dictionary = scn.marks[key]
		if m.level != scn.level or not scn.active(key):
			continue
		var c: Vector2i = m.cell
		match m.type:
			"door":
				if not scn.is_open(key):
					_fog_add(c, [_door_slab(c, scn.is_locked(key))])
			"secret":
				if scn.revealed.has(key) and not scn.opened.has(key):
					_fog_add(c, [_door_slab(c, false, true)])
			"stairs":
				var st := Kenney.instance(str(m.get("model_name", "stairs")))
				st.position = _top(c)
				st.rotation.y = deg_to_rad(float(m.get("rot", 0)))
				world.add_child(st)
				_fog_add(c, [st])
				_fog_add(c, [_label(c, "▼" if str(m.get("dir", "down")) == "down" else "▲", Color(0.7, 0.9, 1.0))])
			"exit":
				_fog_add(c, [_disc(c, Color(1.0, 0.85, 0.3))])
			"trap":
				if scn.revealed.has(key):
					var t := Kenney.instance("trap")
					t.position = _top(c)
					world.add_child(t)
					_fog_add(c, [t])
			"foe":
				var g := str(m.get("group", ""))
				if scn.cleared.has(g) or not scn.group_active(g) or bool(m.get("hidden", false)):
					continue
				var st2 := scn.monster_stats(str(m.monster))
				var cm := CharacterModel.new()
				world.add_child(cm)
				cm.setup(st2.model, st2.sprite_scale, st2.weapon_model)
				if st2.has_feature("flying"):
					cm.set_hover(0.9)
				cm.position = _top(c)
				cm.face(Vector3(float(m.get("fx", 0)), 0, float(m.get("fy", 1))), true)
				if m.has("pose"):
					cm.hold(str(m.pose))
				cm.tint(st2.tint)
				_fog_add(c, [cm])
				_foe_nodes[key] = cm
			"npc":
				if scn.hidden(key):
					continue
				var cm2 := CharacterModel.new()
				world.add_child(cm2)
				cm2.setup(str(m.get("model", "mini-characters/character-female-c")), float(m.get("scale", 1.0)))
				cm2.position = _top(c) + Vector3(0, float(m.get("lift", 0.0)), 0)
				cm2.face(Vector3(float(m.get("fx", 0)), 0, float(m.get("fy", 1))), true)
				if bool(m.get("ghost", true)):
					_ghostify(cm2)
				_fog_add(c, [cm2])
				_fog_add(c, [_label(c, "…", Color(0.7, 0.9, 1.0), 2.0)])
			"feature":
				if scn.hidden(key):
					continue
				if m.has("model"):
					var mp: PackedStringArray = str(m.model).split("/")
					var n := Kenney.instance(mp[1], mp[0]) if mp.size() > 1 else Kenney.instance(mp[0])
					n.position = _top(c)
					n.rotation.y = deg_to_rad(float(m.get("rot", 0)))
					n.scale = Vector3.ONE * float(m.get("scale", 1.0))
					world.add_child(n)
					_fog_add(c, [n])
				if not (bool(m.get("once", false)) and scn.used.has(key)) and not bool(m.get("quiet", false)):
					_fog_add(c, [_label(c, "?", Color(1.0, 0.85, 0.35), 1.4)])
	# 비밀문을 찾아 열면 그 칸은 바닥 (벽판은 _is_floor가 처리)
	if d == null:
		return


## 비밀문은 찾아서 열기 전까지 벽으로 그림
func _is_floor(c: Vector2i) -> bool:
	if not scn.dungeon().is_floor(c):
		return false
	var key: String = scn.mark_at[scn.level].get(c, "")
	if key != "" and scn.marks[key].type == "secret" and not scn.opened.has(key):
		return scn.revealed.has(key)  # 찾았으면 문짝으로 보이게 바닥 취급
	return true


## 닫힌 문 (KayKit 문틀과 문짝). 드러난 비밀문은 금 간 벽. 잠긴 문에는 금빛 손잡이
func _door_slab(c: Vector2i, locked: bool, secret := false) -> Node3D:
	var d := scn.dungeon()
	var horizontal := not d.is_floor(c + Vector2i(1, 0)) and not d.is_floor(c + Vector2i(-1, 0))
	var n := Kenney.instance("wall-cracked" if secret else "door")
	n.position = _top(c)
	n.rotation.y = 0.0 if horizontal else PI / 2.0
	world.add_child(n)
	if locked:
		for z in [-0.1, 0.1]:
			var knob := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.05
			sm.height = 0.1
			knob.mesh = sm
			knob.material_override = _mat(Color(0.9, 0.75, 0.3), true)
			knob.position = Vector3(0.05, 0.42, z)
			n.add_child(knob)
	return n


func _label(c: Vector2i, text: String, col: Color, y := 1.6) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.012
	l.outline_size = 14
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = _top(c) + Vector3(0, y, 0)
	world.add_child(l)
	return l


func _disc(c: Vector2i, col: Color) -> Node3D:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = 0.06
	disc.mesh = cm
	disc.material_override = _mat(col, true)
	disc.position = _top(c) + Vector3(0, 0.03, 0)
	world.add_child(disc)
	return disc


func _ghostify(n: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.8
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _top(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, scn.dungeon().get_height(c), c.y + 0.5)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.5
	return m


# --- 안개: 본 칸만 보임 ---

func _fog_add(c: Vector2i, entry: Array) -> void:
	if not _fog.has(c):
		_fog[c] = []
	_fog[c].append(entry)
	if entry.size() == 1:
		(entry[0] as Node3D).visible = false
	else:
		var xf: Transform3D = entry[2]
		(entry[0] as MultiMesh).set_instance_transform(entry[1], Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))


func _fog_show(entry: Array) -> void:
	if entry.size() == 1:
		(entry[0] as Node3D).visible = true
	else:
		(entry[0] as MultiMesh).set_instance_transform(entry[1], entry[2])


func _apply_fog() -> void:
	for c in scn.seen.get(scn.level, {}):
		if _shown.has(c):
			continue
		_shown[c] = true
		for e in _fog.get(c, []):
			_fog_show(e)


# =====================================================================
# 파티
# =====================================================================

func _place_party(at: Vector2i) -> void:
	if explorer:
		explorer.queue_free()
	if follower:
		follower.queue_free()
	var lead: HeroState = scn.heroes[0]
	explorer = Explorer.new()
	add_child(explorer)
	explorer.setup(scn.dungeon(), at, lead.stats().model, lead.stats().weapon_model)
	explorer.camera_rig = rig
	explorer.blocked = scn.blocked()
	explorer.entered_cell.connect(_on_entered_cell)
	rig.target = explorer
	rig.ortho_size = 11.0
	torch = OmniLight3D.new()
	torch.light_color = Color(1.0, 0.78, 0.5)
	torch.light_energy = 2.2
	torch.omni_range = 7.5
	torch.shadow_enabled = true
	torch.position = Vector3(0, 1.6, 0)
	explorer.add_child(torch)
	if scn.heroes.size() > 1:
		follower = CharacterModel.new()
		add_child(follower)
		var st: CreatureStats = (scn.heroes[1] as HeroState).stats()
		follower.setup(st.model, 1.0, st.weapon_model)
		follower.position = explorer.position
		_trail = [explorer.position]
	scn.cell = at
	scn.on_arrived()
	_apply_fog()


func _on_entered_cell(from: Vector2i, to: Vector2i) -> void:
	if _busy:
		return
	if scn.room_of(scn.level, to) != scn.room_key:
		retreat = from
	scn.enter_cell(from, to)
	_apply_fog()
	_refresh_info()
	_pump()


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


# =====================================================================
# 결과 처리
# =====================================================================

func _blocking() -> bool:
	return msg_panel.visible or doc_panel.visible or end_panel.visible or journal_panel.visible or _busy 		or (level_dialog != null and level_dialog.visible)


## scn.out을 앞에서부터 처리. 창을 띄우는 결과에서 멈추고, 창을 닫으면 다시 부름
func _pump() -> void:
	while not _blocking() and not scn.out.is_empty():
		var o: Dictionary = scn.out.pop_front()
		match str(o.type):
			"text":
				_show_msg(str(o.title), str(o.text))
			"doc":
				_show_doc(str(o.title), str(o.text))
			"dialogue":
				_show_dialogue(o)
			"dialogue_end":
				pass
			"toast":
				_log(str(o.text))
			"refresh":
				_rebuild_keep()
			"level":
				Sfx.play(self, "stairs")
				_build_world()
				if bool(o.get("changed", false)) and bool((scn.data.levels[scn.level] as Dictionary).get("checkpoint", true)):
					scn.save_checkpoint()
				_place_party(o.cell)
			"battle":
				_start_battle(str(o.group))
			"end":
				_show_end(o)
	if explorer:
		explorer.active = not _blocking()
	_refresh_info()


func _rebuild_keep() -> void:
	# 같은 층을 다시 그리고 플레이어는 그 자리에
	_build_world()
	if explorer:
		explorer.blocked = scn.blocked()
	_apply_fog()


## 그 자리에서 실시간 액션 전투 (docs/rules.md 10장). 끝나면 scn.battle_result로 결과를 넘김
func _start_battle(g: String) -> void:
	_busy = true
	if explorer:
		explorer.active = false
	var gd := scn.group_def(g)
	_log("[color=#f88]전투![/color] " + str(gd.get("label", g)))
	Sfx.play(self, "alert")
	await get_tree().create_timer(0.4).timeout
	_fight_group = g
	var d := scn.dungeon()
	var fs := scn.foes_of(g)
	var blk: Dictionary = scn.blocked().duplicate()
	for f in fs:
		blk.erase(f.cell)
	action = ActionLayer.new()
	world.add_child(action)
	action.camera_rig = rig
	action.setup(d, blk)
	members.clear()
	for i in scn.heroes.size():
		var h: HeroState = scn.heroes[i]
		var cell := explorer.cell
		if i > 0:
			cell = _free_near(_cell_of(follower.position) if follower else explorer.cell, blk)
		members.append(action.add_member(h.make_creature(), cell, "player" if i == 0 else "ally", explorer.body if i == 0 else null))
	if follower:
		follower.visible = false
	members[0].pos = Vector2(explorer.position.x, explorer.position.z)
	explorer.actor = members[0]
	for f in fs:
		var key := _mark_key(f)
		if _foe_nodes.has(key) and is_instance_valid(_foe_nodes[key]):
			(_foe_nodes[key] as Node3D).queue_free()
		_foe_nodes.erase(key)
		var m: Node3D = action.add_foe(str(f.monster), f.cell, -1, scn.monster_stats(str(f.monster)))
		m.visible = true
	action.ac.wake_room(-1)
	# 기습: 1 = 적이 기습당함(1.5초 굳음), 0 = 파티가 기습당함(1초 굳음)
	var surprised := int(scn.battle_setup(g).get("surprised", -1))
	for a in action.ac.actors:
		if (surprised == 1 and a.brain == "monster") or (surprised == 0 and a.brain != "monster"):
			a.state = "stun"
			a.t = 1.5 if surprised == 1 else 1.0
	if surprised == 1:
		_log("적이 기습당했다!")
	elif surprised == 0:
		_log("기습당했다!")
	action.message.connect(_log)
	help_label.text = HELP_FIGHT
	action.party_changed.connect(_party_from_action)
	action.fight_over.connect(func(xp: int) -> void: _end_fight("win", xp))
	action.defeated.connect(func() -> void: _end_fight("lose", 0))


func _mark_key(f: Dictionary) -> String:
	for k in scn.marks:
		if scn.marks[k] == f:
			return k
	return ""


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


## c(또는 그 옆)의 서 있을 수 있는 빈 칸
func _free_near(c: Vector2i, blk: Dictionary) -> Vector2i:
	var d := scn.dungeon()
	if d.is_walkable(c) and not blk.has(c) and c != explorer.cell:
		return c
	for dir in Dungeon.DIRS8:
		var n: Vector2i = c + dir
		if d.is_walkable(n) and not blk.has(n) and n != explorer.cell:
			return n
	return c


## 전투 중 크리처 상태를 HeroState에 담아 화면 정보를 고침
func _party_from_action() -> void:
	for i in mini(scn.heroes.size(), members.size()):
		var h: HeroState = scn.heroes[i]
		var c: Creature = members[i].c
		h.hp = maxi(c.hp, 0)
		h.resources = c.resources.duplicate()
	_refresh_info()


func _end_fight(result: String, xp: int) -> void:
	if action == null:
		return
	var g := _fight_group
	if result == "win":
		var share := xp / maxi(scn.heroes.size(), 1)
		var level_up := 0
		for i in mini(scn.heroes.size(), members.size()):
			var up: Dictionary = (scn.heroes[i] as HeroState).absorb(members[i].c, share)
			if up.has("level_up"):
				level_up = up.level_up
		_log("전투 끝! XP +%d씩%s" % [share, ("  — 레벨 업! %d레벨" % level_up) if level_up > 0 else ""])
		Sfx.play(self, "level_up" if level_up > 0 else "win")
	else:
		_log("[color=#f88]파티가 모두 쓰러졌다…[/color]")
		Sfx.play(self, "lose")
	var layer := action
	action = null
	await get_tree().create_timer(1.0 if result == "win" else 2.0).timeout
	# 액션 화면을 걷고 탐험으로 돌아감
	var ally_pos := Vector3.ZERO
	if members.size() > 1 and layer.views.has(members[1]):
		ally_pos = (layer.views[members[1]].model as Node3D).position
	layer.release_model(members[0])
	explorer.actor = null
	explorer.body.set_base("idle")
	if follower:
		follower.visible = true
		if ally_pos != Vector3.ZERO:
			follower.position = ally_pos
		_trail = [explorer.position]
	layer.queue_free()
	members.clear()
	_fight_group = ""
	scn.cell = explorer.cell
	scn.room_key = scn.room_of(scn.level, explorer.cell)
	_busy = false
	help_label.text = HELP_EXPLORE
	scn.battle_result(g, result, scn.cell)
	_pump()


# =====================================================================
# 입력
# =====================================================================

func _process(delta: float) -> void:
	if log_box == null:
		return  # 시나리오 고르는 중
	_level_poll -= delta
	if _level_poll <= 0.0 and level_dialog != null and not _blocking():
		_level_poll = 0.5
		if level_dialog.open(scn.heroes):
			if explorer:
				explorer.active = false
	_update_follower(delta)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if log_box == null:
		if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = (event as InputEventKey).physical_keycode
	if end_panel.visible:
		return
	if msg_panel.visible and choice_box.get_child_count() > 0:
		if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < _choices.size():
			_pick_choice(key - KEY_1)
		return
	if msg_panel.visible:
		if key in [KEY_SPACE, KEY_F, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			_close_msg()
		return
	if doc_panel.visible:
		if key in [KEY_SPACE, KEY_F, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_J]:
			doc_panel.visible = false
			Sfx.play(self, "close")
			_pump()
		return
	if journal_panel.visible:
		if key in [KEY_ESCAPE, KEY_J]:
			journal_panel.visible = false
			_pump()
		return
	if _busy:
		return
	match key:
		KEY_F:
			if _prompt_key != "":
				Sfx.play(self, "click")
				scn.interact(_prompt_key)
				_pump()
		KEY_R:
			Sfx.play(self, "dice")
			scn.search()
			_pump()
		KEY_J:
			_open_journal()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _update_prompt() -> void:
	if explorer == null or _blocking():
		prompt_label.visible = false
		return
	var k := scn.interactable_near(explorer.cell)
	_prompt_key = k
	prompt_label.visible = k != ""
	if k != "":
		prompt_label.text = "F: " + scn.prompt(k)


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
	level_dialog.finished.connect(_pump)
	party_panel = PartyPanel.new()
	party_panel.position = Vector2(12, 12)
	layer.add_child(party_panel)

	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _style(Color(0.06, 0.06, 0.08, 0.78)))
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -330
	info.offset_top = 12
	info.offset_right = -12
	layer.add_child(info)
	info_label = _rich(info, 14)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.offset_top = -210
	log_box.offset_bottom = -40
	log_box.offset_left = 12
	log_box.offset_right = 520
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_font_size_override("normal_font_size", 14)
	log_box.add_theme_constant_override("outline_size", 5)
	log_box.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(log_box)

	prompt_label = Label.new()
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_top = -90
	prompt_label.offset_bottom = -60
	prompt_label.offset_left = -300
	prompt_label.offset_right = 300
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	prompt_label.add_theme_constant_override("outline_size", 8)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(prompt_label)

	help_label = Label.new()
	help_label.text = HELP_EXPLORE
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -30
	help_label.offset_left = 12
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_constant_override("outline_size", 6)
	help_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(help_label)

	# 글·대화 창
	msg_panel = PanelContainer.new()
	msg_panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.07, 0.94), Color(0.55, 0.45, 0.3)))
	msg_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	msg_panel.offset_left = -380
	msg_panel.offset_right = 380
	# 화면 아래쪽: 가운데에 선 파티를 가리지 않게
	msg_panel.offset_top = -270
	msg_panel.offset_bottom = -34
	msg_panel.visible = false
	layer.add_child(msg_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	msg_panel.add_child(mv)
	msg_title = Label.new()
	msg_title.add_theme_font_size_override("font_size", 20)
	msg_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	mv.add_child(msg_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 96
	mv.add_child(sc)
	msg_text = RichTextLabel.new()
	msg_text.bbcode_enabled = true
	msg_text.fit_content = true
	msg_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_text.add_theme_font_size_override("normal_font_size", 17)
	msg_text.add_theme_font_size_override("bold_font_size", 17)
	sc.add_child(msg_text)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 4)
	mv.add_child(choice_box)
	msg_hint = Label.new()
	msg_hint.text = "Space / F: 계속"
	msg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	msg_hint.add_theme_font_size_override("font_size", 13)
	msg_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	mv.add_child(msg_hint)

	# 문서 (편지, 일기)
	doc_panel = PanelContainer.new()
	doc_panel.add_theme_stylebox_override("panel", _style(Color(0.86, 0.8, 0.66, 0.98), Color(0.45, 0.33, 0.2), 24))
	doc_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	doc_panel.offset_left = -330
	doc_panel.offset_right = 330
	doc_panel.offset_top = -280
	doc_panel.offset_bottom = 280
	doc_panel.visible = false
	layer.add_child(doc_panel)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	doc_panel.add_child(dv)
	doc_title = Label.new()
	doc_title.add_theme_font_size_override("font_size", 22)
	doc_title.add_theme_color_override("font_color", Color(0.3, 0.18, 0.08))
	doc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(doc_title)
	var dsc := ScrollContainer.new()
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(dsc)
	doc_text = RichTextLabel.new()
	doc_text.bbcode_enabled = true
	doc_text.fit_content = true
	doc_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc_text.add_theme_color_override("default_color", Color(0.18, 0.12, 0.08))
	doc_text.add_theme_font_size_override("normal_font_size", 17)
	doc_text.add_theme_font_size_override("italics_font_size", 17)
	dsc.add_child(doc_text)
	var dh := Label.new()
	dh.text = "Space: 닫기 · J: 일지에서 다시 읽기"
	dh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dh.add_theme_font_size_override("font_size", 13)
	dh.add_theme_color_override("font_color", Color(0.4, 0.3, 0.2))
	dv.add_child(dh)

	# 일지
	journal_panel = PanelContainer.new()
	journal_panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.06, 0.08, 0.95), Color(0.55, 0.45, 0.3)))
	journal_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	journal_panel.offset_left = -300
	journal_panel.offset_right = 300
	journal_panel.offset_top = -260
	journal_panel.offset_bottom = 260
	journal_panel.visible = false
	layer.add_child(journal_panel)
	var jsc := ScrollContainer.new()
	jsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_panel.add_child(jsc)
	journal_list = VBoxContainer.new()
	journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_list.add_theme_constant_override("separation", 6)
	jsc.add_child(journal_list)

	# 끝 / 패배
	end_panel = PanelContainer.new()
	end_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.04, 0.06, 0.96), Color(0.6, 0.5, 0.3), 24))
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -320
	end_panel.offset_right = 320
	end_panel.offset_top = -200
	end_panel.offset_bottom = 200
	end_panel.visible = false
	layer.add_child(end_panel)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 12)
	end_panel.add_child(ev)
	end_title = Label.new()
	end_title.add_theme_font_size_override("font_size", 30)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(end_title)
	end_text = RichTextLabel.new()
	end_text.bbcode_enabled = true
	end_text.fit_content = true
	end_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	end_text.add_theme_font_size_override("normal_font_size", 17)
	ev.add_child(end_text)
	var eb := HBoxContainer.new()
	eb.alignment = BoxContainer.ALIGNMENT_CENTER
	eb.add_theme_constant_override("separation", 12)
	ev.add_child(eb)
	for spec in [["체크포인트에서 다시", "retry"], ["처음부터", "restart"], ["나가기", "quit"]]:
		var b := Button.new()
		b.text = spec[0]
		b.name = spec[1]
		var what: String = spec[1]
		b.pressed.connect(func() -> void: _end_choice(what))
		eb.add_child(b)


func _style(bg: Color, border := Color(0, 0, 0, 0), margin := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_content_margin_all(margin)
	if border.a > 0:
		s.set_border_width_all(2)
		s.border_color = border
	return s


func _rich(parent: Control, size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size.x = 290
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	parent.add_child(r)
	return r


func _show_msg(title: String, text: String) -> void:
	_clear_choices()
	msg_title.text = title
	msg_title.visible = title != ""
	msg_text.text = text
	msg_hint.text = "Space / F: 계속"
	msg_panel.offset_top = -350
	msg_panel.visible = true
	Sfx.play(self, "open")


func _close_msg() -> void:
	msg_panel.visible = false
	_pump()


func _show_dialogue(o: Dictionary) -> void:
	_clear_choices()
	msg_title.text = str(o.speaker)
	msg_title.visible = str(o.speaker) != ""
	msg_text.text = str(o.text)
	_choices = o.choices
	for i in _choices.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, _choices[i].text]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		b.pressed.connect(func() -> void: _pick_choice(idx))
		choice_box.add_child(b)
	msg_hint.text = "숫자 키나 클릭으로 고르기"
	# 선택지 수만큼 창을 키움 (본문 영역은 최소 96px)
	msg_panel.offset_top = -100 - (130 + 96 + 38 * _choices.size())
	msg_panel.visible = true


func _clear_choices() -> void:
	for ch in choice_box.get_children():
		choice_box.remove_child(ch)
		ch.queue_free()
	_choices = []


func _pick_choice(i: int) -> void:
	var idx := int(_choices[i].index)
	Sfx.play(self, "click")
	msg_panel.visible = false
	_clear_choices()
	scn.choose(idx)
	_pump()


func _show_doc(title: String, text: String) -> void:
	doc_title.text = title
	doc_text.text = "[i]%s[/i]" % text
	doc_panel.visible = true
	Sfx.play(self, "open")


func _open_journal() -> void:
	for ch in journal_list.get_children():
		ch.queue_free()
	var head := Label.new()
	head.text = "일지 — " + scn.title
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	journal_list.add_child(head)
	var it := PackedStringArray()
	for k in scn.items:
		it.append(str(scn.items[k].name) + (" ×%d" % int(scn.items[k].count) if int(scn.items[k].count) > 1 else ""))
	var inv := RichTextLabel.new()
	inv.bbcode_enabled = true
	inv.fit_content = true
	inv.text = "[b]소지품[/b]: %s\n[b]금화[/b]: %d" % [", ".join(it) if not it.is_empty() else "없음", scn.gold]
	journal_list.add_child(inv)
	var dl := Label.new()
	dl.text = "읽은 문서" if not scn.journal.is_empty() else "아직 읽은 문서가 없다"
	dl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	journal_list.add_child(dl)
	for j in scn.journal:
		var b := Button.new()
		b.text = str(j.title)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var t := str(j.title)
		var body := str(j.text)
		b.pressed.connect(func() -> void:
			journal_panel.visible = false
			_show_doc(t, body))
		journal_list.add_child(b)
	var close := Label.new()
	close.text = "J / Esc: 닫기"
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	journal_list.add_child(close)
	journal_panel.visible = true
	if explorer:
		explorer.active = false
	Sfx.play(self, "open")


func _show_end(o: Dictionary) -> void:
	_end_result = str(o.result)
	end_title.text = str(o.title)
	end_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45) if _end_result == "win" else Color(1.0, 0.45, 0.4))
	end_text.text = str(o.text)
	(end_panel.find_child("retry", true, false) as Button).visible = _end_result != "win"
	end_panel.visible = true
	Sfx.play(self, "win" if _end_result == "win" else "lose")


func _end_choice(what: String) -> void:
	end_panel.visible = false
	match what:
		"retry":
			scn.out.clear()
			scn.load_checkpoint()
			_build_world()
			_place_party(scn.cell)
			_log("체크포인트에서 다시 시작")
			_pump()
		"restart":
			scn = null
			get_tree().reload_current_scene()
		"quit":
			if _end_result == "win":
				scn = null
				file = ""  # 다음에는 시나리오를 다시 고름
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 30:
		_log_lines = _log_lines.slice(_log_lines.size() - 30)
	log_box.text = "\n".join(_log_lines)


func _refresh_info() -> void:
	if info_label == null or scn == null:
		return
	var rk := scn.room_key
	var lines := PackedStringArray()
	lines.append("[b][color=#ffd27a]%s[/color][/b]" % scn.title)
	lines.append("%s · %s" % [scn.level_name(), scn.room_name(rk) if rk != "" else "[color=gray]복도[/color]"])
	var pot := 0
	for h in scn.heroes:
		pot += (h as HeroState).potions()
	lines.append("금화 %d · 회복 물약 %d · 수동 지각 %d" % [scn.gold, pot, scn.passive_perception()])
	if rk != "" and scn.searched.has(rk):
		lines.append("[color=gray]이 방은 수색함[/color]")
	info_label.text = "\n".join(lines)
	var members: Array = []
	for h in scn.heroes:
		var hs: HeroState = h
		var st: CreatureStats = hs.stats()
		var fx: Array = []
		if hs.current_hp() * 2 <= hs.max_hp():
			fx.append(["다침", "debuff", "HP가 절반 이하"])
		if hs.max_hp_loss > 0:
			fx.append(["최대 HP -%d" % hs.max_hp_loss, "debuff", "스펙터에게 생명을 빼앗김 (긴 휴식으로 돌아옴)"])
		members.append({"key": hs.cls, "name": "%s  %d레벨" % [hs.display_name(), hs.level()], "model": st.model,
			"weapon": st.weapon_model, "hp": hs.current_hp(), "max_hp": hs.max_hp(), "effects": fx})
	party_panel.show_members(members)
