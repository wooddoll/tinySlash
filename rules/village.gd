## 마을 배치 (기획 12.5, M3). 가운데 광장을 둘러싼 3x3 블록 격자이고, 블록 하나에 건물 하나 또는 마당이 들어갑니다.
## 화면과 상관없는 규칙 쪽입니다: 건물 종류·이름·크기(원본 2m 모듈 수)·자리(칸)·정면 방향만 정합니다.
## 그리기는 scripts/town_builder.gd. 같은 시드와 길 방향이면 언제나 같은 마을입니다.
## 마을 좌표는 바깥 지형 좌표와 같습니다 (광장 가운데 = 빈터 가운데 (0, 0)).
## 다른 스크립트는 const Village = preload("res://rules/village.gd") 로 씁니다.
extends RefCounted

## 블록 한 변 (칸)
const BLOCK := 9.0
## 원본 키트의 벽 한 칸(2m)이 몇 칸인가 (tools/bake_town.gd의 SCALE과 맞춤)
const MODULE := 1.4
## 광장 반 너비 (칸)
const PLAZA := BLOCK / 2.0
## 꼭 있는 건물: 종류 → [가로 모듈, 세로 모듈, 층, 벽]
const MUST := {
	"inn": [3, 5, 2, "plaster"],
	"shop": [2, 3, 1, "plaster"],
	"guild": [3, 4, 1, "brick"],
}
## 집 크기 후보 (가로, 세로 모듈). 지붕 조각(4x4·4x6·4x8·6x6·6x8)에 맞는 것만
const HOUSES := [[2, 2], [2, 3], [2, 4], [3, 3], [3, 4]]
const NAMES_A := ["느릅", "갈대", "돌샘", "여우", "까치", "버들", "솔", "모래"]
const NAMES_B := ["마을", "골", "나루", "말"]
const INN_NAMES := ["졸린 수탉", "녹슨 등불", "두 그루 참나무", "따뜻한 화덕", "늙은 곰"]

## 마을 이름
var name := ""
## 건물: {kind, name, pos: Vector2(가운데, 칸), front: Vector2(정면 방향), w, d(모듈), floors, style, door: Vector2(문 앞 자리)}
var buildings: Array = []
## 건물 없는 블록: {pos, kind ("road" 길이 지나감, "yard" 마당)}
var yards: Array = []
## 의뢰판 자리와 정면 방향
var board := Vector2.ZERO
var board_front := Vector2(0, 1)
## 주민이 돌아다니는 자리들 (광장 가운데 쪽)
var wander: Array[Vector2] = []


