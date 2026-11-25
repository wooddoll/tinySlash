extends CharacterBody3D

const SpriteFactory = preload("res://scripts/sprite_factory.gd")

## 8방향 인덱스(0 = 카메라를 정면으로 봄, 시계방향 45도씩) -> [시트 행, 좌우반전]
## 왼쪽 계열(5, 6, 7)은 오른쪽 행을 뒤집어서 사용합니다.
const DIR_TO_ROW := [
	[SpriteFactory.Dir.FRONT, false],       # 0 앞
	[SpriteFactory.Dir.FRONT_SIDE, false],  # 1 앞-오른쪽
	[SpriteFactory.Dir.SIDE, false],        # 2 오른쪽
	[SpriteFactory.Dir.BACK_SIDE, false],   # 3 뒤-오른쪽
	[SpriteFactory.Dir.BACK, false],        # 4 뒤
	[SpriteFactory.Dir.BACK_SIDE, true],    # 5 뒤-왼쪽
	[SpriteFactory.Dir.SIDE, true],         # 6 왼쪽
	[SpriteFactory.Dir.FRONT_SIDE, true],   # 7 앞-왼쪽
]

@export var speed := 5.0
@export var acceleration := 30.0
@export var jump_velocity := 6.5
## 이동 방향을 카메라 회전에 맞추기 위한 참조
@export var camera_rig: Node3D

@onready var sprite: Sprite3D = $Sprite3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## 캐릭터가 월드에서 바라보는 방향 (수평). 처음엔 카메라 쪽(+Z)을 봅니다.
var facing := Vector3(0, 0, 1)
var _anim_time := 0.0


func _ready() -> void:
	sprite.texture = SpriteFactory.make_character_sheet()
	sprite.hframes = SpriteFactory.FRAMES
	sprite.vframes = SpriteFactory.DIRECTIONS


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	if camera_rig:
		dir = dir.rotated(Vector3.UP, camera_rig.global_rotation.y)
	if dir.length() > 0.1:
		facing = dir.normalized()

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	move_and_slide()

	_animate(delta, input.length() > 0.1)


## 카메라 기준으로 캐릭터가 어느 쪽을 보고 있는지 8방향 인덱스로 구합니다.
func get_view_direction(camera: Camera3D) -> int:
	var cam_basis := camera.global_basis
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()  # 화면 안쪽
	var x := facing.dot(right)
	var z := facing.dot(forward)
	# 0 = 카메라를 향함, +90도 = 화면 오른쪽, 180도 = 등을 보임
	var angle := atan2(x, -z)
	return posmod(roundi(angle / (PI / 4.0)), 8)


func _animate(delta: float, moving: bool) -> void:
	var col := 0
	if not is_on_floor():
		col = 1
	elif moving:
		_anim_time += delta * 10.0
		col = int(_anim_time) % SpriteFactory.FRAMES
	else:
		_anim_time = 0.0

	var row := 0
	var flip := false
	var camera := get_viewport().get_camera_3d()
	if camera:
		var entry: Array = DIR_TO_ROW[get_view_direction(camera)]
		row = entry[0]
		flip = entry[1]

	sprite.frame_coords = Vector2i(col, row)
	sprite.flip_h = flip
