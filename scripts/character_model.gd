## Kenney 3D 캐릭터 모델 하나. 애니메이션, 방향 돌리기, 맞았을 때 번쩍임, 무기 붙이기.
## 모델 경로는 "팩/이름" (예: "mini-characters/character-knight").
extends Node3D

const Kenney = preload("res://scripts/kenney.gd")
const LOOPING := ["idle", "walk", "sprint", "crouch"]
## 모델 원래 키는 약 0.8 유닛. 1칸(1 유닛)에 맞게 키웁니다.
const BASE_SCALE := 1.6

var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
## 높이 (월드 유닛). 이름표 위치에 씁니다.
var height := 1.25
var _base := "idle"
var _yaw := 0.0
var _flash_mat: StandardMaterial3D
var _weapon: Node3D
var _held := ""


func setup(path: String, size := 1.0, weapon := "") -> void:
	var parts := path.split("/")
	model = Kenney.instance(parts[1], parts[0])
	var s := BASE_SCALE * size
	model.scale = Vector3.ONE * s
	height = 0.8 * s
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if anim:
		for a in LOOPING:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		anim.animation_finished.connect(_on_finished)
	if weapon != "" and skeleton:
		_attach_weapon(weapon)
	set_base("idle")


## 계속 반복할 기본 동작 (idle, walk, crouch)
func set_base(n: String) -> void:
	if _base == n and anim and anim.current_animation == n:
		return
	_held = ""
	_base = n
	_play(n, 0.15)


## 한 번만 하고 기본 동작으로 돌아감 (공격 등)
func play_once(n: String) -> void:
	if _held != "":
		return
	_play(n, 0.06)


## 한 번 하고 마지막 자세로 멈춤 (쓰러짐)
func hold(n: String) -> void:
	if _held == n:
		return
	_held = n
	_base = ""
	_play(n, 0.06)


func face(dir: Vector3, instant := false) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	_yaw = atan2(dir.x, dir.z)
	if instant:
		rotation.y = _yaw


## 맞았을 때 붉게 번쩍임
func flash(color := Color(1, 0.15, 0.1)) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for m in _meshes(model):
			m.material_overlay = _flash_mat
	_flash_mat.albedo_color = Color(color, 0.7)
	var tw := create_tween()
	tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.25)


func _process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-14.0 * delta))
	if _weapon:
		# 위치는 손을 따라가고, 방향은 몸 기준으로 날이 위·앞을 향하게 고정
		var b := model.global_basis
		_weapon.global_basis = b * Basis(Vector3.RIGHT, deg_to_rad(35.0))


func _play(n: String, blend: float) -> void:
	if anim and anim.has_animation(n):
		anim.play(n, blend)


func _on_finished(_n: StringName) -> void:
	if _base != "":
		_play(_base, 0.15)


## 오른팔 뼈에 무기 모델을 붙입니다 (Mini Dungeon / Mini Characters의 weapon-*.glb)
func _attach_weapon(path: String) -> void:
	var parts := path.split("/")
	var holder := BoneAttachment3D.new()
	holder.bone_name = "arm-right"
	skeleton.add_child(holder)
	var w := Kenney.instance(parts[1], parts[0])
	# 뼈 공간: 어깨가 원점이고 손은 아래쪽 바깥
	w.position = Vector3(-0.1, -0.15, 0.04)
	holder.add_child(w)
	_weapon = w


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
