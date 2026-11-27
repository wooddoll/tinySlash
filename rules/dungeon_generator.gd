## 파라미터로 던전을 만듭니다. 같은 시드 + 같은 파라미터 = 같은 던전.
## 순서: 방 배치 -> 방 잇기(최소 신장 트리 + 순환로) -> 복도/문 -> 시작·출구 -> 지형 -> 조우 -> 보물
## 조우 예산은 SRD 5.2.1 "XP Budget per Character" 표를 따릅니다 (docs/rules.md 9.2, 생성 방식은 docs/implementation.md 4장).
class_name DungeonGenerator
extends RefCounted

## [파티 레벨 1~5][Low, Moderate, High] (SRD 5.2.1 Gameplay Toolbox)
const XP_BUDGET := [
	[50, 75, 100],
	[100, 150, 200],
	[150, 225, 400],
	[250, 375, 500],
	[500, 750, 1100],
]
const DIFFICULTY_NAMES := ["낮음", "보통", "높음"]
const THEMES := {
	"mixed": ["goblin_minion", "goblin_warrior", "goblin_boss", "skeleton", "wolf"],
	"goblin": ["goblin_minion", "goblin_warrior", "goblin_boss"],
	"undead": ["skeleton"],
	"beast": ["wolf"],
}
## 한 조우에 한 마리만 나오는 몬스터
const UNIQUE := ["goblin_boss", "bellwarden", "cantor", "regent"]
## [변경] 보스 방 전용 몬스터 (XP 순). 예산의 BOSS_STRETCH배 안에서 가장 비싼 것 하나를 먼저 넣음
const BOSSES := ["bellwarden", "cantor", "regent"]
const BOSS_STRETCH := 1.2
const MAX_FOES := 8

var p: DungeonParams
var rng := RandomNumberGenerator.new()
var d: Dungeon
var room_min := 4
var room_max := 9
var _xp_cache := {}
var _names := {}


static func generate(params: DungeonParams) -> Dungeon:
	var g := DungeonGenerator.new()
	return g._run(params)


func _run(params: DungeonParams) -> Dungeon:
	p = params
	var s := p.rng_seed
	if s == 0:
		s = randi_range(1, 999999)
	rng.seed = s
	room_min = mini(p.room_min, p.room_max)
	room_max = maxi(p.room_min, p.room_max)
	d = Dungeon.new(p.width, p.height)
	d.seed_used = s
	d.params = p

	if p.algorithm == DungeonParams.Algorithm.CAVE:
		_cave()
	else:
		if p.algorithm == DungeonParams.Algorithm.BSP:
			_rooms_bsp()
		else:
			_rooms_scatter()
		for r in d.rooms:
			for c in r.cells:
				d.set_tile(c, Dungeon.Tile.FLOOR)
		d.edges = _connect_rooms()
		for e in d.edges:
			_corridor(d.rooms[e.x].center, d.rooms[e.y].center)
		_mark_doors()

	_choose_start_exit()
	_features()
	_encounters()
	_treasure()
	_campfires()
	return d


# =====================================================================
# 방 배치
# =====================================================================

func _add_room(rect: Rect2i) -> void:
	var cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y))
	_register_room(cells, rect, rect.position + rect.size / 2)


func _register_room(cells: Array[Vector2i], rect: Rect2i, center: Vector2i) -> void:
	var id := d.rooms.size()
	for c in cells:
		d.room_index[c] = id
	d.rooms.append({
		"id": id, "cells": cells, "rect": rect, "center": center, "kind": "normal",
		"depth": 0.0, "encounter": {}, "treasure": [],
	})


