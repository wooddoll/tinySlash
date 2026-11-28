## 지방 (기획 9장 수직 조각, M5): 3x3 칸. 칸 하나 = 바깥 지형 한 장(OutdoorTerrain.SIZE = 256칸).
## 가운데 칸에 마을, 던전 넷(가운데 칸 하나 + 다른 칸 셋). 같은 세계 시드면 언제나 같은 지방입니다.
## 지형 높이 노이즈는 칸을 넘어 이어지게(세계 좌표로) 뽑으므로 칸 경계를 걸어서 넘어도 땅이 맞물립니다.
## 화면과 상관없는 규칙 쪽입니다. 다른 스크립트는 const Region = preload("res://rules/region.gd") 로 씁니다.
extends RefCounted

const W := 3
const H := 3
const VILLAGE := Vector2i(1, 1)
## 이웃 칸까지 걸어서 걸리는 시간 (빠른 이동, 대각선은 거리만큼 더)
const TILE_HOURS := 6.0
const PLACE_A := ["까마귀", "서리", "붉은", "늑대", "안개", "고목", "바람", "잿빛", "가시", "달빛"]
const PLACE_B := ["숲", "언덕", "벌판", "고개", "골짜기", "등성이"]
## 던전 종류: [이름 끝, 몬스터 주제, 생성 방식(0 BSP, 1 흩뿌림, 2 동굴)]
const DUNGEON_KINDS := [["굴", "beast", 2], ["광산", "goblin", 0], ["무덤", "undead", 0], ["요새", "goblin", 1], ["동굴", "beast", 2], ["지하 사원", "undead", 1]]
const DUNGEON_A := ["버려진", "잊힌", "검은", "무너진", "젖은", "속삭이는", "깊은"]

## 칸 → {name, kind ("village" / "wild"), dungeon (던전 번호, 없으면 -1)}
var tiles := {}
## 던전: {id, tile, name, theme, algorithm, seed}
var dungeons: Array = []


static func generate(world_seed: int):
	var r = load("res://rules/region.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 2654435 + 97
	var used := {}
	for y in H:
		for x in W:
			var t := Vector2i(x, y)
			var name := ""
			for k in 20:
				name = "%s %s" % [PLACE_A[rng.randi() % PLACE_A.size()], PLACE_B[rng.randi() % PLACE_B.size()]]
				if not used.has(name):
					break
			used[name] = true
			r.tiles[t] = {"name": name, "kind": "village" if t == VILLAGE else "wild", "dungeon": -1}
	# 던전: 가운데 칸 + 나머지 여덟 칸 중 셋
	var others: Array[Vector2i] = []
	for t in r.tiles:
		if t != VILLAGE:
			others.append(t)
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp := others[i]
		others[i] = others[j]
		others[j] = tmp
	var at: Array[Vector2i] = [VILLAGE]
	at.append_array(others.slice(0, 3))
	var used_names := {}
	for i in at.size():
		var kind: Array = DUNGEON_KINDS[rng.randi() % DUNGEON_KINDS.size()]
		var dname := ""
		for k in 20:
			dname = "%s %s" % [DUNGEON_A[rng.randi() % DUNGEON_A.size()], kind[0]]
			if not used_names.has(dname):
				break
		used_names[dname] = true
		r.dungeons.append({"id": i, "tile": at[i], "name": dname, "theme": kind[1], "algorithm": int(kind[2]),
			"seed": world_seed * 31 + 7 + i * 1009})
		r.tiles[at[i]].dungeon = i
	return r


static func inside(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < W and t.y < H


static func index(t: Vector2i) -> int:
	return t.y * W + t.x


## 칸 하나의 시드 (나무·몬스터 배치). 지형 높이 노이즈는 세계 시드 하나를 같이 씀
static func tile_seed(world_seed: int, t: Vector2i) -> int:
	return world_seed if t == VILLAGE else world_seed * 131 + index(t) * 7919 + 1


## 칸 가운데의 세계 좌표 (칸) — 마을 칸 가운데가 (0, 0)
static func offset(t: Vector2i, size: int) -> Vector2:
	return Vector2(t - VILLAGE) * size


## 빠른 이동 시간 (시간)
static func travel_hours(a: Vector2i, b: Vector2i) -> float:
	return snappedf(Vector2(b - a).length() * TILE_HOURS, 0.5)


## 이 칸의 던전 (없으면 빈 사전)
func dungeon_at(t: Vector2i) -> Dictionary:
	var i: int = tiles.get(t, {}).get("dungeon", -1)
	return dungeons[i] if i >= 0 else {}


## 칸 b가 칸 a에서 어느 쪽인가 (-Y가 북쪽, rules/quests.gd compass와 같은 기준)
static func direction(a: Vector2i, b: Vector2i) -> String:
	if a == b:
		return "이곳"
	var names := ["동", "남동", "남", "남서", "서", "북서", "북", "북동"]
	var v := Vector2(b - a)
	return names[posmod(roundi(atan2(v.y, v.x) / (PI / 4.0)), 8)]
