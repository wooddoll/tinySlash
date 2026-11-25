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


func test_battle_setup_uses_entry_cell() -> void:
	for algo in ALGOS:
		var d := DungeonGenerator.generate(params(algo, 7))
		for r in d.rooms:
			if r.encounter.is_empty():
				continue
			var taken := {}
			for f in r.encounter.foes:
				taken[f[1]] = true
			var entry: Vector2i = Vector2i(-1, -1)
			for c in r.cells:
				if d.is_walkable(c) and not taken.has(c):
					entry = c
					break
			var b := d.battle_setup(r.id, entry)
			var rect: Rect2i = (r.rect as Rect2i).grow(2).intersection(Rect2i(0, 0, d.width, d.height))
			eq(b.pc_start, entry - rect.position, "algo %d room %d starts at entry" % [algo, r.id])


func test_explorer_collision() -> void:
	const Explorer = preload("res://scripts/dungeon_explorer.gd")
	var d := DungeonGenerator.generate(params(DungeonParams.Algorithm.BSP, 3))
	var s := d.start
	check(Explorer.can_stand(d, Vector2(s.x + 0.5, s.y + 0.5)), "can stand at start")
	# 벽 칸 한가운데는 못 섬
	var wall := Vector2i(0, 0)
	check(not Explorer.can_stand(d, Vector2(wall.x + 0.5, wall.y + 0.5)), "cannot stand in wall")
	for c in d.obstacles:
		check(not Explorer.can_stand(d, Vector2(c.x + 0.5, c.y + 0.5)), "cannot stand on obstacle")


func test_hero_state_carries_between_battles() -> void:
	var h := HeroState.fresh()
	var c := h.make_creature()
	eq(c.hp, 12, "fresh full hp")
	eq(c.resources.get("potion", 0), 1, "fresh potion")
	eq(c.resources.get("second_wind", 0), 2, "fresh second wind")
	c.hp = 5
	c.resources["second_wind"] = 1
	c.resources["potion"] = 0
	c.temp_hp = 4
	eq(h.absorb(c, 50), {}, "no level up at 50 xp")
	var c2 := h.make_creature()
	eq(c2.hp, 5, "hp carried")
	eq(c2.temp_hp, 0, "temp hp not carried")
	eq(c2.resources.get("second_wind", 0), 1, "second wind carried")
	eq(c2.resources.get("potion", 0), 0, "potion carried")
	eq(h.xp, 50, "xp accumulates")


func test_hero_state_level_up() -> void:
	var h := HeroState.fresh()
	var c := h.make_creature()
	c.hp = 6
	var up := h.absorb(c, 300)
	eq(up.get("level_up", 0), 2, "level 2 at 300 xp")
	var c2 := h.make_creature()
	eq(c2.stats.level, 2, "creature built at new level")
	eq(c2.stats.max_hp, 20, "level 2 max hp")
	eq(c2.hp, 14, "hp grows by max hp gain")
	eq(c2.resources.get("action_surge", 0), 1, "action surge gained")
	eq(c2.resources.get("second_wind", 0), 2, "second wind kept")


func test_hero_state_down_after_win_stands_at_one() -> void:
	var h := HeroState.fresh()
	var c := h.make_creature()
	c.hp = 0
	h.absorb(c, 25)
	eq(h.make_creature().hp, 1, "stands at 1 hp")
	var copy := h.duplicate_state()
	copy.xp = 999
	eq(h.xp, 25, "duplicate is independent")


func test_campfires_in_safe_rooms() -> void:
	for algo in ALGOS:
		for s in range(1, 11):
			var p := params(algo, s)
			p.campfire_count = 2
			var d := DungeonGenerator.generate(p)
			check(d.campfires.size() >= 1, "algo %d seed %d has a campfire" % [algo, s])
			var dist: Dictionary = d.flood(d.start).dist
			var seen := {}
			for c in d.campfires:
				check(d.is_walkable(c), "campfire walkable")
				check(dist.has(c), "campfire reachable")
				check(not seen.has(c), "campfires on different cells")
				seen[c] = true
				var r := d.room_at(c)
				check(r >= 0 and d.rooms[r].encounter.is_empty(), "campfire room has no monsters")
				for t in d.rooms[r].treasure:
					check(t.cell != c, "campfire not on chest")
	var p0 := params(DungeonParams.Algorithm.BSP, 5)
	p0.campfire_count = 0
	eq(DungeonGenerator.generate(p0).campfires.size(), 0, "no campfires when count 0")


