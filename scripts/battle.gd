## 격자 턴제 전투 장면. 규칙은 rules/ 의 Combat이 처리하고,
## 여기서는 그 결과(event)를 순서대로 애니메이션으로 보여주고 플레이어 입력을 받습니다.
extends Node3D

const UnitView = preload("res://scripts/unit_view.gd")
const InputSetup = preload("res://scripts/input_setup.gd")
const Kenney = preload("res://scripts/kenney.gd")
const Sfx = preload("res://scripts/sfx.gd")
const PartyPanel = preload("res://scripts/party_panel.gd")
const RadialMenu = preload("res://scripts/radial_menu.gd")
const ActionLayer = preload("res://scripts/action_layer.gd")

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
	"undead": {"label": "언데드 — 스켈레톤 2 + 섀도 + 스펙터", "foes": [["skeleton", Vector2i(11, 2)], ["skeleton", Vector2i(11, 7)],
		["shadow", Vector2i(12, 4)], ["specter", Vector2i(12, 6)]]},
	"bellwarden": {"label": "보스 — 가라앉은 종지기 (2레벨 파티용)", "foes": [["bellwarden", Vector2i(11, 5)]], "level": 2},
	"cantor": {"label": "보스 — 심연의 노래꾼 (3레벨 파티용)", "foes": [["cantor", Vector2i(11, 5)]], "level": 3},
	"regent": {"label": "보스 — 납골 섭정 (4레벨 파티용)", "foes": [["regent", Vector2i(11, 5)]], "level": 4},
}
const ENCOUNTER_KEYS := {KEY_F1: "easy", KEY_F2: "normal", KEY_F3: "hard", KEY_F4: "boss", KEY_F5: "undead", KEY_F6: "bellwarden", KEY_F7: "cantor", KEY_F8: "regent"}

static var encounter_id := "normal"
## [변경] 단독 전투(B 키)는 실시간 액션 전투(docs/rules.md 10장). T 키로 예전 턴제와 바꿈.
## 던전 지도 화면에서 고른 방 전투(custom에 map이 있음)도 실시간 (2026-11-27)
static var action_mode := true
const ACTION_HELP_DUNGEON := "이동: 왼쪽 스틱/WASD · 공격: X/J · 구르기: A/Space · 기술: B/K · 기술2: 십자→/L · 물약: 십자↑/1 · 카메라: LB·RB/Q·E · T: 턴제로 · Esc: 도망쳐 던전으로"
const ACTION_HELP := "이동: 왼쪽 스틱/WASD · 공격: X/J (누르고 있으면 계속) · 구르기: A/Space · 기술: B/K · 기술2: 십자→/L · 물약: 십자↑/1 · 카메라: LB·RB/Q·E · F1~F8: 조우 · R: 다시 · T: 턴제로 · Esc: 바깥으로"
var action: ActionLayer
var _action_ui := {}
## 던전 생성기에서 넘겨준 전투 (Dungeon.battle_setup). 비어 있으면 기본 맵과 F1~F8 조우.
## 끝나면 custom["result"]에 "win" 또는 "lose"를 남깁니다.
## custom["party"]: 던전 탐험의 파티 (HeroState 배열). 없으면 1레벨 파이터 + 클레릭
## custom["return_scene"]: 끝나고 돌아갈 장면 (없으면 던전), custom["surprised"]: 기습당한 편 (1 = 적)
static var custom := {}

@onready var focus: Node3D = $Focus
@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var grid: CombatGrid
var combat: Combat
## 지금 조종하는 파티원 (파티원 차례마다 바뀜)
var pc: Creature
var party: Array[Creature] = []
## party와 같은 순서의 HeroState (던전 탐험일 때만)
var heroes: Array = []
## 대상을 고르는 중인 주문 id
var pending_spell := ""
## 대상을 고르는 중인 주문의 슬롯 레벨 (0이면 가장 낮은 것)
var pending_slot := 0
## 시전자 → 떠 있는 영적 무기 모델
var spirit_views := {}
## 시전자 → Spirit Guardians 범위 표시 {node, cell}
var aura_views := {}
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
var weapon_box: HBoxContainer
var action_buttons := {}
var category_buttons := {}
var party_panel: PartyPanel
var radial: RadialMenu