## 공간을 큰 것부터 반으로 나눠 room_count개의 구역을 만들고, 구역마다 방 하나
func _rooms_bsp() -> void:
	var leaves: Array[Rect2i] = [Rect2i(1, 1, p.width - 2, p.height - 2)]
	var min_leaf := room_min + 2
	while leaves.size() < p.room_count:
		leaves.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.get_area() > b.get_area())
		var split := false
		for i in leaves.size():
			var parts := _split(leaves[i], min_leaf)
			if parts.size() == 2:
				leaves.remove_at(i)
				leaves.append_array(parts)
				split = true
				break
		if not split:
			break
	_shuffle(leaves)  # 방 번호가 위치 순서로 몰리지 않게
	for leaf in leaves:
		var max_w := mini(room_max, leaf.size.x - 2)
		var max_h := mini(room_max, leaf.size.y - 2)
		if max_w < 3 or max_h < 3:
			continue
		var w := rng.randi_range(mini(room_min, max_w), max_w)
		var h := rng.randi_range(mini(room_min, max_h), max_h)
		var x := rng.randi_range(leaf.position.x + 1, leaf.end.x - 1 - w)
		var y := rng.randi_range(leaf.position.y + 1, leaf.end.y - 1 - h)
		_add_room(Rect2i(x, y, w, h))


func _split(r: Rect2i, min_leaf: int) -> Array[Rect2i]:
	var can_x := r.size.x >= min_leaf * 2
	var can_y := r.size.y >= min_leaf * 2
	if not can_x and not can_y:
		return []
	var vertical: bool
	if can_x and not can_y:
		vertical = true
	elif can_y and not can_x:
		vertical = false
	elif r.size.x > r.size.y * 1.25:
		vertical = true
	elif r.size.y > r.size.x * 1.25:
		vertical = false
	else:
		vertical = rng.randf() < 0.5
	if vertical:
		var cut := rng.randi_range(min_leaf, r.size.x - min_leaf)
		return [Rect2i(r.position, Vector2i(cut, r.size.y)),
				Rect2i(r.position.x + cut, r.position.y, r.size.x - cut, r.size.y)]
	var cut_y := rng.randi_range(min_leaf, r.size.y - min_leaf)
	return [Rect2i(r.position, Vector2i(r.size.x, cut_y)),
			Rect2i(r.position.x, r.position.y + cut_y, r.size.x, r.size.y - cut_y)]


## 겹치지 않게(벽 2칸 이상 간격) 무작위 위치에 방을 놓아 봅니다
func _rooms_scatter() -> void:
	var placed: Array[Rect2i] = []
	var attempts := p.room_count * 60
	while placed.size() < p.room_count and attempts > 0:
		attempts -= 1
		var w := rng.randi_range(room_min, mini(room_max, p.width - 4))
		var h := rng.randi_range(room_min, mini(room_max, p.height - 4))
		var x := rng.randi_range(1, p.width - 1 - w)
		var y := rng.randi_range(1, p.height - 1 - h)
		var rect := Rect2i(x, y, w, h)
		var grown := rect.grow(2)
		var ok := true
		for o in placed:
			if grown.intersects(o):
				ok = false
				break
		if ok:
			placed.append(rect)
			_add_room(rect)


# =====================================================================
# 동굴
# =====================================================================

func _cave() -> void:
	var w := p.width
	var h := p.height
	var wall := PackedByteArray()
	wall.resize(w * h)
	for y in h:
		for x in w:
			var border := x == 0 or y == 0 or x == w - 1 or y == h - 1
			wall[y * w + x] = 1 if border or rng.randf() < p.cave_fill else 0
	# 3x3 안에 벽이 5개 이상이면 벽 (4-5 규칙)
	for it in 5:
		var nxt := wall.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var n := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						n += wall[(y + dy) * w + x + dx]
				nxt[y * w + x] = 1 if n >= 5 else 0
		wall = nxt
	for y in h:
		for x in w:
			if wall[y * w + x] == 0:
				d.set_tile(Vector2i(x, y), Dungeon.Tile.FLOOR)

	# 작은 웅덩이는 메움
	var min_region := maxi(room_min * room_min / 2, 6)
	var regions: Array = []
	var seen := {}
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if seen.has(c) or not d.is_floor(c):
				continue
			var region := _flood_tiles(c, seen)
			if region.size() < min_region:
				for rc in region:
					d.set_tile(rc, Dungeon.Tile.WALL)
			else:
				regions.append(region)
	if regions.is_empty():
		# 너무 빽빽하면 가운데에 방 하나라도 만듭니다
		var rect := Rect2i(w / 2 - 3, h / 2 - 3, 6, 6)
		var cells: Array[Vector2i] = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
				d.set_tile(Vector2i(x, y), Dungeon.Tile.FLOOR)
		regions.append(cells)

	# 떨어진 동굴들을 굴로 잇기: 큰 동굴부터, 이미 이어진 덩어리에서 가장 가까운 칸으로
	regions.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var joined: Array = (regions[0] as Array).duplicate()
	for i in range(1, regions.size()):
		var reg: Array = regions[i]
		var a: Vector2i = reg[rng.randi_range(0, reg.size() - 1)]
		var best: Vector2i = joined[0]
		var best_d := 1 << 30
		for j in range(0, joined.size(), 3):
			var c: Vector2i = joined[j]
			var dd := (c - a).length_squared()
			if dd < best_d:
				best_d = dd
				best = c
		_tunnel(a, best)
		joined.append_array(reg)

	_cave_chambers()


