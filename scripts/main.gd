extends Node3D

const InputSetup = preload("res://scripts/input_setup.gd")
const Kenney = preload("res://scripts/kenney.gd")
const Outdoor = preload("res://scripts/outdoor_terrain.gd")
const DungeonView = preload("res://scripts/dungeon_view.gd")
const Battle = preload("res://scripts/battle.gd")
const Monsters = preload("res://scripts/outdoor_monsters.gd")

@export var tree_count := 40
@export var grass_count := 150
@export var decor_count := 40
@export var world_half_size := 18.0

@onready var decor: Node3D = $Decor
## 0이면 실행할 때마다 새 지형
@export var terrain_seed := 0

## 이번 판의 바깥 세상 시드 (던전에 다녀와도 같은 지형), 던전에서 돌아왔으면 입구 앞에서 시작
static var world_seed := 0
static var back_from_dungeon := false
## 이 세상에서 물리친 바깥 몬스터 무리 번호
static var defeated := {}
## 바깥 몬스터와 싸우러 가기 직전 자리 (도망쳐 오면 여기로)
static var _fight_pos := Vector3.INF
## 바깥 전투 지도의 풀밭 크기와 시작 자리
const FIELD_W := 14
const FIELD_H := 10
const FIELD_PC := Vector2i(2, 5)
const FIELD_FOES := [Vector2i(11, 4), Vector2i(11, 7), Vector2i(12, 5)]

## 만든 지형 (Terrain3D가 없으면 null: 예전 평평한 풀밭 + Kenney 나무)
var outdoor: Node3D = null
var monsters: Node3D = null
var _seed := 0
var _toast_label: Label
var _toast_left := 0.0
var _pending_toast := ""


func _ready() -> void:
	InputSetup.register()
	if not _build_terrain():
		_scatter_decor()
	_add_hint()
	if _pending_toast != "":
		_toast(_pending_toast)


## Terrain3D가 설치돼 있으면 노이즈 언덕·숲 지형을 만들고 평평한 바닥·연습용 돌 블록을 치움
func _build_terrain() -> bool:
	if not Outdoor.available():
		return false
	if world_seed == 0:
		world_seed = terrain_seed if terrain_seed != 0 else randi() % 100000 + 1
	_seed = world_seed
	outdoor = Outdoor.new()
	outdoor.name = "Outdoor"
	add_child(outdoor)
	if not outdoor.generate(_seed):
		outdoor.queue_free()
		outdoor = null
		return false
	$Ground.queue_free()
	$Props.queue_free()
	# 빈터 가운데에 세움 (조금 위에서 떨어져 땅에 닿음). 던전에서 나왔으면 입구 앞
	var player := $Player as Node3D
	player.global_position = Vector3(0, outdoor.height_at(Vector3.ZERO) + 0.3, 0)
	if back_from_dungeon:
		back_from_dungeon = false
		player.global_position = outdoor.before_entrance()
	outdoor.entrance_entered.connect(_enter_dungeon)
	var calm := _take_battle_result(player)
	monsters = Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	monsters.spawn(outdoor, world_seed, defeated, player)
	monsters.calm = calm
	monsters.engaged.connect(_fight_outdoor)
	($CameraRig as Node3D).global_position = player.global_position
	return true


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast_label.modulate.a = clampf(_toast_left, 0.0, 1.0)
	# v1: 탐험 중 조우 대신 B 키로 전투 장면을 엽니다
	if Input.is_action_just_pressed("start_battle"):
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
	elif Input.is_action_just_pressed("open_dungeon"):
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
	elif Input.is_action_just_pressed("open_scenario"):
		get_tree().change_scene_to_file("res://scenes/scenario.tscn")


func _add_hint() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = ("지형 시드 %d · " % _seed if outdoor else "") + "WASD 이동 · Space 점프 · Q/E 카메라 90° 회전 · 휠 줌 · B 전투 시작 · G 던전 생성기 · H 모험(시나리오)"
	label.position = Vector2(16, 12)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(label)
	add_child(layer)


## 나무, 풀, 꽃, 바위 같은 Nature Kit 모델을 흩뿌립니다. 나무에는 충돌체를 붙입니다.
func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025

	for i in tree_count:
		var pos := _random_pos(rng, 5.0)
		var tree := Kenney.instance(Kenney.TREES[rng.randi() % Kenney.TREES.size()], Kenney.NATURE)
		tree.scale = Vector3.ONE * rng.randf_range(2.0, 2.8)
		tree.rotation.y = rng.randf() * TAU
		tree.position = pos
		decor.add_child(tree)
		# 나무에 부딪히도록 충돌체 추가
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.25
		cyl.height = 2.0
		shape.shape = cyl
		body.position = pos + Vector3(0, 1.0, 0)
		body.add_child(shape)
		decor.add_child(body)

	for i in grass_count:
		var g := Kenney.instance(Kenney.GRASS[rng.randi() % Kenney.GRASS.size()], Kenney.NATURE)
		g.scale = Vector3.ONE * rng.randf_range(1.6, 2.4)
		g.rotation.y = rng.randf() * TAU
		g.position = _random_pos(rng, 1.5)
		decor.add_child(g)

	for i in decor_count:
		var dcr := Kenney.instance(Kenney.DECOR[rng.randi() % Kenney.DECOR.size()], Kenney.NATURE)
		dcr.scale = Vector3.ONE * rng.randf_range(1.8, 2.6)
		dcr.rotation.y = rng.randf() * TAU
		dcr.position = _random_pos(rng, 3.0)
		decor.add_child(dcr)


