## 시나리오 엔진과 "소금바람 저택" 데이터 검사
extends RefCounted

const FILE := "res://scenarios/saltkeeper"

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func fresh() -> Scenario:
	var s := Scenario.load_pack(FILE)
	s.dice = Dice.new(7)
	s.new_game()
	s.out.clear()
	return s


## res://scenarios의 모든 팩 (데이터 검사는 팩마다 돌림)
func all_packs() -> Array[Scenario]:
	var out: Array[Scenario] = []
	for p in Scenario.list_packs(["res://scenarios"]):
		var s := Scenario.load_pack(str(p.path))
		check(s != null and s.errors.is_empty(), "pack %s loads cleanly" % p.id)
		if s:
			s.dice = Dice.new(7)
			s.new_game()
			s.out.clear()
			out.append(s)
	check(out.size() >= 2, "at least two packs")
	return out


func types(s: Scenario) -> Array:
	return s.out.map(func(o: Dictionary) -> String: return str(o.type))


# --- 데이터 ---

func test_loads_all_levels() -> void:
	var s := fresh()
	eq(s.levels.size(), 4, "levels")
	eq(s.level, "f1", "start level")
	check(s.room_key == "" or s.rooms.has(s.room_key), "start room valid")
	eq(s.heroes.size(), 2, "party size")
	eq((s.heroes[0] as HeroState).level(), 1, "start at level 1")


func test_links_point_to_real_marks() -> void:
	for s in all_packs():
		for key in s.marks:
			var m: Dictionary = s.marks[key]
			if m.type == "stairs":
				check(s.marks.has(str(m.to_level) + ":" + str(m.to_mark)), "%s leads to missing %s:%s" % [key, m.to_level, m.to_mark])
			if m.type == "foe":
				check(s.group_def(str(m.group)) != {}, "%s: group %s has no encounter" % [key, m.group])
				check(s.monster_stats(str(m.monster)).max_hp > 1, "%s: monster %s" % [key, m.monster])
		for g in s.data.encounters:
			var any := false
			for key in s.marks:
				if s.marks[key].type == "foe" and str(s.marks[key].group) == g:
					any = true
			check(any, "encounter %s has foes" % g)


func test_dialogue_nodes_exist() -> void:
	for s in all_packs():
		for did in s.data.dialogues:
			var dd: Dictionary = s.data.dialogues[did]
			check(dd.nodes.has(dd.start), "%s start node" % did)
			for nid in dd.nodes:
				for ch in dd.nodes[nid].get("choices", []):
					var targets: Array = [str(ch.get("next", "end"))]
					if ch.has("check"):
						targets.append_array([str(ch.check.success), str(ch.check.fail)])
					for t in targets:
						check(t == "end" or t == "" or dd.nodes.has(t), "%s/%s → missing node %s" % [did, nid, t])


	## 문과 비밀문을 모두 열었다고 치면 층마다 모든 바닥 칸에 갈 수 있어야 함 (단단한 물건만 막음)
func test_every_cell_reachable_when_open() -> void:
	for s in all_packs():
		for lid in s.levels:
			var dg: Dungeon = s.levels[lid]
			var solid := {}
			for key in s.marks:
				var m: Dictionary = s.marks[key]
				if m.level == lid and bool(m.get("solid", false)):
					solid[m.cell] = true
			var start := Vector2i(-1, -1)
			for key in s.marks:
				var m: Dictionary = s.marks[key]
				if m.level == lid and m.type == "stairs":
					start = m.cell
					break
			check(start.x >= 0, "%s has stairs" % lid)
			var seen := {start: true}
			var q: Array[Vector2i] = [start]
			while not q.is_empty():
				var c: Vector2i = q.pop_front()
				for d in Dungeon.DIRS4:
					var n: Vector2i = c + d
					if seen.has(n) or not dg.is_walkable(n) or solid.has(n):
						continue
					seen[n] = true
					q.append(n)
			for y in dg.height:
				for x in dg.width:
					var c := Vector2i(x, y)
					if dg.is_walkable(c) and not solid.has(c):
						check(seen.has(c), "%s %s (%d, %d) unreachable" % [s.id, lid, x, y])


