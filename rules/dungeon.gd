## 생성된 던전 데이터. DungeonGenerator.generate()가 만듭니다.
## 화면과 무관한 순수 데이터라서 테스트와 전투 장면 양쪽에서 씁니다.
class_name Dungeon
extends RefCounted

enum Tile { WALL, FLOOR, DOOR }

const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var width: int
var height: int
var seed_used := 0
var params: DungeonParams
var tiles := PackedByteArray()
## 칸 -> 바닥 높이 (0.5 / 1.0)
var heights := {}
## 칸 -> 장애물 높이 (기둥 3.0 = 완전 엄폐, 바위 1.0)
var obstacles := {}
## 칸 -> true (잔해 = 험지)
var difficult := {}
## 칸 -> 방 번호 (복도 칸은 없음)
var room_index := {}
## 방: {id, cells, rect, center, kind("normal"/"start"/"exit"), depth, encounter, treasure}
var rooms: Array[Dictionary] = []
## 방 번호 쌍 (이어진 방)
var edges: Array[Vector2i] = []
var start := Vector2i.ZERO
var exit := Vector2i.ZERO
var start_room := 0
var exit_room := 0


func _init(w: int, h: int) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	tiles.fill(Tile.WALL)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func get_tile(c: Vector2i) -> int:
	if not in_bounds(c):
		return Tile.WALL
	return tiles[c.y * width + c.x]


func set_tile(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		tiles[c.y * width + c.x] = t


func is_floor(c: Vector2i) -> bool:
	return get_tile(c) != Tile.WALL


## 서 있을 수 있는 칸 (바닥이고 장애물 없음)
func is_walkable(c: Vector2i) -> bool:
	return is_floor(c) and not obstacles.has(c)


func get_height(c: Vector2i) -> float:
	return heights.get(c, 0.0)


func room_at(c: Vector2i) -> int:
	return room_index.get(c, -1)


func floor_count() -> int:
	var n := 0
	for t in tiles:
		if t != Tile.WALL:
			n += 1
	return n


## 서 있을 수 있는 칸만 따라가는 4방향 BFS. {dist: {칸: 거리}, prev: {칸: 이전 칸}}
func flood(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var prev := {}
	var q: Array[Vector2i] = [from]
	var i := 0
	while i < q.size():
		var c := q[i]
		i += 1
		for d in DIRS4:
			var n: Vector2i = c + d
			if dist.has(n) or not is_walkable(n):
				continue
			dist[n] = dist[c] + 1
			prev[n] = c
			q.append(n)
	return {"dist": dist, "prev": prev}


## 모든 몬스터 수와 XP 합계
func encounter_totals() -> Dictionary:
	var foes := 0
	var xp := 0
	for r in rooms:
		if r.encounter.is_empty():
			continue
		foes += (r.encounter.foes as Array).size()
		xp += int(r.encounter.xp)
	return {"foes": foes, "xp": xp}


## 텍스트 지도. # 벽 . 바닥 + 문 O 기둥 o 바위 , 잔해 1/2 단상 S 시작 E 출구 m 몬스터 $ 보물
func to_ascii(show_contents := true) -> String:
	var marks := {}
	if show_contents:
		for r in rooms:
			if not r.encounter.is_empty():
				for f in r.encounter.foes:
					marks[f[1]] = "m"
			for t in r.treasure:
				marks[t.cell] = "$"
		marks[start] = "S"
		marks[exit] = "E"
	var lines := PackedStringArray()
	for y in height:
		var row := ""
		for x in width:
			var c := Vector2i(x, y)
			if marks.has(c):
				row += marks[c]
				continue
			match get_tile(c):
				Tile.WALL:
					row += "#"
				Tile.DOOR:
					row += "+"
				_:
					if obstacles.has(c):
						row += "O" if obstacles[c] >= 2.0 else "o"
					elif difficult.has(c):
						row += ","
					elif get_height(c) >= 1.0:
						row += "2"
					elif get_height(c) > 0.0:
						row += "1"
					else:
						row += "."
		lines.append(row)
	return "\n".join(lines)


## 방 하나를 전투 장면용 지도로 잘라냅니다 (scripts/battle.gd의 MAP 기호).
## X 던전 벽  P 기둥  # 바위  , 험지  1/2 높이  . 바닥
func battle_setup(room_id: int) -> Dictionary:
	var room: Dictionary = rooms[room_id]
	var rect: Rect2i = (room.rect as Rect2i).grow(2).intersection(Rect2i(0, 0, width, height))
	var map: Array[String] = []
	for y in rect.size.y:
		var row := ""
		for x in rect.size.x:
			var c := rect.position + Vector2i(x, y)
			if not is_floor(c):
				row += "X"
			elif obstacles.has(c):
				row += "P" if obstacles[c] >= 2.0 else "#"
			elif difficult.has(c):
				row += ","
			elif get_height(c) >= 1.0:
				row += "2"
			elif get_height(c) > 0.0:
				row += "1"
			else:
				row += "."
		map.append(row)

	var foes: Array = []
	var taken := {}
	if not room.encounter.is_empty():
		for f in room.encounter.foes:
			var local: Vector2i = f[1] - rect.position
			foes.append([f[0], local])
			taken[f[1]] = true

	# 시작 지점에서 이 방까지 걸어온 길이 처음 지도 안으로 들어오는 칸에서 시작
	var pc_cell: Vector2i = room.center
	if room_id != start_room:
		var fl := flood(start)
		var trail: Array[Vector2i] = []
		var c: Vector2i = room.center
		while fl.prev.has(c):
			trail.push_front(c)
			c = fl.prev[c]
		for t in trail:
			if rect.has_point(t) and not taken.has(t):
				pc_cell = t
				break
	if taken.has(pc_cell) or not is_walkable(pc_cell):
		pc_cell = _nearest_free(pc_cell, rect, taken)

	var label := "방 %d" % room_id
	if not room.encounter.is_empty():
		label += " — %s (XP %d)" % [room.encounter.label, room.encounter.xp]
	return {"map": map, "pc_start": pc_cell - rect.position, "foes": foes, "label": label,
			"theme": "dungeon", "room_id": room_id}


func _nearest_free(from: Vector2i, rect: Rect2i, taken: Dictionary) -> Vector2i:
	var best := from
	var best_d := 1 << 30
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if is_walkable(c) and not taken.has(c):
				var dd := (c - from).length_squared()
				if dd < best_d:
					best_d = dd
					best = c
	return best
