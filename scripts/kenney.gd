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