## road_dir: 마을 밖으로 이어지는 길 방향 (던전 입구 쪽). 그 쪽 블록은 비워 둡니다.
static func generate(seed_value: int, road_dir: Vector2 = Vector2.ZERO):
	var v = load("res://rules/village.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	v.name = str(NAMES_A[rng.randi() % NAMES_A.size()]) + str(NAMES_B[rng.randi() % NAMES_B.size()])
	# 둘레 블록 8개, 길 쪽 하나는 비움
	var blocks: Array[Vector2i] = []
	for bz in [-1, 0, 1]:
		for bx in [-1, 0, 1]:
			if bx != 0 or bz != 0:
				blocks.append(Vector2i(bx, bz))
	var road := Vector2i(99, 99)
	if road_dir != Vector2.ZERO:
		var best := -2.0
		for b in blocks:
			var dot := Vector2(b).normalized().dot(road_dir.normalized())
			if dot > best:
				best = dot
				road = b
	var edges: Array[Vector2i] = []
	var corners: Array[Vector2i] = []
	for b in blocks:
		if b == road:
			v.yards.append({"pos": Vector2(b) * BLOCK, "kind": "road"})
		elif b.x == 0 or b.y == 0:
			edges.append(b)
		else:
			corners.append(b)
	_shuffle(edges, rng)
	_shuffle(corners, rng)
	# 꼭 있는 건물은 광장을 바로 보는 가장자리 블록에
	var kinds := ["inn", "shop", "guild"]
	_shuffle(kinds, rng)
	var rest: Array[Vector2i] = []
	for b in edges:
		if not kinds.is_empty():
			var k: String = kinds.pop_back()
			var s: Array = MUST[k]
			v._place(b, k, int(s[0]), int(s[1]), int(s[2]), str(s[3]), rng)
		else:
			rest.append(b)
	rest.append_array(corners)
	# 나머지는 집, 하나쯤은 마당 (수레·상자)
	var yard_at := rng.randi() % rest.size() if rest.size() > 3 else -1
	for i in rest.size():
		if i == yard_at:
			v.yards.append({"pos": Vector2(rest[i]) * BLOCK, "kind": "yard"})
			continue
		var hs: Array = HOUSES[rng.randi() % HOUSES.size()]
		v._place(rest[i], "house", int(hs[0]), int(hs[1]), 2 if rng.randf() < 0.25 else 1,
			"brick" if rng.randf() < 0.35 else "plaster", rng)
	# 의뢰판: 광장에서 길 반대쪽 모서리 가까이, 광장 가운데를 봄
	var away := -road_dir.normalized() if road_dir != Vector2.ZERO else Vector2(1, 1).normalized()
	var corner := Vector2(signf(away.x) if absf(away.x) > 0.2 else 1.0, signf(away.y) if absf(away.y) > 0.2 else 1.0)
	v.board = corner * (PLAZA - 1.6)
	v.board_front = -v.board.normalized()
	for i in 8:
		var a := TAU * i / 8.0 + rng.randf_range(-0.3, 0.3)
		v.wander.append(Vector2(cos(a), sin(a)) * rng.randf_range(1.0, PLAZA - 0.8))
	return v


func _place(b: Vector2i, kind: String, w: int, d: int, floors: int, style: String, rng: RandomNumberGenerator) -> void:
	var center := Vector2(b) * BLOCK
	var front := -center.normalized()
	var depth := d * MODULE
	var pos := center
	if b.x == 0 or b.y == 0:
		# 가장자리 블록: 정면이 광장 끝에 닿도록 광장 쪽으로 붙임
		pos = center + front * (BLOCK / 2.0 - depth / 2.0 - 0.8)
	else:
		# 모서리 블록: 광장 쪽으로 조금, 방향은 광장을 보되 살짝 틀어짐
		pos = center + front * 1.0
		front = front.rotated(rng.randf_range(-0.2, 0.2))
	var label := ""
	match kind:
		"inn":
			label = "%s 여관" % INN_NAMES[rng.randi() % INN_NAMES.size()]
		"shop":
			label = "잡화점"
		"guild":
			label = "모험가 조합 회관"
		_:
			label = "집"
	buildings.append({"kind": kind, "name": label, "pos": pos, "front": front, "w": w, "d": d,
		"floors": floors, "style": style, "door": pos + front * (depth / 2.0 + 0.7)})


## 건물 하나의 바닥 크기 (칸): 가로(x), 세로(정면 방향)
static func footprint(b: Dictionary) -> Vector2:
	return Vector2(int(b.w) * MODULE, int(b.d) * MODULE)


## p(칸)가 어느 건물 바닥(+pad) 안인가. 풀·나무를 두지 않거나 전투 칸을 막을 때 씀
func blocked(p: Vector2, pad: float = 0.0) -> bool:
	for b in buildings:
		if blocked_by(b, p, pad):
			return true
	if p.distance_to(board) < 0.6 + pad:
		return true
	return false


## p(칸)가 건물 b의 바닥(+pad) 안인가
static func blocked_by(b: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	var f := footprint(b) / 2.0 + Vector2(pad, pad)
	var fr: Vector2 = b.front
	var rel: Vector2 = p - (b.pos as Vector2)
	return absf(rel.dot(Vector2(-fr.y, fr.x))) <= f.x and absf(rel.dot(fr)) <= f.y


## 종류로 건물 찾기 (없으면 빈 사전)
func find(kind: String) -> Dictionary:
	for b in buildings:
		if b.kind == kind:
			return b
	return {}


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
