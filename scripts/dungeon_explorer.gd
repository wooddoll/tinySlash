## 던전 안을 걸어 다니는 플레이어. 물리 엔진 대신 던전 격자로 직접 충돌을 판정합니다.
## 서 있을 수 없는 칸(벽, 기둥, 바위)은 막히고, 높이는 지금 칸의 바닥 높이를 따라갑니다.
extends Node3D

const CharacterModel = preload("res://scripts/character_model.gd")

## 새 칸에 들어설 때마다 (이전 칸, 새 칸)
signal entered_cell(from: Vector2i, to: Vector2i)

const RADIUS := 0.28

@export var speed := 4.5
var dungeon: Dungeon
## 이동 방향을 카메라 회전에 맞추기 위한 참조
var camera_rig: Node3D
var active := true
var cell := Vector2i(-1, -1)
var body: CharacterModel


func setup(d: Dungeon, at: Vector2i, model := "mini-characters/character-knight",
		weapon := "mini-characters/weapon-sword") -> void:
	dungeon = d
	cell = at
	position = Vector3(at.x + 0.5, d.get_height(at), at.y + 0.5)
	body = CharacterModel.new()
	add_child(body)
	body.setup(model, 1.0, weapon)
	body.face(Vector3(0, 0, 1), true)


## 반지름 r인 원이 p(월드 x, z)에 설 수 있는지: 원을 감싼 네 귀퉁이가 모두 서 있을 수 있는 칸이어야 함
static func can_stand(d: Dungeon, p: Vector2, r := RADIUS) -> bool:
	for sx in [-r, r]:
		for sy in [-r, r]:
			if not d.is_walkable(Vector2i(floori(p.x + sx), floori(p.y + sy))):
				return false
	return true


func _physics_process(delta: float) -> void:
	if dungeon == null:
		return
	var dir := Vector3.ZERO
	if active:
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		dir = Vector3(input.x, 0.0, input.y)
		if camera_rig:
			dir = dir.rotated(Vector3.UP, camera_rig.global_rotation.y)
	var moving := dir.length() > 0.1
	if moving:
		dir = dir.normalized()
		body.face(dir)
		var step := dir * speed * delta
		# 축마다 따로 시험해서 벽을 따라 미끄러지게
		var p := Vector2(position.x, position.z)
		if can_stand(dungeon, p + Vector2(step.x, 0)):
			p.x += step.x
		if can_stand(dungeon, p + Vector2(0, step.z)):
			p.y += step.z
		position.x = p.x
		position.z = p.y
	body.set_base("sprint" if moving else "idle")

	var now := Vector2i(floori(position.x), floori(position.z))
	position.y = lerpf(position.y, dungeon.get_height(now), 1.0 - exp(-14.0 * delta))
	if now != cell:
		var before := cell
		cell = now
		entered_cell.emit(before, now)
