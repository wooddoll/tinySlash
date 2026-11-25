## 격자 턴제 전투 장면. 규칙은 rules/ 의 Combat이 처리하고,
## 여기서는 그 결과(event)를 순서대로 애니메이션으로 보여주고 플레이어 입력을 받습니다.
extends Node3D

const UnitView = preload("res://scripts/unit_view.gd")
const InputSetup = preload("res://scripts/input_setup.gd")
const Kenney = preload("res://scripts/kenney.gd")
const Sfx = preload("res://scripts/sfx.gd")

## . 평지  1/2/3 높이 0.5/1.0/1.5  , 험지(덤불)  T 나무(완전 엄폐)  # 바위(낮은 벽)
## 던전용: X 던전 벽(통과 불가, 완전 엄폐)  P 돌기둥(완전 엄폐)
const MAP := [
	"..............",
	"..T.....,,..T.",
	"......##......",
	"..............",
	".....222......",
	".....211......",
	"..T...........",
	"......,,......",
	"...#......T...",
	"..............",
]
const PC_START := Vector2i(2, 4)
const ENCOUNTERS := {
	"easy": {"label": "쉬움 — 고블린 졸개 2", "foes": [["goblin_minion", Vector2i(11, 6)], ["goblin_minion", Vector2i(12, 7)]]},
	"normal": {"label": "보통 — 고블린 전사 + 졸개 2", "foes": [["goblin_warrior", Vector2i(11, 4)], ["goblin_minion", Vector2i(10, 7)], ["goblin_minion", Vector2i(12, 6)]]},
	"hard": {"label": "어려움 — 늑대 2", "foes": [["wolf", Vector2i(11, 3)], ["wolf", Vector2i(11, 6)]]},
	"boss": {"label": "보스 — 고블린 대장 + 졸개 2", "foes": [["goblin_boss", Vector2i(11, 5)], ["goblin_minion", Vector2i(12, 4)], ["goblin_minion", Vector2i(12, 6)]]},
	"undead": {"label": "언데드 — 스켈레톤 2", "foes": [["skeleton", Vector2i(11, 2)], ["skeleton", Vector2i(11, 7)]]},
}
const ENCOUNTER_KEYS := {KEY_F1: "easy", KEY_F2: "normal", KEY_F3: "hard", KEY_F4: "boss", KEY_F5: "undead"}

static var encounter_id := "normal"
## 던전 생성기에서 넘겨준 전투 (Dungeon.battle_setup). 비어 있으면 기본 맵과 F1~F5 조우.
## 끝나면 custom["result"]에 "win" 또는 "lose"를 남깁니다.
static var custom := {}

@onready var focus: Node3D = $Focus
@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var grid: CombatGrid
var combat: Combat
var pc: Creature
var views := {}
var overlays := {}
var overlay_mats := {}
var queue: Array[Dictionary] = []
var busy := false
var dirty := true
var weapon_index := 0
var move_opts := {}
var move_reach := {}
var hover_cell := Vector2i(-1, -1)
var hover_creature: Creature = null

# UI
var order_label: RichTextLabel
var status_label: Label
var hint_label: Label
var log_box: RichTextLabel
var result_label: Label
var weapon_buttons: Array[Button] = []
var action_buttons := {}


func _ready() -> void:
	InputSetup.register()
	_build_world()
	_build_ui()
	_spawn_units()
	combat.event.connect(func(ev: Dictionary) -> void: queue.append(ev))
	_log("[color=gray]%s[/color]" % _encounter_label())
	Sfx.wire_buttons(self)
	Sfx.play(self, "fight")
	combat.start()


# =====================================================================
# 맵 만들기
# =====================================================================

func _map() -> Array:
	return custom.get("map", MAP)


func _encounter_label() -> String:
	return custom.label if _dungeon() else ENCOUNTERS[encounter_id].label


func _dungeon() -> bool:
	return custom.has("map")


