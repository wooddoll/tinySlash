extends Node3D

const InputSetup = preload("res://scripts/input_setup.gd")
const Kenney = preload("res://scripts/kenney.gd")
const Outdoor = preload("res://scripts/outdoor_terrain.gd")

@export var tree_count := 40
@export var grass_count := 150
@export var decor_count := 40
@export var world_half_size := 18.0

@onready var decor: Node3D = $Decor
## 0이면 실행할 때마다 새 지형
@export var terrain_seed := 0

## 만든 지형 (Terrain3D가 없으면 null: 예전 평평한 풀밭 + Kenney 나무)
var outdoor: Node3D = null
var _seed := 0


func _ready() -> void:
	InputSetup.register()
	if not _build_terrain():
		_scatter_decor()
	_add_hint()


## Terrain3D가 설치돼 있으면 노이즈 언덕·숲 지형을 만들고 평평한 바닥·연습용 돌 블록을 치움
func _build_terrain() -> bool:
	if not Outdoor.available():
		return false
	_seed = terrain_seed if terrain_seed != 0 else randi() % 100000 + 1
	outdoor = Outdoor.new()
	outdoor.name = "Outdoor"
	add_child(outdoor)
	if not outdoor.generate(_seed):
		outdoor.queue_free()
		outdoor = null
		return false
	$Ground.queue_free()
	$Props.queue_free()
	# 빈터 가운데에 세움 (조금 위에서 떨어져 땅에 닿음)
	var player := $Player as Node3D
	player.global_position = Vector3(0, outdoor.height_at(Vector3.ZERO) + 0.3, 0)
	($CameraRig as Node3D).global_position = player.global_position
	return true


func _process(_delta: float) -> void:
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