func _ready() -> void:
	InputSetup.register()
	if action_mode:
		_start_action()
		return
	_build_world()
	_build_ui()
	_spawn_units()
	combat.event.connect(func(ev: Dictionary) -> void: queue.append(ev))
	_log("[color=gray]%s[/color]" % _encounter_label())
	Sfx.wire_buttons(self)
	_rebuild_bar()  # 무기·주문 버튼은 직접 효과음을 붙임 (wire_buttons 뒤에)
	Sfx.play(self, "fight")
	combat.start(int(custom.get("surprised", -1)))


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
		# [다크 판타지] 던전 방 전투는 어둡게: 약한 푸른 달빛 + 횃불이 주인공
		env.background_color = Color(0.03, 0.03, 0.04)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.4, 0.4, 0.52)
		env.ambient_light_energy = 0.5
		$WorldEnvironment.environment = env
		var sun := get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			sun.light_energy *= 0.45
			sun.light_color = Color(0.75, 0.8, 1.0)
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
					_kenney(terrain, Kenney.pick(Kenney.CAVE_FLOORS, Vector2i(x, y)), Vector3(x + 0.5, th + 0.002, y + 0.5), yaw)
				else:
					var tile := Kenney.pick(Kenney.FLOOR_DETAILS, Vector2i(x, y)) if (x * 7 + y * 13) % 9 == 0 else "floor"
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
		var open_cell := func(c: Vector2i) -> bool: return not _is_wall_char(map, c)
		var is_cave: bool = custom.get("style", "") == "cave"
		Kenney.build_edge_walls(terrain, floors, open_cell, grid.get_height, is_cave)
		Kenney.decorate(terrain, floors, open_cell, grid.get_height, is_cave,
				func(c: Vector2i) -> bool: return grid.walls.has(c) or grid.difficult.has(c))
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
	if custom.has("party"):
		heroes = custom.party  # 던전 탐험: 앞 전투의 HP와 사용 횟수를 이어 감
		for h in heroes:
			party.append((h as HeroState).make_creature())
	else:
		# 단독 전투: 고른 파티(던전 생성기·시나리오 창에서 바꿈)를 1레벨로 (보스 조우는 그 레벨)
		for i in HeroState.party_classes.size():
			var h := HeroState.fresh(str(HeroState.party_classes[i]), 1 if i == 0 else 0)
			h.xp = Rules.XP_THRESHOLDS[int(ENCOUNTERS[encounter_id].get("level", 1)) - 1]
			party.append(h.make_creature())
	pc = party[0]
	var foes: Array = custom.foes if _dungeon() else ENCOUNTERS[encounter_id].foes
	var foe_cells: Array = foes.map(func(e: Array) -> Vector2i: return e[1])
	var start: Vector2i = custom.get("pc_start", PC_START)
	for i in party.size():
		party[i].facing = Vector2i(1, 0)
		combat.add(party[i], start if i == 0 else _free_cell_near(start, foe_cells))
	var counts := {}
	for entry in foes:
		var id: String = entry[0]
		var st := Catalog.custom_monster(id, custom.get("monster_defs", {}))
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


## start 가까이에서 비어 있고 설 수 있는 칸. 같은 거리면 적에게서 먼 칸
func _free_cell_near(start: Vector2i, avoid: Array) -> Vector2i:
	for r in range(1, 6):
		var best := Vector2i(-1, -1)
		var best_score := -1
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := start + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) != r or not grid.heights.has(c) or grid.walls.has(c):
					continue
				if grid.occupant(c) != null or avoid.has(c) or absf(grid.get_height(c) - grid.get_height(start)) > 1.0:
					continue
				var score := 0
				for a in avoid:
					score += grid.distance(c, a)
				if score > best_score:
					best_score = score
					best = c
		if best.x >= 0:
			return best
	return start


## 왼쪽 파티 창 갱신
func _refresh_party_panel() -> void:
	if party_panel == null:
		return
	var members: Array = []
	for i in party.size():
		var c := party[i]
		members.append({"key": str(i), "name": "%s  %d레벨" % [c.display_name, c.stats.level],
			"model": c.stats.model, "weapon": c.stats.weapon_model,
			"hp": views[c].shown_hp if views.has(c) else c.hp, "max_hp": c.stats.max_hp, "temp_hp": c.temp_hp,
			"active": combat.current() == c and not combat.over, "down": c.is_down(), "dead": c.dead,
			"effects": effects_of(c)})
	party_panel.show_members(members)


