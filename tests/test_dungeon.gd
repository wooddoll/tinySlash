extends RefCounted

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func params(algo: DungeonParams.Algorithm, s: int) -> DungeonParams:
	var p := DungeonParams.new()
	p.algorithm = algo
	p.rng_seed = s
	return p


const ALGOS := [DungeonParams.Algorithm.BSP, DungeonParams.Algorithm.SCATTER, DungeonParams.Algorithm.CAVE]


func test_same_seed_same_dungeon() -> void:
	for algo in ALGOS:
		var a := DungeonGenerator.generate(params(algo, 1234))
		var b := DungeonGenerator.generate(params(algo, 1234))
		eq(a.to_ascii(), b.to_ascii(), "algo %d deterministic" % algo)
		var c := DungeonGenerator.generate(params(algo, 4321))
		check(a.to_ascii() != c.to_ascii(), "algo %d: different seed differs" % algo)


func test_every_room_reachable() -> void:
	for algo in ALGOS:
		for s in range(1, 21):
			var d := DungeonGenerator.generate(params(algo, s))
			var dist: Dictionary = d.flood(d.start).dist
			for r in d.rooms:
				check(dist.has(r.center), "algo %d seed %d: room %d unreachable" % [algo, s, r.id])
				for f in (r.encounter.get("foes", []) as Array):
					check(dist.has(f[1]), "algo %d seed %d: foe unreachable" % [algo, s])
				for t in r.treasure:
					check(dist.has(t.cell), "algo %d seed %d: treasure unreachable" % [algo, s])
			check(dist.has(d.exit), "algo %d seed %d: exit unreachable" % [algo, s])


func test_bsp_makes_requested_rooms() -> void:
	for s in range(1, 11):
		var p := params(DungeonParams.Algorithm.BSP, s)
		p.room_count = 8
		eq(DungeonGenerator.generate(p).rooms.size(), 8, "seed %d" % s)


func test_rooms_do_not_overlap_and_respect_size() -> void:
	for algo in [DungeonParams.Algorithm.BSP, DungeonParams.Algorithm.SCATTER]:
		for s in range(1, 11):
			var p := params(algo, s)
			var d := DungeonGenerator.generate(p)
			for i in d.rooms.size():
				var ri: Rect2i = d.rooms[i].rect
				check(ri.size.x >= 3 and ri.size.x <= p.room_max and ri.size.y <= p.room_max,
						"room size %s" % ri)
				check(Rect2i(1, 1, p.width - 2, p.height - 2).encloses(ri), "room inside border")
				for j in range(i + 1, d.rooms.size()):
					check(not ri.intersects(d.rooms[j].rect), "rooms %d/%d overlap" % [i, j])


func test_border_is_wall() -> void:
	for algo in ALGOS:
		var p := params(algo, 7)
		p.corridor_width = 2
		var d := DungeonGenerator.generate(p)
		for x in d.width:
			check(not d.is_floor(Vector2i(x, 0)) and not d.is_floor(Vector2i(x, d.height - 1)), "top/bottom")
		for y in d.height:
			check(not d.is_floor(Vector2i(0, y)) and not d.is_floor(Vector2i(d.width - 1, y)), "left/right")


func test_start_and_exit_far_apart() -> void:
	for s in range(1, 11):
		var d := DungeonGenerator.generate(params(DungeonParams.Algorithm.BSP, s))
		check(d.start_room != d.exit_room, "different rooms")
		eq(d.rooms[d.exit_room].depth, 1.0, "exit is the deepest room")


## SRD 예산을 넘지 않음 (가장 싼 몬스터보다 예산이 작은 경우만 예외)
func test_encounters_within_xp_budget() -> void:
	for lvl in range(1, 6):
		for diff in 3:
			var p := params(DungeonParams.Algorithm.BSP, 50 + lvl * 3 + diff)
			p.party_level = lvl
			p.difficulty = diff
			p.encounter_ratio = 1.0
			var d := DungeonGenerator.generate(p)
			for r in d.rooms:
				if r.encounter.is_empty():
					continue
				var e: Dictionary = r.encounter
				eq(e.budget, DungeonGenerator.XP_BUDGET[lvl - 1][e.difficulty] * p.party_size, "budget lvl %d" % lvl)
				check(int(e.xp) <= int(e.budget), "xp %d <= budget %d" % [e.xp, e.budget])
				check((e.foes as Array).size() >= 1, "at least one foe")


