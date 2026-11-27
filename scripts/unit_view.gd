## 전투 격자 위 크리처 한 명의 모습 (Kenney 3D 모델 + 이름/HP 표시)
extends Node3D

const CharacterModel = preload("res://scripts/character_model.gd")

## 비행 크리처가 떠 있는 높이 (가구 높이 1.0 근처)
const FLY_HEIGHT := 0.9

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
	body.tint(c.stats.tint)
	if c.stats.has_feature("flying"):
		body.set_hover(FLY_HEIGHT)

	label = _make_label(40)
	label.position.y = body.height + body.hover + 0.35
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
	shape.position.y = cap.height / 2.0 + body.hover
	col.add_child(shape)
	add_child(col)

	shown_hp = c.hp
	set_facing(c.facing, true)
	refresh()


## 스탯의 모델이 바뀌었을 때 (Wild Shape) 몸을 새로 만듦
func reshape() -> void:
	if body:
		body.queue_free()
	body = CharacterModel.new()
	add_child(body)
	body.setup(creature.stats.model, creature.stats.sprite_scale, creature.stats.weapon_model)
	body.tint(creature.stats.tint)
	label.position.y = body.height + body.hover + 0.35
	marker.position.y = label.position.y + 0.45
	set_facing(creature.facing, true)
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
	if creature and not creature.dead:
		body.play_once("hit")


func refresh() -> void:
	var state := ""
	if creature.has_condition("unconscious"):
		state = " (의식 없음)"
	elif creature.has_condition("prone"):
		state = " (넘어짐)"
	label.text = "%s%s\n%d/%d" % [creature.display_name, state, shown_hp, creature.stats.max_hp]
	label.modulate = Color(1, 0.5, 0.45) if shown_hp * 2 <= creature.stats.max_hp else Color.WHITE
	_update_pose()


## 쓰러짐 > 넘어짐(웅크림) > 걷기 > 서 있기 (체력 절반 이하면 다친 자세로)
func _update_pose() -> void:
	if body == null or creature == null:
		return
	if creature.dead or creature.has_condition("unconscious"):
		body.hold("die")
	elif creature.has_condition("prone"):
		body.set_base("crouch")
	elif walking:
		body.set_base("walk")
	elif shown_hp * 2 <= creature.stats.max_hp:
		body.set_base("hurt")
	else:
		body.set_base("idle")
