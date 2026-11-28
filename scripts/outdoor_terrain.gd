## 야외 지형 (지방 전체 한 장, M5 뒤 심리스). Terrain3D(Tokisan Games, MIT) 위에 노이즈 언덕·산을 만들고
## Quaternius Stylized Nature MegaKit 나무·풀·바위를 뿌립니다.
##   var t := OutdoorTerrain.new(); add_child(t); t.generate_region(region, world_seed)
## 3x3 칸(칸 하나 SIZE x SIZE)의 높이를 처음에 모두 만들어 Terrain3D 한 장에 넣으므로 칸 경계를 걸어 넘어도 다시 불러오지 않습니다.
## 나무·풀·바위는 무거워서 칸마다 따로, 플레이어가 가까이 가면 여러 프레임에 나눠 채웁니다 (ensure_near).
## 높이 이미지는 같은 세계 시드면 정적 변수에 남겨 두어 장면을 다시 열 때(던전에서 나옴) 빨리 다시 씁니다.
## Terrain3D는 tools/install_terrain3d.sh로 addons/terrain_3d에 설치합니다 (저장소에 넣지 않음).
## 단위: 1 유닛 = 1칸 (사람 키 1.28칸). 세계 좌표: 마을 칸 가운데 = (0, 0), 칸 t의 가운데 = Region.offset(t).
class_name OutdoorTerrain
extends Node3D

