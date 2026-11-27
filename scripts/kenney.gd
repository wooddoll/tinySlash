## 던전·자연 소품 메시를 꺼내 쓰는 도우미 (모두 CC0). assets/kenney/<팩>/<이름>.glb
## Mini Dungeon 이름("floor", "column", "chest" …)은 SWAP 표를 따라 KayKit Dungeon Remastered 조각
## (assets/kaykit/dungeon)으로 바뀝니다. 크기와 원점을 미리 구워 넣어, 바꾼 조각도
## 바닥 1x1 유닛, 바닥면 y=0, 가운데가 원점이라 격자 칸에 그대로 맞습니다.
extends RefCounted

const DUNGEON := "mini-dungeon"
const KAYKIT := "res://assets/kaykit/dungeon/%s.glb"
## Mini Dungeon 이름 → [KayKit 조각, 크기(숫자 또는 Vector3), 줄인 뒤 원점 옮김]
## KayKit은 벽 한 칸이 4 유닛, 작은 바닥 타일이 2 유닛이라 줄여 씁니다
const SWAP := {
	"floor": ["floor_tile_small", 0.5],
	"floor-detail": ["floor_tile_small_broken_A", 0.5],
	"floor-broken": ["floor_tile_small_broken_B", 0.5],
	"floor-weeds": ["floor_tile_small_weeds_A", 0.5],
	"wall": ["wall", 0.25],
	"wall-cracked": ["wall_cracked", 0.25],
	"wall-post": ["pillar", Vector3(0.2, 0.26, 0.2)],
	"door": ["wall_doorway", 0.25],
	"column": ["pillar", Vector3(0.4, 0.3, 0.4)],
	"rocks": ["box_large", 0.5],
	"stones": ["rubble_half", Vector3(0.2, 0.07, 0.2), Vector3(-0.4, 0, 0)],
	"table": ["table_small", 0.75],
	"barrel": ["barrel_small", 0.75],
	"chair": ["chair", 0.7],
	"pot": ["keg", 0.38],
	"chest": ["chest", 0.5, Vector3(0, 0.085, -0.18)],
	"stairs": ["stairs", 0.2, Vector3(0, 0, -0.4)],
	"banner": ["banner_red", 0.3, Vector3(0, 0, -0.16)],
	"trap": ["floor_tile_big_spikes", Vector3(0.25, 0.15, 0.25)],
	"shield-rectangle": ["sword_shield", 0.4, Vector3(0, 0.34, 0)],
	"wall-half": ["barrier", Vector3(0.25, 0.8, 0.5)],
	"coin": ["coin_stack_small", 0.5],
	"dirt": ["floor_dirt_small_A", 0.5],
	"dirt-b": ["floor_dirt_small_B", 0.5],
	"dirt-c": ["floor_dirt_small_C", 0.5],
	"dirt-d": ["floor_dirt_small_D", 0.5],
	"dirt-weeds": ["floor_dirt_small_weeds", 0.5],
	# 벽에 거는 장식: 원점이 벽면, 로컬 +Z가 방 안쪽
	"torch-wall": ["torch_mounted", 0.4],
	"shelf-candles": ["shelf_small_candles", 0.35],
	"banner-wall": ["banner_patternA_red", 0.25],
	"banner-shield": ["banner_shield_blue", 0.25],
	# 바닥 잡동사니 (지나다닐 수 있는 작은 것만)
	"candle": ["candle_melted", 0.35],
	"candles": ["candle_triple", 0.35],
	"bottle": ["bottle_A_green", 0.35],
	"bottle-b": ["bottle_B_brown", 0.35],
	"plates": ["plate_stack", 0.3],
}
## 바닥 변형: 대부분 매끈한 타일, 가끔 깨지거나 풀 난 타일
const FLOOR_DETAILS := ["floor-detail", "floor-broken", "floor-weeds"]
## 동굴 흙바닥 변형
const CAVE_FLOORS := ["dirt", "dirt-b", "dirt-c", "dirt-d", "dirt", "dirt-weeds"]
## 벽 앞 바닥 잡동사니: 방 던전 / 동굴 (동굴은 Nature Kit 버섯과 작은 돌)
const CLUTTER := ["candle", "candles", "bottle", "bottle-b", "plates"]
const CAVE_CLUTTER := ["nature-kit/mushroom_redGroup", "nature-kit/mushroom_tanGroup", "nature-kit/rock_smallC", "nature-kit/mushroom_tanGroup"]
const NATURE := "nature-kit"
## [다크 판타지] 벽에 기대 세우는 무기·방패 걸이 (Fab AZ 3D studio 던전 세트를 tools/bake_props.gd로 구운 것).
## assets/dark는 저장소에 없으므로 파일이 없으면 놓지 않음
const DARK_PROPS := "dark-props"
const RACKS := ["rack-swords", "rack-shields", "rack-spears"]
## [다크 판타지] Unity 에셋 스토어 CobraGamesAssets "Stylized Dungeon Props Pack" (tools/bake_unity_props.gd로 구움)
## 벽에 붙여 세우는 가구(앞이 방 안쪽)와, 벽 가까이 아무렇게나 놓는 잡동사니
const DARK_WALL := ["bookshelf-a", "bookshelf-b", "drawers", "chest-empty", "crate-small", "crate-large"]
const DARK_CLUTTER := ["barrel", "barrel-moss", "pot-large", "pot-small", "fire-bin", "barrel"]
## 동굴 소품 (Nature Kit의 갈색 바위): 기둥(완전 엄폐), 바위(높이 1), 잔해(험지)
const CAVE_PILLARS := ["rock_tallA", "rock_tallB", "rock_tallC", "rock_tallD", "rock_tallE", "rock_tallF"]
const CAVE_ROCKS := ["rock_largeA", "rock_largeB", "rock_largeC", "rock_largeD", "rock_largeE", "rock_largeF"]
const CAVE_RUBBLE := ["rock_smallFlatA", "rock_smallFlatB", "rock_smallFlatC", "rock_smallA", "rock_smallB"]
## 바깥 나무와 풀
const TREES := ["tree_default", "tree_oak", "tree_detailed", "tree_fat", "tree_pineDefaultA", "tree_pineRoundA", "tree_cone"]
const GRASS := ["grass", "grass_large", "grass_leafs", "flower_redA", "flower_yellowA", "flower_purpleA"]
const DECOR := ["rock_smallA", "rock_smallC", "stump_round", "mushroom_redGroup", "mushroom_tanGroup", "plant_bush", "log"]