func test_rooms_are_closed() -> void:
	for s in all_packs():
		# 방이 문 없이 다른 방과 붙어 있으면 flood가 두 방을 합침 → 방마다 칸 수가 적당해야 함
		for key in s.rooms:
			var n: int = (s.rooms[key].cells as Array).size()
			check(n >= 4 and n <= 160, "%s %s room size %d" % [s.id, key, n])


# --- 진행 ---

func test_locked_door_needs_key() -> void:
	var s := fresh()
	var door := "f1:a"
	check(s.is_locked(door), "study locked")
	s.dice.forced = [1]  # 억지로 열기 실패
	s.interact(door)
	check(not s.is_open(door), "still closed after failed force")
	s.out.clear()
	s.interact(door)
	check(not s.is_open(door), "second force not allowed")
	s.items["study_key"] = {"name": "서재 열쇠", "count": 1}
	s.interact(door)
	check(s.is_open(door), "opened with key")
	check(not s.blocked().has(s.marks[door].cell), "open door not blocked")


func test_feature_gives_key_once() -> void:
	var s := fresh()
	s.interact("f1:y")
	check(s.items.has("cellar_key"), "desk gives cellar key")
	check(s.journal.size() == 1, "journal has the log")
	var xp: int = (s.heroes[0] as HeroState).xp
	s.out.clear()
	s.interact("f1:y")
	eq((s.heroes[0] as HeroState).xp, xp, "no second xp")
	check(types(s).has("text"), "after text shown")


func test_search_reveals_secret() -> void:
	var s := fresh()
	s.level = "f2"
	s.cell = s.mark_cell("f2", "L")
	s.room_key = "f2:L"
	var secret := "f2:z"
	check(s.blocked().has(s.marks[secret].cell), "secret blocks before found")
	s.dice.forced = [18]
	s.search()
	check(s.revealed.has(secret), "search 18+1+2 finds DC 14")
	s.interact(secret)
	check(s.opened.has(secret) and not s.blocked().has(s.marks[secret].cell), "secret door opens")
	s.out.clear()
	s.search()
	eq(types(s), ["toast"], "room searched only once")


func test_failed_search_finds_nothing() -> void:
	var s := fresh()
	s.level = "f2"
	s.cell = s.mark_cell("f2", "L")
	s.room_key = "f2:L"
	s.dice.forced = [2]
	s.search()
	check(not s.revealed.has("f2:z"), "low roll misses secret")


func test_trap_springs_once() -> void:
	var s := fresh()
	s.level = "b1"
	var t := s.mark_cell("b1", "T")
	var before: int = (s.heroes[0] as HeroState).current_hp()
	s.dice.forced = [6, 6, 6, 1]  # 1d6+2d6 = 18, 내성 1
	s.enter_cell(t + Vector2i(-1, 0), t)
	var after: int = (s.heroes[0] as HeroState).current_hp()
	check(after < before, "trap hurt the leader")
	check(after >= 1, "out-of-combat damage leaves 1 HP when the other hero is up")
	s.out.clear()
	s.enter_cell(t + Vector2i(1, 0), t)
	eq((s.heroes[0] as HeroState).current_hp(), after, "trap only once")


func test_passive_perception_spots_trap() -> void:
	var s := fresh()
	s.level = "b1"
	var t := s.mark_cell("b1", "T")
	s.marks["b1:T"]["dc_find"] = 10
	s.enter_cell(t + Vector2i(-3, 0), t + Vector2i(-2, 0))
	check(s.revealed.has("b1:T"), "passive 13 spots DC 10 within 2 cells")


func test_entering_room_starts_battle() -> void:
	var s := fresh()
	s.go_to("b1", "u")
	s.out.clear()
	var wine := s.mark_cell("b1", "B")
	s.enter_cell(wine + Vector2i(0, 1), wine)
	check(types(s).has("battle"), "wine cellar battle")
	var setup := s.battle_setup("wine")
	eq((setup.foes as Array).size(), 2, "two zombies")
	var map: Array = setup.map
	var pc: Vector2i = setup.pc_start
	check(str(map[pc.y])[pc.x] != "X", "pc starts on floor")
	for f in setup.foes:
		var fc: Vector2i = f[1]
		check(str(map[fc.y])[fc.x] != "X", "foe on floor")


