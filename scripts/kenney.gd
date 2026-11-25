## Kenney 에셋(CC0)에서 메시를 꺼내 쓰는 도우미. assets/kenney/<팩>/<이름>.glb
## Mini Dungeon 조각은 바닥 1x1 유닛, 바닥면 y=0, 가운데가 원점이라 격자 칸에 그대로 맞습니다.
extends RefCounted

const DUNGEON := "mini-dungeon"

static var _meshes := {}


## GLB 안의 첫 MeshInstance3D 메시 (MultiMesh에 쓰기 좋음)
static func mesh(model: String, pack := DUNGEON) -> Mesh:
	var key := pack + "/" + model
	if _meshes.has(key):
		return _meshes[key]
	var scene := load("res://assets/kenney/%s/%s.glb" % [pack, model]) as PackedScene
	var found: Mesh = null
	if scene:
		var inst := scene.instantiate()
		var mi := _first_mesh(inst)
		if mi:
			found = mi.mesh
		inst.free()
	if found == null:
		push_error("Kenney 모델 없음: " + key)
	_meshes[key] = found
	return found


## 애니메이션이 있는 모델(상자, 캐릭터)은 장면째로 씁니다
static func instance(model: String, pack := DUNGEON) -> Node3D:
	var scene := load("res://assets/kenney/%s/%s.glb" % [pack, model]) as PackedScene
	return scene.instantiate() as Node3D


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m:
			return m
	return null


## 바닥 칸과 벽 칸 사이 모서리마다 얇은 벽판을 세웁니다 (Modular Dungeon/Cave Kit, 4유닛 조각을 1/4로 줄여 씀).
## floors: 바닥 칸 목록, is_floor(c) -> bool, height(c) -> float. 볼록한 모서리에는 기둥 조각을 놓습니다.
## 돌려주는 값: [[MultiMesh, 칸들, 변환들], ...] (조각마다 어느 바닥 칸에 붙었는지. 전장의 안개에 씀)
static func build_edge_walls(parent: Node3D, floors: Array, is_floor: Callable, height: Callable, cave := false) -> Array:
	var pack := "modular-cave-kit" if cave else "modular-dungeon-kit"
	var s := Basis.from_scale(Vector3.ONE * 0.25)
	var walls: Array[Transform3D] = []
	var corners: Array[Transform3D] = []
	var wall_cells: Array = []
	var corner_cells: Array = []
	for c in floors:
		var h: float = height.call(c)
		var center := Vector3(c.x + 0.5, h, c.y + 0.5)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not is_floor.call(c + d):
				# 조각의 -Z(벽 두께 방향)가 벽 칸 쪽을 보게
				var yaw := atan2(-float(d.x), -float(d.y))
				walls.append(Transform3D(Basis(Vector3.UP, yaw) * s, center + Vector3(d.x, 0, d.y) * 0.5))
				wall_cells.append(c)
		for dx in [-1, 1]:
			for dy in [-1, 1]:
				if is_floor.call(c + Vector2i(dx, 0)) and is_floor.call(c + Vector2i(0, dy)) \
						and not is_floor.call(c + Vector2i(dx, dy)):
					corners.append(Transform3D(_corner_basis(dx, dy) * s, center + Vector3(dx, 0, dy) * 0.5))
					corner_cells.append(c)
	var out: Array = []
	var a := _multimesh(parent, mesh("template-wall", pack), walls)
	if a:
		out.append([a.multimesh, wall_cells, walls])
	var b := _multimesh(parent, mesh("template-wall-corner", pack), corners)
	if b:
		out.append([b.multimesh, corner_cells, corners])
	return out


## 모서리 조각은 원점에서 (-X, -Z) 쪽으로 놓여 있음 -> 그 방향이 (dx, dy)를 보게 돌림
static func _corner_basis(dx: int, dy: int) -> Basis:
	for k in 4:
		var b := Basis(Vector3.UP, k * PI / 2.0)
		var v := b * Vector3(-1, 0, -1)
		if signi(roundi(v.x)) == dx and signi(roundi(v.z)) == dy:
			return b
	return Basis.IDENTITY


static func _multimesh(parent: Node3D, m: Mesh, xfs: Array[Transform3D]) -> MultiMeshInstance3D:
	if xfs.is_empty() or m == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	parent.add_child(inst)
	return inst