func _build_world() -> void:
	var map := _map()
	var h := map.size()
	var w := (map[0] as String).length()
	grid = CombatGrid.new(w, h)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var mats := {
		"a": _mat(Color(0.37, 0.6, 0.31)), "b": _mat(Color(0.33, 0.55, 0.28)),
		"brush": _mat(Color(0.27, 0.43, 0.22)), "dirt": _mat(Color(0.56, 0.47, 0.33)),
		"stone": _mat(Color(0.6, 0.58, 0.55)),
		"wall": _mat(Color(0.3, 0.29, 0.33)),
		"cave": _mat(Color(0.4, 0.29, 0.24)),
	}
	if _dungeon():
		var env: Environment = $WorldEnvironment.environment.duplicate()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.06, 0.06, 0.08)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.55, 0.65)
		env.ambient_light_energy = 0.6
		$WorldEnvironment.environment = env
		mats["a"] = _mat(Color(0.47, 0.45, 0.43))
		mats["b"] = _mat(Color(0.43, 0.41, 0.4))
		mats["brush"] = _mat(Color(0.38, 0.33, 0.28))
		mats["dirt"] = _mat(Color(0.55, 0.52, 0.48))
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.9, 0.9)
	for key in ["move", "path", "danger", "target", "hover"]:
		overlay_mats[key] = _overlay_mat(key)

	for y in h:
		var row: String = map[y]
		for x in w:
			var ch := row[x]
			var cell := Vector2i(x, y)
			var th := 0.0
			match ch:
				"1": th = 0.5
				"2": th = 1.0
				"3": th = 1.5
			grid.heights[cell] = th
			if ch == ",":
				grid.difficult[cell] = true
			elif ch == "T":
				grid.walls[cell] = 3.0
			elif ch == "#":
				grid.walls[cell] = 1.0
			elif ch == "X" or ch == "P":
				grid.walls[cell] = 3.0
			if ch == "X":
				# 바닥과 맞닿은 벽만 그립니다 (안쪽 벽은 격자에만 있음)
				continue  # 벽은 아래에서 바닥 가장자리에 벽판으로 그림 (규칙상 높이는 3.0)

			var body := StaticBody3D.new()
			body.position = Vector3(x + 0.5, 0, y + 0.5)
			body.set_meta("cell", cell)
			var box := BoxMesh.new()
			var bh := th + 0.5
			box.size = Vector3(1, bh, 1)
			var mesh := MeshInstance3D.new()
			mesh.mesh = box
			mesh.position.y = th - bh / 2.0
			var mat_key := "a" if (x + y) % 2 == 0 else "b"
			if th > 0.0:
				mat_key = "dirt"
			elif ch == ",":
				mat_key = "brush"
			mesh.material_override = mats[mat_key]
			if _dungeon():
				mesh.material_override = mats["wall"]
				var yaw := ((x * 3 + y) % 4) * PI / 2.0
				if custom.get("style", "") == "cave":
					mesh.material_override = mats["cave"]
					_kenney(terrain, "template-floor", Vector3(x + 0.5, th + 0.002, y + 0.5), yaw, "modular-cave-kit", 0.25)
				else:
					var tile := "floor-detail" if (x * 7 + y * 13) % 9 == 0 else "floor"
					_kenney(terrain, tile, Vector3(x + 0.5, th + 0.002, y + 0.5), yaw)
			body.add_child(mesh)
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = box.size
			shape.shape = bs
			shape.position = mesh.position
			body.add_child(shape)
			terrain.add_child(body)

			var top := Vector3(x + 0.5, th, y + 0.5)
			var cave: bool = custom.get("style", "") == "cave"
			var turn := ((x * 5 + y * 3) % 4) * PI / 2.0
			if ch == "T":
				# 유닛을 덜 가리게 바깥 장면보다 작게
				_kenney(terrain, Kenney.pick(Kenney.TREES, cell), top, turn, Kenney.NATURE, 1.5)
			elif ch == "P" and cave:
				_kenney(terrain, Kenney.pick(Kenney.CAVE_PILLARS, cell), top, turn, Kenney.NATURE, 1.0, 1.7)
			elif ch == "#" and cave:
				_kenney(terrain, Kenney.pick(Kenney.CAVE_ROCKS, cell), top, turn, Kenney.NATURE, 1.0, 2.6)
			elif ch == "," and cave:
				_kenney(terrain, Kenney.pick(Kenney.CAVE_RUBBLE, cell), top, turn, Kenney.NATURE, 1.5)
			elif ch == "P" and _dungeon():
				_kenney(terrain, "column", top, 0.0)
			elif ch == "#" and _dungeon():
				_kenney(terrain, "rocks", top, (x % 4) * PI / 2.0)
			elif ch == "," and _dungeon():
				_kenney(terrain, "stones", top, (y % 4) * PI / 2.0)
			elif ch == "P":
				var pillar := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.32
				cyl.bottom_radius = 0.38
				cyl.height = 2.2
				pillar.mesh = cyl
				pillar.material_override = mats["stone"]
				pillar.position = top + Vector3(0, 1.1, 0)
				terrain.add_child(pillar)
			elif ch == "#":
				var rock := MeshInstance3D.new()
				var rb := BoxMesh.new()
				rb.size = Vector3(0.9, 1.0, 0.9)
				rock.mesh = rb
				rock.material_override = mats["stone"]
				rock.position = top + Vector3(0, 0.5, 0)
				terrain.add_child(rock)
			elif ch == "," and not _dungeon():
				for i in 3:
					var gp := top + Vector3(-0.3 + i * 0.3, 0.0, -0.2 + (i % 2) * 0.35)
					_kenney(terrain, Kenney.pick(Kenney.GRASS, cell + Vector2i(i, 0)), gp, turn + i, Kenney.NATURE, 1.6)

			var ov := MeshInstance3D.new()
			ov.mesh = plane
			ov.position = top + Vector3(0, 0.03, 0)
			ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ov.visible = false
			terrain.add_child(ov)
			overlays[cell] = ov
	if _dungeon():
		var floors: Array = []
		for c in grid.heights:
			if not _is_wall_char(map, c):
				floors.append(c)
		Kenney.build_edge_walls(terrain, floors, func(c: Vector2i) -> bool: return not _is_wall_char(map, c),
				grid.get_height, custom.get("style", "") == "cave")
	focus.position = Vector3(w / 2.0, 0, h / 2.0)


