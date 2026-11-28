## 마을(rules/village.gd 배치)을 바깥 지형 위에 세웁니다 (M3).
## 집은 Quaternius Medieval Village MegaKit 조각(tools/bake_town.gd로 구운 assets/quaternius/town/)을 2m(=1.4칸) 격자로 조립:
## 벽(문·창 섞음)·모서리 기둥·지붕·박공·굴뚝. 건물마다 상자 충돌체, 여관·상점·조합 회관에는 이름표.
## 광장에는 의뢰판과 돌아다니는 주민. 조각이 없으면(에셋 미설치) 상자 모양 집으로 대신합니다.
extends Node3D

const Village = preload("res://rules/village.gd")
const CharModel = preload("res://scripts/character_model.gd")
const PIECE := "res://assets/quaternius/town/%s.res"
## 벽 한 층 높이 (원본 3.12m × 0.7)
const STOREY := 2.184
const M := Village.MODULE
const VILLAGERS := ["qhero/villager_m", "qhero/villager_f"]

var village
## 높이 함수 (지형 height_at). 없으면 0
var height_at: Callable
var villagers: Array[Node3D] = []
## 이 캐릭터를 가리는 건물은 반투명하게 (main.gd가 탐험 캐릭터 / 전투 주인공으로 바꿔 넣음)
var focus: Node3D = null
## 건물마다 [사전, 루트, 지금 투명도]
var _houses: Array = []
## 비칠 때 투명도와 바뀌는 빠르기
const FADED := 0.7
const FADE_SPEED := 5.0
var _targets: Array[Vector2] = []
var _wait: Array[float] = []
var _meshes := {}
var _rng := RandomNumberGenerator.new()


static func available() -> bool:
	return ResourceLoader.exists(PIECE % "Wall_Plaster_Straight")


func build(v, heights: Callable, seed_value: int) -> void:
	village = v
	height_at = heights
	_rng.seed = seed_value + 404
	for b in village.buildings:
		_building(b)
	for y in village.yards:
		if y.kind == "yard":
			_yard(y.pos)
	_board()
	_spawn_villagers(5)


func _h(p: Vector2) -> float:
	return float(height_at.call(Vector3(p.x, 0, p.y))) if height_at.is_valid() else 0.0


func _mesh(name: String) -> Mesh:
	if not _meshes.has(name):
		_meshes[name] = load(PIECE % name) if ResourceLoader.exists(PIECE % name) else null
	return _meshes[name]


func _put(parent: Node3D, name: String, pos: Vector3, rot := 0.0) -> void:
	var m := _mesh(name)
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation.y = rot
	parent.add_child(mi)


## 건물 하나. 집 좌표: +Z가 정면(문 쪽), 가운데 바닥이 원점
func _building(b: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "%s_%s" % [b.kind, b.name]
	var pos: Vector2 = b.pos
	var fr: Vector2 = b.front
	# 바닥은 네 귀퉁이 중 가장 낮은 땅에 맞춤 (빈터는 평평하지만 가장자리는 조금 기울 수 있음)
	var foot := Village.footprint(b) / 2.0
	var ground := INF
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var side := Vector2(fr.y, -fr.x) * foot.x * c.x
		ground = minf(ground, _h(pos + side + fr * foot.y * c.y))
	root.position = Vector3(pos.x, ground, pos.y)
	root.rotation.y = atan2(fr.x, fr.y)
	add_child(root)
	_houses.append([b, root, 0.0])
	var w: int = b.w
	var d: int = b.d
	var floors: int = b.floors
	if not available():
		_box_house(root, foot, floors)
	else:
		_assemble(root, b, w, d, floors)
	# 충돌: 바닥 크기 상자
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(foot.x * 2.0, STOREY * floors, foot.y * 2.0)
	shape.shape = box
	shape.position.y = STOREY * floors / 2.0
	body.add_child(shape)
	root.add_child(body)
	# 이름표 (집은 없음)
	if b.kind != "house":
		var l := Label3D.new()
		l.text = b.name
		l.font_size = 48
		l.pixel_size = 0.012
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, STOREY + 0.4, foot.y + 0.35)
		l.modulate = Color(1.0, 0.93, 0.75)
		root.add_child(l)