const Region = preload("res://rules/region.gd")
const Village = preload("res://rules/village.gd")
const SIZE := 256
## 언덕 높이 (칸), 큰 산 높이(지형 성격 relief가 0.5를 넘는 만큼), 잔 기복
const HILL := 14.0
const MOUNT := 30.0
const BUMP := 0.9
## 지방 끝을 막는 둔덕 높이
const RIM := 32.0
## 마을 칸 가운데 빈터 반지름 (칸): 여기는 평평하고 나무가 없음 (마을이 들어섬, rules/village.gd)
const CLEARING := 20.0
const TEX := "res://assets/terrain/"
const NATURE := "res://assets/quaternius/nature/%s.scn"
const WindFoliage = preload("res://scripts/wind_foliage.gd")
## 식생: [모델들, 몇 그루(대략), 숲 노이즈 문턱(높을수록 숲 가운데만), 크기 범위, 가장 가파른 경사(코사인)]
const FOLIAGE := [
	[["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"], 2600, 0.0, Vector2(0.8, 1.3), 0.85],
	[["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"], 2000, 0.15, Vector2(0.8, 1.4), 0.8],
	[["TwistedTree_1", "TwistedTree_2", "DeadTree_1", "DeadTree_2", "DeadTree_3"], 120, -0.2, Vector2(0.8, 1.2), 0.8],
	[["Bush_Common", "Fern_1", "Plant_1", "Plant_7"], 1400, -0.1, Vector2(0.7, 1.2), 0.75],
	[["Flower_3_Group", "Flower_4_Group"], 500, -0.3, Vector2(0.6, 0.9), 0.85],
	[["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], 260, -1.0, Vector2(0.6, 1.6), 0.0],
	[["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall", "Grass_Common_Short", "Grass_Common_Tall", "Clover_1"], 6000, -0.35, Vector2(0.4, 0.7), 0.8],
	# 바람에 흔들리는 풀 덤불 (EmacEArt Stylized Grass, tools/install_emace_grass.sh). 없으면 건너뜀
	[["Grass_Wind"], 110000, -1.0, Vector2(0.35, 0.6), 0.78],
]
const WIND_GRASS_MESH := "res://assets/emace_grass/Meshes/EA_Grass_Clump.mesh"
const WIND_GRASS_MAT := "res://assets/emace_grass/Materials/EA_Grass_Green.tres"

## 던전 입구에 들어서면 (플레이어 몸, 그 입구가 있는 칸)
signal entrance_entered(body: Node3D, tile: Vector2i)

## 던전 입구: 빈터에서 ENTRANCE_DIST칸 떨어진 평평한 터, 빈터 쪽(+Z)을 봄. 빈터에서 돌길이 이어짐
const ENTRANCE_DIST := 40.0
const PAD := 5.0
const PATH_W := 1.6
## 입구 뒤 둔덕 높이 (칸)
const MOUND := 4.0

var terrain: Node3D = null
## 칸마다: {offset: Vector2, village: bool, entrance: Transform3D 또는 null, seed: int, filled: bool}
var tiles := {}
var region = null
## 모델 이름 → 메시 번호
var _mesh_ids := {}
## 부딪히는 식생 (나무·바위) 충돌체를 담는 노드
var _hills: FastNoiseLite
var _mount: FastNoiseLite
var _bump: FastNoiseLite
var _relief := PackedFloat32Array()
var _trees := PackedFloat32Array()
## 모델 → 부딪히는 반지름 (0이면 안 부딪힘), 반지름 → 공유 원기둥 모양
var _solid_r := {}
## 도는 일꾼 스레드 작업 번호
var _tasks: Array[int] = []
## 칸 → [길까지 거리(칸 픽셀마다), 그 자리 길 높이]. 길이 없는 칸은 없음
var _road_rast := {}
## 칠하기 값: 길 한가운데, 길 가장자리 섞임 8단계 (일꾼 스레드에서 쓰려고 미리 구함)
var _road_ctl := 0.0
var _road_edge: Array[float] = []
var _auto_ctl := 0.0
var _shapes := {}
## 같은 것을 값으로: Vector3(x, z, 반지름). 바깥 전투 격자(battle_grid)가 막힌 칸을 정할 때 씀
var solids: Array[Vector3] = []
## 마을 건물 자리 (Callable(p: Vector2, pad: float) -> bool). 그 자리엔 풀·나무를 두지 않고, 전투 격자에서 막힘
var keep_out: Callable
var _world_seed := 0
## 이 모델들(이름 앞부분)에는 충돌체를 붙임: [앞부분, 반지름(크기 1일 때)]
const SOLID := [["CommonTree_", 0.22], ["Pine_", 0.25], ["TwistedTree_", 0.22], ["DeadTree_", 0.2], ["Rock_Medium_", 0.5]]
## 높이·칠하기 이미지 기억 (칸 → [높이, 칠하기]), _cache_seed 세계 시드 것
static var _cache := {}
static var _cache_seed := -1
## 지도 그림 (지방 전체, 2칸 = 1픽셀). 세계 시드마다 한 번 만들어 기억
const MAP_MPP := 2.0
static var _map_img: Image = null
static var _map_seed := -1
static var _map_task := -1
## 길: 마을 빈터에서 다른 칸 던전 입구까지 흙길 (세계 좌표 점들 x, 높이, z). 세계 시드마다 한 번 찾아 기억
const ROAD_HALF := 1.3
const ROAD_REACH := 5.0
const ROAD_TEX := 2
static var _roads: Array = []
static var _roads_seed := -1


static func available() -> bool:
	return ClassDB.class_exists("Terrain3D")


## 땅 높이 (지형이 없으면 0)
func height_at(p: Vector3) -> float:
	if terrain == null:
		return 0.0
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


## 세계 좌표 → 칸 (지방 밖이면 가장 가까운 칸)
static func tile_of(p: Vector3) -> Vector2i:
	var t := Vector2i(floori((p.x + SIZE / 2.0) / SIZE), floori((p.z + SIZE / 2.0) / SIZE)) + Region.VILLAGE
	return Vector2i(clampi(t.x, 0, Region.W - 1), clampi(t.y, 0, Region.H - 1))


## 시드로 정해지는 마을 칸 던전 입구 방향 (빈터에서 본 단위 벡터). _entrance_of와 같은 난수 순서
static func entrance_dir(seed_value: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ang := deg_to_rad(225.0 + rng.randf_range(-35.0, 35.0))
	return Vector2(cos(ang), sin(ang))


## 칸의 던전 입구 (칸 안 좌표 e2, 문이 보는 쪽 face). 마을 칸은 빈터에서 ENTRANCE_DIST, 다른 칸은 가운데에서 25~55칸
static func _entrance_of(seed_value: int, village: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ang := deg_to_rad(225.0 + rng.randf_range(-35.0, 35.0))
	var e2 := Vector2(cos(ang), sin(ang)) * ENTRANCE_DIST
	var face := Vector3(-e2.x, 0, -e2.y).normalized()
	if not village:
		var a2 := rng.randf() * TAU
		e2 = Vector2(cos(a2), sin(a2)) * rng.randf_range(25.0, 55.0)
		var fa := deg_to_rad(45.0 + rng.randf_range(-35.0, 35.0))
		face = Vector3(cos(fa), 0, sin(fa))
	return [e2, face]


## 지방 전체 지형. reg: rules/region.gd, keep: 마을 건물 자리 (Callable, 없으면 빈 것)
func generate_region(reg, world_seed: int, keep: Callable = Callable()) -> bool:
	if not available():
		push_warning("Terrain3D가 설치되지 않음 (tools/install_terrain3d.sh)")
		return false
	region = reg
	keep_out = keep
	_world_seed = world_seed
	terrain = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	add_child(terrain)
	terrain.region_size = 256
	terrain.vertex_spacing = 1.0
	_setup_material()
	if _cache_seed != world_seed:
		_cache = {}
		_cache_seed = world_seed
	_hills = FastNoiseLite.new()
	_hills.seed = world_seed
	_hills.frequency = 0.012
	_hills.fractal_octaves = 4
	_mount = FastNoiseLite.new()
	_mount.seed = world_seed + 5
	_mount.frequency = 0.0035
	_mount.fractal_octaves = 3
	_bump = FastNoiseLite.new()
	_bump.seed = world_seed + 9
	_bump.frequency = 0.05
	_bump.fractal_octaves = 2
	_prepare_look()
	var half := SIZE / 2.0
	var todo := []
	for t in reg.tiles:
		var off: Vector2 = Region.offset(t, SIZE)
		var is_village: bool = t == Region.VILLAGE
		var sd := Region.tile_seed(world_seed, t)
		var info := {"offset": off, "village": is_village, "entrance": null, "seed": sd, "filled": false}
		var e: Array = _entrance_of(sd, is_village)
		var e2: Vector2 = e[0]
		var face: Vector3 = e[1]
		var has_door: bool = not reg.dungeon_at(t).is_empty()
		var e_h := _raw_height(e2.x + off.x, e2.y + off.y)
		if has_door:
			info.entrance = Transform3D(Basis.looking_at(-face, Vector3.UP), Vector3(e2.x + off.x, e_h, e2.y + off.y))
		tiles[t] = info
		if not _cache.has(t):
			todo.append([t, info, e2, e_h, face, has_door, null])
	# 길 (기억에 없으면 찾고) → 칸마다 길까지 거리 그림
	_prepare_road_ctl()
	if _roads_seed != world_seed:
		_roads = _find_roads()
		_roads_seed = world_seed
	_rasterize_roads()
	# 아직 기억에 없는 칸의 높이는 일꾼 스레드들이 나눠서 만듦
	if not todo.is_empty():
		var group := WorkerThreadPool.add_group_task(func(k: int) -> void:
			var j: Array = todo[k]
			j[6] = _tile_images(j[0], j[1], j[2], j[3], j[4], j[5]), todo.size())
		WorkerThreadPool.wait_for_group_task_completion(group)
		for j in todo:
			_cache[j[0]] = j[6]
	for t in tiles:
		var off: Vector2 = tiles[t].offset
		var imgs: Array = _cache[t]
		terrain.data.import_images([imgs[0], imgs[1], null], Vector3(off.x - half, 0, off.y - half), 0.0, 1.0)
	# 땅 충돌은 카메라 둘레만 (지방 전체는 768칸이라 한꺼번에 만들면 무거움)
	terrain.collision.mode = ClassDB.class_get_integer_constant("Terrain3DCollision", "DYNAMIC_GAME")
	terrain.collision.radius = 96
	for t in tiles:
		if tiles[t].entrance != null:
			_build_entrance(t, tiles[t].entrance)
	return true


## 지형 성격 격자 (칸 가운데 값). region.terrain_at과 같은 이중선형 보간을 빠르게 하려고 배열로 둠
func _prepare_look() -> void:
	_relief.resize(Region.W * Region.H)
	_trees.resize(Region.W * Region.H)
	for t in region.tiles:
		_relief[t.y * Region.W + t.x] = float(region.tiles[t].relief)
		_trees[t.y * Region.W + t.x] = float(region.tiles[t].trees)


## 세계 좌표의 지형 성격 (기복, 숲) — region.terrain_at과 같은 값
func _look(wx: float, wz: float) -> Vector2:
	var gx := wx / SIZE + Region.VILLAGE.x
	var gy := wz / SIZE + Region.VILLAGE.y
	var x0 := clampi(floori(gx), 0, Region.W - 1)
	var y0 := clampi(floori(gy), 0, Region.H - 1)
	var x1 := mini(x0 + 1, Region.W - 1)
	var y1 := mini(y0 + 1, Region.H - 1)
	var fx := clampf(gx - x0, 0.0, 1.0)
	var fy := clampf(gy - y0, 0.0, 1.0)
	var a := y0 * Region.W
	var b := y1 * Region.W
	return Vector2(
		lerpf(lerpf(_relief[a + x0], _relief[a + x1], fx), lerpf(_relief[b + x0], _relief[b + x1], fx), fy),
		lerpf(lerpf(_trees[a + x0], _trees[a + x1], fx), lerpf(_trees[b + x0], _trees[b + x1], fx), fy))


## 세계 좌표의 노이즈 높이 (빈터·입구 손질 전). 지형 성격(relief)은 칸 가운데 값을 섞은 것이라 경계에서 이어짐
func _raw_height(wx: float, wz: float) -> float:
	var relief := _look(wx, wz).x
	var h := (_hills.get_noise_2d(wx, wz) * 0.5 + 0.5) * HILL * relief
	h += (_mount.get_noise_2d(wx, wz) * 0.5 + 0.5) * MOUNT * maxf(relief - 0.5, 0.0)
	h += _bump.get_noise_2d(wx, wz) * BUMP
	return h


## 칸 하나의 높이·칠하기 이미지. 노이즈는 2칸 간격 격자(세계 전체에 맞춘 격자라 칸 경계가 이어짐)에서 구해 보간하고,
## 빈터·입구·길·둘레 손질은 해당 자리 근처에서만 함
func _tile_images(t: Vector2i, info: Dictionary, e2: Vector2, e_h: float, face: Vector3, has_door: bool) -> Array:
	var half := SIZE / 2.0
	var off: Vector2 = info.offset
	var n := SIZE / 2 + 1
	var coarse := PackedFloat32Array()
	coarse.resize(n * n)
	for j in n:
		for i in n:
			coarse[j * n + i] = _raw_height(off.x - half + i * 2, off.y - half + j * 2)
	# 칠하기 지도: 모든 칸을 "자동"(경사에 따라 풀/바위)으로, 길은 흙. 비트값을 float로 담는 형식.
	var cs_arr := PackedFloat32Array()
	cs_arr.resize(SIZE * SIZE)
	cs_arr.fill(_auto_ctl)
	var road: Array = _road_rast.get(t, [])
	var rd := PackedFloat32Array()
	var rh := PackedFloat32Array()
	if not road.is_empty():
		rd = road[0]
		rh = road[1]
	var village: bool = info.village
	var c_h := _raw_height(off.x, off.y)
	var f2 := Vector2(face.x, face.z)
	var side := Vector2(-f2.y, f2.x)
	var cw := not Region.inside(t + Vector2i.LEFT)
	var ce := not Region.inside(t + Vector2i.RIGHT)
	var cn := not Region.inside(t + Vector2i.UP)
	var cs := not Region.inside(t + Vector2i.DOWN)
	var e_len2 := e2.length_squared()
	var hs := PackedFloat32Array()
	hs.resize(SIZE * SIZE)
	for y in SIZE:
		var wz := y - half
		var row := (y >> 1) * n
		var fy := (y & 1) * 0.5
		for x in SIZE:
			var wx := x - half
			var k := row + (x >> 1)
			var fx := (x & 1) * 0.5
			var h := lerpf(lerpf(coarse[k], coarse[k + 1], fx), lerpf(coarse[k + n], coarse[k + n + 1], fx), fy)
			var q := Vector2(wx, wz)
			if not rd.is_empty():
				var pi := y * SIZE + x
				var dr := rd[pi]
				if dr < ROAD_REACH:
					# 길은 가로로 평평하게 깎고 둘레는 이어지게
					h = lerpf(rh[pi], h, smoothstep(ROAD_HALF + 0.3, ROAD_REACH, dr))
					if dr < ROAD_HALF:
						cs_arr[pi] = _road_ctl
					elif dr < ROAD_HALF + 1.0:
						cs_arr[pi] = _road_edge[clampi(int((dr - ROAD_HALF) * 8.0), 0, 7)]
			if village:
				# 가운데 빈터는 평평하게 (가장자리로 갈수록 원래 높이)
				var d := q.length()
				if d < CLEARING * 2.2:
					h = lerpf(c_h, h, smoothstep(CLEARING, CLEARING * 2.2, d))
			if has_door:
				var rel := q - e2
				if rel.length_squared() < 400.0:
					# 입구 앞 터
					h = lerpf(e_h, h, smoothstep(PAD, PAD * 2.0, rel.length()))
				if village:
					# 빈터 → 입구 길: 길 위는 두 높이 사이 비탈
					var along := clampf(q.dot(e2) / e_len2, 0.0, 1.0)
					var pd := q.distance_to(e2 * along)
					if pd < PATH_W * 3.0:
						h = lerpf(lerpf(c_h, e_h, smoothstep(0.3, 0.9, along)), h, smoothstep(PATH_W, PATH_W * 3.0, pd))
				if rel.length_squared() < 400.0:
					# 입구 뒤 둔덕: 문이 비탈에 박힌 것처럼
					var back := rel.dot(-f2)
					var lat := absf(rel.dot(side))
					h += MOUND * smoothstep(0.9, 3.0, back) * (1.0 - smoothstep(6.0, 14.0, back)) * (1.0 - smoothstep(3.0, 9.0, lat))
			# 지방 끝(막힌 쪽)은 높여 막음. 이웃 칸이 있는 쪽은 그대로 이어짐
			var edge := 0.0
			if cw:
				edge = maxf(edge, -wx / half)
			if ce:
				edge = maxf(edge, wx / half)
			if cn:
				edge = maxf(edge, -wz / half)
			if cs:
				edge = maxf(edge, wz / half)
			if edge > 0.82:
				h += smoothstep(0.82, 1.0, edge) * RIM
			hs[y * SIZE + x] = h
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, hs.to_byte_array())
	var ctl := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, cs_arr.to_byte_array())
	return [img, ctl, hs]


## 칠하기 값 미리 구하기 (Terrain3DUtil은 일꾼 스레드에서 부르지 않음)
func _prepare_road_ctl() -> void:
	var u := "Terrain3DUtil"
	_auto_ctl = ClassDB.class_call_static(u, "as_float", ClassDB.class_call_static(u, "enc_auto", true))
	var base_road: int = ClassDB.class_call_static(u, "enc_base", ROAD_TEX)
	_road_ctl = ClassDB.class_call_static(u, "as_float", base_road)
	_road_edge.clear()
	for i in 8:
		# 가장자리: 바탕은 풀(0), 위에 흙을 점점 옅게
		var bits: int = ClassDB.class_call_static(u, "enc_base", 0) | ClassDB.class_call_static(u, "enc_overlay", ROAD_TEX) \
			| ClassDB.class_call_static(u, "enc_blend", int(lerpf(220.0, 30.0, i / 7.0)))
		_road_edge.append(ClassDB.class_call_static(u, "as_float", bits))


## 길 찾기: 마을 빈터 가장자리에서 다른 칸 던전 입구 앞까지, 8칸 격자에서 가파른 곳을 피해 돌아감 (A*).
## 먼저 낸 길 위는 싸게 쳐서 길이 서로 합쳐짐. 결과는 매끄럽게 다듬고 2칸마다 점, 높이도 앞뒤로 고르게
func _find_roads() -> Array:
	var cell := 8.0
	var o := map_origin()
	var nx := int(Region.W * SIZE / cell)
	var nz := int(Region.H * SIZE / cell)
	var hg := PackedFloat32Array()
	hg.resize(nx * nz)
	for j in nz:
		for i in nx:
			hg[j * nx + i] = _raw_height(o.x + (i + 0.5) * cell, o.y + (j + 0.5) * cell)
	var used := {}
	var out := []
	var goals := []
	for t in tiles:
		if tiles[t].village or tiles[t].entrance == null:
			continue
		var xf: Transform3D = tiles[t].entrance
		var front := xf * Vector3(0, 0, 7.0)
		goals.append(Vector2(front.x, front.z))
	# 가까운 입구부터 (나중 길이 앞 길에 붙음)
	goals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	for g in goals:
		var start := (g as Vector2).normalized() * (CLEARING * 1.3)
		var to_cell := func(w: Vector2) -> Vector2i:
			return Vector2i(clampi(int((w.x - o.x) / cell), 0, nx - 1), clampi(int((w.y - o.y) / cell), 0, nz - 1))
		var a: Vector2i = to_cell.call(start)
		var b: Vector2i = to_cell.call(g)
		var cells := _astar(hg, nx, nz, cell, a, b, used)
		if cells.is_empty():
			continue
		for c in cells:
			used[c] = true
		var pts := PackedVector2Array([start])
		for k in range(1, cells.size() - 1):
			pts.append(o + (Vector2(cells[k]) + Vector2(0.5, 0.5)) * cell)
		pts.append(g)
		for it in 3:
			pts = _chaikin(pts)
		out.append(_road_points(pts))
	return out


func _astar(hg: PackedFloat32Array, nx: int, nz: int, cell: float, a: Vector2i, b: Vector2i, used: Dictionary) -> Array:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var g := {a: 0.0}
	var prev := {}
	var open := [[0.0, a]]
	var done := {}
	while not open.is_empty():
		var cur: Vector2i = _heap_pop(open)[1]
		if cur == b:
			break
		if done.has(cur):
			continue
		done[cur] = true
		for dd in dirs:
			var n: Vector2i = cur + dd
			if n.x < 2 or n.y < 2 or n.x >= nx - 2 or n.y >= nz - 2:
				continue  # 지방 끝 언덕은 피함
			var len := cell * (1.4142 if dd.x != 0 and dd.y != 0 else 1.0)
			var slope := absf(hg[n.y * nx + n.x] - hg[cur.y * nx + cur.x]) / len
			var cost := len * (1.0 + 40.0 * slope * slope) * (0.45 if used.has(n) else 1.0)
			var ng: float = g[cur] + cost
			if ng < float(g.get(n, INF)):
				g[n] = ng
				prev[n] = cur
				_heap_push(open, [ng + Vector2(n - b).length() * cell * 0.45, n])
	if not prev.has(b) and a != b:
		return []
	var path := [b]
	var c := b
	while c != a:
		c = prev[c]
		path.push_front(c)
	return path


## 가장 싼 것을 먼저 꺼내는 더미 (h[i][0]이 값)
static func _heap_push(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and h[l][0] < h[m][0]:
				m = l
			if r < n and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var tmp = h[m]
			h[m] = h[i]
			h[i] = tmp
			i = m
	return top


static func _chaikin(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([p[0]])
	for i in p.size() - 1:
		out.append(p[i].lerp(p[i + 1], 0.25))
		out.append(p[i].lerp(p[i + 1], 0.75))
	out.append(p[p.size() - 1])
	return out


## 2칸 간격 점 (x, 높이, z). 높이는 앞뒤 점과 고르게 섞어 길이 울퉁불퉁하지 않게
func _road_points(p: PackedVector2Array) -> PackedVector3Array:
	var pts := PackedVector2Array([p[0]])
	var carry := 0.0
	for i in p.size() - 1:
		var a := p[i]
		var seg := a.distance_to(p[i + 1])
		var d := 2.0 - carry
		while d <= seg:
			pts.append(a.lerp(p[i + 1], d / seg))
			d += 2.0
		carry = seg - (d - 2.0)
	pts.append(p[p.size() - 1])
	var hs := PackedFloat32Array()
	for q in pts:
		hs.append(_raw_height(q.x, q.y))
	var out := PackedVector3Array()
	for i in pts.size():
		var sum := 0.0
		var cnt := 0
		for k in range(maxi(0, i - 4), mini(pts.size(), i + 5)):
			sum += hs[k]
			cnt += 1
		out.append(Vector3(pts[i].x, sum / cnt, pts[i].y))
	return out


## 칸 픽셀마다 가까운 길까지 거리와 그 자리 길 높이
func _rasterize_roads() -> void:
	_road_rast.clear()
	var half := SIZE / 2.0
	for road in _roads:
		var pts: PackedVector3Array = road
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 1e-6)
			for wz in range(floori(minf(a.y, b.y) - ROAD_REACH), ceili(maxf(a.y, b.y) + ROAD_REACH) + 1):
				for wx in range(floori(minf(a.x, b.x) - ROAD_REACH), ceili(maxf(a.x, b.x) + ROAD_REACH) + 1):
					var q := Vector2(wx, wz)
					var u := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
					var dist := q.distance_to(a + ab * u)
					if dist >= ROAD_REACH:
						continue
					var t := Outdoor_tile_of(wx, wz)
					if not tiles.has(t):
						continue
					var off: Vector2 = tiles[t].offset
					var px := wx - int(off.x - half)
					var py := wz - int(off.y - half)
					if px < 0 or py < 0 or px >= SIZE or py >= SIZE:
						continue
					if not _road_rast.has(t):
						var dd := PackedFloat32Array()
						dd.resize(SIZE * SIZE)
						dd.fill(1e9)
						var hh := PackedFloat32Array()
						hh.resize(SIZE * SIZE)
						_road_rast[t] = [dd, hh]
					var r: Array = _road_rast[t]
					var k := py * SIZE + px
					if dist < r[0][k]:
						r[0][k] = dist
						r[1][k] = lerpf(pts[i].y, pts[i + 1].y, u)


static func Outdoor_tile_of(wx: int, wz: int) -> Vector2i:
	return Vector2i(floori((wx + SIZE / 2.0) / SIZE), floori((wz + SIZE / 2.0) / SIZE)) + Region.VILLAGE


## 세계 자리에서 가까운 길까지 거리 (길이 멀면 큰 값)
func _road_d(wx: float, wz: float) -> float:
	var t := Outdoor_tile_of(floori(wx), floori(wz))
	var r: Array = _road_rast.get(t, [])
	if r.is_empty():
		return 1e9
	var off: Vector2 = tiles[t].offset
	var px := floori(wx) - int(off.x - SIZE / 2.0)
	var py := floori(wz) - int(off.y - SIZE / 2.0)
	if px < 0 or py < 0 or px >= SIZE or py >= SIZE:
		return 1e9
	return (r[0] as PackedFloat32Array)[py * SIZE + px]


## 칸의 높이 이미지 (없으면 null)
func height_image(t: Vector2i) -> Image:
	return (_cache[t] as Array)[0] if _cache.has(t) else null


## 지방 지도 그림이 다 됐으면 돌려줌 (아직이면 null). 처음 부르면 일꾼 스레드에서 만들기 시작.
## buildings: 마을 건물 (rules/village.gd buildings) — 지붕 색으로 칠함
func map_image(buildings: Array = []) -> Image:
	if _map_img != null and _map_seed == _world_seed:
		return _map_img
	if _map_task >= 0:
		if not WorkerThreadPool.is_task_completed(_map_task):
			return null
		WorkerThreadPool.wait_for_task_completion(_map_task)
		_map_task = -1
		return _map_img if _map_seed == _world_seed else null
	_map_seed = _world_seed
	_map_img = null
	_map_task = WorkerThreadPool.add_task(_build_map.bind(buildings.duplicate(true)))
	return null


## 세계 좌표 → 지도 그림 픽셀 (지도 그림 왼쪽 위 = 지방 북서쪽 끝)
static func map_origin() -> Vector2:
	return Vector2(-Region.W * SIZE / 2.0, -Region.H * SIZE / 2.0)


## 기억한 높이 배열에서 세계 좌표의 높이 (지방 밖이면 가장자리 값)
func _cached_height(wx: float, wz: float) -> float:
	var o := map_origin()
	var gx := clampi(int(wx - o.x), 0, Region.W * SIZE - 1)
	var gz := clampi(int(wz - o.y), 0, Region.H * SIZE - 1)
	var t := Vector2i(gx / SIZE, gz / SIZE)
	var hs: PackedFloat32Array = _cache[t][2]
	return hs[(gz % SIZE) * SIZE + (gx % SIZE)]


## 지도 그림 만들기 (일꾼 스레드): 높이에 따라 풀색, 가파르면 바위색, 숲, 북서쪽 빛 음영, 5칸마다 등고선, 마을 건물·길
func _build_map(buildings: Array) -> void:
	var w := int(Region.W * SIZE / MAP_MPP)
	var hgt := int(Region.H * SIZE / MAP_MPP)
	var img := Image.create_empty(w, hgt, false, Image.FORMAT_RGB8)
	var forest := FastNoiseLite.new()
	forest.seed = _world_seed + 17
	forest.frequency = 0.02
	var o := map_origin()
	var light := Vector3(-1.0, 1.6, -1.0).normalized()
	var grass := Color(0.42, 0.6, 0.29)
	var high := Color(0.64, 0.66, 0.44)
	var rock := Color(0.56, 0.55, 0.52)
	var wood := Color(0.18, 0.36, 0.17)
	var dirt := Color(0.72, 0.62, 0.43)
	var roof := Color(0.66, 0.3, 0.2)
	var vt: Dictionary = tiles[Region.VILLAGE]
	var e2 := Vector2.ZERO
	if vt.entrance != null:
		e2 = Vector2(vt.entrance.origin.x, vt.entrance.origin.z)
	for v in hgt:
		for u in w:
			var wx := o.x + (u + 0.5) * MAP_MPP
			var wz := o.y + (v + 0.5) * MAP_MPP
			var h := _cached_height(wx, wz)
			var hw := _cached_height(wx - MAP_MPP, wz)
			var he := _cached_height(wx + MAP_MPP, wz)
			var hn := _cached_height(wx, wz - MAP_MPP)
			var hs := _cached_height(wx, wz + MAP_MPP)
			var nrm := Vector3(-(he - hw) / (2.0 * MAP_MPP), 1.0, -(hs - hn) / (2.0 * MAP_MPP)).normalized()
			var c := grass.lerp(high, clampf(h / 45.0, 0.0, 1.0))
			c = c.lerp(rock, smoothstep(0.9, 0.72, nrm.y))
			var q := Vector2(wx, wz)
			var in_clearing := q.length() < CLEARING * 1.3
			if not in_clearing and nrm.y > 0.8 and forest.get_noise_2d(wx, wz) >= _look(wx, wz).y:
				c = c.lerp(wood, 0.6)
			if in_clearing:
				c = c.lerp(dirt, 0.35 * (1.0 - smoothstep(CLEARING * 0.4, CLEARING * 1.3, q.length())))
			var rdm := _road_d(wx, wz)
			if rdm < ROAD_HALF + 0.6:
				c = dirt
			if e2 != Vector2.ZERO:
				var along := clampf(q.dot(e2) / e2.length_squared(), 0.0, 1.0)
				if q.distance_to(e2 * along) < PATH_W and along > 0.05:
					c = dirt
			var shade := clampf(0.2 + 1.05 * nrm.dot(light), 0.45, 1.25)
			c = Color(c.r * shade, c.g * shade, c.b * shade)
			# 등고선 (5칸마다, 진하게는 25칸마다)
			var band := floorf(h / 5.0)
			if floorf(he / 5.0) != band or floorf(hs / 5.0) != band:
				c = c.darkened(0.3 if int(maxf(band, floorf(he / 5.0))) % 5 == 0 else 0.14)
			if in_clearing:
				for b in buildings:
					if Village.blocked_by(b, q):
						c = roof
						break
			img.set_pixel(u, v, c)
	_map_img = img


## 플레이어 둘레 칸들의 나무·풀·바위를 채움 (아직 안 채운 칸만, 여러 프레임에 나눠서)
func ensure_near(p: Vector3, reach := 110.0) -> void:
	for t in tiles:
		var info: Dictionary = tiles[t]
		if info.filled:
			continue
		var off: Vector2 = info.offset
		var dx := maxf(absf(p.x - off.x) - SIZE / 2.0, 0.0)
		var dz := maxf(absf(p.z - off.y) - SIZE / 2.0, 0.0)
		if Vector2(dx, dz).length() <= reach:
			info.filled = true
			_scatter_tile(t)


## 칸 하나를 지금 바로 다 채움 (처음 서 있는 칸)
func fill_now(t: Vector2i) -> void:
	if tiles.has(t) and not tiles[t].filled:
		tiles[t].filled = true
		_scatter_tile(t, false)


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
	# 흙길: 바위 텍스처를 잘게, 흙빛으로
	var dirt = ClassDB.instantiate("Terrain3DTextureAsset")
	dirt.name = "Dirt"
	dirt.albedo_texture = rock.albedo_texture
	dirt.normal_texture = rock.normal_texture
	dirt.uv_scale = 0.3
	dirt.albedo_color = Color(0.78, 0.62, 0.44)
	terrain.assets.set_texture_asset(0, grass)
	terrain.assets.set_texture_asset(1, rock)
	terrain.assets.set_texture_asset(ROAD_TEX, dirt)
	terrain.material.world_background = 0  # NONE: 지도 밖은 비움
	terrain.material.auto_shader_enabled = true
	terrain.material.set_shader_param("auto_slope", 1.5)
	terrain.material.set_shader_param("auto_base_texture", 1)
	terrain.material.set_shader_param("auto_overlay_texture", 0)
	terrain.material.set_shader_param("blend_sharpness", 0.9)


func _mesh_id(model: String) -> int:
	if _mesh_ids.has(model):
		return _mesh_ids[model]
	var scene := _wind_grass_scene() if model == "Grass_Wind" else WindFoliage.scene(NATURE % model)
	if scene == null:
		return -1
	var id := _mesh_ids.size()
	var ma = ClassDB.instantiate("Terrain3DMeshAsset")
	ma.name = model
	ma.scene_file = scene
	if model == "Grass_Wind":
		ma.material_override = _wind_grass_mat()
		ma.set("cast_shadows", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)  # 수만 개라 그림자는 끔
	terrain.assets.set_mesh_asset(id, ma)
	_mesh_ids[model] = id
	return id


## 바람 풀 재질 (식생 배치 메시와 장면이 같은 재질을 씀)
var _wind_mat: ShaderMaterial = null
func _wind_grass_mat() -> ShaderMaterial:
	if _wind_mat == null:
		_wind_mat = (load(WIND_GRASS_MAT) as ShaderMaterial).duplicate()
	return _wind_mat


## 바람 풀 덤불 하나를 장면으로 (Terrain3D 식생 배치는 장면 파일을 받음). 설치가 안 됐으면 null
func _wind_grass_scene() -> PackedScene:
	if not ResourceLoader.exists(WIND_GRASS_MESH) or not ResourceLoader.exists(WIND_GRASS_MAT):
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Grass_Wind"
	mi.mesh = load(WIND_GRASS_MESH)
	mi.material_override = _wind_grass_mat()
	var packed := PackedScene.new()
	packed.pack(mi)
	mi.free()
	return packed


## 숲 노이즈가 높은 곳에 나무, 경사가 급하면 바위만. sliced면 몇천 개마다 한 프레임 쉼
func _scatter_tile(t: Vector2i, sliced := true) -> void:
	var info: Dictionary = tiles[t]
	var off: Vector2 = info.offset
	var village: bool = info.village
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info.seed) * 31 + 5
	var forest := FastNoiseLite.new()
	forest.seed = _world_seed + 17  # 지방 전체가 같은 숲 노이즈 (칸을 넘어 이어짐)
	forest.frequency = 0.02
	var lim := SIZE / 2.0
	var budget := 0
	# 부딪히는 몸은 칸마다 따로, 다 채운 뒤에 붙임 (한 몸에 모양을 하나씩 붙이면 느림)
	var body := StaticBody3D.new()
	body.name = "Obstacles%d_%d" % [t.x, t.y]
	var has_door: bool = info.entrance != null
	var wind_layer: Array = []
	var slice_from := Time.get_ticks_usec()
	for layer in FOLIAGE:
		var models: Array = layer[0]
		if models[0] == "Grass_Wind":
			wind_layer = layer  # 아래에서 일꾼 스레드로
			continue
		var by_model := {}
		for i in int(layer[1]):
			budget += 1
			# 한 프레임에 4ms까지만
			if sliced and budget % 64 == 0 and Time.get_ticks_usec() - slice_from > 4000:
				await get_tree().process_frame
				if not is_inside_tree():
					return
				slice_from = Time.get_ticks_usec()
			var lp := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
			var p := Vector3(lp.x + off.x, 0, lp.y + off.y)
			var is_grass: bool = String(models[0]).begins_with("Grass")
			# 빈터: 풀만 (가운데는 비움)
			if village and lp.length() < CLEARING * (0.5 if is_grass else 1.3):
				continue
			if has_door and (not is_grass or models[0] == "Grass_Wind") and _near_path(t, Vector2(p.x, p.z)):
				continue
			if _road_d(p.x, p.z) < (3.0 if not is_grass else 1.6):
				continue
			if village and keep_out.is_valid() and lp.length_squared() < 4900.0 and keep_out.call(Vector2(p.x, p.z), 0.4 if is_grass else 1.5):
				continue
			var trees: float = _look(p.x, p.z).y
			if forest.get_noise_2d(p.x, p.z) < float(layer[2]) + trees * (1.0 if not is_grass else 0.3) + rng.randf_range(-0.1, 0.1):
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
			if not is_grass:
				_add_obstacle(body, m, p, s)
		for m in by_model:
			var id := _mesh_id(m)
			if id < 0:
				continue
			# 많이 한꺼번에 넣으면 한 프레임이 길어져서 조금씩
			var all: Array = by_model[m]
			var start := 0
			while start < all.size():
				var xfs: Array[Transform3D] = []
				xfs.assign(all.slice(start, start + 3000))
				terrain.instancer.add_transforms(id, xfs)
				start += 3000
				if sliced:
					await get_tree().process_frame
					if not is_inside_tree():
						return
	add_child(body)
	if village and info.entrance != null:
		_path_stones(rng, Vector2(info.entrance.origin.x, info.entrance.origin.z))
	# 바람 풀은 칸마다 10만 개라 자리 계산을 일꾼 스레드에서 하고, 다 되면 조금씩 넣음
	var gid := _mesh_id("Grass_Wind")
	if wind_layer.is_empty() or gid < 0:
		return
	var out: Array[Transform3D] = []
	var task := WorkerThreadPool.add_task(_wind_grass.bind(t, wind_layer, out))
	_tasks.append(task)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_tasks.erase(task)
	WorkerThreadPool.wait_for_task_completion(task)
	var start := 0
	while start < out.size():
		terrain.instancer.add_transforms(gid, out.slice(start, start + 3000))
		start += 3000
		await get_tree().process_frame
		if not is_inside_tree():
			return


## 바람 풀 자리 (일꾼 스레드). 높이·경사는 기억한 높이 배열에서 바로 읽음 (지형 노드는 건드리지 않음)
func _wind_grass(t: Vector2i, layer: Array, out: Array[Transform3D]) -> void:
	var info: Dictionary = tiles[t]
	var off: Vector2 = info.offset
	var village: bool = info.village
	var has_door: bool = info.entrance != null
	var hs: PackedFloat32Array = _cache[t][2]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info.seed) * 31 + 11
	var forest := FastNoiseLite.new()
	forest.seed = _world_seed + 17
	forest.frequency = 0.02
	var lim := SIZE / 2.0
	var min_ny: float = layer[4]
	var sr: Vector2 = layer[3]
	var floor_n: float = layer[2]
	var clear2 := (CLEARING * 0.5) * (CLEARING * 0.5)
	for i in int(layer[1]):
		var lx := rng.randf_range(-lim + 1.0, lim - 2.0)
		var lz := rng.randf_range(-lim + 1.0, lim - 2.0)
		var rot := rng.randf() * TAU
		var s := rng.randf_range(sr.x, sr.y)
		var jitter := rng.randf_range(-0.1, 0.1)
		var d2 := lx * lx + lz * lz
		if village and d2 < clear2:
			continue
		var wp := Vector2(lx + off.x, lz + off.y)
		if has_door and _near_path(t, wp):
			continue
		if _road_d(wp.x, wp.y) < 1.6:
			continue
		if village and d2 < 4900.0 and keep_out.is_valid() and keep_out.call(wp, 0.4):
			continue
		if forest.get_noise_2d(wp.x, wp.y) < floor_n + _look(wp.x, wp.y).y * 0.3 + jitter:
			continue
		var px := lx + lim
		var pz := lz + lim
		var ix := int(px)
		var iz := int(pz)
		var k := iz * SIZE + ix
		var h00 := hs[k]
		var h10 := hs[k + 1]
		var h01 := hs[k + SIZE]
		var h11 := hs[k + SIZE + 1]
		var gx := (h10 - h00 + h11 - h01) * 0.5
		var gz := (h01 - h00 + h11 - h10) * 0.5
		if 1.0 / sqrt(1.0 + gx * gx + gz * gz) < min_ny:
			continue
		var fx := px - ix
		var fz := pz - iz
		var h := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
		out.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(wp.x, h, wp.y)))


