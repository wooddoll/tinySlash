extends Node3D

const InputSetup = preload("res://scripts/input_setup.gd")
const Kenney = preload("res://scripts/kenney.gd")

@export var tree_count := 40
@export var grass_count := 150
@export var decor_count := 40
@export var world_half_size := 18.0

@onready var decor: Node3D = $Decor


func _ready() -> void:
	InputSetup.register()
	_scatter_decor()
	_add_hint()


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
	label.text = "WASD 이동 · Space 점프 · Q/E 카메라 90° 회전 · 휠 줌 · B 전투 시작 · G 던전 생성기 · H 모험(시나리오)"
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