## Kenney 모델 하나를 칸 위에 놓습니다 (그림자만 있고 충돌은 칸 상자가 맡음). stretch_y: 세로로만 늘림
func _kenney(parent: Node3D, model: String, pos: Vector3, yaw: float, pack := Kenney.DUNGEON, size := 1.0, stretch_y := 1.0) -> void:
	var m := MeshInstance3D.new()
	m.mesh = Kenney.mesh(model, pack)
	m.scale = Vector3(size, size * stretch_y, size)
	m.position = pos
	m.rotation.y = yaw
	parent.add_child(m)


func _is_wall_char(map: Array, c: Vector2i) -> bool:
	if c.y < 0 or c.x < 0 or c.y >= map.size() or c.x >= (map[c.y] as String).length():
		return true
	return (map[c.y] as String)[c.x] == "X"


func _touches_floor(map: Array, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var yy := y + dy
			var xx := x + dx
			if yy < 0 or xx < 0 or yy >= map.size() or xx >= (map[yy] as String).length():
				continue
			if (map[yy] as String)[xx] != "X":
				return true
	return false


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _overlay_mat(kind: String) -> StandardMaterial3D:
	var colors := {
		"move": Color(0.3, 0.6, 1.0, 0.35), "path": Color(0.4, 0.95, 1.0, 0.6),
		"danger": Color(1.0, 0.25, 0.2, 0.65), "target": Color(1.0, 0.55, 0.1, 0.55),
		"hover": Color(1, 1, 1, 0.45),
	}
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colors[kind]
	return m




func _spawn_units() -> void:
	combat = Combat.new(grid, Dice.new())
	if custom.has("hero"):
		pc = (custom.hero as HeroState).make_creature()  # 던전 탐험: 앞 전투의 HP와 사용 횟수를 이어 감
	else:
		pc = Creature.new(Catalog.fighter(1), 0, "파이터")
		pc.resources["potion"] = 1
	pc.facing = Vector2i(1, 0)
	combat.add(pc, custom.get("pc_start", PC_START))
	var counts := {}
	var foes: Array = custom.foes if _dungeon() else ENCOUNTERS[encounter_id].foes
	for entry in foes:
		var id: String = entry[0]
		var st := Catalog.monster(id)
		counts[id] = counts.get(id, 0) + 1
		var c := Creature.new(st, 1, "%s %d" % [st.display_name, counts[id]])
		var to_pc: Vector2i = pc.cell - (entry[1] as Vector2i)
		c.facing = Vector2i(signi(to_pc.x), signi(to_pc.y)) if to_pc != Vector2i.ZERO else Vector2i(-1, 0)
		combat.add(c, entry[1])
	var units := Node3D.new()
	units.name = "Units"
	add_child(units)
	for c in combat.creatures:
		var v := UnitView.new()
		units.add_child(v)
		v.setup(c)
		v.position = cell_pos(c.cell)
		views[c] = v


func cell_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, grid.get_height(cell), cell.y + 0.5)