func test_short_and_long_rest() -> void:
	var h := HeroState.fresh()
	h.xp = 900  # 3레벨: 히트 다이스 3개, 최대 HP 28
	var c := h.make_creature()
	c.hp = 4
	c.resources["second_wind"] = 0
	c.resources["action_surge"] = 0
	h.absorb(c)
	eq(h.hit_dice_left(), 3, "hit dice = level")
	var dice := Dice.new(11)
	var r := h.spend_hit_die(dice)
	check(r.heal >= 1 and r.heal == r.roll + 2, "heal = d10 + CON 2")
	eq(h.current_hp(), 4 + r.heal, "hp went up")
	eq(h.hit_dice_left(), 2, "one hit die spent")
	h.finish_short_rest()
	var c2 := h.make_creature()
	eq(c2.resources.second_wind, 1, "short rest regains one second wind")
	eq(c2.resources.action_surge, 1, "short rest regains action surge")
	h.finish_short_rest()
	eq(h.make_creature().resources.second_wind, 2, "second wind capped at max")
	h.finish_short_rest()
	eq(h.make_creature().resources.second_wind, 2, "still capped")
	# 다 쓰면 더 못 씀
	h.spend_hit_die(dice)
	h.spend_hit_die(dice)
	eq(h.spend_hit_die(dice), {}, "no hit dice left")
	h.long_rest()
	eq(h.current_hp(), 28, "long rest full hp")
	eq(h.hit_dice_left(), 3, "long rest restores hit dice")
	eq(h.make_creature().resources.get("potion", 0), 1, "long rest keeps potion count")
	var full := HeroState.fresh()
	eq(full.spend_hit_die(dice), {}, "cannot spend at full hp")


func test_sfx_files_exist() -> void:
	const Sfx = preload("res://scripts/sfx.gd")
	for g in Sfx.GROUPS:
		for f in Sfx.GROUPS[g][0]:
			check(ResourceLoader.exists(Sfx.path_of(f)), "sound %s: %s" % [g, f])


func test_deeper_floor_bigger_budget() -> void:
	eq(DungeonGenerator.depth_multiplier(1), 1.0, "floor 1 x1")
	check(is_equal_approx(DungeonGenerator.depth_multiplier(3), 1.3), "floor 3 x1.3")
	eq(DungeonGenerator.depth_multiplier(20), 2.0, "capped at x2")
	var p1 := params(DungeonParams.Algorithm.BSP, 9)
	var p5 := params(DungeonParams.Algorithm.BSP, 9)
	p5.floor_depth = 5
	var a := DungeonGenerator.generate(p1)
	var b := DungeonGenerator.generate(p5)
	for i in a.rooms.size():
		if a.rooms[i].encounter.is_empty() or b.rooms[i].encounter.is_empty():
			continue
		eq(b.rooms[i].encounter.budget, int(a.rooms[i].encounter.budget * 1.6), "room %d budget x1.6" % i)
		check(b.rooms[i].encounter.xp <= b.rooms[i].encounter.budget, "within deeper budget")


func test_fog_visible_cells() -> void:
	const DV = preload("res://scripts/dungeon_view.gd")
	var d := DungeonGenerator.generate(params(DungeonParams.Algorithm.BSP, 4))
	var r: Dictionary = d.rooms[d.start_room]
	eq(DV.visible_from(d, r.center).size(), (r.cells as Array).size(), "room shows whole room")
	for c in d.flood(d.start).dist:
		if d.room_at(c) == -1:
			var v := DV.visible_from(d, c)
			check(v.has(c), "corridor sees itself")
			for n in v:
				check(d.is_floor(n), "only floor cells")
				check(maxi(absi(n.x - c.x), absi(n.y - c.y)) <= 3, "within 3 steps")
			break


func test_shelter_floors_and_cell() -> void:
	const DV = preload("res://scripts/dungeon_view.gd")
	check(DV.is_save_floor(1) and DV.is_save_floor(4) and DV.is_save_floor(7), "save floors 1,4,7")
	check(not DV.is_save_floor(2) and not DV.is_save_floor(3) and not DV.is_save_floor(5), "no save on 2,3,5")
	for algo in ALGOS:
		for s in range(1, 11):
			var d := DungeonGenerator.generate(params(algo, s))
			var c := DV.shelter_cell(d)
			check(c != Vector2i(-1, -1), "algo %d seed %d has shelter cell" % [algo, s])
			check(d.is_walkable(c) and c != d.start, "shelter walkable and not on start")
			eq(d.room_at(c), d.start_room, "shelter in start room")
			check(not d.campfires.has(c), "shelter not on campfire")


func test_buy_potion() -> void:
	var h := HeroState.fresh()
	eq(h.potions(), 1, "start with one potion")
	eq(h.buy_potion(40), 40, "not enough gold")
	eq(h.potions(), 1, "still one")
	eq(h.buy_potion(120), 70, "paid 50")
	eq(h.potions(), 2, "two potions")
	for i in 10:
		h.buy_potion(1000)
	eq(h.potions(), HeroState.MAX_POTIONS, "capped")
	check(not h.can_buy_potion(1000), "cannot buy past cap")
	eq(h.make_creature().resources.potion, HeroState.MAX_POTIONS, "potions reach battle")


func test_cleric_hero_state_slots_and_rests() -> void:
	var h := HeroState.fresh("cleric")
	eq(h.potions(), 0, "cleric starts without potion")
	var c := h.make_creature()
	eq(c.display_name, "클레릭", "name")
	c.resources["slot1"] = 0
	h.absorb(c)
	eq(h.make_creature().resources.slot1, 0, "spent slot carries")
	h.finish_short_rest()
	eq(h.make_creature().resources.slot1, 0, "short rest keeps slots spent")
	h.long_rest()
	eq(h.make_creature().resources.slot1, 2, "long rest restores slots")
	var up := h.absorb(h.make_creature(), 900)
	eq(up.get("level_up", 0), 3, "level 3")
	var c3 := h.make_creature()
	eq(c3.resources.get("slot2", 0), 2, "new 2nd-level slots")
	eq(c3.resources.get("channel", 0), 2, "channel divinity")