## [다크 판타지] KayKit 돌(밝은 회청색)을 어둡고 따뜻한 돌색으로 (텍스처에 곱함)
const DARK_STONE := Color(0.72, 0.64, 0.58)
const DARK_STONE_PARTS := ["floor", "floor-detail", "floor-broken", "floor-weeds", "wall", "wall-cracked", "wall-post",
	"door", "column", "stairs", "wall-half", "dirt", "dirt-b", "dirt-c", "dirt-d", "dirt-weeds"]


static func _tint(m: ArrayMesh, col: Color) -> void:
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i) as BaseMaterial3D
		if mat == null:
			continue
		var t := mat.duplicate() as BaseMaterial3D
		t.albedo_color = mat.albedo_color * col
		m.surface_set_material(i, t)


## 칸 좌표로 고르는 변형 (같은 칸은 늘 같은 모양)
static func pick(list: Array, c: Vector2i) -> String:
	return list[absi(c.x * 7 + c.y * 13 + c.x * c.y) % list.size()]

static var _meshes := {}


## GLB 안의 첫 MeshInstance3D 메시 (MultiMesh에 쓰기 좋음)
static func mesh(model: String, pack := DUNGEON) -> Mesh:
	var key := pack + "/" + model
	if _meshes.has(key):
		return _meshes[key]
	if pack == DARK_PROPS:
		var path := "res://assets/dark/props/%s.res" % model
		_meshes[key] = load(path) as Mesh if ResourceLoader.exists(path) else null
		return _meshes[key]
	if pack == DUNGEON and SWAP.has(model):
		var k := _kaykit(model)
		var baked := _bake(k)
		k.free()
		if model in DARK_STONE_PARTS:
			_tint(baked, DARK_STONE)
		_meshes[key] = baked
		return baked
	var scene := load("res://assets/kenney/%s/%s.glb" % [pack, model]) as PackedScene
	var found: Mesh = null
	if scene:
		var inst := scene.instantiate()
		var mi := _first_mesh(inst)
		if mi:
			found = _recolor(mi.mesh) if pack == NATURE else mi.mesh
		inst.free()
	if found == null:
		push_error("Kenney 모델 없음: " + key)
	_meshes[key] = found
	return found