func _random_pos(rng: RandomNumberGenerator, keep_clear: float) -> Vector3:
	while true:
		var p := Vector3(rng.randf_range(-world_half_size, world_half_size), 0.0,
				rng.randf_range(-world_half_size, world_half_size))
		if p.length() > keep_clear:
			return p
	return Vector3.ZERO


## 입구 문턱을 넘으면 이 세상 시드로 정한 던전에서 바로 탐험 시작
func _enter_dungeon(_body: Node3D) -> void:
	if get_tree().paused:
		return
	DungeonView.enter_seed = world_seed * 31 + 7
	back_from_dungeon = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/dungeon.tscn")


## 바깥 전투에서 돌아왔으면 결과를 반영: 이기면 그 무리는 사라지고, 지면 빈터에서 다시 (기력 회복),
## 도망치면 싸우기 전 자리. 몬스터가 바로 다시 덤비지 않게 잠깐 조용히 (초)
func _take_battle_result(player: Node3D) -> float:
	if not Battle.custom.has("outdoor_group"):
		return 0.0
	var res := str(Battle.custom.get("result", ""))
	var calm := 4.0
	if res == "win":
		defeated[int(Battle.custom.outdoor_group)] = true
		_pending_toast = "물리쳤어요!" + (" 레벨 업! %d레벨" % Battle.custom.level_up if Battle.custom.has("level_up") else "")
		calm = 1.0
	elif res == "lose":
		for h in DungeonView.party():
			(h as HeroState).long_rest()
		_pending_toast = "쓰러졌어요… 빈터에서 정신을 차렸어요 (기력 회복)"
	else:
		_pending_toast = "도망쳤어요"
	if res != "lose" and _fight_pos != Vector3.INF:
		player.global_position = _fight_pos
	_fight_pos = Vector3.INF
	Battle.custom = {}
	return calm


## 바깥 몬스터 무리와 마주침: 풀밭 전투 지도로 (파티는 던전 탐험과 같은 HeroState)
func _fight_outdoor(group: int) -> void:
	if DungeonView.hero == null:
		DungeonView.hero = DungeonView._fresh_member(0)
	if DungeonView.ally == null:
		DungeonView.ally = DungeonView._fresh_member(1)
	var player := $Player as Node3D
	_fight_pos = player.global_position
	player.set_physics_process(false)
	var foes: Array = []
	var ids: Array = monsters.foes_of(group)
	for i in ids.size():
		foes.append([ids[i], FIELD_FOES[i % FIELD_FOES.size()]])
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 101 + group
	Battle.custom = {"map": field_map(rng), "pc_start": FIELD_PC, "foes": foes, "label": monsters.label(group),
			"style": "outdoor", "return_scene": "res://scenes/main.tscn", "outdoor_group": group,
			"party": DungeonView.party()}
	_toast("몬스터 발견! — " + monsters.label(group))
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


## 바깥 전투용 풀밭: 나무(T)·덤불(,)·바위(#)를 조금 흩뿌림. 시작 자리와 몬스터 자리 둘레는 비움
static func field_map(rng: RandomNumberGenerator) -> Array:
	var rows: Array = []
	for y in FIELD_H:
		var row := ""
		for x in FIELD_W:
			var c := Vector2i(x, y)
			var ch := "."
			var clear := (c - FIELD_PC).length() < 2.0 or FIELD_FOES.any(func(f: Vector2i) -> bool: return (c - f).length() < 1.5)
			if not clear:
				var r := rng.randf()
				if r < 0.07:
					ch = "T"
				elif r < 0.14:
					ch = ","
				elif r < 0.17:
					ch = "#"
			row += ch
		rows.append(row)
	return rows


func _toast(text: String) -> void:
	if _toast_label == null:
		var layer := CanvasLayer.new()
		_toast_label = Label.new()
		_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_toast_label.position.y = 120
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast_label.add_theme_font_size_override("font_size", 28)
		_toast_label.add_theme_constant_override("outline_size", 8)
		_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(_toast_label)
		add_child(layer)
	_toast_label.text = text
	_toast_left = 3.0
	_toast_label.modulate.a = 1.0
