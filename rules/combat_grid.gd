## 전투 격자: 높이, 벽, 험지, 점유, 이동 비용, 길찾기, 엄폐 (docs/rules.md 2장)
class_name CombatGrid
extends RefCounted

const INF := 1 << 20
const TOTAL_COVER := 99
const NEIGHBORS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var width: int
var height: int
## 칸 -> 지형 높이 (0.5 단위)
var heights := {}
## 칸 -> 장애물 높이 (나무, 바위). 통과 불가
var walls := {}
## 칸 -> true
var difficult := {}
## 칸 -> Creature
var occupants := {}


func _init(w: int, h: int) -> void:
	width = w
	height = h


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func get_height(c: Vector2i) -> float:
	return heights.get(c, 0.0)


func is_wall(c: Vector2i) -> bool:
	return walls.has(c)


func is_edge(c: Vector2i) -> bool:
	return c.x == 0 or c.y == 0 or c.x == width - 1 or c.y == height - 1


func occupant(c: Vector2i) -> Creature:
	return occupants.get(c)


func place(cr: Creature, c: Vector2i) -> void:
	if occupants.get(cr.cell) == cr:
		occupants.erase(cr.cell)
	cr.cell = c
	occupants[c] = cr


func remove(cr: Creature) -> void:
	if occupants.get(cr.cell) == cr:
		occupants.erase(cr.cell)


## 체비셰프 거리. 높이차도 칸으로 칩니다.
func distance(a: Vector2i, b: Vector2i) -> int:
	var d := maxi(absi(a.x - b.x), absi(a.y - b.y))
	var dh := absf(get_height(a) - get_height(b))
	return maxi(d, ceili(dh - 0.001))


## 이웃 칸으로 한 걸음 옮기는 비용. 갈 수 없으면 INF
func step_cost(from: Vector2i, to: Vector2i, mover: Creature) -> int:
	if not in_bounds(to) or is_wall(to):
		return INF
	var d := to - from
	# 벽 모서리는 대각선으로 넘을 수 없음
	if d.x != 0 and d.y != 0:
		if is_wall(Vector2i(from.x + d.x, from.y)) or is_wall(Vector2i(from.x, from.y + d.y)):
			return INF
	var dh := get_height(to) - get_height(from)
	if dh > 1.001 or dh < -1.001:
		return INF  # v1: 사다리와 낙하 없음
	var cost := 2 if dh > 0.501 else 1  # 높이 1.0 오르기 = 2칸
	var is_difficult: bool = difficult.has(to)
	var occ: Creature = occupants.get(to)
	if occ != null and occ != mover and mover != null and occ.is_hostile_to(mover):
		var size_gap := absi(int(occ.stats.size) - int(mover.stats.size))
		if occ.is_incapacitated() or size_gap >= 2:
			is_difficult = true
		else:
			return INF
	if is_difficult:
		cost += 1
	return cost


## 다익스트라. 반환: {"start", "cost": {칸: 비용}, "prev": {칸: 이전 칸}}
func reachable(mover: Creature, budget: int) -> Dictionary:
	var start := mover.cell
	var cost := {start: 0}
	var prev := {}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var best_i := 0
		for i in frontier.size():
			if cost[frontier[i]] < cost[frontier[best_i]]:
				best_i = i
		var cur: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		for n in NEIGHBORS:
			var nxt: Vector2i = cur + n
			var c := step_cost(cur, nxt, mover)
			if c >= INF:
				continue
			var nd: int = cost[cur] + c
			if nd <= budget and nd < cost.get(nxt, INF):
				cost[nxt] = nd
				prev[nxt] = cur
				if not frontier.has(nxt):
					frontier.append(nxt)
	return {"start": start, "cost": cost, "prev": prev}


## reachable 결과에서 목적지까지의 경로 (출발 칸 제외)
func path(r: Dictionary, dest: Vector2i) -> Array:
	var out: Array = []
	var cur := dest
	var prev: Dictionary = r.prev
	while prev.has(cur):
		out.push_front(cur)
		cur = prev[cur]
	return out


## from에서 to로 움직일 때 기회 공격을 할 수 있는 적들
func opportunity_attackers(mover: Creature, from: Vector2i, to: Vector2i) -> Array[Creature]:
	var out: Array[Creature] = []
	for v in occupants.values():
		var e: Creature = v
		if e == mover or not e.is_hostile_to(mover) or not e.can_act() or not e.reaction_available:
			continue
		if e.melee_weapon() == null:
			continue
		var r := e.melee_reach()
		if distance(from, e.cell) <= r and distance(to, e.cell) > r:
			out.append(e)
	return out


## 엄폐: 0, 2(절반), 5(3/4), TOTAL_COVER(완전)
## 공격자 눈높이에서 대상 몸의 네 점으로 광선 4개를 쏴서 가려진 수를 셉니다.
func cover(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	var eye := Vector3(from.x + 0.5, get_height(from) + 1.0, from.y + 0.5)
	var center := Vector3(to.x + 0.5, get_height(to), to.y + 0.5)
	var flat := Vector2(center.x - eye.x, center.z - eye.z).normalized()
	var perp := Vector3(-flat.y, 0.0, flat.x) * 0.3
	var points := [
		center + perp + Vector3(0, 0.3, 0), center - perp + Vector3(0, 0.3, 0),
		center + perp + Vector3(0, 1.1, 0), center - perp + Vector3(0, 1.1, 0),
	]
	var blocked := 0
	var creature_cover := false
	for p in points:
		var res := _trace(eye, p, from, to)
		if res.blocked:
			blocked += 1
		if res.creature:
			creature_cover = true
	if blocked >= 4:
		return TOTAL_COVER
	if blocked == 3:
		return 5
	if blocked >= 1 or creature_cover:
		return 2
	return 0


func _trace(a: Vector3, b: Vector3, from: Vector2i, to: Vector2i) -> Dictionary:
	var length := a.distance_to(b)
	var steps := maxi(2, ceili(length / 0.1))
	var creature := false
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		var c := Vector2i(floori(p.x), floori(p.z))
		if c == from or c == to or not in_bounds(c):
			continue
		var top: float = get_height(c) + walls.get(c, 0.0)
		if p.y < top:
			return {"blocked": true, "creature": creature}
		if occupants.has(c):
			creature = true
	return {"blocked": false, "creature": creature}