## 애니메이션이 있는 모델(상자, 캐릭터)은 장면째로 씁니다
static func instance(model: String, pack := DUNGEON) -> Node3D:
	if pack == DUNGEON and SWAP.has(model):
		var root := Node3D.new()
		root.name = model
		root.add_child(_kaykit(model))
		if model == "chest":
			_add_lid_anim(root)
		return root
	var scene := load("res://assets/kenney/%s/%s.glb" % [pack, model]) as PackedScene
	var n := scene.instantiate() as Node3D
	if pack == NATURE:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			mi.mesh = mesh(model, pack) if mi == _first_mesh(n) else _recolor(mi.mesh)
	return n


## Nature Kit 색 고치기: 가져온 색이 한 번 더 밝아져 있어 되돌리고(sRGB→선형),
## 원래 청록색인 잎과 풀은 우리 초록 땅에 맞는 녹색으로 바꿉니다 (동굴 바위 윗면은 이끼처럼 보임)
const NATURE_GREENS := {
	"leafsGreen": Color(0.30, 0.55, 0.22),
	"leafsDark": Color(0.18, 0.40, 0.20),
	"grass": Color(0.36, 0.58, 0.24),
}
static var _recolored := {}


static func _recolor(src: Mesh) -> Mesh:
	if _recolored.has(src):
		return _recolored[src]
	var m := src.duplicate() as Mesh
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i) as StandardMaterial3D
		if mat == null:
			continue
		var fixed := mat.duplicate() as StandardMaterial3D
		fixed.albedo_color = NATURE_GREENS.get(mat.resource_name, mat.albedo_color.srgb_to_linear())
		m.surface_set_material(i, fixed)
	_recolored[src] = m
	return m


## SWAP 표의 KayKit 조각을 크기·원점을 맞춰 불러옵니다 (이름이 "Model"인 Node3D)
static func _kaykit(model: String) -> Node3D:
	var e: Array = SWAP[model]
	var n := (load(KAYKIT % e[0]) as PackedScene).instantiate() as Node3D
	n.name = "Model"
	var sz: Vector3 = e[1] if e[1] is Vector3 else Vector3.ONE * float(e[1])
	n.scale = sz
	n.position = e[2] if e.size() > 2 else Vector3.ZERO
	return n


## 장면 안의 메시를 모두 하나로 굽습니다 (노드 변환 포함). MultiMesh에 쓰려고
static func _bake(root: Node3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null:
			if p is Node3D:
				t = (p as Node3D).transform * t
			if p == root:
				break
			p = p.get_parent()
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, s, t)
			st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(s))
	return out


## KayKit 상자에는 애니메이션이 없어 뚜껑 여는 "open" 동작을 만들어 붙입니다
static func _add_lid_anim(root: Node3D) -> void:
	var lid := root.find_child("*_lid", true, false) as Node3D
	if lid == null:
		return
	var path := String(lid.name)
	var p := lid.get_parent()
	while p != root:
		path = String(p.name) + "/" + path
		p = p.get_parent()
	var a := Animation.new()
	a.length = 0.45
	var tr := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tr, NodePath(path + ":rotation:x"))
	a.track_insert_key(tr, 0.0, 0.0)
	a.track_insert_key(tr, 0.45, -1.9)
	var lib := AnimationLibrary.new()
	lib.add_animation("open", a)
	var ap := AnimationPlayer.new()
	ap.add_animation_library("", lib)
	root.add_child(ap)


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
	if not cave:
		return _kaykit_walls(parent, floors, is_floor, height)
	var pack := "modular-cave-kit"
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