func _exit_tree() -> void:
	# 장면이 바뀔 때 아직 도는 일꾼 스레드를 기다림 (이 노드를 읽으니까)
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	if _map_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_map_task)
		_map_task = -1


## 나무 줄기·바위에 부딪히게 원기둥 충돌체 (식생 배치는 그림만 그림)
func _add_obstacle(body: StaticBody3D, model: String, p: Vector3, s: float) -> void:
	if not _solid_r.has(model):
		_solid_r[model] = 0.0
		for e in SOLID:
			if model.begins_with(e[0]):
				_solid_r[model] = float(e[1])
	var base: float = _solid_r[model]
	if base <= 0.0:
		return
	var r := snappedf(base * s, 0.02)
	if not _shapes.has(r):
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = 2.0
		_shapes[r] = cyl
	var shape := CollisionShape3D.new()
	shape.shape = _shapes[r]
	shape.position = p + Vector3(0, 1.0, 0)
	body.add_child(shape)
	solids.append(Vector3(p.x, p.z, r))


## 입구 터나 마을 길 위인가 (큰 식생을 두지 않음). p는 세계 좌표
func _near_path(t: Vector2i, p: Vector2) -> bool:
	var info: Dictionary = tiles[t]
	if info.entrance == null:
		return false
	var e2 := Vector2(info.entrance.origin.x, info.entrance.origin.z)
	if p.distance_to(e2) < PAD * 1.6:
		return true
	if not info.village:
		return false
	var along := clampf(p.dot(e2) / e2.length_squared(), 0.0, 1.0)
	return p.distance_to(e2 * along) < PATH_W * 2.0