# =====================================================================
# UI
# =====================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	order_label = RichTextLabel.new()
	order_label.bbcode_enabled = true
	order_label.fit_content = true
	order_label.scroll_active = false
	order_label.position = Vector2(12, 8)
	order_label.size = Vector2(760, 30)
	_outline(order_label)
	layer.add_child(order_label)

	status_label = Label.new()
	status_label.position = Vector2(12, 40)
	_outline(status_label)
	layer.add_child(status_label)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	log_box.offset_left = -470
	log_box.offset_top = 8
	log_box.offset_bottom = -120
	log_box.offset_right = -8
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_font_size_override("bold_font_size", 13)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_content_margin_all(8)
	log_box.add_theme_stylebox_override("normal", bg)
	layer.add_child(log_box)

	hint_label = Label.new()
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -100
	hint_label.offset_bottom = -72
	hint_label.offset_left = 12
	_outline(hint_label)
	layer.add_child(hint_label)

	var help := Label.new()
	help.text = "좌클릭: 이동/공격 · WASD: 카메라 이동 · Q/E: 90° 회전 · 휠: 줌 · Enter: 턴 종료 · " + ("Esc: 던전으로" if _dungeon() else "F1~F5: 조우 바꾸기 · Esc: 탐험으로")
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -24
	help.offset_left = 12
	help.add_theme_font_size_override("font_size", 12)
	_outline(help)
	layer.add_child(help)

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -66
	bar.offset_bottom = -30
	bar.offset_left = 12
	bar.add_theme_constant_override("separation", 6)
	layer.add_child(bar)
	var group := ButtonGroup.new()
	for i in 3:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void: weapon_index = i; dirty = true)
		bar.add_child(b)
		weapon_buttons.append(b)
	bar.add_child(VSeparator.new())
	var actions := [
		["dash", "질주"], ["disengage", "이탈"], ["dodge", "회피"],
		["second_wind", "Second Wind"], ["potion", "물약"], ["end", "턴 종료"],
	]
	for a in actions:
		var b := Button.new()
		b.text = a[1]
		var id: String = a[0]
		b.pressed.connect(func() -> void: _do_action(id))
		bar.add_child(b)
		action_buttons[id] = b

	result_label = Label.new()
	result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_label.add_theme_font_size_override("font_size", 40)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_outline(result_label)
	result_label.visible = false
	layer.add_child(result_label)


func _outline(c: Control) -> void:
	c.add_theme_constant_override("outline_size", 6)
	c.add_theme_color_override("font_outline_color", Color.BLACK)
	c.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))


func _log(text: String) -> void:
	log_box.append_text(text + "\n")


func _weapon() -> WeaponData:
	return pc.stats.weapons[weapon_index]


func _player_turn() -> bool:
	return not combat.over and combat.current() == pc and queue.is_empty() and not busy