func _assemble(root: Node3D, b: Dictionary, w: int, d: int, floors: int) -> void:
	var hx := w * M / 2.0
	var hz := d * M / 2.0
	var door_i := w / 2
	for f in floors:
		var y := STOREY * f
		# 아래층 벽돌 + 위층 회반죽 (벽돌 집은 모두 벽돌)
		var brick: bool = b.style == "brick" or (floors > 1 and f == 0 and _rng.randf() < 0.6)
		var kit := "UnevenBrick" if brick else "Plaster"
		# 앞·뒤 벽 (x 방향으로 w개), 옆 벽 (z 방향으로 d개)
		for i in w:
			var x := -hx + M / 2.0 + i * M
			_wall(root, kit, Vector3(x, y, hz), 0.0, f == 0 and i == door_i)
			_wall(root, kit, Vector3(x, y, -hz), PI, false)
		for j in d:
			var z := -hz + M / 2.0 + j * M
			_wall(root, kit, Vector3(hx, y, z), PI / 2.0, false)
			_wall(root, kit, Vector3(-hx, y, z), -PI / 2.0, false)
		var corner := "Corner_Exterior_Brick" if brick else "Corner_Exterior_Wood"
		_put(root, corner, Vector3(hx, y, hz), 0.0)
		_put(root, corner, Vector3(hx, y, -hz), PI / 2.0)
		_put(root, corner, Vector3(-hx, y, -hz), PI)
		_put(root, corner, Vector3(-hx, y, hz), -PI / 2.0)
	var top := STOREY * floors
	_put(root, "Roof_RoundTiles_%dx%d" % [w * 2, d * 2], Vector3(0, top, 0))
	_put(root, "Roof_Front_Brick%d" % (w * 2), Vector3(0, top, hz), 0.0)
	_put(root, "Roof_Front_Brick%d" % (w * 2), Vector3(0, top, -hz), PI)
	if b.kind != "shop" and _rng.randf() < 0.7:
		# 굴뚝 밑동은 지붕 속에, 지붕 면 위로 0.8칸쯤 솟게 (지붕 용마루 높이: 원본 지붕 높이 × 0.7)
		var ridge := (4.23 - 0.52) * 0.7 if w == 2 else (5.67 - 0.78) * 0.7
		var y := top + ridge * (1.0 - 0.45) - 2.2 + 0.8
		_put(root, "Prop_Chimney", Vector3(hx * 0.45 * (1 if _rng.randf() < 0.5 else -1), y, -hz * 0.4))
	# 문 앞 소품
	if b.kind == "shop":
		_put(root, "Prop_Crate", Vector3(hx - 0.5, 0, hz + 0.7), 0.3)
		_put(root, "Prop_Crate", Vector3(hx - 0.6, 0.74, hz + 0.75), 1.1)


## 벽 한 칸. door면 문 벽 + 문짝, 아니면 반쯤은 창문 벽 + 창틀·덧문
func _wall(root: Node3D, kit: String, pos: Vector3, rot: float, door: bool) -> void:
	if door:
		_put(root, "Wall_%s_Door_Round" % kit, pos, rot)
		_put(root, "Door_1_Round", pos + Vector3(-0.39, 0, 0).rotated(Vector3.UP, rot), rot)
		return
	var r := _rng.randf()
	if r < 0.35:
		_put(root, "Wall_%s_Window_Wide_Round" % kit, pos, rot)
		_put(root, "Window_Wide_Round1", pos, rot)
		if _rng.randf() < 0.5:
			_put(root, "WindowShutters_Wide_Round_Open", pos, rot)
	elif r < 0.55:
		_put(root, "Wall_%s_Window_Thin_Round" % kit, pos, rot)
		_put(root, "Window_Thin_Round1", pos, rot)
	elif kit == "Plaster" and r < 0.7:
		_put(root, "Wall_Plaster_WoodGrid", pos, rot)
	else:
		_put(root, "Wall_%s_Straight" % kit, pos, rot)


## 에셋이 없을 때: 벽 상자 + 지붕 상자
func _box_house(root: Node3D, foot: Vector2, floors: int) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(foot.x * 2.0, STOREY * floors, foot.y * 2.0)
	mi.mesh = bm
	mi.position.y = STOREY * floors / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.8, 0.7)
	mi.material_override = mat
	root.add_child(mi)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(foot.x * 2.3, 1.4, foot.y * 2.2)
	roof.mesh = pm
	roof.position.y = STOREY * floors + 0.7
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.55, 0.25, 0.2)
	roof.material_override = rmat
	root.add_child(roof)


## 마당: 수레, 상자 몇 개, 울타리
func _yard(p: Vector2) -> void:
	var root := Node3D.new()
	root.name = "Yard"
	root.position = Vector3(p.x, _h(p), p.y)
	root.rotation.y = _rng.randf() * TAU
	add_child(root)
	_put(root, "Prop_Wagon", Vector3(0, 0, 1.0), 0.4)
	for i in 3:
		_put(root, "Prop_Crate", Vector3(_rng.randf_range(-2.5, -1.0), 0, _rng.randf_range(-2.0, 1.0)), _rng.randf() * TAU)
	for i in 4:
		_put(root, "Prop_WoodenFence_Single", Vector3(-3.0 + i * 1.3, 0, -2.8))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.2, 2.9)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0.2)
	body.add_child(shape)
	root.add_child(body)