## 크리처에 걸린 상태와 효과를 [글자, 종류, 설명] 목록으로
static func effects_of(c: Creature) -> Array:
	var out: Array = []
	if c.dead:
		return [["사망", "debuff", "죽었습니다"]]
	if c.has_condition("unconscious"):
		out.append(["의식 없음", "debuff", "행동 불능, 넘어짐. 1칸 안에서 맞으면 치명타"])
		if c.stable:
			out.append(["안정", "info", "사망 내성을 더 굴리지 않음"])
		else:
			out.append(["사망 내성 ✓%d ✗%d" % [c.death_successes, c.death_failures], "debuff", "3번 성공하면 안정, 3번 실패하면 사망"])
	elif c.has_condition("prone"):
		out.append(["넘어짐", "debuff", "내 공격 불리점, 일어서려면 이동력 절반"])
	var names := {
		"blessed": ["Bless", "buff", "공격과 내성에 +1d4"],
		"shield_of_faith": ["Shield of Faith", "buff", "AC +2"],
		"dodging": ["회피", "buff", "나를 노리는 공격에 불리점"],
		"vex": ["Vex", "buff", "그 대상에 대한 다음 공격에 이점"],
		"guided": ["Guiding Bolt", "debuff", "나를 노리는 다음 공격에 이점"],
		"sapped": ["Sap", "debuff", "다음 공격에 불리점"],
		"slowed": ["Slow", "debuff", "속도 −2칸"],
		"turned": ["Turn Undead", "debuff", "겁에 질려 행동 불능"],
		"paralyzed": ["마비", "debuff", "행동 불능. 나를 노리는 공격에 이점, 1칸 안에서 맞으면 치명타"],
		"poisoned": ["중독", "debuff", "가스트의 악취. 내 공격에 불리점 (다음 내 턴 시작까지)"],
		"raging": ["분노", "buff", "B/P/S 피해 저항, 근력 공격 피해 +2, 근력 내성 이점. 공격하지 않은 턴이 끝나면 풀림"],
		"reckless": ["무모한 공격", "info", "내 근력 공격에 이점, 나를 노리는 공격에도 이점 (다음 내 턴 시작까지)"],
		"steady_aim": ["정조준", "buff", "이번 턴 다음 공격에 이점"],
		"stunned": ["기절", "debuff", "행동 불능, 속도 0. STR·DEX 내성 자동 실패, 나를 노리는 공격에 이점"],
		"staggered": ["비틀거림", "debuff", "속도 절반"],
		"exposed": ["빈틈", "debuff", "나를 노리는 다음 공격에 이점"],
		"heroism": ["Heroism", "buff", "턴을 시작할 때마다 임시 HP"],
		"protected": ["보호", "buff", "언데드 같은 이계 존재의 공격에 불리점"],
		"sacred_weapon": ["축복받은 무기", "buff", "근접 공격 굴림 + CHA"],
		"marked": ["표식", "debuff", "표식을 건 이가 맞힐 때마다 1d6 추가 피해"],
		"shield_spell": ["Shield", "buff", "AC +5 (다음 내 턴 시작까지)"],
		"innate_sorcery": ["Innate Sorcery", "buff", "주문 내성 DC +1, 주문 공격에 이점"],
		"no_heal": ["회복 불가", "debuff", "Chill Touch: HP를 회복하지 못함"],
		"inspired": ["영감", "buff", "공격이나 내성에 실패하면 영감 주사위를 더함"],
		"outlined": ["요정불", "debuff", "이 크리처를 노리는 공격에 이점"],
		"cs_trip": ["교활한 일격", "info", "다음 Sneak Attack에 넘어뜨리기"],
	}
	var seen := {}
	for e in c.effects:
		if names.has(e.type) and not seen.has(e.type):
			seen[e.type] = true
			out.append(names[e.type])
	if c.str_loss > 0:
		out.append(["근력 -%d" % c.str_loss, "debuff", "섀도에게 근력을 빼앗김 (전투가 끝나면 돌아옴)"])
	if c.max_hp_loss > 0:
		out.append(["최대 HP -%d" % c.max_hp_loss, "debuff", "스펙터에게 생명을 빼앗김 (긴 휴식으로 돌아옴)"])
	if c.aid_bonus > 0:
		out.append(["Aid +%d" % c.aid_bonus, "buff", "최대 HP +%d (전투가 끝날 때까지)" % c.aid_bonus])
	if c.concentration != "":
		out.append(["집중: " + Spells.spell_name(c.concentration), "info", "피해를 받으면 CON 내성으로 유지"])
	return out


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
	# 오른쪽 위 작은 창 (최근 몇 줄만 보이고 스크롤로 지난 기록)
	log_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	log_box.offset_left = -400
	log_box.offset_top = 8
	log_box.offset_bottom = 196
	log_box.offset_right = -8
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_font_size_override("bold_font_size", 13)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.38)
	bg.set_corner_radius_all(6)
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
	help.text = "좌클릭: 이동/공격/대상 · 스킬·주문·아이템: 원형 메뉴(숫자로 고름) · 우클릭: 취소 · WASD: 카메라 이동 · Q/E: 90° 회전 · 휠: 줌 · Enter: 턴 종료 · " + ("T: 실시간으로 · Esc: 던전으로" if _dungeon() else "F1~F8: 조우 바꾸기 · T: 실시간으로 · Esc: 탐험으로")
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
	weapon_box = HBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 6)
	bar.add_child(weapon_box)
	bar.add_child(VSeparator.new())
	# 무기 공격 말고는 분류 버튼 → 원형 메뉴에서 고름
	for cat in [["skill", "스킬"], ["spell", "주문"], ["item", "아이템"]]:
		var b := Button.new()
		b.text = "%s ▴" % cat[1]
		var id: String = cat[0]
		b.pressed.connect(func() -> void: _open_radial(id))
		bar.add_child(b)
		category_buttons[id] = b
	bar.add_child(VSeparator.new())
	var end := Button.new()
	end.text = "턴 종료"
	end.pressed.connect(func() -> void: _do_action("end"))
	bar.add_child(end)
	action_buttons["end"] = end

	party_panel = PartyPanel.new()
	party_panel.position = Vector2(12, 72)
	layer.add_child(party_panel)
	radial = RadialMenu.new()
	layer.add_child(radial)
	radial.chosen.connect(_on_radial_chosen)

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
	return pc.stats.weapons[mini(weapon_index, pc.stats.weapons.size() - 1)]


## 지금 파티원에 맞게 무기, 행동, 주문 버튼을 다시 만듦
func _rebuild_bar() -> void:
	for b in weapon_buttons:
		b.queue_free()
	weapon_buttons.clear()
	weapon_index = 0
	var group := ButtonGroup.new()
	for i in pc.stats.weapons.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			weapon_index = i
			pending_spell = ""
			dirty = true)
		b.pressed.connect(func() -> void: Sfx.play(b, "click"))
		weapon_box.add_child(b)
		weapon_buttons.append(b)
	category_buttons["spell"].visible = not _radial_items("spell").is_empty()
	category_buttons["item"].visible = not _radial_items("item").is_empty()
	radial.close()


# =====================================================================
# 원형 메뉴: 스킬 / 주문 / 아이템
# =====================================================================

func _open_radial(cat: String) -> void:
	if not _player_turn():
		return
	pending_spell = ""
	dirty = true
	var b: Button = category_buttons[cat]
	var titles := {"skill": "스킬", "spell": "주문", "item": "아이템"}
	radial.open(b.global_position + Vector2(b.size.x / 2.0, 0), "%s\n%s" % [pc.display_name, titles[cat]], _radial_items(cat))
	Sfx.play(self, "open")


func _on_radial_chosen(id: String) -> void:
	if id.begins_with("slot:"):
		var parts := id.split(":")
		_pick_spell(parts[1], int(parts[2]))
	elif Spells.DATA.has(id):
		_pick_spell(id)
	else:
		_do_action(id)