func _do_action(id: String) -> void:
	if not _player_turn():
		return
	match id:
		"dash": combat.dash(pc)
		"disengage": combat.disengage(pc)
		"dodge": combat.dodge(pc)
		"second_wind": combat.second_wind(pc)
		"potion": combat.drink_potion(pc)
		"end": combat.end_turn(pc)
	dirty = true


func _update_status() -> void:
	var dot := func(b: bool) -> String: return "●" if b else "○"
	status_label.text = "%s  HP %d/%d  AC %d  |  이동 %d칸  행동 %s  보너스 %s  반응 %s  |  Second Wind %d  물약 %d" % [
		pc.display_name, pc.hp, pc.stats.max_hp, pc.ac(), combat.move_budget(pc),
		dot.call(pc.action_available or pc.attacks_left > 0), dot.call(pc.bonus_available),
		dot.call(pc.reaction_available), pc.resources.get("second_wind", 0), pc.resources.get("potion", 0)]
	for i in weapon_buttons.size():
		var w: WeaponData = pc.stats.weapons[i]
		var extra := "" if w.range_normal == 0 else " %d/%d칸" % [w.range_normal, w.range_long]
		weapon_buttons[i].text = "%d %s (%s, %s%s)" % [i + 1, w.display_name, w.damage_text(), w.mastery, extra]
	var mine := _player_turn()
	for id in action_buttons:
		action_buttons[id].disabled = not mine
	var cur := combat.current()
	var parts: Array[String] = []
	for c in combat.order:
		if not c.is_alive():
			continue
		var color := "#9fd3ff" if c.team == 0 else "#ffb3a7"
		var txt := "[color=%s]%s %d[/color]" % [color, c.display_name, c.initiative]
		if c == cur:
			txt = "[b]▶ %s[/b]" % txt
		parts.append(txt)
	order_label.text = "라운드 %d   %s" % [combat.round_num, "   ".join(parts)]


# =====================================================================
# 매 프레임: 이벤트 재생 → 몬스터 턴 → 플레이어 입력
# =====================================================================

func _process(delta: float) -> void:
	_pan_camera(delta)
	if busy:
		return
	if not queue.is_empty():
		_play(queue.pop_front())
		return
	if combat.over:
		_show_result()
		return
	var cur := combat.current()
	if cur != null and cur.team == 1:
		combat.run_monster_turn()
		return
	if dirty:
		dirty = false
		_refresh_player_turn()


func _pan_camera(delta: float) -> void:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v != Vector2.ZERO:
		focus.position += Vector3(v.x, 0, v.y).rotated(Vector3.UP, rig.rotation.y) * 6.0 * delta


func _play(ev: Dictionary) -> void:
	busy = true
	match ev.type:
		"log":
			_log(ev.text)
		"turn_start":
			await _on_turn_start(ev.creature)
		"move":
			await _anim_move(ev.creature, ev.from, ev.to)
		"teleport":
			var tw := create_tween()
			tw.tween_property(views[ev.creature], "position", cell_pos(ev.to), 0.15)
			await tw.finished
		"attack":
			await _anim_attack(ev)
		"hp":
			if ev.delta > 0:
				Sfx.play(self, "heal")
			views[ev.creature].set_hp(ev.hp)
			_popup(ev.creature, ev.delta, ev.crit)
		"condition":
			views[ev.creature].refresh()
		"death", "fled":
			if ev.type == "death":
				Sfx.play(self, "death")
			await _anim_vanish(ev.creature)
		"end":
			pass
	busy = false
	dirty = true


func _on_turn_start(c: Creature) -> void:
	for v in views.values():
		v.set_active(false)
	views[c].set_active(true)
	focus.position = views[c].position
	_update_status()
	if c.team == 1:
		await get_tree().create_timer(0.35).timeout


func _anim_move(c: Creature, from: Vector2i, to: Vector2i) -> void:
	var v = views[c]
	v.set_facing(to - from)
	v.walking = true
	Sfx.play(self, "step", 4.0)
	var tw := create_tween()
	tw.tween_property(v, "position", cell_pos(to), 0.16)
	await tw.finished
	v.walking = false