func test_battle_win_runs_after() -> void:
	var s := fresh()
	s.level = "b1"
	s.battle_result("servants", "win", Vector2i.ZERO)
	check(s.cleared.has("servants"), "cleared")
	check(s.items.has("iron_key"), "ghoul drops iron key")
	check(s.active("b1:b"), "bed usable after the fight")


func test_conditional_foes() -> void:
	var s := fresh()
	eq(s.foes_of("boss").size(), 2, "ghast + zombie")
	s.flags["aldous_moved"] = true
	eq(s.foes_of("boss").size(), 1, "ring removes zombies")


func test_dialogue_check_and_flags() -> void:
	var s := fresh()
	s.items["ring"] = {"name": "반지", "count": 1}
	s.start_dialogue("aldous")
	var d: Dictionary = s.out.back()
	eq(d.type, "dialogue", "dialogue shown")
	eq((d.choices as Array).size(), 5, "ring choice visible")
	s.out.clear()
	s.dice.forced = [15]  # 설득 15 + 1 = 16 ≥ 12
	s.choose(0)
	check(s.flags.has("aldous_moved") and s.flags.has("surprise:boss"), "ring success flags")
	s.out.clear()
	s.choose(0)
	check(types(s).has("battle"), "then battle")
	eq(s.battle_setup("boss").surprised, 1, "monsters surprised")


func test_exit_needs_escape() -> void:
	var s := fresh()
	s.interact("f1:X")
	check(not s.ended, "cannot leave before escape")
	s.flags["escape"] = true
	s.out.clear()
	s.interact("f1:X")
	check(s.ended, "leave after escape")
	eq((s.heroes[0] as HeroState).level(), 3, "level 3 at the end")


func test_checkpoint_restores() -> void:
	var s := fresh()
	s.save_checkpoint()
	s.flags["x"] = true
	s.gold = 99
	(s.heroes[0] as HeroState).hp = 3
	s.load_checkpoint()
	check(not s.flags.has("x"), "flags restored")
	eq(s.gold, 0, "gold restored")
	eq((s.heroes[0] as HeroState).current_hp(), (s.heroes[0] as HeroState).max_hp(), "hp restored")


func test_story_xp_levels_up() -> void:
	var s := fresh()
	s.run([{"do": "xp", "amount": 300}])
	eq((s.heroes[0] as HeroState).level(), 2, "300 xp → level 2")
	eq((s.heroes[1] as HeroState).level(), 2, "each hero gets story xp")


# --- 몬스터 규칙 ---

func _duel(attacker_id: String, target: CreatureStats) -> Array:
	var g := CombatGrid.new(6, 3)
	for y in 3:
		for x in 6:
			g.heights[Vector2i(x, y)] = 0.0
	var cb := Combat.new(g, Dice.new(1))
	var a := Creature.new(Catalog.monster(attacker_id), 1)
	var t := Creature.new(target, 0)
	cb.add(a, Vector2i(1, 1))
	cb.add(t, Vector2i(2, 1))
	return [cb, a, t]


func test_ghoul_claw_paralyzes() -> void:
	var r := _duel("ghoul", Catalog.cleric(1))
	var cb: Combat = r[0]
	var a: Creature = r[1]
	var t: Creature = r[2]
	cb.dice.forced = [19, 2, 1]  # 명중, 피해 1d4=2, CON 내성 1
	cb.resolve_attack(a, t, a.stats.weapons[0], cb.attack_info(a, t, a.stats.weapons[0]))
	check(t.has_effect("paralyzed"), "paralyzed on failed save")
	check(not t.can_act(), "paralyzed can't act")
	eq(t.speed(), 0, "speed 0")
	var sv := cb.saving_throw(t, Rules.Ability.DEX, 5)
	check(not sv.success, "auto-fail DEX save")
	var info := cb.attack_info(a, t, a.stats.weapons[0])
	eq(info.adv, 1, "attacks vs paralyzed have advantage")
	# 구울의 이번 턴 끝(skip 1→0), 다음 턴 끝에 풀림
	t.process_phase(a, "end")
	check(t.has_effect("paralyzed"), "still paralyzed after this turn")
	t.process_phase(a, "end")
	check(not t.has_effect("paralyzed"), "ends after ghoul's next turn")


