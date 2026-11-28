## 야외 지형 자동 생성 (시제품). Terrain3D(Tokisan Games, MIT) 위에 노이즈 언덕을 만들고
## Quaternius Stylized Nature MegaKit 나무·풀·바위를 뿌립니다.
##   var t := OutdoorTerrain.new(); add_child(t); t.generate(seed)
## Terrain3D는 tools/install_terrain3d.sh로 addons/terrain_3d에 설치합니다 (저장소에 넣지 않음).
## 설치가 안 됐으면 generate()가 false를 돌려주고 아무것도 만들지 않습니다.
## 단위: 1 유닛 = 1칸 (사람 키 1.28칸). 지형은 SIZE x SIZE 칸, 가운데(0, 0)가 평평한 빈터.
class_name OutdoorTerrain
extends Node3D

const SIZE := 256
## 언덕 높이 (칸)
const HILL := 14.0
## 가운데 빈터 반지름 (칸): 여기는 평평하고 나무가 없음
const CLEARING := 14.0
const TEX := "res://assets/terrain/"
const NATURE := "res://assets/quaternius/nature/%s.scn"
## 식생: [모델들, 몇 그루(대략), 숲 노이즈 문턱(높을수록 숲 가운데만), 크기 범위, 가장 가파른 경사(코사인)]
const FOLIAGE := [
	[["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"], 2600, 0.0, Vector2(0.8, 1.3), 0.85],
	[["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"], 2000, 0.15, Vector2(0.8, 1.4), 0.8],
	[["TwistedTree_1", "TwistedTree_2", "DeadTree_1", "DeadTree_2", "DeadTree_3"], 120, -0.2, Vector2(0.8, 1.2), 0.8],
	[["Bush_Common", "Fern_1", "Plant_1", "Plant_7"], 1400, -0.1, Vector2(0.7, 1.2), 0.75],
	[["Flower_3_Group", "Flower_4_Group"], 500, -0.3, Vector2(0.6, 0.9), 0.85],
	[["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], 260, -1.0, Vector2(0.6, 1.6), 0.0],
	[["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall", "Grass_Common_Short", "Grass_Common_Tall", "Clover_1"], 12000, -0.35, Vector2(0.4, 0.7), 0.8],
]

## 던전 입구에 들어서면 (플레이어 몸)
signal entrance_entered(body: Node3D)

## 던전 입구: 빈터에서 ENTRANCE_DIST칸 떨어진 평평한 터, 빈터 쪽(+Z)을 봄. 빈터에서 돌길이 이어짐
const ENTRANCE_DIST := 40.0
const PAD := 5.0
const PATH_W := 1.6
## 입구 뒤 둔덕 높이 (칸)
const MOUND := 4.0

var terrain: Node3D = null
## 입구 자리와 방향 (+Z가 빈터 쪽, 문 앞)
var entrance := Transform3D.IDENTITY
## 모델 이름 → 메시 번호
var _mesh_ids := {}
## 부딪히는 식생 (나무·바위) 충돌체를 담는 노드
var _obstacles: StaticBody3D = null
## 이 모델들(이름 앞부분)에는 충돌체를 붙임: [앞부분, 반지름(크기 1일 때)]
const SOLID := [["CommonTree_", 0.22], ["Pine_", 0.25], ["TwistedTree_", 0.22], ["DeadTree_", 0.2], ["Rock_Medium_", 0.5]]


static func available() -> bool:
	return ClassDB.class_exists("Terrain3D")


## 땅 높이 (지형이 없으면 0)
func height_at(p: Vector3) -> float:
	if terrain == null:
		return 0.0
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func generate(seed_value: int) -> bool:
	if not available():
		push_warning("Terrain3D가 설치되지 않음 (tools/install_terrain3d.sh)")
		return false
	terrain = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	add_child(terrain)
	terrain.region_size = 256
	terrain.vertex_spacing = 1.0
	_setup_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var hills := FastNoiseLite.new()
	hills.seed = seed_value
	hills.frequency = 0.012
	hills.fractal_octaves = 4
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	# 칠하기 지도: 모든 칸을 "자동"(경사에 따라 풀/바위)으로. 비트값을 float로 담는 형식.
	# 자동 섞기 값은 평지일수록 1이라 덧칠(overlay)이 평지 쪽: 덧칠 = 풀(0), 바탕 = 바위(1)
	var auto_bits: int = ClassDB.class_call_static("Terrain3DUtil", "enc_auto", true)
	var ctl := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	ctl.fill(Color(ClassDB.class_call_static("Terrain3DUtil", "as_float", auto_bits), 0, 0, 1))
	var half := SIZE / 2.0
	# 입구 자리: 빈터에서 화면 위쪽(기본 카메라가 -X-Z 쪽을 봄) 방향으로 ENTRANCE_DIST칸.
	# 그래야 문이 카메라 쪽을 보고 뒤 둔덕에 가려지지 않음. 그 자리의 원래 높이로 터를 고르고, 빈터까지 비탈길
	var ang := deg_to_rad(225.0 + rng.randf_range(-35.0, 35.0))
	var e2 := Vector2(cos(ang), sin(ang)) * ENTRANCE_DIST
	var e_h := (hills.get_noise_2d(e2.x, e2.y) * 0.5 + 0.5) * HILL
	var c_h := _clearing_height(hills)
	var face := Vector3(-e2.x, 0, -e2.y).normalized()
	var f2 := Vector2(face.x, face.z)
	entrance = Transform3D(Basis.looking_at(-face, Vector3.UP), Vector3(e2.x, e_h, e2.y))
	for y in SIZE:
		for x in SIZE:
			var wx := x - half
			var wz := y - half
			var h := (hills.get_noise_2d(wx, wz) * 0.5 + 0.5) * HILL
			# 가운데 빈터는 평평하게 (가장자리로 갈수록 원래 높이)
			var d := Vector2(wx, wz).length()
			var t := smoothstep(CLEARING, CLEARING * 2.2, d)
			h = lerpf(c_h, h, t)
			# 입구 앞 터
			var de := Vector2(wx, wz).distance_to(e2)
			h = lerpf(e_h, h, smoothstep(PAD, PAD * 2.0, de))
			# 빈터 → 입구 길: 길 위는 두 높이 사이 비탈
			var along := clampf(Vector2(wx, wz).dot(e2) / e2.length_squared(), 0.0, 1.0)
			var off := Vector2(wx, wz).distance_to(e2 * along)
			h = lerpf(lerpf(c_h, e_h, smoothstep(0.3, 0.9, along)), h, smoothstep(PATH_W, PATH_W * 3.0, off))
			# 입구 뒤 둔덕: 문이 비탈에 박힌 것처럼 (뒤로 갈수록 솟았다가 다시 낮아짐)
			var rel := Vector2(wx, wz) - e2
			var back := rel.dot(-f2)
			var lat := absf(rel.dot(Vector2(-f2.y, f2.x)))
			h += MOUND * smoothstep(0.9, 3.0, back) * (1.0 - smoothstep(6.0, 14.0, back)) * (1.0 - smoothstep(3.0, 9.0, lat))
			# 지도 끝은 높여 막힌 느낌
			var edge := maxf(absf(wx), absf(wz)) / half
			h += smoothstep(0.8, 1.0, edge) * HILL * 1.5
			img.set_pixel(x, y, Color(h, 0, 0, 1))
	terrain.data.import_images([img, ctl, null], Vector3(-half, 0, -half), 0.0, 1.0)
	# 땅 전체에 충돌 (캐릭터가 언덕을 오르내림). 256칸이라 한 번에 만들어도 가벼움
	terrain.collision.mode = ClassDB.class_get_integer_constant("Terrain3DCollision", "FULL_GAME")
	_obstacles = StaticBody3D.new()
	_obstacles.name = "Obstacles"
	add_child(_obstacles)
	_scatter(rng, seed_value)
	_path_stones(rng, e2)
	_build_entrance()
	return true


func _clearing_height(hills: FastNoiseLite) -> float:
	return (hills.get_noise_2d(0, 0) * 0.5 + 0.5) * HILL


## 풀밭 + 경사면 바위 (Terrain3D 자동 셰이더가 경사로 섞음)
func _setup_material() -> void:
	var grass = ClassDB.instantiate("Terrain3DTextureAsset")
	grass.name = "Grass"
	grass.albedo_texture = load(TEX + "ground037_alb_ht.png")
	grass.normal_texture = load(TEX + "ground037_nrm_rgh.png")
	grass.uv_scale = 0.12
	# 이 풀 텍스처는 사실풍이라 저폴리 나무와 어울리게 밝고 따뜻하게
	grass.albedo_color = Color(0.85, 1.0, 0.7)
	var rock = ClassDB.instantiate("Terrain3DTextureAsset")
	rock.name = "Rock"
	rock.albedo_texture = load(TEX + "rock023_alb_ht.png")
	rock.normal_texture = load(TEX + "rock023_nrm_rgh.png")
	rock.uv_scale = 0.08
	terrain.assets.set_texture_asset(0, grass)
	terrain.assets.set_texture_asset(1, rock)
	terrain.material.world_background = 0  # NONE: 지도 밖은 비움
	terrain.material.auto_shader_enabled = true
	terrain.material.set_shader_param("auto_slope", 1.5)
	terrain.material.set_shader_param("auto_base_texture", 1)
	terrain.material.set_shader_param("auto_overlay_texture", 0)
	terrain.material.set_shader_param("blend_sharpness", 0.9)


func _mesh_id(model: String) -> int:
	if _mesh_ids.has(model):
		return _mesh_ids[model]
	var scene := load(NATURE % model) as PackedScene
	if scene == null:
		return -1
	var id := _mesh_ids.size()
	var ma = ClassDB.instantiate("Terrain3DMeshAsset")
	ma.name = model
	ma.scene_file = scene
	terrain.assets.set_mesh_asset(id, ma)
	_mesh_ids[model] = id
	return id


## 숲 노이즈가 높은 곳에 나무, 경사가 급하면 바위만
func _scatter(rng: RandomNumberGenerator, seed_value: int) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 17
	forest.frequency = 0.02
	var lim := SIZE / 2.0 - 4.0
	for layer in FOLIAGE:
		var models: Array = layer[0]
		var by_model := {}
		for i in int(layer[1]):
			var p := Vector3(rng.randf_range(-lim, lim), 0, rng.randf_range(-lim, lim))
			var d := Vector2(p.x, p.z).length()
			var is_grass: bool = String(models[0]).begins_with("Grass")
			# 빈터: 풀만 (가운데는 비움)
			if d < CLEARING * (0.5 if is_grass else 1.3):
				continue
			if not is_grass and _near_path(Vector2(p.x, p.z)):
				continue
			if forest.get_noise_2d(p.x, p.z) < float(layer[2]) + rng.randf_range(-0.1, 0.1):
				continue
			var n: Vector3 = terrain.data.get_normal(p)
			if not n.is_finite() or n.y < float(layer[4]):
				continue
			p.y = height_at(p)
			var s: float = rng.randf_range(layer[3].x, layer[3].y)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p)
			var m: String = models[rng.randi() % models.size()]
			if not by_model.has(m):
				by_model[m] = []
			by_model[m].append(xf)
			_add_obstacle(m, p, s)
		for m in by_model:
			var id := _mesh_id(m)
			if id < 0:
				continue
			var xfs: Array[Transform3D] = []
			xfs.assign(by_model[m])
			terrain.instancer.add_transforms(id, xfs)


## 나무 줄기·바위에 부딪히게 원기둥 충돌체 (식생 배치는 그림만 그림)
func _add_obstacle(model: String, p: Vector3, s: float) -> void:
	for e in SOLID:
		if model.begins_with(e[0]):
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = float(e[1]) * s
			cyl.height = 2.0
			shape.shape = cyl
			shape.position = p + Vector3(0, 1.0, 0)
			_obstacles.add_child(shape)
			return


## 입구 터나 길 위인가 (큰 식생을 두지 않음)
func _near_path(p: Vector2) -> bool:
	var e2 := Vector2(entrance.origin.x, entrance.origin.z)
	if p.distance_to(e2) < PAD * 1.6:
		return true
	var along := clampf(p.dot(e2) / e2.length_squared(), 0.0, 1.0)
	return p.distance_to(e2 * along) < PATH_W * 2.0


## 빈터에서 입구까지 디딤돌
func _path_stones(rng: RandomNumberGenerator, e2: Vector2) -> void:
	var stones := ["RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3", "RockPath_Round_Wide", "RockPath_Round_Thin"]
	var by_model := {}
	var start := CLEARING * 0.6
	var dist := start
	var dir := e2.normalized()
	var side := Vector2(-dir.y, dir.x)
	while dist < e2.length() - 2.0:
		var q := dir * dist + side * rng.randf_range(-0.5, 0.5)
		var p := Vector3(q.x, 0, q.y)
		p.y = height_at(p) + 0.02
		var m: String = stones[rng.randi() % stones.size()]
		if not by_model.has(m):
			by_model[m] = []
		by_model[m].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.3)), p))
		dist += rng.randf_range(0.9, 1.3)
	for m in by_model:
		var id := _mesh_id(m)
		if id >= 0:
			var xfs: Array[Transform3D] = []
			xfs.assign(by_model[m])
			terrain.instancer.add_transforms(id, xfs)