## 의뢰판: 기둥 둘 + 판자 + 붙은 종이들
func _board() -> void:
	var p: Vector2 = village.board
	var fr: Vector2 = village.board_front
	var root := Node3D.new()
	root.name = "QuestBoard"
	root.position = Vector3(p.x, _h(p), p.y)
	root.rotation.y = atan2(fr.x, fr.y)
	add_child(root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.28, 0.17)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.88, 0.74)
	for x in [-0.55, 0.55]:
		_box(root, Vector3(0.1, 1.6, 0.1), Vector3(x, 0.8, 0), wood)
	_box(root, Vector3(1.3, 0.8, 0.06), Vector3(0, 1.15, 0.02), wood)
	_box(root, Vector3(1.45, 0.08, 0.2), Vector3(0, 1.6, 0.02), wood)
	var spots := [Vector2(-0.38, 1.25), Vector2(0.05, 1.3), Vector2(0.4, 1.2), Vector2(-0.15, 0.98), Vector2(0.3, 0.95)]
	for s in spots:
		var q := _box(root, Vector3(0.24, 0.3, 0.01), Vector3(s.x, s.y, 0.06), paper)
		q.rotation.z = _rng.randf_range(-0.15, 0.15)
	var l := Label3D.new()
	l.text = "의뢰판"
	l.font_size = 48
	l.pixel_size = 0.012
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 2.0, 0)
	l.modulate = Color(1.0, 0.93, 0.75)
	root.add_child(l)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.6, 0.3)
	shape.shape = box
	shape.position.y = 0.8
	body.add_child(shape)
	root.add_child(body)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## 주민: 광장 자리들 사이를 천천히 걷다가 멈춤
func _spawn_villagers(n: int) -> void:
	for i in n:
		var m := CharModel.new()
		add_child(m)
		m.setup(VILLAGERS[i % VILLAGERS.size()])
		var p: Vector2 = village.wander[_rng.randi() % village.wander.size()]
		m.position = Vector3(p.x, _h(p), p.y)
		m.set_base("idle")
		villagers.append(m)
		_targets.append(p)
		_wait.append(_rng.randf_range(0.5, 4.0))


func _process(delta: float) -> void:
	_fade(delta)
	for i in villagers.size():
		var m := villagers[i]
		if _wait[i] > 0.0:
			_wait[i] -= delta
			if _wait[i] <= 0.0:
				_targets[i] = village.wander[_rng.randi() % village.wander.size()]
				m.set_base("walk")
			continue
		var at := Vector2(m.position.x, m.position.z)
		var to := _targets[i] - at
		if to.length() < 0.15:
			_wait[i] = _rng.randf_range(2.0, 6.0)
			m.set_base("idle")
			continue
		var step := to.normalized() * minf(1.1 * delta, to.length())
		at += step
		m.position = Vector3(at.x, _h(at), at.y)
		m.face(Vector3(step.x, 0, step.y))


## 카메라에서 focus까지 시선이 지나는 건물은 반투명. 쿼터뷰(30° 내려다봄)라 캐릭터에서 카메라 쪽으로
## 수평 t칸 가면 시선 높이가 t·tan30°: 그 높이가 건물(지붕 포함) 높이보다 낮은 동안 바닥 안을 지나면 가림
func _fade(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or focus == null or not is_instance_valid(focus):
		return
	var back := cam.global_basis.z
	var dir := Vector2(back.x, back.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var from := Vector2(focus.global_position.x, focus.global_position.z)
	for hse in _houses:
		var b: Dictionary = hse[0]
		var height := STOREY * int(b.floors) + 2.5
		var reach := height / tan(deg_to_rad(30.0))
		var hit := false
		var t := 0.3
		while t < reach and not hit:
			hit = village.blocked_by(b, from + dir * t, 0.4)
			t += 0.5
		var want := FADED if hit else 0.0
		var now: float = hse[2]
		if absf(now - want) < 0.01:
			continue
		now = move_toward(now, want, FADE_SPEED * delta)
		hse[2] = now
		for mi in (hse[1] as Node3D).find_children("*", "GeometryInstance3D", true, false):
			if not (mi is Label3D):
				(mi as GeometryInstance3D).transparency = now