func test_undead_immune_to_paralysis() -> void:
	var r := _duel("ghoul", Catalog.monster("zombie"))
	var cb: Combat = r[0]
	var a: Creature = r[1]
	var t: Creature = r[2]
	cb.dice.forced = [19, 2]
	cb.resolve_attack(a, t, a.stats.weapons[0], cb.attack_info(a, t, a.stats.weapons[0]))
	check(not t.has_effect("paralyzed"), "undead not paralyzed")


func test_swarm_halves_dice_when_bloodied() -> void:
	var r := _duel("swarm_rats", Catalog.fighter(1))
	var cb: Combat = r[0]
	var a: Creature = r[1]
	var w: WeaponData = a.stats.weapons[0]
	cb.dice.forced = [4, 4]
	eq(cb.roll_weapon_damage(a, w, false, false, 0), 8, "full swarm 2d4")
	a.hp = 5
	cb.dice.forced = [4, 4]
	eq(cb.roll_weapon_damage(a, w, false, false, 0), 4, "bloodied swarm 1d4")


func test_undead_fortitude() -> void:
	var r := _duel("zombie", Catalog.fighter(1))
	var cb: Combat = r[0]
	var z: Creature = r[1]
	cb.dice.forced = [20]  # CON 내성 20+3 ≥ 5+15
	cb._deal(z, 15, "slashing", false, "")
	check(z.is_alive() and z.hp == 1, "zombie stays up at 1 HP")
	cb._deal(z, 5, "radiant", false, "")
	check(not z.is_alive(), "radiant bypasses fortitude")


func test_shadow_drains_strength() -> void:
	var r := _duel("shadow", Catalog.fighter(1))
	var cb: Combat = r[0]
	var a: Creature = r[1]
	var t: Creature = r[2]
	var before := t.mod(Rules.Ability.STR)
	cb.dice.forced = [19, 1, 1, 4]  # 명중, 2d6 = 2, 근력 -4
	cb.resolve_attack(a, t, a.stats.weapons[0], cb.attack_info(a, t, a.stats.weapons[0]))
	eq(t.str_loss, 4, "strength -4")
	eq(t.mod(Rules.Ability.STR), before - 2, "STR mod drops")


func test_ghast_stench_poisons() -> void:
	var r := _duel("ghast", Catalog.fighter(1))
	var cb: Combat = r[0]
	var a: Creature = r[1]
	var t: Creature = r[2]
	cb.dice.forced = [1]  # CON 내성 실패
	cb._begin_turn(t)
	check(t.has_effect("poisoned"), "poisoned by stench")
	var info := cb.attack_info(t, a, t.stats.weapons[0])
	check(info.adv < 0 and info.dis_src.has("중독"), "poisoned attacks have disadvantage")
	cb.dice.forced = [20]  # 다음 턴: 중독이 풀리고 다시 굴려 성공
	cb._begin_turn(t)
	check(not t.has_effect("poisoned"), "poison ends at start of next turn")
	check(not t.find_effect("stench_immune", a).is_empty(), "immune after success")
	cb._begin_turn(t)
	check(not t.has_effect("poisoned"), "no more stench saves once immune")
	# 언데드는 중독 면역
	var z := Creature.new(Catalog.monster("zombie"), 1)
	cb.add(z, Vector2i(1, 0))
	cb._begin_turn(z)
	check(not z.has_effect("poisoned"), "undead immune to stench")


func test_specter_drains_max_hp() -> void:
	var h := HeroState.fresh("fighter")
	h.xp = Rules.XP_THRESHOLDS[2]
	var full := h.max_hp()
	var r := _duel("specter", Catalog.fighter(1))
	var cb: Combat = r[0]
	var a: Creature = r[1]
	var t := h.make_creature()
	cb.grid.remove(r[2])
	cb.creatures.erase(r[2])
	cb.add(t, Vector2i(2, 1))
	cb.dice.forced = [19, 3, 3, 3, 1]  # 명중, 3d6 = 9, CON 내성 실패
	cb.resolve_attack(a, t, a.stats.weapons[0], cb.attack_info(a, t, a.stats.weapons[0]))
	eq(t.max_hp_loss, 9, "max HP -9")
	eq(t.stats.max_hp, full - 9, "creature max HP reduced")
	h.absorb(t)
	eq(h.max_hp(), full - 9, "loss carries after battle")
	eq(h.make_creature().stats.max_hp, full - 9, "next battle starts reduced")
	h.long_rest()
	eq(h.max_hp(), full, "long rest restores max HP")
	eq(h.current_hp(), full, "and HP")