func _flood_tiles(from: Vector2i, seen: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = [from]
	seen[from] = true
	var i := 0
	while i < out.size():
		var c := out[i]
		i += 1
		for dd in Dungeon.DIRS4:
			var n: Vector2i = c + dd
			if not seen.has(n) and d.is_floor(n):
				seen[n] = true
				out.append(n)
	return out


## 목표 쪽으로 70% 확률로 다가가며 구불구불 파는 굴
func _tunnel(a: Vector2i, b: Vector2i) -> void:
	var c := a
	var guard := (p.width + p.height) * 8
	while c != b and guard > 0:
		guard -= 1
		_carve(c, Dungeon.Tile.FLOOR)
		var step := Vector2i.ZERO
		if rng.randf() < 0.7:
			var diff := b - c
			if absi(diff.x) > absi(diff.y) or (absi(diff.x) == absi(diff.y) and rng.randf() < 0.5):
				step.x = signi(diff.x)
			else:
				step.y = signi(diff.y)
		else:
			step = Dungeon.DIRS4[rng.randi_range(0, 3)]
		var n := c + step
		if n.x >= 1 and n.y >= 1 and n.x < p.width - 1 and n.y < p.height - 1:
			c = n
	_carve(b, Dungeon.Tile.FLOOR)


## 동굴 바닥을 room_count개의 "방"(구역)으로 나눕니다: 서로 먼 씨앗 칸을 고르고 가까운 씨앗에 배정
func _cave_chambers() -> void:
	var floor_cells: Array[Vector2i] = []
	for y in p.height:
		for x in p.width:
			if d.is_floor(Vector2i(x, y)):
				floor_cells.append(Vector2i(x, y))
	var area_per_room := maxi(room_min * room_min, 12)
	var count := clampi(floor_cells.size() / area_per_room, 1, p.room_count)
	var seeds: Array[Vector2i] = [floor_cells[rng.randi_range(0, floor_cells.size() - 1)]]
	var far := d.flood(seeds[0]).dist as Dictionary
	while seeds.size() < count:
		var best: Vector2i = seeds[0]
		var best_d := -1
		for c in floor_cells:
			var dd: int = far.get(c, 0)
			if dd > best_d:
				best_d = dd
				best = c
		if best_d <= 2:
			break
		seeds.append(best)
		var fl: Dictionary = d.flood(best).dist
		for c in fl:
			far[c] = mini(far.get(c, 1 << 30), fl[c])

	# 여러 씨앗에서 동시에 BFS: 먼저 닿은 씨앗의 방
	var owner := {}
	var q: Array[Vector2i] = []
	for i in seeds.size():
		owner[seeds[i]] = i
		q.append(seeds[i])
	var qi := 0
	while qi < q.size():
		var c := q[qi]
		qi += 1
		for dd in Dungeon.DIRS4:
			var n: Vector2i = c + dd
			if not owner.has(n) and d.is_floor(n):
				owner[n] = owner[c]
				q.append(n)
	var cells_by: Array = []
	for i in seeds.size():
		var empty: Array[Vector2i] = []
		cells_by.append(empty)
	for c in owner:
		(cells_by[owner[c]] as Array[Vector2i]).append(c)
	for i in seeds.size():
		var cells: Array[Vector2i] = cells_by[i]
		var mn := cells[0]
		var mx := cells[0]
		for c in cells:
			mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
			mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
		_register_room(cells, Rect2i(mn, mx - mn + Vector2i.ONE), seeds[i])
	# 맞닿은 구역끼리 이어진 것으로 기록
	var seen := {}
	for c in owner:
		for dd in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + dd
			if owner.has(n) and owner[n] != owner[c]:
				var e := Vector2i(mini(owner[c], owner[n]), maxi(owner[c], owner[n]))
				if not seen.has(e):
					seen[e] = true
					d.edges.append(e)


# =====================================================================
# 방 잇기, 복도, 문
# =====================================================================

## 최소 신장 트리(Prim)로 모든 방을 잇고, 가까운 방 사이에 loop_chance 확률로 길을 더 놓습니다
func _connect_rooms() -> Array[Vector2i]:
	var n := d.rooms.size()
	var out: Array[Vector2i] = []
	if n < 2:
		return out
	var in_tree := {0: true}
	var has_edge := {}
	while in_tree.size() < n:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for a in in_tree:
			for b in n:
				if in_tree.has(b):
					continue
				var dd := _room_dist(a, b)
				if dd < best_d:
					best_d = dd
					best = Vector2i(a, b)
		in_tree[best.y] = true
		out.append(best)
		has_edge[Vector2i(mini(best.x, best.y), maxi(best.x, best.y))] = true
	# 순환로: 각 방에서 가까운 방 2개 중 아직 안 이어진 쪽
	for a in n:
		var others: Array = range(n)
		others.erase(a)
		others.sort_custom(func(x: int, y: int) -> bool: return _room_dist(a, x) < _room_dist(a, y))
		for b in others.slice(0, 2):
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not has_edge.has(key) and rng.randf() < p.loop_chance:
				has_edge[key] = true
				out.append(key)
	return out


func _room_dist(a: int, b: int) -> float:
	return Vector2(d.rooms[a].center).distance_to(Vector2(d.rooms[b].center))


## ㄱ자 복도 (꺾는 방향은 무작위)
func _corridor(a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_line(a, corner)
	_carve_line(corner, b)


func _carve_line(a: Vector2i, b: Vector2i) -> void:
	var c := a
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	while true:
		_carve(c, Dungeon.Tile.FLOOR)
		if c == b:
			break
		c += step


func _carve(c: Vector2i, t: int) -> void:
	for dy in p.corridor_width:
		for dx in p.corridor_width:
			var n := c + Vector2i(dx, dy)
			if n.x >= 1 and n.y >= 1 and n.x < p.width - 1 and n.y < p.height - 1:
				if not d.is_floor(n):
					d.set_tile(n, t)


## 폭 1 복도가 방에 들어가는 칸을 문으로 (보기용, 규칙상 바닥과 같음)
func _mark_doors() -> void:
	if p.corridor_width != 1:
		return
	for y in range(1, p.height - 1):
		for x in range(1, p.width - 1):
			var c := Vector2i(x, y)
			if not d.is_floor(c) or d.room_index.has(c):
				continue
			var touches_room := false
			for dd in Dungeon.DIRS4:
				if d.room_index.has(c + dd):
					touches_room = true
			if not touches_room:
				continue
			var l := d.is_floor(c + Vector2i(-1, 0))
			var r := d.is_floor(c + Vector2i(1, 0))
			var u := d.is_floor(c + Vector2i(0, -1))
			var dn := d.is_floor(c + Vector2i(0, 1))
			if (not l and not r and u and dn) or (not u and not dn and l and r):
				d.set_tile(c, Dungeon.Tile.DOOR)


# =====================================================================
# 시작, 출구, 깊이
# =====================================================================

## 가장 멀리 떨어진 두 방을 시작과 출구로 (임의 방 -> 가장 먼 방 -> 거기서 가장 먼 방)
func _choose_start_exit() -> void:
	var any: int = rng.randi_range(0, d.rooms.size() - 1)
	var a := _farthest_room(d.rooms[any].center)
	var b := _farthest_room(d.rooms[a].center)
	d.start_room = a
	d.exit_room = b
	d.start = d.rooms[a].center
	d.exit = d.rooms[b].center
	d.rooms[a].kind = "start"
	if b != a:
		d.rooms[b].kind = "exit"
	var dist: Dictionary = d.flood(d.start).dist
	var max_d := 1
	for r in d.rooms:
		max_d = maxi(max_d, dist.get(r.center, 0))
	for r in d.rooms:
		r.depth = float(dist.get(r.center, 0)) / max_d


func _farthest_room(from: Vector2i) -> int:
	var dist: Dictionary = d.flood(from).dist
	var best := 0
	var best_d := -1
	for r in d.rooms:
		var dd: int = dist.get(r.center, -1)
		if dd > best_d:
			best_d = dd
			best = r.id
	return best


# =====================================================================
# 지형: 기둥/바위, 단상, 잔해
# =====================================================================

func _features() -> void:
	var cave := p.algorithm == DungeonParams.Algorithm.CAVE
	if cave and p.height_variation > 0.0:
		var noise := FastNoiseLite.new()
		noise.seed = rng.randi()
		noise.frequency = 0.09
		var t := p.height_variation
		for r in d.rooms:
			for c in r.cells:
				var v := noise.get_noise_2d(c.x, c.y)
				if v > 0.6 - 0.45 * t:
					d.heights[c] = 1.0
				elif v > 0.35 - 0.45 * t:
					d.heights[c] = 0.5

	for r in d.rooms:
		if not cave and (r.rect as Rect2i).size.x >= 5 and (r.rect as Rect2i).size.y >= 5 \
				and rng.randf() < p.height_variation:
			_platform(r)
		if r.kind != "start":
			_obstacles(r)

	# 잔해: 작은 덩어리로 흩뿌림 (문, 시작, 출구 칸은 피함)
	var floor_cells: Array[Vector2i] = []
	for y in p.height:
		for x in p.width:
			var c := Vector2i(x, y)
			if d.get_tile(c) == Dungeon.Tile.FLOOR and not d.obstacles.has(c):
				floor_cells.append(c)
	var want := int(floor_cells.size() * p.rubble_density)
	var guard := want * 4
	while d.difficult.size() < want and guard > 0 and not floor_cells.is_empty():
		guard -= 1
		var c := floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
		for i in rng.randi_range(1, 4):
			if d.get_tile(c) == Dungeon.Tile.FLOOR and not d.obstacles.has(c) and c != d.start and c != d.exit:
				d.difficult[c] = true
			c += Dungeon.DIRS8[rng.randi_range(0, 7)]


## 방 안에 0.5 높이 단상, 크면 가운데를 1.0으로 한 단 더 (한 걸음 높이차는 최대 0.5)
func _platform(r: Dictionary) -> void:
	var rect: Rect2i = r.rect
	var w := rng.randi_range(2, rect.size.x - 2)
	var h := rng.randi_range(2, rect.size.y - 2)
	var x := rng.randi_range(rect.position.x + 1, rect.end.x - 1 - w)
	var y := rng.randi_range(rect.position.y + 1, rect.end.y - 1 - h)
	var plat := Rect2i(x, y, w, h)
	for yy in range(plat.position.y, plat.end.y):
		for xx in range(plat.position.x, plat.end.x):
			d.heights[Vector2i(xx, yy)] = 0.5
	if w >= 4 and h >= 4 and rng.randf() < p.height_variation:
		var inner := plat.grow(-1)
		for yy in range(inner.position.y, inner.end.y):
			for xx in range(inner.position.x, inner.end.x):
				d.heights[Vector2i(xx, yy)] = 1.0


## 주변 8칸이 모두 같은 방 바닥이고 다른 장애물이 붙어 있지 않은 칸에만 놓음 -> 길이 막히지 않음
func _obstacles(r: Dictionary) -> void:
	var cells: Array = (r.cells as Array).duplicate()
	_shuffle(cells)
	var want := int(round(cells.size() * p.pillar_density))
	var placed := 0
	for c in cells:
		if placed >= want:
			break
		if not _open_spot(c, r.id) or c == r.center or c == d.start or c == d.exit:
			continue
		d.obstacles[c] = 3.0 if rng.randf() < 0.7 else 1.0
		placed += 1


func _open_spot(c: Vector2i, room_id: int) -> bool:
	for dd in Dungeon.DIRS8:
		var n: Vector2i = c + dd
		if d.room_at(n) != room_id or d.get_tile(n) != Dungeon.Tile.FLOOR or d.obstacles.has(n):
			return false
	return true


# =====================================================================
# 조우와 보물
# =====================================================================

func _encounters() -> void:
	var pool: Array = THEMES.get(p.theme, THEMES["mixed"])
	var lvl := clampi(p.party_level, 1, 5)
	var candidates: Array = []
	for r in d.rooms:
		if r.kind == "normal":
			candidates.append(r)
	_shuffle(candidates)
	var n := int(round(candidates.size() * p.encounter_ratio))
	var chosen: Array = candidates.slice(0, n)
	if d.exit_room != d.start_room and (p.boss_room or rng.randf() < p.encounter_ratio):
		chosen.append(d.rooms[d.exit_room])

	for r in chosen:
		var diff: int = p.difficulty
		var boss := false
		if r.kind == "exit" and p.boss_room:
			diff = DungeonParams.Difficulty.HIGH
			boss = true
		elif p.difficulty_ramp and r.depth > 0.66:
			diff = mini(diff + 1, DungeonParams.Difficulty.HIGH)
		var budget: int = int(XP_BUDGET[lvl - 1][diff] * p.party_size * depth_multiplier(p.floor_depth))
		var free := _free_cells(r)
		var cap := clampi(free.size() / 4, 1, MAX_FOES)
		var ids := _pick_monsters(budget, pool, boss, cap)
		var cells := _cluster(free, ids.size())
		var foes: Array = []
		var xp := 0
		for i in cells.size():
			foes.append([ids[i], cells[i]])
			xp += _xp(ids[i])
		r.encounter = {
			"difficulty": diff, "budget": budget, "xp": xp, "foes": foes, "boss": boss,
			"label": _encounter_label(ids, diff, boss),
		}


## 예산 안에서 무작위로 고름. 보스 방은 예산 안에서 가장 비싼 몬스터부터
func _pick_monsters(budget: int, pool: Array, boss: bool, cap: int) -> Array[String]:
	var out: Array[String] = []
	var left := budget
	if boss:
		var best := ""
		for id in BOSSES:
			if _xp(id) <= budget * BOSS_STRETCH and (best == "" or _xp(id) > _xp(best)):
				best = id
		if best == "":  # 보스를 감당할 예산이 아니면 예전처럼 무리에서 가장 비싼 것
			for id in pool:
				if _xp(id) <= left and (best == "" or _xp(id) > _xp(best)):
					best = id
		if best != "":
			out.append(best)
			left -= _xp(best)
	while out.size() < cap:
		var options: Array = []
		for id in pool:
			if _xp(id) <= left and not (id in UNIQUE and id in out):
				options.append(id)
		if options.is_empty():
			break
		var pick: String = options[rng.randi_range(0, options.size() - 1)]
		out.append(pick)
		left -= _xp(pick)
	if out.is_empty():
		# 예산이 가장 싼 몬스터보다 작을 때 (보통은 없음)
		var cheapest: String = pool[0]
		for id in pool:
			if _xp(id) < _xp(cheapest):
				cheapest = id
		out.append(cheapest)
	return out


func _xp(id: String) -> int:
	if not _xp_cache.has(id):
		var st := Catalog.monster(id)
		_xp_cache[id] = st.xp
		_names[id] = st.display_name
	return _xp_cache[id]


func _encounter_label(ids: Array[String], diff: int, boss: bool) -> String:
	var counts := {}
	for id in ids:
		counts[id] = counts.get(id, 0) + 1
	var parts := PackedStringArray()
	for id in counts:
		parts.append("%s %d" % [_names[id], counts[id]])
	return "%s%s — %s" % ["보스 · " if boss else "", DIFFICULTY_NAMES[diff], ", ".join(parts)]


## 몬스터·보물을 놓을 수 있는 칸: 서 있을 수 있고, 문이나 복도 바로 옆이 아니고, 시작/출구가 아님
func _free_cells(r: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var used := {}
	if not r.encounter.is_empty():
		for f in r.encounter.foes:
			used[f[1]] = true
	for t in r.treasure:
		used[t.cell] = true
	for c in r.cells:
		if not d.is_walkable(c) or c == d.start or c == d.exit or used.has(c):
			continue
		var near_entry := false
		for dd in Dungeon.DIRS8:
			var n: Vector2i = c + dd
			if d.get_tile(n) == Dungeon.Tile.DOOR or (d.is_floor(n) and d.room_at(n) == -1):
				near_entry = true
				break
		if not near_entry:
			out.append(c)
	return out


## 기준 칸 주변으로 뭉치게 고름
func _cluster(free: Array[Vector2i], k: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if free.is_empty():
		return out
	var anchor := free[rng.randi_range(0, free.size() - 1)]
	var scored: Array = []
	for c in free:
		scored.append([Vector2(c - anchor).length() + rng.randf() * 1.5, c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(k, scored.size()):
		out.append(scored[i][1])
	return out


## 보물 상자. 금액은 v1 임시값 [변경]: 2d6 x 5 x 파티 레벨 (보스 방은 두 배)
func _treasure() -> void:
	var candidates: Array = []
	for r in d.rooms:
		if r.kind == "normal":
			candidates.append(r)
	_shuffle(candidates)
	var chosen: Array = candidates.slice(0, int(round(candidates.size() * p.treasure_ratio)))
	if p.boss_room and d.exit_room != d.start_room:
		chosen.append(d.rooms[d.exit_room])
	for r in chosen:
		var free := _free_cells(r)
		if free.is_empty():
			continue
		# 벽에 많이 붙은 칸(구석)을 선호
		var best := free[0]
		var best_score := -1.0
		for c in free:
			var walls := 0
			for dd in Dungeon.DIRS8:
				if not d.is_floor(c + dd):
					walls += 1
			var score := walls + rng.randf()
			if score > best_score:
				best_score = score
				best = c
		var gold := (rng.randi_range(1, 6) + rng.randi_range(1, 6)) * 5 * p.party_level
		if r.kind == "exit":
			gold *= 2
		(r.treasure as Array).append({"cell": best, "gold": gold})


## 층이 깊을수록 조우 예산을 늘림: 1층 1.0배, 층마다 +0.15, 최대 2배
static func depth_multiplier(floor_depth: int) -> float:
	return minf(1.0 + 0.15 * maxi(floor_depth - 1, 0), 2.0)


## 모닥불: 몬스터 없는 보통 방 중 깊이가 고르게 퍼지게 고르고, 방 가운데에 가까운 빈 칸에 놓음.
## 난수를 쓰지 않아서 다른 내용물에 영향을 주지 않음
func _campfires() -> void:
	if p.campfire_count <= 0:
		return
	var pool: Array = []
	for r in d.rooms:
		if r.encounter.is_empty() and r.kind == "normal":
			pool.append(r)
	if pool.is_empty():
		for r in d.rooms:
			if r.encounter.is_empty():
				pool.append(r)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.depth < b.depth)
	var k := mini(p.campfire_count, pool.size())
	for i in k:
		var r: Dictionary = pool[int((i + 0.5) * pool.size() / k)]
		var free := _free_cells(r)
		if free.is_empty():
			continue
		var best := free[0]
		for c in free:
			if (c - r.center).length_squared() < (best - r.center).length_squared():
				best = c
		d.campfires.append(best)


## rng 시드를 따르는 섞기 (Array.shuffle은 전역 난수를 씀)
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
