## 전투 격자 위 크리처 한 명의 모습 (8방향 스프라이트 + 이름/HP 표시)
extends Node3D

const SpriteFactory = preload("res://scripts/sprite_factory.gd")
const Player = preload("res://scripts/player.gd")

var creature: Creature
var sprite: Sprite3D
var label: Label3D
var marker: Label3D
var facing := Vector3(0, 0, 1)
var walking := false
var shown_hp := 0
var _anim := 0.0
var _base_y := 0.0


func setup(c: Creature, tex: Texture2D) -> void:
	creature = c
	var s := c.stats.sprite_scale
	sprite = Sprite3D.new()
	sprite.texture = tex
	sprite.hframes = SpriteFactory.FRAMES
	sprite.vframes = SpriteFactory.DIRECTIONS
	sprite.pixel_size = 0.0625 * s
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = true
	sprite.modulate = c.stats.tint
	_base_y = 0.75 * s
	sprite.position.y = _base_y
	add_child(sprite)

	label = _make_label(40)
	label.position.y = 1.5 * s + 0.25
	add_child(label)
	marker = _make_label(64)
	marker.text = "▼"
	marker.modulate = Color(1, 0.9, 0.2)
	marker.position.y = label.position.y + 0.45
	marker.visible = false
	add_child(marker)

	# 마우스로 고를 수 있게 충돌체를 붙입니다
	var body := StaticBody3D.new()
	body.set_meta("creature", c)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4 * s
	shape.shape = cap
	shape.position.y = 0.7 * s
	body.add_child(shape)
	add_child(body)

	shown_hp = c.hp
	set_facing(c.facing)
	refresh()


func _make_label(size: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = size
	l.pixel_size = 0.004
	l.outline_size = 10
	l.render_priority = 2
	return l


func set_facing(d: Vector2i) -> void:
	if d != Vector2i.ZERO:
		facing = Vector3(d.x, 0, d.y).normalized()


func set_hp(hp: int) -> void:
	shown_hp = hp
	refresh()


func set_active(active: bool) -> void:
	marker.visible = active


func refresh() -> void:
	var state := ""
	if creature.has_condition("unconscious"):
		state = " (의식 없음)"
	elif creature.has_condition("prone"):
		state = " (넘어짐)"
	label.text = "%s%s\n%d/%d" % [creature.display_name, state, shown_hp, creature.stats.max_hp]
	label.modulate = Color(1, 0.5, 0.45) if shown_hp * 2 <= creature.stats.max_hp else Color.WHITE
	# 넘어지면 몸을 낮춰서 보여줍니다
	sprite.position.y = _base_y * (0.55 if creature.has_condition("prone") else 1.0)


func _process(delta: float) -> void:
	if sprite == null:
		return
	var col := 0
	if walking:
		_anim += delta * 10.0
		col = int(_anim) % SpriteFactory.FRAMES
	var row := 0
	var flip := false
	var cam := get_viewport().get_camera_3d()
	if cam:
		var entry: Array = Player.DIR_TO_ROW[_view_dir(cam)]
		row = entry[0]
		flip = entry[1]
	sprite.frame_coords = Vector2i(col, row)
	sprite.flip_h = flip


func _view_dir(cam: Camera3D) -> int:
	var b := cam.global_basis
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var forward := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var angle := atan2(facing.dot(right), -facing.dot(forward))
	return posmod(roundi(angle / (PI / 4.0)), 8)