func test_party_size_scales_budget() -> void:
	var p := params(DungeonParams.Algorithm.BSP, 3)
	p.party_size = 4
	p.encounter_ratio = 1.0
	p.difficulty_ramp = false
	p.boss_room = false
	var d := DungeonGenerator.generate(p)
	for r in d.rooms:
		if not r.encounter.is_empty():
			eq(r.encounter.budget, 75 * 4, "moderate lvl1 x4")


func test_boss_room_is_exit_and_high() -> void:
	var p := params(DungeonParams.Algorithm.BSP, 11)
	p.theme = "goblin"
	p.party_level = 3  # High 400 -> 고블린 대장(200) 들어감
	var d := DungeonGenerator.generate(p)
	var e: Dictionary = d.rooms[d.exit_room].encounter
	check(not e.is_empty(), "exit has encounter")
	eq(e.difficulty, DungeonParams.Difficulty.HIGH, "high difficulty")
	eq(e.foes[0][0], "goblin_boss", "boss leads")
	check(d.rooms[d.start_room].encounter.is_empty(), "start room is safe")


func test_theme_restricts_monsters() -> void:
	var p := params(DungeonParams.Algorithm.SCATTER, 5)
	p.theme = "undead"
	p.encounter_ratio = 1.0
	var d := DungeonGenerator.generate(p)
	for r in d.rooms:
		for f in (r.encounter.get("foes", []) as Array):
			eq(f[0], "skeleton", "undead only")


func test_no_contents_on_obstacles() -> void:
	for algo in ALGOS:
		var p := params(algo, 9)
		p.pillar_density = 0.2
		p.encounter_ratio = 1.0
		p.treasure_ratio = 1.0
		var d := DungeonGenerator.generate(p)
		var used := {}
		for r in d.rooms:
			for f in (r.encounter.get("foes", []) as Array):
				check(d.is_walkable(f[1]), "foe on walkable")
				check(not used.has(f[1]), "one thing per cell")
				used[f[1]] = true
			for t in r.treasure:
				check(d.is_walkable(t.cell), "treasure on walkable")
				check(not used.has(t.cell), "treasure not on foe")
				used[t.cell] = true
		check(d.is_walkable(d.start) and d.is_walkable(d.exit), "start/exit walkable")


## 한 걸음 높이차가 1.0을 넘지 않음 -> 전투 격자에서 다 걸어갈 수 있음
func test_height_steps_are_walkable() -> void:
	for algo in ALGOS:
		var p := params(algo, 13)
		p.height_variation = 1.0
		var d := DungeonGenerator.generate(p)
		for c in d.heights:
			for dd in Dungeon.DIRS4:
				var n: Vector2i = c + dd
				if d.is_floor(n):
					check(absf(d.get_height(c) - d.get_height(n)) <= 1.0, "step %s->%s" % [c, n])


func test_battle_setup_matches_grid() -> void:
	var p := params(DungeonParams.Algorithm.BSP, 21)
	p.encounter_ratio = 1.0
	var d := DungeonGenerator.generate(p)
	for r in d.rooms:
		if r.encounter.is_empty():
			continue
		var b := d.battle_setup(r.id)
		var map: Array = b.map
		var h := map.size()
		var w := (map[0] as String).length()
		for row in map:
			eq((row as String).length(), w, "rows same length")
		var pc: Vector2i = b.pc_start
		check(pc.x >= 0 and pc.y >= 0 and pc.x < w and pc.y < h, "pc in bounds")
		check((map[pc.y] as String)[pc.x] in [".", ",", "1", "2"], "pc on floor")
		eq((b.foes as Array).size(), (r.encounter.foes as Array).size(), "foe count")
		for f in b.foes:
			var c: Vector2i = f[1]
			check(c != pc, "pc not on foe")
			check((map[c.y] as String)[c.x] in [".", ",", "1", "2"], "foe on floor")


func test_cave_has_chambers() -> void:
	var p := params(DungeonParams.Algorithm.CAVE, 2)
	var d := DungeonGenerator.generate(p)
	check(d.rooms.size() >= 2, "cave split into chambers (%d)" % d.rooms.size())
	var total := 0
	for r in d.rooms:
		total += (r.cells as Array).size()
	eq(total, d.floor_count(), "every floor cell belongs to a chamber")


func test_tiny_and_extreme_params_do_not_crash() -> void:
	for algo in ALGOS:
		var p := params(algo, 99)
		p.width = 20
		p.height = 16
		p.room_count = 40
		p.room_min = 20
		p.room_max = 3
		p.corridor_width = 3
		p.cave_fill = 0.6
		var d := DungeonGenerator.generate(p)
		check(d.rooms.size() >= 1, "algo %d has a room" % algo)
		check(d.is_walkable(d.start), "algo %d start walkable" % algo)