func _anim_attack(ev: Dictionary) -> void:
	var a = views[ev.attacker]
	var t = views[ev.target]
	a.set_facing(ev.target.cell - ev.attacker.cell)
	var ranged: bool = ev.get("ranged", false)
	a.attack(ranged)
	Sfx.play(self, "shoot" if ranged else "swing")
	var start: Vector3 = a.position
	var tw := create_tween()
	if not ranged:
		var lunge: Vector3 = start + (t.position - start).normalized() * 0.25
		tw.tween_property(a, "position", lunge, 0.1)
		tw.tween_property(a, "position", start, 0.12)
	else:
		tw.tween_interval(0.2)
	await tw.finished
	if ev.hit:
		Sfx.play(self, "crit" if ev.crit else "hit")
		t.hit_flash()
	else:
		Sfx.play(self, "miss")
		_float_text(t.position, "빗나감", Color(0.8, 0.8, 0.8))
	await get_tree().create_timer(0.25).timeout


func _anim_vanish(c: Creature) -> void:
	var v = views[c]
	v.set_active(false)
	v.label.visible = false
	v.body.hold("die")
	await get_tree().create_timer(0.5).timeout
	var tw := create_tween()
	tw.tween_property(v, "scale", Vector3(1, 0.01, 1), 0.3)
	await tw.finished
	v.visible = false


func _popup(c: Creature, delta: int, crit: bool) -> void:
	if delta == 0:
		return
	var color := Color(0.4, 1, 0.4) if delta > 0 else (Color(1, 0.85, 0.2) if crit else Color(1, 0.35, 0.3))
	_float_text(views[c].position, ("%+d" % delta), color)