func test_flying_and_incorporeal_movement() -> void:
	var g := CombatGrid.new(5, 3)
	for y in 3:
		for x in 5:
			g.heights[Vector2i(x, y)] = 0.0
	for y in 3:
		g.walls[Vector2i(2, y)] = 1.0  # 가구 줄
	g.walls[Vector2i(3, 0)] = 3.0
	g.walls[Vector2i(3, 1)] = 3.0
	g.walls[Vector2i(3, 2)] = 3.0  # 그 뒤 벽
	g.difficult[Vector2i(1, 0)] = true
	var cb := Combat.new(g, Dice.new(1))
	var walker := Creature.new(Catalog.monster("zombie"), 1)
	var bats := Creature.new(Catalog.monster("swarm_bats"), 1)
	var ghost := Creature.new(Catalog.monster("specter"), 1)
	cb.add(walker, Vector2i(0, 0))
	cb.add(bats, Vector2i(0, 1))
	cb.add(ghost, Vector2i(0, 2))
	for c in [walker, bats, ghost]:
		(c as Creature).start_turn_reset()
	var wr := g.reachable(walker, 10)
	check(not wr.cost.has(Vector2i(2, 0)), "walker blocked by furniture")
	eq(g.step_cost(Vector2i(0, 0), Vector2i(1, 0), walker), 2, "walker pays for difficult terrain")
	eq(g.step_cost(Vector2i(0, 1), Vector2i(1, 0), bats), 1, "flyer ignores difficult terrain")
	var br := g.reachable(bats, 10)
	check(br.cost.has(Vector2i(2, 1)), "flyer passes over furniture")
	check(not br.cost.has(Vector2i(3, 1)), "flyer still blocked by tall wall")
	check(not cb.move_options(bats).has(Vector2i(2, 1)), "flyer can't stop on furniture")
	var gr := g.reachable(ghost, 10)
	check(gr.cost.has(Vector2i(4, 2)), "specter passes through walls")
	var opts := cb.move_options(ghost)
	check(opts.has(Vector2i(4, 2)) and not opts.has(Vector2i(3, 2)), "specter can't stop inside a wall")
	check(cb.move(ghost, Vector2i(4, 2)), "specter moves through")
	eq(ghost.cell, Vector2i(4, 2), "specter on far side")


func test_skills_and_passive() -> void:
	var f := Creature.new(Catalog.fighter(1), 0)
	var c := Creature.new(Catalog.cleric(1), 0)
	eq(f.skill_bonus("athletics"), 5, "fighter athletics +3+2")
	eq(f.passive_perception(), 13, "fighter passive 13")
	eq(c.skill_bonus("religion"), 2, "cleric religion INT 0 + 2")
	eq(c.skill_bonus("stealth"), -1, "cleric stealth DEX -1 untrained")


## 핵심 경로를 처음부터 끝까지 (전투는 이겼다고 침)
func test_full_playthrough() -> void:
	var s := fresh()
	s.go_to("f2", "D")
	s.on_arrived()
	check(types(s).has("battle"), "armor ambush upstairs")
	s.battle_result("armor", "win", Vector2i.ZERO)
	s.interact("f2:k")
	check(s.items.has("study_key"), "study key")
	s.interact("f2:D")
	eq(s.level, "f1", "back downstairs")
	s.interact("f1:a")
	check(s.is_open("f1:a"), "study open")
	s.interact("f1:y")
	s.interact("f1:c")
	check(s.is_open("f1:c"), "cellar open")
	s.interact("f1:v")
	eq(s.level, "b1", "cellar")
	s.battle_result("servants", "win", Vector2i.ZERO)
	s.interact("b1:G")
	check(s.is_open("b1:G"), "grate open")
	s.interact("b1:v")
	eq(s.level, "b2", "sea cave")
	s.on_arrived()
	eq((s.heroes[0] as HeroState).level(), 3, "milestone level 3 in the cave")
	s.interact("b2:R")
	check(s.items.has("ring"), "ring")
	s.out.clear()
	s.cell = s.mark_cell("b2", "C")
	s.on_arrived()
	check(types(s).has("dialogue"), "aldous talks")
	s.dice.forced = [20]
	s.choose(0)
	s.choose(0)
	check(types(s).has("battle"), "boss battle")
	eq(s.foes_of("boss").size(), 1, "ring left the ghast alone")
	s.battle_result("boss", "win", Vector2i.ZERO)
	check(s.flags.has("escape"), "escape phase")
	s.interact("b2:L")
	eq(s.level, "f1", "rope lift to kitchen")
	s.interact("f1:X")
	check(s.ended, "walked out")


