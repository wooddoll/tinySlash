extends Node3D

const SpriteFactory = preload("res://scripts/sprite_factory.gd")
const InputSetup = preload("res://scripts/input_setup.gd")

@export var tree_count := 40
@export var grass_count := 150
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


func _add_hint() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "WASD 이동 · Space 점프 · Q/E 카메라 90° 회전 · 휠 줌 · B 전투 시작 · G 던전 생성기"
	label.position = Vector2(16, 12)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(label)
	add_child(layer)


## 나무와 풀을 빌보드 스프라이트로 흩뿌립니다.
func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025
	var tree_tex := SpriteFactory.make_tree()
	var grass_tex := SpriteFactory.make_grass()

	for i in tree_count:
		var pos := _random_pos(rng, 5.0)
		var s := _make_billboard(tree_tex, 1.0 / 12.0)
		s.position = pos + Vector3(0, 2.0, 0)
		decor.add_child(s)
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
		var g := _make_billboard(grass_tex, 1.0 / 16.0)
		g.position = _random_pos(rng, 1.5) + Vector3(0, 0.19, 0)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		decor.add_child(g)


func _random_pos(rng: RandomNumberGenerator, keep_clear: float) -> Vector3:
	while true:
		var p := Vector3(rng.randf_range(-world_half_size, world_half_size), 0.0,
				rng.randf_range(-world_half_size, world_half_size))
		if p.length() > keep_clear:
			return p
	return Vector3.ZERO


func _make_billboard(tex: Texture2D, pixel_size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = pixel_size
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	return s
