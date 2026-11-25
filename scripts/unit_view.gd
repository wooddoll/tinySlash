## 전투 격자 위 크리처 한 명의 모습 (Kenney 3D 모델 + 이름/HP 표시)
extends Node3D

const CharacterModel = preload("res://scripts/character_model.gd")

var creature: Creature
var body: CharacterModel
var label: Label3D
var marker: Label3D
var shown_hp := 0
## 이동 중이면 걷기 동작
var walking := false:
	set(v):
		walking = v
		_update_pose()


func setup(c: Creature) -> void:
	creature = c
	var s := c.stats.sprite_scale
	body = CharacterModel.new()
	add_child(body)
	body.setup(c.stats.model, s, c.stats.weapon_model)

	label = _make_label(40)
	label.position.y = body.height + 0.35
	add_child(label)
	marker = _make_label(64)
	marker.text = "▼"
	marker.modulate = Color(1, 0.9, 0.2)
	marker.position.y = label.position.y + 0.45
	marker.visible = false
	add_child(marker)

	# 마우스로 고를 수 있게 충돌체를 붙입니다
	var col := StaticBody3D.new()
	col.set_meta("creature", c)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = maxf(body.height, 0.8)
	shape.shape = cap
	shape.position.y = cap.height / 2.0
	col.add_child(shape)
	add_child(col)

	shown_hp = c.hp
	set_facing(c.facing, true)
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


func set_facing(d: Vector2i, instant := false) -> void:
	if d != Vector2i.ZERO:
		body.face(Vector3(d.x, 0, d.y), instant)


func set_hp(hp: int) -> void:
	shown_hp = hp
	refresh()


func set_active(active: bool) -> void:
	marker.visible = active


## 공격 동작. 원거리면 쏘는 자세
func attack(ranged: bool) -> void:
	body.play_once("holding-right-shoot" if ranged else "attack-melee-right")


func hit_flash() -> void:
	body.flash()


func refresh() -> void:
	var state := ""
	if creature.has_condition("unconscious"):
		state = " (의식 없음)"
	elif creature.has_condition("prone"):
		state = " (넘어짐)"
	label.text = "%s%s\n%d/%d" % [creature.display_name, state, shown_hp, creature.stats.max_hp]
	label.modulate = Color(1, 0.5, 0.45) if shown_hp * 2 <= creature.stats.max_hp else Color.WHITE
	_update_pose()


## 쓰러짐 > 넘어짐(웅크림) > 걷기 > 서 있기
func _update_pose() -> void:
	if body == null or creature == null:
		return
	if creature.dead or creature.has_condition("unconscious"):
		body.hold("die")
	elif creature.has_condition("prone"):
		body.set_base("crouch")
	elif walking:
		body.set_base("walk")
	else:
		body.set_base("idle")