func _radial_items(cat: String) -> Array:
	var out: Array = []
	var act := "" if pc.action_available else "행동을 이미 썼음"
	var bonus := "" if pc.bonus_available else "보너스 행동을 이미 썼음"
	match cat:
		"skill":
			out.append(_item("dash", "질주", "행동", "이번 턴 이동력 +%d칸" % pc.speed(), act))
			out.append(_item("disengage", "이탈", "행동", "이번 턴에는 움직여도 기회 공격을 받지 않음", act))
			out.append(_item("dodge", "회피", "행동", "다음 내 턴까지 나를 노리는 공격에 불리점", act))
			out.append_array(ClassFeatures.actions(combat, pc))
			for id in pc.stats.spells:
				if Spells.DATA[id].level == -1 or Spells.DATA[id].level == -3:
					out.append(_spell_item(id))
		"spell":
			if Spells.knows(pc, "spirit_strike"):
				out.append(_spell_item("spirit_strike"))
			if Spells.knows(pc, "mark_move"):
				out.append(_spell_item("mark_move"))
			for id in pc.stats.spells:
				if Spells.DATA[id].level >= 0:
					out.append(_spell_item(id))
		"item":
			if pc.resources.has("potion"):
				var n: int = pc.resources.potion
				out.append(_item("potion", "회복 물약", "보너스 · %d개" % n, "2d4 + 2 회복", "물약이 없음" if n <= 0 else bonus))
	return out


func _item(id: String, text: String, sub: String, desc: String, reason: String) -> Dictionary:
	return {"id": id, "text": text, "sub": sub, "desc": desc, "disabled": reason != "", "reason": reason}


func _spell_item(id: String) -> Dictionary:
	var d: Dictionary = Spells.DATA[id]
	var cost := "소마법"
	if d.level == -1:
		cost = "Channel %d" % pc.resources.get("channel", 0)
	elif d.level == -3:
		cost = "남은 %d" % pc.resources.get(Spells.RESOURCE_OF.get(id, id), 0)
	elif Spells.has_free(pc, id):
		cost = "무료 %d회" % pc.resources.get(Spells.FREE_CASTS[id], 0)
	elif d.level == -2:
		cost = "슬롯 없이"
	elif d.level >= 1:
		var levels := Spells.slot_levels(pc, d.level)
		if levels.is_empty():
			cost = "슬롯 없음"
		elif levels.size() == 1:
			cost = "%d레벨 슬롯" % levels[0]
		else:
			cost = "%d~%d레벨 슬롯" % [levels[0], levels[-1]]
	var sub := "%s · %s" % [{"action": "행동", "bonus": "보너스", "free": "무료", "reaction": "반응"}[d.time], cost]
	var title := Spells.spell_name(id) + (" ✓" if pc.toggles.get(id, false) else "")
	return _item(id, title, sub, "%s\n%s" % [Spells.SUMMARY.get(id, ""), _spell_tooltip(id)],
		Spells.why_not(combat, pc, id))


func _spell_tooltip(id: String) -> String:
	var d: Dictionary = Spells.DATA[id]
	var kind := "소마법" if d.level == 0 else ("Channel Divinity" if d.level == -1 else ("후속 행동" if d.level == -2 else ("클래스 기능" if d.level == -3 else "%d레벨 주문" % d.level)))
	return "%s · %s · %s · %d칸%s" % [kind, {"action": "행동", "bonus": "보너스 행동", "free": "행동 안 씀", "reaction": "반응"}[d.time],
		{"enemy": "적 하나", "ally": "아군 하나", "downed": "쓰러진 아군", "any": "누구든 하나", "area": "주변", "toggle": "켜기/끄기", "auto": "자동"}[d.target],
		Spells.range_of(pc, id), " · 집중" if d.get("conc", false) else ""]


## slot: 고른 슬롯 레벨. 0이고 쓸 수 있는 슬롯 레벨이 여럿이면 슬롯 고르기 메뉴를 엽니다
func _pick_spell(id: String, slot := 0) -> void:
	if not _player_turn():
		return
	var why := Spells.why_not(combat, pc, id, slot)
	if why != "":
		_log("[color=gray]%s: %s[/color]" % [Spells.spell_name(id), why])
		pending_spell = ""
	elif slot == 0 and Spells.slot_levels(pc, Spells.DATA[id].level).size() > 1 and Spells.DATA[id].level >= 1 \
			and not Spells.has_free(pc, id) and Spells.DATA[id].target != "toggle":
		_open_slot_radial(id)
		return
	elif not Spells.needs_target(id):
		pending_spell = ""
		Spells.cast(combat, pc, id, null, slot)
	else:
		pending_spell = "" if pending_spell == id and pending_slot == slot else id
		pending_slot = slot
	dirty = true


func _open_slot_radial(id: String) -> void:
	var items: Array = []
	for l in Spells.slot_levels(pc, Spells.DATA[id].level):
		var n: int = pc.resources.get("slot%d" % l, 0)
		items.append(_item("slot:%s:%d" % [id, l], "%d레벨 슬롯" % l, "남은 %d개" % n,
			"%s %d레벨: %s" % [Spells.spell_name(id), l, Spells.upcast_text(pc, id, l)], ""))
	var b: Button = category_buttons["spell"]
	radial.open(b.global_position + Vector2(b.size.x / 2.0, 0), "%s\n슬롯" % Spells.spell_name(id), items)
	Sfx.play(self, "open")


func _player_turn() -> bool:
	return not combat.over and pc != null and pc.team == 0 and combat.current() == pc and queue.is_empty() and not busy


func _do_action(id: String) -> void:
	if not _player_turn():
		return
	pending_spell = ""
	if ClassFeatures.use(combat, pc, id):
		# 맨손 타격을 얻었으면 무기 버튼을 맨손으로
		if pc.bonus_attacks > 0:
			for i in pc.stats.weapons.size():
				if pc.stats.weapons[i].id == "unarmed":
					weapon_index = i
					weapon_buttons[i].button_pressed = true
		dirty = true
		return
	match id:
		"dash": combat.dash(pc)
		"disengage": combat.disengage(pc)
		"dodge": combat.dodge(pc)
		"potion": combat.drink_potion(pc)
		"end": combat.end_turn(pc)
	dirty = true