## 방 던전 벽 (KayKit): 칸 모서리 가운데에 벽판(가끔 금 간 벽)을 세우고,
## 가로·세로 벽이 만나는 꼭짓점에는 가는 기둥을 세워 틈을 메웁니다. 돌려주는 값은 build_edge_walls와 같음
static func _kaykit_walls(parent: Node3D, floors: Array, is_floor: Callable, height: Callable) -> Array:
	var lists := {"wall": [[], []], "wall-cracked": [[], []], "wall-post": [[], []]}
	var vertex := {}  # 꼭짓점(높이 포함) -> [가로 벽 있음, 세로 벽 있음, 칸, 높이]
	for c in floors:
		var h: float = height.call(c)
		var center := Vector3(c.x + 0.5, h, c.y + 0.5)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if is_floor.call(c + d):
				continue
			var yaw := atan2(-float(d.x), -float(d.y))
			var kind := "wall-cracked" if absi(hash(c * 2 + d)) % 7 == 0 else "wall"
			lists[kind][0].append(Transform3D(Basis(Vector3.UP, yaw), center + Vector3(d.x, 0, d.y) * 0.5))
			lists[kind][1].append(c)
			# 이 벽판의 두 끝 꼭짓점 (x, y는 칸 모서리 좌표의 두 배)
			var mid := Vector2i(c.x * 2 + 1 + d.x, c.y * 2 + 1 + d.y)
			var along := Vector2i(absi(d.y), absi(d.x))
			for e in [mid + along, mid - along]:
				var key := Vector3i(e.x, e.y, roundi(h * 10))
				if not vertex.has(key):
					vertex[key] = [false, false, c, h]
				vertex[key][0 if d.y != 0 else 1] = true
	for key in vertex:
		var v: Array = vertex[key]
		if v[0] and v[1]:
			lists["wall-post"][0].append(Transform3D(Basis.IDENTITY, Vector3(key.x / 2.0, v[3], key.y / 2.0)))
			lists["wall-post"][1].append(v[2])
	var out: Array = []
	for kind in lists:
		var xfs: Array[Transform3D] = []
		xfs.assign(lists[kind][0])
		var inst := _multimesh(parent, mesh(kind), xfs)
		if inst:
			out.append([inst.multimesh, lists[kind][1], xfs])
	return out


