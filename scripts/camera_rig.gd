## 대상을 부드럽게 따라가는 카메라.
## isometric = true: 직교 투영 + 45도 대각선 시점. Q/E로 90도 회전, 마우스 휠로 줌.
## isometric = false: 원근 투영 + 뒤에서 내려다보는 시점. Q/E로 45도 회전.
extends Node3D

@export var target: Node3D
@export var follow_speed := 6.0
@export var rotate_speed := 8.0

@export_group("Isometric")
@export var isometric := true
## 30도 = 픽셀아트 게임에서 흔한 2:1 비율, 35.264도 = 진짜 아이소메트릭
@export var pitch_deg := 30.0
@export var yaw_offset_deg := 45.0
## 화면에 보이는 세로 높이 (월드 유닛)
@export var ortho_size := 10.0
@export var min_ortho_size := 5.0
@export var max_ortho_size := 22.0
## 직교 카메라가 지형 뒤로 물러나 있는 거리 (화면 크기와는 무관)
@export var iso_distance := 30.0

@export_group("Perspective")
@export var height := 6.0
@export var distance := 9.0

@onready var camera: Camera3D = $Camera3D

## 대상에서 비켜 볼 자리 (전투 때 적 쪽으로), 화면을 더 넓게 볼 양 (월드 유닛). 바깥에서 정하면 부드럽게 따라감
var look_offset := Vector3.ZERO
var zoom_bonus := 0.0
var _offset := Vector3.ZERO
var _bonus := 0.0
var _shake := 0.0
var _cam_base := Vector3.ZERO

var _target_yaw := 0.0
var _rotate_step := 90.0


func _ready() -> void:
	if isometric:
		var p := deg_to_rad(pitch_deg)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ortho_size
		camera.position = Vector3(0.0, sin(p) * iso_distance, cos(p) * iso_distance)
		camera.rotation = Vector3(-p, 0.0, 0.0)
		rotation.y = deg_to_rad(yaw_offset_deg)
		_rotate_step = 90.0
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = Vector3(0.0, height, distance)
		camera.rotation = Vector3(-atan2(height, distance) + 0.08, 0.0, 0.0)
		_rotate_step = 45.0
	if target:
		global_position = target.global_position
	_target_yaw = rotation.y
	_cam_base = camera.position


## 화면 흔들기 (월드 유닛, 0.1~0.3 정도). 금방 잦아듦
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	_offset = _offset.lerp(look_offset, 1.0 - exp(-3.0 * delta))
	_bonus = lerpf(_bonus, zoom_bonus, 1.0 - exp(-2.5 * delta))
	if target:
		var t := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target.global_position + _offset, t)
	if _shake > 0.001:
		camera.position = _cam_base + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake
		_shake = move_toward(_shake, 0.0, 1.5 * delta)
	elif camera.position != _cam_base:
		camera.position = _cam_base

	if Input.is_action_just_pressed("cam_left"):
		_target_yaw -= deg_to_rad(_rotate_step)
	if Input.is_action_just_pressed("cam_right"):
		_target_yaw += deg_to_rad(_rotate_step)
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-rotate_speed * delta))

	if isometric:
		camera.size = lerpf(camera.size, ortho_size + _bonus, 1.0 - exp(-10.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if not isometric or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		ortho_size = clampf(ortho_size * 0.9, min_ortho_size, max_ortho_size)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		ortho_size = clampf(ortho_size / 0.9, min_ortho_size, max_ortho_size)