func _update_status() -> void:
	var dot := func(b: bool) -> String: return "●" if b else "○"
	var res: Array[String] = []
	for t in ClassFeatures.resource_labels(pc):
		if not t.begins_with("Channel"):
			res.append(t)
	if pc.bonus_attacks > 0:
		res.append("맨손 타격 %d회 남음" % pc.bonus_attacks)
	if pc.resources.has("potion"):
		res.append("물약 %d" % pc.resources.potion)
	var slots: Array[String] = []
	for l in range(1, pc.stats.spell_slots.size() + 1):
		slots.append("%d레벨 %d/%d" % [l, pc.resources.get("slot%d" % l, 0), pc.stats.spell_slots[l - 1]])
	if not slots.is_empty():
		res.append("슬롯 " + " · ".join(slots))
	if pc.resources.has("channel"):
		res.append("Channel Divinity %d" % pc.resources.channel)
	if pc.concentration != "":
		res.append("집중: " + Spells.spell_name(pc.concentration))
	if pc.has_effect("blessed"):
		res.append("Bless")
	status_label.text = "%s  HP %d/%d  AC %d  |  이동 %d칸  행동 %s  보너스 %s  반응 %s  |  %s" % [
		pc.display_name, pc.hp, pc.stats.max_hp, pc.ac(), combat.move_budget(pc),
		dot.call(pc.action_available or pc.attacks_left > 0), dot.call(pc.bonus_available),
		dot.call(pc.reaction_available), "  ".join(res)]
	for i in weapon_buttons.size():
		var w: WeaponData = pc.stats.weapons[i]
		var extra := "" if w.range_normal == 0 else " %d/%d칸" % [w.range_normal, w.range_long]
		var mastery := (", " + w.mastery) if pc.can_use_mastery(w) else ""
		weapon_buttons[i].text = "%d %s (%s%s%s)" % [i + 1, w.display_name, w.damage_text(), mastery, extra]
	var mine := _player_turn()
	for id in action_buttons:
		action_buttons[id].disabled = not mine
	for id in category_buttons:
		category_buttons[id].disabled = not mine
		category_buttons[id].text = "%s ▴" % {"skill": "스킬", "spell": "주문", "item": "아이템"}[id]
	if pending_spell != "":
		category_buttons["skill" if Spells.DATA[pending_spell].level in [-1, -3] else "spell"].text = "▶ %s%s" % [Spells.spell_name(pending_spell),
			(" (%d레벨)" % pending_slot) if pending_slot > 0 else ""]
	_refresh_party_panel()
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
	if combat == null:
		return  # 액션 전투
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
		"cast":
			await _anim_cast(ev)
		"spirit":
			await _anim_spirit(ev.caster, ev.cell)
		"hp":
			if ev.delta > 0:
				Sfx.play(self, "heal")
			views[ev.creature].set_hp(ev.hp)
			_popup(ev.creature, ev.delta, ev.crit)
		"condition":
			views[ev.creature].refresh()
		"reshape":
			views[ev.creature].reshape()
			if ev.creature == pc:
				_rebuild_bar()
		"death", "fled":
			if ev.type == "death":
				Sfx.play(self, "death")
			await _anim_vanish(ev.creature)
		"end":
			pass
	_refresh_party_panel()
	_sync_auras()
	busy = false
	dirty = true


func _on_turn_start(c: Creature) -> void:
	for v in views.values():
		v.set_active(false)
	views[c].set_active(true)
	if c.team == 0:
		pc = c
		pending_spell = ""
		_rebuild_bar()
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


## 영적 무기: 칸이 (-1, -1)이면 사라짐, 아니면 그 칸 위로 날아감 (처음이면 생김)
func _anim_spirit(caster: Creature, cell: Vector2i) -> void:
	var node: Node3D = spirit_views.get(caster)
	if cell.x < 0:
		if node:
			spirit_views.erase(caster)
			var tw := create_tween()
			tw.tween_property(node, "scale", Vector3.ONE * 0.01, 0.25)
			await tw.finished
			node.queue_free()
		return
	var pos := cell_pos(cell) + Vector3(0, 1.1, 0)
	if node == null:
		node = Node3D.new()
		# 영적 무기는 늘 빛나는 망치 (Kenney 공구 모델)
		var m := Kenney.instance("tool-hammer", "survival-kit")
		m.scale = Vector3.ONE * 4.5
		node.add_child(m)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.4)
		light.light_energy = 3.0
		light.omni_range = 2.5
		node.add_child(light)
		add_child(node)
		node.position = views[caster].position + Vector3(0, 1.2, 0)
		spirit_views[caster] = node
		Sfx.play(self, "cast")
	var tw := create_tween()
	tw.tween_property(node, "position", pos, 0.3).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _anim_attack(ev: Dictionary) -> void:
	if ev.get("spirit", false) and spirit_views.has(ev.attacker):
		await _anim_spirit_hit(ev)
		return
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
		tw.tween_interval(0.15)
	await tw.finished
	if ranged:
		await _fly_arrow(a.position, t.position, ev.hit)
	if ev.hit:
		Sfx.play(self, "crit" if ev.crit else "hit")
		t.hit_flash()
	else:
		Sfx.play(self, "miss")
		_float_text(t.position, "빗나감", Color(0.8, 0.8, 0.8))
	await get_tree().create_timer(0.25).timeout