## 돌 문(Medieval Village 둥근 문 벽) + 양옆 기둥 + 횃불. 문 안쪽은 어둠, 문턱에 들어서면 entrance_entered
func _build_entrance() -> void:
	var root := Node3D.new()
	root.name = "DungeonEntrance"
	root.transform = entrance
	add_child(root)
	var k := 2.2  # 마을 조각(1칸 너비)을 이만큼 키움
	var door := MeshInstance3D.new()
	door.mesh = load("res://assets/quaternius/village/door.res")
	door.scale = Vector3.ONE * k
	root.add_child(door)
	for sx in [-1.0, 1.0]:
		var col := MeshInstance3D.new()
		col.mesh = load("res://assets/quaternius/village/column.res")
		col.scale = Vector3(0.45, k * 1.05, 0.45)
		col.position = Vector3(sx * (k * 0.5 + 0.2), 0, 0)
		root.add_child(col)
		var torch := MeshInstance3D.new()
		torch.mesh = load("res://assets/quaternius/props/Torch_Metal.res")
		torch.position = Vector3(sx * (k * 0.5 + 0.2), 1.5, 0.3)
		root.add_child(torch)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.65, 0.3)
		light.light_energy = 1.6
		light.omni_range = 5.0
		light.position = torch.position + Vector3(0, 0.5, 0.15)
		root.add_child(light)
	# 문 안쪽 어둠 (계단이 아래로 내려가는 느낌)
	var dark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(k * 0.5, k * 0.95)
	dark.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.02, 0.02, 0.03)
	dark.material_override = mat
	dark.position = Vector3(0, quad.size.y * 0.5, -0.02)
	root.add_child(dark)
	# 벽: 문 구멍 빼고 막음
	var body := StaticBody3D.new()
	root.add_child(body)
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(k * 0.35 + 0.5, 3.0, 0.6)
		cs.shape = box
		cs.position = Vector3(sx * (k * 0.25 + box.size.x * 0.5), 1.5, 0)
		body.add_child(cs)
	var back := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(k, 3.0, 0.4)
	back.shape = bb
	back.position = Vector3(0, 1.5, -0.6)
	body.add_child(back)
	# 문턱
	var area := Area3D.new()
	area.name = "Threshold"
	var ac := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(k * 0.45, 2.0, 0.5)
	ac.shape = abox
	ac.position = Vector3(0, 1.0, 0.05)
	area.add_child(ac)
	root.add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b is CharacterBody3D:
			entrance_entered.emit(b))


## 입구 앞 (빈터 쪽으로 dist칸) 땅 위 자리
func before_entrance(dist := 2.5) -> Vector3:
	var p := entrance * Vector3(0, 0, dist)
	p.y = height_at(p) + 0.3
	return p