## 빈터에서 입구까지 디딤돌 (마을 칸, 세계 좌표 = 칸 좌표)
func _path_stones(rng: RandomNumberGenerator, e2: Vector2) -> void:
	var stones := ["RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3", "RockPath_Round_Wide", "RockPath_Round_Thin"]
	var by_model := {}
	var dist := 5.0  # 마을 광장 끝부터 (길 쪽 블록은 비어 있음)
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
func _build_entrance(t: Vector2i, xf: Transform3D) -> void:
	var root := Node3D.new()
	root.name = "DungeonEntrance%d_%d" % [t.x, t.y]
	root.transform = xf
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
			entrance_entered.emit(b, t))


## 바깥 전투용 격자: origin(왼쪽 위 칸의 모서리, 월드 x·z)부터 size칸. 칸 (x, y)의 가운데는 월드 (origin.x + x + 0.5, origin.y + y + 0.5).
## 높이는 땅 높이 그대로(월드 y), 너무 가파른 칸(이웃과 높이 차 STEEP 넘음)은 벽, 나무 줄기·바위 칸은 장애물.
## 실시간 액션 전투(ActionCombat)는 높이를 통과 판정에 쓰지 않으므로 벽·장애물만 막음.
const STEEP := 0.9
func battle_grid(origin: Vector2i, size: Vector2i) -> Dungeon:
	var d := Dungeon.new(size.x, size.y)
	var hs := {}
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			hs[Vector2i(x, y)] = height_at(Vector3(origin.x + x + 0.5, 0, origin.y + y + 0.5))
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			var h: float = hs[c]
			var steep := false
			for dd in Dungeon.DIRS4:
				if absf(float(hs[c + dd]) - h) > STEEP:
					steep = true
					break
			if steep:
				continue
			d.set_tile(c, Dungeon.Tile.FLOOR)
			d.heights[c] = h
	var rect := Rect2(Vector2(origin), Vector2(size))
	for sd in solids:
		var at := Vector2(sd.x, sd.y)
		if not rect.grow(1.0).has_point(at):
			continue
		var r := maxf(sd.z, 0.3)
		for cy in range(floori(at.y - r), floori(at.y + r) + 1):
			for cx in range(floori(at.x - r), floori(at.x + r) + 1):
				var c := Vector2i(cx - origin.x, cy - origin.y)
				if d.is_floor(c) and Vector2(cx + 0.5, cy + 0.5).distance_to(at) < r + 0.35:
					d.obstacles[c] = 3.0
	if keep_out.is_valid():
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if d.is_floor(c) and keep_out.call(Vector2(origin.x + x + 0.5, origin.y + y + 0.5), 0.3):
					d.obstacles[c] = 3.0
	return d