## Spirit Guardians 범위(시전자에게서 3칸 안)의 칸마다 옅은 금색 판을 깝니다. 시전자가 움직이면 다시 깝니다
func _sync_auras() -> void:
	for c in combat.creatures:
		var on := c.concentration == "spirit_guardians" and c.is_alive()
		var cur: Dictionary = aura_views.get(c, {})
		if on and cur.get("cell", Vector2i(-99, -99)) == c.cell:
			continue
		if not cur.is_empty():
			cur.node.queue_free()
			aura_views.erase(c)
		if not on:
			continue
		var node := MultiMeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.94, 0.94)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.85, 0.35, 0.3)
		plane.material = mat
		var cells: Array[Vector2i] = []
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var cell := c.cell + Vector2i(dx, dy)
				if grid.in_bounds(cell) and not grid.is_wall(cell) and grid.distance(c.cell, cell) <= 3:
					cells.append(cell)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = plane
		mm.instance_count = cells.size()
		for i in cells.size():
			mm.set_instance_transform(i, Transform3D(Basis(), cell_pos(cells[i]) + Vector3(0, 0.04, 0)))
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		aura_views[c] = {"node": node, "cell": c.cell}


func _anim_spirit_hit(ev: Dictionary) -> void:
	var node: Node3D = spirit_views[ev.attacker]
	var t = views[ev.target]
	var start := node.position
	Sfx.play(self, "swing")
	var tw := create_tween()
	tw.tween_property(node, "position", start.lerp(t.position + Vector3(0, 0.8, 0), 0.6), 0.12)
	tw.tween_property(node, "position", start, 0.15)
	await tw.finished
	if ev.hit:
		Sfx.play(self, "crit" if ev.crit else "hit")
		t.hit_flash()
	else:
		Sfx.play(self, "miss")
		_float_text(t.position, "빗나감", Color(0.8, 0.8, 0.8))
	await get_tree().create_timer(0.25).timeout


func _anim_cast(ev: Dictionary) -> void:
	var a = views[ev.caster]
	var t: Creature = ev.target
	if t != null and t != ev.caster:
		a.set_facing(t.cell - (ev.caster as Creature).cell)
	a.attack(true)
	Sfx.play(self, "cast")
	await get_tree().create_timer(0.2).timeout
	var friendly: bool = t == null or not t.is_hostile_to(ev.caster)
	if t != null and not friendly and t != ev.caster:
		await _fly_orb(a.position, views[t].position)
	if t != null:
		views[t].body.flash(Color(1.0, 0.85, 0.35) if friendly else Color(1.0, 0.95, 0.7))
	await get_tree().create_timer(0.15).timeout