func _float_text(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.pixel_size = 0.005
	l.outline_size = 12
	l.render_priority = 3
	add_child(l)
	l.position = at + Vector3(0, 1.4, 0)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _show_result() -> void:
	if result_label.visible:
		return
	_update_status()
	_clear_overlays()
	for v in views.values():
		v.set_active(false)
	var keys := "Esc: 던전으로 · R: 다시" if _dungeon() else "F1~F5: 다른 조우 · R: 다시"
	if _dungeon():
		custom["result"] = "win" if combat.winner == 0 else "lose"
	if combat.winner == 0 and custom.has("hero"):
		# 이긴 전투는 다시 할 수 없음 (XP가 두 번 쌓이지 않게)
		var hero: HeroState = custom.hero
		var up := hero.absorb(pc, combat.xp_earned)
		result_label.text = "승리!\n경험치 +%d (누적 %d) · 레벨 %d%s\nEsc: 던전으로" % [
			combat.xp_earned, hero.xp, hero.level(), "\n레벨 업!" if up.has("level_up") else ""]
		if up.has("level_up"):
			custom["level_up"] = up.level_up
		Sfx.play(self, "level_up" if up.has("level_up") else "win")
	elif combat.winner == 0:
		Sfx.play(self, "win")
		result_label.text = "승리!\n경험치 %d · 레벨 %d\n%s" % [combat.xp_earned, Rules.level_for_xp(combat.xp_earned), keys]
	else:
		Sfx.play(self, "lose")
		result_label.text = "패배...\n%s" % keys
	result_label.visible = true


# =====================================================================
# 플레이어 턴: 이동 범위 / 대상 표시, 마우스 입력
# =====================================================================

func _refresh_player_turn() -> void:
	_update_status()
	_clear_overlays()
	move_opts = {}
	if not _player_turn():
		return
	move_opts = combat.move_options(pc)
	move_reach = grid.reachable(pc, combat.move_budget(pc))
	for cell in move_opts:
		if cell != pc.cell:
			_set_overlay(cell, "move")
	for c in combat.creatures:
		if c.team == 1 and c.is_alive() and combat.can_attack(pc) and combat.attack_info(pc, c, _weapon()).valid:
			_set_overlay(c.cell, "target")
	_update_hover()


func _clear_overlays() -> void:
	for ov in overlays.values():
		ov.visible = false


func _set_overlay(cell: Vector2i, kind: String) -> void:
	if overlays.has(cell):
		overlays[cell].visible = true
		overlays[cell].material_override = overlay_mats[kind]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pick(event.position)
		if _player_turn():
			_refresh_player_turn()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(event.position)
		_click()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if ENCOUNTER_KEYS.has(key) and not _dungeon():
			encounter_id = ENCOUNTER_KEYS[key]
			get_tree().reload_current_scene()
		elif key == KEY_R and combat.over and not (custom.has("hero") and combat.winner == 0):
			custom.erase("result")
			get_tree().reload_current_scene()
		elif key >= KEY_1 and key <= KEY_3:
			weapon_buttons[key - KEY_1].button_pressed = true
			weapon_index = key - KEY_1
			dirty = true
		elif event.is_action("end_turn"):
			_do_action("end")
		elif event.is_action("back"):
			if custom.has("hero") and not combat.over:
				# 전투 중 도망: 쓰러져 있었으면 패배, 아니면 지금 HP와 사용 횟수를 그대로 가져감
				if pc.is_down() or not pc.is_alive():
					custom["result"] = "lose"
				else:
					(custom.hero as HeroState).absorb(pc)
			if _dungeon():
				get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/main.tscn")


func _pick(screen_pos: Vector2) -> void:
	hover_cell = Vector2i(-1, -1)
	hover_creature = null
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return
	var col: Object = hit.collider
	if col.has_meta("creature"):
		var c: Creature = col.get_meta("creature")
		if c.is_alive():
			hover_creature = c
			hover_cell = c.cell
	elif col.has_meta("cell"):
		hover_cell = col.get_meta("cell")
		hover_creature = grid.occupant(hover_cell)


func _update_hover() -> void:
	hint_label.text = ""
	if hover_cell.x < 0:
		return
	if hover_creature != null and hover_creature.team == 1:
		var info := combat.attack_info(pc, hover_creature, _weapon())
		var desc := "%s  HP %d/%d  AC %d" % [hover_creature.display_name, hover_creature.hp, hover_creature.stats.max_hp, hover_creature.ac()]
		if not combat.can_attack(pc):
			hint_label.text = desc + "  —  이번 턴 행동을 이미 썼습니다"
		elif not info.valid:
			hint_label.text = desc + "  —  공격 불가: " + info.reason
		else:
			var notes: Array = []
			if info.adv > 0:
				notes.append("이점: " + ", ".join(info.adv_src))
			elif info.adv < 0:
				notes.append("불리점: " + ", ".join(info.dis_src))
			if info.cover > 0:
				notes.append("엄폐 +%d" % info.cover)
			hint_label.text = "%s  —  %s 명중 확률 %d%%  %s" % [desc, _weapon().display_name, roundi(info.chance * 100), "  ".join(notes)]
			_set_overlay(hover_cell, "hover")
		return
	if move_opts.has(hover_cell) and hover_cell != pc.cell:
		var p := grid.path(move_reach, hover_cell)
		var cur := pc.cell
		var danger := 0
		for s in p:
			var step: Vector2i = s
			var threats: Array = [] if pc.disengaged else grid.opportunity_attackers(pc, cur, step)
			_set_overlay(step, "path")
			if not threats.is_empty():
				_set_overlay(cur, "danger")
				danger += threats.size()
			cur = step
		_set_overlay(hover_cell, "hover")
		hint_label.text = "이동: %d칸 사용" % move_opts[hover_cell]
		if danger > 0:
			hint_label.text += "  —  ⚠ 기회 공격 %d회 유발 (빨간 칸)" % danger


func _click() -> void:
	if not _player_turn() or hover_cell.x < 0:
		return
	if hover_creature != null and hover_creature.team == 1:
		combat.attack(pc, hover_creature, _weapon())
	elif move_opts.has(hover_cell) and hover_cell != pc.cell:
		combat.move(pc, hover_cell)
	dirty = true