## 칸 t의 던전 입구 앞 (빈터 쪽으로 dist칸) 땅 위 자리. 입구가 없으면 칸 가운데
func before_entrance(t: Vector2i, dist := 2.5) -> Vector3:
	var info: Dictionary = tiles.get(t, {})
	if info.is_empty() or info.entrance == null:
		var off: Vector2 = Region.offset(t, SIZE)
		return Vector3(off.x, height_at(Vector3(off.x, 0, off.y)) + 0.5, off.y)
	var p: Vector3 = (info.entrance as Transform3D) * Vector3(0, 0, dist)
	p.y = height_at(p) + 0.3
	return p


## p(세계 x·z) 가까이에서 나무·바위·건물이 없고 너무 가파르지 않은 땅 위 자리 (빙글빙글 넓혀 가며 찾음)
func free_spot(p: Vector3, room := 1.5) -> Vector3:
	for ring in 40:
		var r := ring * 1.5
		var steps := maxi(1, ring * 6)
		for k in steps:
			var a := TAU * k / steps
			var q := Vector3(p.x + cos(a) * r, 0, p.z + sin(a) * r)
			if _clear_at(q, room):
				q.y = height_at(q) + 0.5
				return q
	p.y = height_at(p) + 0.5
	return p


func _clear_at(q: Vector3, room: float) -> bool:
	var n: Vector3 = terrain.data.get_normal(q)
	if not n.is_finite() or n.y < 0.85:
		return false
	if keep_out.is_valid() and keep_out.call(Vector2(q.x, q.z), room):
		return false
	for sd in solids:
		if Vector2(sd.x - q.x, sd.y - q.z).length() < sd.z + room:
			return false
	return true


## 칸의 던전 입구 자리 (없으면 null)
func entrance_of(t: Vector2i):
	return tiles.get(t, {}).get("entrance", null)