## 화살이 공격자 가슴께에서 대상까지 낮은 포물선으로 날아감. 빗나가면 대상 옆으로 지나쳐 떨어짐
func _fly_arrow(from: Vector3, to: Vector3, hit: bool) -> void:
	var arrow := Node3D.new()
	var model := (load("res://assets/kaykit/items/arrow.gltf") as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * 0.45
	# KayKit 화살은 촉이 -Y 쪽: 눕혀서 촉이 앞(-Z)을 보게
	model.rotation.x = PI / 2.0
	arrow.add_child(model)
	add_child(arrow)
	var a := from + Vector3(0, 0.75, 0)
	var b := to + Vector3(0, 0.65, 0)
	if not hit:
		var side := (b - a).cross(Vector3.UP).normalized() * 0.45
		b = b + side + (b - a).normalized() * 0.8 - Vector3(0, 0.6, 0)
	var dur := clampf(a.distance_to(b) * 0.05, 0.12, 0.4)
	var t := 0.0
	while t < dur:
		var k := t / dur
		var p := a.lerp(b, k) + Vector3(0, sin(k * PI) * 0.25, 0)
		var nxt := a.lerp(b, minf(k + 0.05, 1.0)) + Vector3(0, sin(minf(k + 0.05, 1.0) * PI) * 0.25, 0)
		arrow.position = p
		if nxt.distance_to(p) > 0.001:
			arrow.look_at(nxt, Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()
	arrow.queue_free()


## 공격 주문의 빛 구슬: 빛을 내며 대상에게 날아가 터짐
func _fly_orb(from: Vector3, to: Vector3) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 2.0
	light.omni_range = 2.0
	orb.add_child(light)
	add_child(orb)
	var a := from + Vector3(0, 0.9, 0)
	var b := to + Vector3(0, 0.7, 0)
	orb.position = a
	var tw := create_tween()
	tw.tween_property(orb, "position", b, clampf(a.distance_to(b) * 0.06, 0.15, 0.45)).set_trans(Tween.TRANS_SINE)
	await tw.finished
	var pop := create_tween().set_parallel()
	pop.tween_property(orb, "scale", Vector3.ONE * 2.2, 0.15)
	pop.tween_property(light, "light_energy", 0.0, 0.15)
	pop.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	await pop.finished
	orb.queue_free()


func _anim_vanish(c: Creature) -> void:
	var v = views[c]
	v.set_active(false)
	v.label.visible = false
	v.body.hold("die")
	await get_tree().create_timer(0.9).timeout
	var tw := create_tween()
	tw.tween_property(v, "position:y", v.position.y - 0.7, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
	var keys := "Esc: 던전으로 · R: 다시" if _dungeon() else "F1~F8: 다른 조우 · R: 다시"
	if _dungeon():
		custom["result"] = "win" if combat.winner == 0 else "lose"
	if combat.winner == 0 and not heroes.is_empty():
		# 이긴 전투는 다시 할 수 없음 (XP가 두 번 쌓이지 않게). XP는 파티 인원수로 나눔 [SRD]
		var share: int = combat.xp_earned / heroes.size()
		var level_up := 0
		for i in heroes.size():
			var up: Dictionary = (heroes[i] as HeroState).absorb(party[i], share)
			if up.has("level_up"):
				level_up = up.level_up
		var lead: HeroState = heroes[0]
		result_label.text = "승리!\n경험치 %d → 한 명당 +%d (누적 %d) · 레벨 %d%s\nEsc: 던전으로" % [
			combat.xp_earned, share, lead.xp, lead.level(), "\n레벨 업!" if level_up > 0 else ""]
		if level_up > 0:
			custom["level_up"] = level_up
		Sfx.play(self, "level_up" if level_up > 0 else "win")
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
	if pending_spell != "":
		for c in combat.creatures:
			if Spells.target_error(combat, pc, pending_spell, c) == "":
				_set_overlay(c.cell, "target")
		_update_hover()
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
	if combat == null:
		_action_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T:
		action_mode = true
		get_tree().reload_current_scene()
		return
	if event is InputEventMouseMotion:
		_pick(event.position)
		if _player_turn():
			_refresh_player_turn()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(event.position)
		_click()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if pending_spell != "":
			pending_spell = ""
			dirty = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if ENCOUNTER_KEYS.has(key) and not _dungeon():
			encounter_id = ENCOUNTER_KEYS[key]
			get_tree().reload_current_scene()
		elif key == KEY_R and combat.over and not (not heroes.is_empty() and combat.winner == 0):
			custom.erase("result")
			get_tree().reload_current_scene()
		elif key >= KEY_1 and key <= KEY_3 and key - KEY_1 < weapon_buttons.size():
			weapon_buttons[key - KEY_1].button_pressed = true
			weapon_index = key - KEY_1
			pending_spell = ""
			dirty = true
		elif event.is_action("end_turn"):
			_do_action("end")
		elif event.is_action("back") and pending_spell != "":
			pending_spell = ""
			dirty = true
		elif event.is_action("back"):
			if not heroes.is_empty() and not combat.over:
				# 전투 중 도망: 모두 쓰러져 있었으면 패배, 아니면 지금 HP와 사용 횟수를 그대로 가져감
				if party.all(func(m: Creature) -> bool: return m.is_down() or not m.is_alive()):
					custom["result"] = "lose"
				else:
					for i in heroes.size():
						(heroes[i] as HeroState).absorb(party[i])
			if _dungeon():
				get_tree().change_scene_to_file(str(custom.get("return_scene", "res://scenes/dungeon.tscn")))
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
	if pending_spell != "":
		var nm := Spells.spell_name(pending_spell)
		if hover_creature == null:
			hint_label.text = "%s: 대상을 고르세요 — 우클릭이나 Esc로 취소" % nm
			return
		var err := Spells.target_error(combat, pc, pending_spell, hover_creature)
		if err != "":
			hint_label.text = "%s → %s: %s" % [nm, hover_creature.display_name, err]
		else:
			hint_label.text = "%s → %s (HP %d/%d): %s" % [nm, hover_creature.display_name, hover_creature.hp,
				hover_creature.stats.max_hp, Spells.describe(combat, pc, pending_spell, hover_creature, pending_slot)]
			_set_overlay(hover_cell, "hover")
		return
	if hover_cell.x < 0:
		return
	if hover_creature != null and hover_creature.team == 0 and hover_creature != pc:
		hint_label.text = "%s  HP %d/%d  AC %d%s" % [hover_creature.display_name, hover_creature.hp,
			hover_creature.stats.max_hp, hover_creature.ac(), "  (의식 없음)" if hover_creature.is_down() else ""]
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
	if not _player_turn():
		return
	if pending_spell != "":
		if hover_creature != null and Spells.target_error(combat, pc, pending_spell, hover_creature) == "":
			Spells.cast(combat, pc, pending_spell, hover_creature, pending_slot)
		pending_spell = ""
		dirty = true
		return
	if hover_cell.x < 0:
		return
	if hover_creature != null and hover_creature.team == 1:
		combat.attack(pc, hover_creature, _weapon())
	elif move_opts.has(hover_cell) and hover_cell != pc.cell:
		combat.move(pc, hover_cell)
	dirty = true


# =====================================================================
# 실시간 액션 전투 (단독 전투) [변경]
# =====================================================================

## 같은 맵(MAP)과 조우(F1~F8)를 액션 전투로. 높이 2.0 이상 장애물(나무, 기둥)은 못 지나고, 낮은 담(#)은 나는 몬스터만 넘음
func _start_action() -> void:
	_build_world()
	var d := Dungeon.new(grid.width, grid.height)
	var map := _map()
	for c in grid.heights:
		if _is_wall_char(map, c):
			continue  # 던전 벽(X)은 바닥이 아님: 화살·시야를 막음
		d.set_tile(c, Dungeon.Tile.FLOOR)
		if grid.heights[c] > 0.0:
			d.heights[c] = grid.heights[c]
		if grid.walls.has(c):
			d.obstacles[c] = grid.walls[c]
	action = ActionLayer.new()
	add_child(action)
	action.camera_rig = rig
	action.setup(d, {})
	var foes: Array = custom.foes if _dungeon() else ENCOUNTERS[encounter_id].foes
	var foe_cells: Array = foes.map(func(e: Array) -> Vector2i: return e[1])
	var taken: Array = foe_cells.duplicate()
	var start: Vector2i = custom.get("pc_start", PC_START)
	var members: Array[Creature] = []
	if custom.has("party"):
		heroes = custom.party  # 던전 탐험: 앞 전투의 HP와 사용 횟수를 이어 감
		for h in heroes:
			members.append((h as HeroState).make_creature())
	else:
		for i in HeroState.party_classes.size():
			var h := HeroState.fresh(str(HeroState.party_classes[i]), 1 if i == 0 else 0)
			h.xp = Rules.XP_THRESHOLDS[int(ENCOUNTERS[encounter_id].get("level", 1)) - 1]  # 보스 조우는 그 레벨 파티로
			members.append(h.make_creature())
	for i in members.size():
		var c := members[i]
		party.append(c)
		var cell := start
		if i > 0:
			cell = _free_cell_near(start, taken)
		taken.append(cell)
		action.add_member(c, cell, "player" if i == 0 else "ally")
	pc = party[0]
	for e in foes:
		var id := str(e[0])
		action.add_foe(id, e[1], 0, Catalog.custom_monster(id, custom.get("monster_defs", {})) if _dungeon() else null)
	action.ac.wake_room(-1)
	rig.target = action.views[action.player].model
	_build_action_ui()
	action.message.connect(_action_log)
	action.party_changed.connect(_action_party)
	action.fight_over.connect(func(xp: int) -> void: _action_result(true, xp))
	action.defeated.connect(func() -> void: _action_result(false, 0))
	_action_log("[color=gray]%s[/color]" % _encounter_label())
	_action_party()
	Sfx.play(self, "fight")


func _build_action_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var party_l := Label.new()
	party_l.position = Vector2(16, 12)
	party_l.add_theme_font_size_override("font_size", 18)
	_outline(party_l)
	layer.add_child(party_l)
	var log_l := RichTextLabel.new()
	log_l.bbcode_enabled = true
	log_l.scroll_following = true
	log_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_l.anchor_top = 1.0
	log_l.anchor_bottom = 1.0
	log_l.offset_left = 12
	log_l.offset_top = -230
	log_l.offset_right = 520
	log_l.offset_bottom = -40
	log_l.add_theme_constant_override("outline_size", 4)
	log_l.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(log_l)
	var help_l := Label.new()
	help_l.text = ACTION_HELP_DUNGEON if _dungeon() else ACTION_HELP
	help_l.anchor_top = 1.0
	help_l.anchor_bottom = 1.0
	help_l.offset_left = 12
	help_l.offset_top = -30
	help_l.add_theme_font_size_override("font_size", 14)
	_outline(help_l)
	layer.add_child(help_l)
	var res := Label.new()
	res.visible = false
	res.set_anchors_preset(Control.PRESET_CENTER)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.grow_horizontal = Control.GROW_DIRECTION_BOTH
	res.grow_vertical = Control.GROW_DIRECTION_BOTH
	res.add_theme_font_size_override("font_size", 36)
	_outline(res)
	layer.add_child(res)
	_action_ui = {"party": party_l, "log": log_l, "result": res}


func _action_log(text: String) -> void:
	(_action_ui.log as RichTextLabel).append_text(text + "
")


func _action_party() -> void:
	var lines := PackedStringArray()
	for c in party:
		lines.append("%s  HP %d/%d%s" % [c.stats.display_name, maxi(c.hp, 0), c.stats.max_hp,
			("  물약 %d" % c.resources.potion) if c.resources.get("potion", 0) > 0 else ""])
	(_action_ui.party as Label).text = "
".join(lines)


func _action_result(won: bool, xp: int) -> void:
	var res: Label = _action_ui.result
	if res.visible:
		return
	_action_party()
	if _dungeon():
		custom["result"] = "win" if won else "lose"
	if won and not heroes.is_empty():
		# 던전 전투: XP를 파티 인원수로 나눠 담음 [SRD]. 이긴 전투는 다시 할 수 없음
		var share: int = xp / heroes.size()
		var level_up := 0
		for i in heroes.size():
			var up: Dictionary = (heroes[i] as HeroState).absorb(party[i], share)
			if up.has("level_up"):
				level_up = up.level_up
		if level_up > 0:
			custom["level_up"] = level_up
		var lead: HeroState = heroes[0]
		Sfx.play(self, "level_up" if level_up > 0 else "win")
		res.text = "승리!\n경험치 %d → 한 명당 +%d · 레벨 %d%s\nEsc: 던전으로" % [xp, share, lead.level(),
			"\n레벨 업!" if level_up > 0 else ""]
	else:
		Sfx.play(self, "win" if won else "lose")
		res.text = ("승리!\n경험치 %d" % xp if won else "패배...") + (
			"\nR: 다시 · Esc: 던전으로" if _dungeon() else "\nF1~F8: 다른 조우 · R: 다시 · Esc: 바깥으로")
	res.visible = true


func _action_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.physical_keycode
	var done: bool = (_action_ui.result as Label).visible
	var won_dungeon: bool = done and custom.get("result", "") == "win" and not heroes.is_empty()
	if ENCOUNTER_KEYS.has(key) and not _dungeon():
		encounter_id = ENCOUNTER_KEYS[key]
		get_tree().reload_current_scene()
	elif key == KEY_R and (not _dungeon() or (done and not won_dungeon)):
		custom.erase("result")
		get_tree().reload_current_scene()
	elif key == KEY_T and not done:
		action_mode = false
		get_tree().reload_current_scene()
	elif event.is_action("back"):
		if not _dungeon():
			get_tree().change_scene_to_file("res://scenes/main.tscn")
			return
		if not done and not heroes.is_empty():
			# 싸우다 도망: 모두 쓰러져 있었으면 패배, 아니면 지금 HP와 사용 횟수를 그대로 가져감
			if party.all(func(m: Creature) -> bool: return m.hp <= 0 or not m.is_alive()):
				custom["result"] = "lose"
			else:
				for i in heroes.size():
					(heroes[i] as HeroState).absorb(party[i])
		get_tree().change_scene_to_file(str(custom.get("return_scene", "res://scenes/dungeon.tscn")))