## 꾸미기: 벽에 횃불(불빛 포함)·선반·깃발을 걸고, 벽 앞 바닥에 잡동사니를 조금 둡니다.
## 칸 좌표로 정해서 같은 맵은 늘 같은 모습. skip(c) -> bool: 아무것도 두지 않을 칸 (문·표식·장애물 등).
## 동굴은 벽 장식 없이 버섯과 작은 돌만. 돌려주는 값: {"parts": build_edge_walls와 같은 형식, "lights": [[OmniLight3D, 칸], ...]}
static func decorate(parent: Node3D, floors: Array, is_floor: Callable, height: Callable, cave: bool, skip: Callable) -> Dictionary:
	var lists := {}
	var lights: Array = []
	var put := func(model: String, xf: Transform3D, c: Vector2i) -> void:
		if not lists.has(model):
			lists[model] = [[], []]
		lists[model][0].append(xf)
		lists[model][1].append(c)
	for c in floors:
		var h: float = height.call(c)
		var center := Vector3(c.x + 0.5, h, c.y + 0.5)
		var walls: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not is_floor.call(c + d):
				walls.append(d)
		if walls.is_empty() or skip.call(c):
			continue
		# 폭 1칸 통로(양쪽이 벽)에는 큰 가구·잡동사니를 두지 않음 (길을 막아 보임)
		var corridor := (Vector2i(1, 0) in walls and Vector2i(-1, 0) in walls) or (Vector2i(0, 1) in walls and Vector2i(0, -1) in walls)
		for d in walls:
			var roll := absi(hash(c * 3 + d * 7)) % 100
			var yaw := atan2(-float(d.x), -float(d.y))
			var face := Basis(Vector3.UP, yaw)
			var dv := Vector3(d.x, 0, d.y)
			if cave:
				continue
			if roll < 9:
				put.call("torch-wall", Transform3D(face, center + dv * 0.375 + Vector3(0, 0.55, 0)), c)
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.65, 0.3)
				l.light_energy = 1.8
				l.omni_range = 3.2
				l.position = center + dv * 0.2 + Vector3(0, 0.75, 0)
				l.add_child(_flame_glow())
				parent.add_child(l)
				lights.append([l, c])
			elif roll < 13:
				put.call("banner-wall" if roll < 12 else "banner-shield", Transform3D(face, center + dv * 0.5), c)
			elif roll < 16:
				put.call("shelf-candles", Transform3D(face, center + dv * 0.375 + Vector3(0, 0.5, 0)), c)
			elif roll < 19:
				var rack: String = RACKS[roll % RACKS.size()]
				if mesh(rack, DARK_PROPS) != null:
					put.call(DARK_PROPS + "/" + rack, Transform3D(face, center + dv * 0.38), c)
			elif roll < 33 and not corridor:
				var item: String = DARK_WALL[(roll + c.x + c.y) % DARK_WALL.size()]
				var m := mesh(item, DARK_PROPS)
				if m != null:
					# 뒷면이 벽(0.5)에 닿게
					put.call(DARK_PROPS + "/" + item, Transform3D(face, center + dv * (0.48 - m.get_aabb().size.z * 0.5)), c)
		var r2 := absi(hash(c * 11 + Vector2i(5, 3))) % 100
		var dark := not cave and not corridor and mesh(DARK_CLUTTER[0], DARK_PROPS) != null
		if r2 < (7 if cave else (16 if dark else 5)):
			var d: Vector2i = walls[r2 % walls.size()]
			var spin := Basis(Vector3.UP, (r2 % 4) * PI / 2.0 + 0.3)
			var off := 0.28
			var model := pick(CAVE_CLUTTER if cave else CLUTTER, c)
			if dark and r2 % 4 != 0:
				var item: String = pick(DARK_CLUTTER, c)
				var m := mesh(item, DARK_PROPS)
				if m != null:
					model = DARK_PROPS + "/" + item
					var sz := m.get_aabb().size
					off = minf(0.28, 0.47 - maxf(sz.x, sz.z) * 0.5)
			put.call(model, Transform3D(spin, center + Vector3(d.x, 0, d.y) * off), c)
	var parts: Array = []
	for model in lists:
		var xfs: Array[Transform3D] = []
		xfs.assign(lists[model][0])
		var p: PackedStringArray = model.split("/")
		var inst := _multimesh(parent, mesh(p[-1], p[0] if p.size() > 1 else DUNGEON), xfs)
		if inst:
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parts.append([inst.multimesh, lists[model][1], xfs])
	if not lights.is_empty():
		var fl = load("res://scripts/torch_flicker.gd").new()
		fl.name = "TorchFlicker"
		parent.add_child(fl)
		for l in lights:
			fl.add(l[0])
	return {"parts": parts, "lights": lights}


static var _glow_mat: StandardMaterial3D


## 횃불 불꽃 둘레의 빛무리 (늘 카메라를 보는 둥근 판, 더해 그리기)
static func _flame_glow() -> MeshInstance3D:
	if _glow_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
		g.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_glow_mat.albedo_texture = tex
		_glow_mat.no_depth_test = false
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var m := MeshInstance3D.new()
	m.mesh = q
	m.material_override = _glow_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(0, 0.05, 0)
	return m


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