# --- 시나리오 팩 (폴더 + scenario.json) ---

func test_pack_assembles_files() -> void:
	var s := fresh()
	eq(s.errors.size(), 0, "no pack errors: %s" % ", ".join(s.errors))
	eq(s.pack_dir, FILE, "pack dir")
	check(s.data.levels.has("f1") and s.data.levels.has("b2"), "levels from level files")
	check(s.data.dialogues.has("mira") and s.data.dialogues.has("aldous"), "dialogues merged from files")
	check(s.data.encounters.has("boss"), "encounters from file")
	check(s.data.intro is Array and not (s.data.intro as Array).is_empty(), "intro read from intro.json")


func test_pack_custom_monster() -> void:
	var s := fresh()
	var a := s.monster_stats("aldous")
	var base := Catalog.monster("ghast")
	eq(a.display_name, "올더스 브레넌", "custom name")
	eq(a.max_hp, base.max_hp, "keeps base HP")
	check(a.has_feature("stench"), "keeps base features")
	eq(s.battle_setup("boss").monster_defs.has("aldous"), true, "battle gets monster defs")
	var defs := {"brute": {"base": "zombie", "hp": 40, "ac": 12, "add_features": ["flying"], "weapons": ["slam"]}}
	var b := Catalog.custom_monster("brute", defs)
	eq(b.max_hp, 40, "hp override")
	eq(b.ac, 12, "ac override")
	check(b.has_feature("flying") and b.has_feature("undead_fortitude"), "add_features appends")
	eq(b.weapons[0].id, "slam", "weapons override")
	eq(Catalog.custom_monster("zombie", defs).display_name, "좀비", "plain SRD id still works")


func test_list_and_load_other_pack() -> void:
	var root := "user://_test_packs"
	DirAccess.make_dir_recursive_absolute(root + "/mini/levels")
	var lvl := {"id": "a", "name": "작은 방", "map": ["#####", "#S.E#", "#####"],
		"marks": {"S": {"type": "start"}, "E": {"type": "exit", "do": [{"do": "end", "result": "win", "title": "끝", "text": "끝"}]}}}
	var man := {"id": "mini", "title": "작은 시나리오", "version": "0.1", "start": {"level": "a", "mark": "S"},
		"levels": ["levels/a.json", "levels/missing.json"], "intro": [{"do": "text", "text": "시작"}],
		"monsters": {"rat_king": {"base": "swarm_rats", "name": "쥐 왕"}}}
	var f := FileAccess.open(root + "/mini/levels/a.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(lvl))
	f.close()
	f = FileAccess.open(root + "/mini/scenario.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(man))
	f.close()
	var packs := Scenario.list_packs([root])
	eq(packs.size(), 1, "one pack found")
	eq(packs[0].title, "작은 시나리오", "pack title")
	var s := Scenario.load_pack(root + "/mini")
	check(s != null, "loads by folder")
	check(s.errors.size() == 1 and s.errors[0].contains("missing.json"), "missing file reported")
	s.new_game()
	eq(s.level, "a", "starts on pack level")
	eq(s.monster_stats("rat_king").display_name, "쥐 왕", "inline monster defs")
	DirAccess.remove_absolute(root + "/mini/levels/a.json")
	DirAccess.remove_absolute(root + "/mini/levels")
	DirAccess.remove_absolute(root + "/mini/scenario.json")
	DirAccess.remove_absolute(root + "/mini")
	DirAccess.remove_absolute(root)
