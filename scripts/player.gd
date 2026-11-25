## 탐험 중 플레이어. 카메라 기준으로 움직이고, Kenney 3D 모델이 이동 방향을 봅니다.
extends CharacterBody3D

const CharacterModel = preload("res://scripts/character_model.gd")

@export var speed := 5.0
@export var acceleration := 30.0
@export var jump_velocity := 6.5
## 이동 방향을 카메라 회전에 맞추기 위한 참조
@export var camera_rig: Node3D
@export var model := "mini-characters/character-knight"
@export var weapon_model := "mini-characters/weapon-sword"

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## 캐릭터가 월드에서 바라보는 방향 (수평). 처음엔 카메라 쪽(+Z)을 봅니다.
var facing := Vector3(0, 0, 1)
var body: CharacterModel


func _ready() -> void:
	body = CharacterModel.new()
	add_child(body)
	body.setup(model, 1.0, weapon_model)
	body.face(facing, true)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		body.play_once("jump")

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	if camera_rig:
		dir = dir.rotated(Vector3.UP, camera_rig.global_rotation.y)
	var moving := dir.length() > 0.1
	if moving:
		facing = dir.normalized()
		body.face(facing)

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	move_and_slide()

	if is_on_floor():
		body.set_base("sprint" if moving else "idle")
