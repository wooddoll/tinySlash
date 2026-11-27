## 카메라와 캐릭터(또는 몹) 사이에 선 벽을 반투명하게 합니다.
## Kenney.build_edge_walls가 벽을 만들 때 같이 붙입니다. 캐릭터는 "wall_fade_target" 무리에 든 노드
## (CharacterModel이 스스로 들어감). 벽 조각마다 MultiMesh 색의 알파를 낮추고, 재질은 알파 해시(점묘)라
## 정렬 문제 없이 비쳐 보입니다.
extends Node

const GROUP := "wall_fade_target"
## 비칠 때 알파 (점묘라 0.35면 벽 무늬는 남고 뒤가 잘 보임)
const FADED := 0.25
## 벽 높이(칸)와 캐릭터 가슴 높이: 이 사이를 지나는 시선만 가려진다고 봄
const WALL_H := 1.75
const CHEST := 0.6
## 시선에서 이만큼(칸) 옆까지는 같이 비침 (몸 너비 + 벽판 반 칸)
const SIDE := 0.85
## 알파가 바뀌는 빠르기 (1초에)
const SPEED := 6.0

## [MultiMesh, 변환들]
var _parts: Array = []
## 칸 → [[조각 번호, 인스턴스 번호], ...]
var _by_cell := {}
## "조각:인스턴스" → 지금 알파 (1이 아닌 것만)
var _alpha := {}


func setup(parts: Array) -> void:
	_parts = parts
	for pi in parts.size():
		var xfs: Array = parts[pi][1]
		for i in xfs.size():
			var o: Vector3 = (xfs[i] as Transform3D).origin
			var c := Vector2i(floori(o.x), floori(o.z))
			if not _by_cell.has(c):
				_by_cell[c] = []
			_by_cell[c].append([pi, i])


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _parts.is_empty():
		return
	var want := {}
	var eye := cam.global_position
	for n in get_tree().get_nodes_in_group(GROUP):
		var t := n as Node3D
		if t == null or not t.is_visible_in_tree():
			continue
		_mark(t.global_position, eye, want)
	# 알파를 목표 쪽으로 천천히
	var keys := {}
	for k in _alpha:
		keys[k] = true
	for k in want:
		keys[k] = true
	var step := SPEED * delta
	for k in keys:
		var target := FADED if want.has(k) else 1.0
		var a: float = move_toward(_alpha.get(k, 1.0), target, step)
		var p: PackedInt32Array = k
		(_parts[p[0]][0] as MultiMesh).set_instance_color(p[1], Color(1, 1, 1, a))
		if a >= 1.0:
			_alpha.erase(k)
		else:
			_alpha[k] = a


## 이 캐릭터를 가리는 벽 조각을 want에 넣음
func _mark(t: Vector3, eye: Vector3, want: Dictionary) -> void:
	var to_eye := Vector2(eye.x - t.x, eye.z - t.z)
	var dist := to_eye.length()
	if dist < 0.01:
		return
	var dir := to_eye / dist
	# 가슴에서 카메라로 가는 시선이 벽 꼭대기 높이에 닿는 수평 거리
	var rise := (eye.y - t.y - CHEST) / dist
	var reach := (WALL_H - CHEST) / maxf(rise, 0.05) + 0.6
	reach = minf(reach, 4.0)
	var cx := floori(t.x)
	var cz := floori(t.z)
	var r := ceili(reach) + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var list: Array = _by_cell.get(Vector2i(cx + dx, cz + dz), [])
			for e in list:
				var o: Vector3 = (_parts[e[0]][1][e[1]] as Transform3D).origin
				if o.y > t.y + CHEST:
					continue  # 위층(높은 단) 벽은 따로 보지 않음
				var v := Vector2(o.x - t.x, o.z - t.z)
				var along := v.dot(dir)
				if along < 0.15 or along > reach:
					continue
				if (v - dir * along).length() > SIDE:
					continue
				want[PackedInt32Array([e[0], e[1]])] = true
